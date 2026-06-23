import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:onnxruntime/onnxruntime.dart';

import '../../../core/constants/bg_remover_assets.dart';

class BgRemoverAiEngine {
  static bool _ortEnvReady = false;

  OrtSession? _session;
  bool _initialized = false;
  bool _initializing = false;

  // Ce modèle u2netp.onnx est fixe: il attend exactement [1, 3, 320, 320].
  // On garde la qualité avec ratio + padding + post-traitement du masque.
  static const int inputSize = 320;
  static const String inputName = 'input.1';

  static const List<double> mean = [0.485, 0.456, 0.406];
  static const List<double> std = [0.229, 0.224, 0.225];

  Future<void> initialize() async {
    if (_initialized) return;

    while (_initializing) {
      await Future<void>.delayed(const Duration(milliseconds: 80));
      if (_initialized) return;
    }

    _initializing = true;
    OrtSessionOptions? sessionOptions;
    try {
      if (!_ortEnvReady) {
        try {
          OrtEnv.instance.init();
        } catch (_) {
          // Safe when the host app already initialized ONNX Runtime.
        }
        _ortEnvReady = true;
      }

      // ignore: avoid_print
      print('🔄 Loading U2Net model...');
      final modelBytes = await rootBundle.load(BgRemoverAssets.u2netpModel);

      sessionOptions = OrtSessionOptions()
        ..setIntraOpNumThreads(2)
        ..setInterOpNumThreads(1)
        ..setSessionGraphOptimizationLevel(
          GraphOptimizationLevel.ortEnableAll,
        );

      _session = OrtSession.fromBuffer(
        modelBytes.buffer.asUint8List(),
        sessionOptions,
      );

      _initialized = true;
      // ignore: avoid_print
      print('✅ U2Net model loaded successfully');
    } catch (e) {
      // ignore: avoid_print
      print('❌ Failed to load model: $e');
      rethrow;
    } finally {
      sessionOptions?.release();
      _initializing = false;
    }
  }

  Future<Uint8List> generateMask(Uint8List imageBytes) async {
    // ignore: avoid_print
    print('🧠 Starting mask generation...');
    if (!_initialized) await initialize();

    final session = _session;
    if (session == null) throw Exception('ONNX session is not ready');

    final prep = await compute(_preprocessImageForU2Net, imageBytes);
    final originalWidth = prep['originalWidth'] as int;
    final originalHeight = prep['originalHeight'] as int;
    final contentWidth = prep['contentWidth'] as int;
    final contentHeight = prep['contentHeight'] as int;
    final offsetX = prep['offsetX'] as int;
    final offsetY = prep['offsetY'] as int;
    final tensorData = prep['tensor'] as Float32List;

    // ignore: avoid_print
    print('📏 Original size: ${originalWidth}x$originalHeight');
    // ignore: avoid_print
    print('🔧 Building tensor [1, 3, $inputSize, $inputSize]...');

    OrtValueTensor? inputTensor;
    OrtRunOptions? runOptions;
    List<OrtValue?>? outputs;

    try {
      final resolvedInputName = session.inputNames.contains(inputName)
          ? inputName
          : session.inputNames.first.toString();

      inputTensor = OrtValueTensor.createTensorWithDataList(
        [tensorData],
        [1, 3, inputSize, inputSize],
      );

      runOptions = OrtRunOptions();
      // ignore: avoid_print
      print('🚀 Running AI inference...');
      outputs = await session.runAsync(runOptions, {resolvedInputName: inputTensor});

      if (outputs == null || outputs.isEmpty || outputs.first == null) {
        throw Exception('ONNX inference returned no output');
      }

      // ignore: avoid_print
      print('✅ Inference complete, processing output...');
      final outputTensor = outputs.first! as OrtValueTensor;
      final raw = _flattenTensorValues(outputTensor.value);
      if (raw.isEmpty) throw Exception('ONNX output tensor is empty');

      final normalized = _normalizeMask(raw);

      final maskBytes = await compute(_encodeMaskPng, {
        'normalized': normalized,
        'originalWidth': originalWidth,
        'originalHeight': originalHeight,
        'contentWidth': contentWidth,
        'contentHeight': contentHeight,
        'offsetX': offsetX,
        'offsetY': offsetY,
      });

      // ignore: avoid_print
      print('✅ Mask generation complete!');
      return maskBytes;
    } finally {
      inputTensor?.release();
      runOptions?.release();
      if (outputs != null) {
        for (final out in outputs) {
          out?.release();
        }
      }
    }
  }

  static Map<String, dynamic> _preprocessImageForU2Net(Uint8List imageBytes) {
    final image = img.decodeImage(imageBytes);
    if (image == null) throw Exception('Could not decode image');

    final scale = math.min(inputSize / image.width, inputSize / image.height);
    final resizedWidth = math.max(1, (image.width * scale).round());
    final resizedHeight = math.max(1, (image.height * scale).round());
    final offsetX = ((inputSize - resizedWidth) / 2).floor();
    final offsetY = ((inputSize - resizedHeight) / 2).floor();

    final resized = img.copyResize(
      image,
      width: resizedWidth,
      height: resizedHeight,
      interpolation: img.Interpolation.cubic,
    );

    final canvas = img.Image(width: inputSize, height: inputSize, numChannels: 3);
    img.fill(canvas, color: img.ColorRgb8(0, 0, 0));
    img.compositeImage(canvas, resized, dstX: offsetX, dstY: offsetY);

    final tensorData = Float32List(3 * inputSize * inputSize);
    var idx = 0;

    for (var y = 0; y < inputSize; y++) {
      for (var x = 0; x < inputSize; x++) {
        final pixel = canvas.getPixel(x, y);
        tensorData[idx++] = ((pixel.r / 255.0) - mean[0]) / std[0];
      }
    }
    for (var y = 0; y < inputSize; y++) {
      for (var x = 0; x < inputSize; x++) {
        final pixel = canvas.getPixel(x, y);
        tensorData[idx++] = ((pixel.g / 255.0) - mean[1]) / std[1];
      }
    }
    for (var y = 0; y < inputSize; y++) {
      for (var x = 0; x < inputSize; x++) {
        final pixel = canvas.getPixel(x, y);
        tensorData[idx++] = ((pixel.b / 255.0) - mean[2]) / std[2];
      }
    }

    return {
      'originalWidth': image.width,
      'originalHeight': image.height,
      'contentWidth': resizedWidth,
      'contentHeight': resizedHeight,
      'offsetX': offsetX,
      'offsetY': offsetY,
      'tensor': tensorData,
    };
  }

  List<double> _flattenTensorValues(dynamic value) {
    final values = <double>[];

    void visit(dynamic item) {
      if (item is num) {
        values.add(item.toDouble());
      } else if (item is Iterable) {
        for (final child in item) {
          visit(child);
        }
      }
    }

    visit(value);
    return values;
  }

  Float32List _normalizeMask(List<double> rawValues) {
    final expectedLength = inputSize * inputSize;
    final effectiveLength = rawValues.length >= expectedLength
        ? expectedLength
        : rawValues.length;

    final data = Float32List(expectedLength);
    if (effectiveLength == 0) return data;

    var minValue = double.infinity;
    var maxValue = double.negativeInfinity;

    final logitsLike = rawValues.any((v) => v < 0 || v > 1);

    for (var i = 0; i < effectiveLength; i++) {
      final raw = rawValues[i];
      final value = logitsLike ? 1.0 / (1.0 + math.exp(-raw)) : raw;
      data[i] = value.toDouble();
      if (value < minValue) minValue = value;
      if (value > maxValue) maxValue = value;
    }

    final range = maxValue - minValue;
    if (range <= 1e-8) {
      return data;
    }

    for (var i = 0; i < data.length; i++) {
      data[i] = ((data[i] - minValue) / range).clamp(0.0, 1.0);
    }

    return data;
  }

  static Uint8List _encodeMaskPng(Map<String, dynamic> args) {
    final normalized = args['normalized'] as Float32List;
    final originalWidth = args['originalWidth'] as int;
    final originalHeight = args['originalHeight'] as int;
    final contentWidth = args['contentWidth'] as int;
    final contentHeight = args['contentHeight'] as int;
    final offsetX = args['offsetX'] as int;
    final offsetY = args['offsetY'] as int;

    final fullMask = img.Image(width: inputSize, height: inputSize, numChannels: 4);

    for (var y = 0; y < inputSize; y++) {
      for (var x = 0; x < inputSize; x++) {
        final index = y * inputSize + x;
        final value = index < normalized.length ? normalized[index] : 0.0;
        final px = (value * 255).round().clamp(0, 255).toInt();
        fullMask.setPixelRgba(x, y, px, px, px, 255);
      }
    }

    final safeWidth = contentWidth.clamp(1, inputSize - offsetX).toInt();
    final safeHeight = contentHeight.clamp(1, inputSize - offsetY).toInt();

    final cropped = img.copyCrop(
      fullMask,
      x: offsetX,
      y: offsetY,
      width: safeWidth,
      height: safeHeight,
    );

    final resizedMask = img.copyResize(
      cropped,
      width: originalWidth,
      height: originalHeight,
      interpolation: img.Interpolation.cubic,
    );

    return Uint8List.fromList(img.encodePng(resizedMask));
  }

  Future<void> dispose() async {
    _session?.release();
    _session = null;
    _initialized = false;
    _initializing = false;
  }
}
