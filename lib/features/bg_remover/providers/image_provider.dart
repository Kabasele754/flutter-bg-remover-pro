import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/constants/bg_remover_constants.dart';
import '../services/ai_engine.dart';
import '../services/image_processor.dart';

enum BgRemoverProcessingStatus {
  idle,
  picking,
  loadingModel,
  generatingMask,
  applyingMask,
  done,
  error,
  batchProcessing,
}

class BgRemoverImageState {
  final Uint8List? originalImage;
  final Uint8List? maskImage;
  final Uint8List? foregroundImage;
  final Uint8List? processedImage;
  final int? backgroundColor;
  final Uint8List? backgroundImage;
  final double previewAspectRatio;
  final BgRemoverProcessingStatus status;
  final String? errorMessage;
  final double progress;
  final int batchCompleted;
  final int batchTotal;
  final int undoCount;
  final int redoCount;

  const BgRemoverImageState({
    this.originalImage,
    this.maskImage,
    this.foregroundImage,
    this.processedImage,
    this.backgroundColor,
    this.backgroundImage,
    this.previewAspectRatio = 1.0,
    this.status = BgRemoverProcessingStatus.idle,
    this.errorMessage,
    this.progress = 0.0,
    this.batchCompleted = 0,
    this.batchTotal = 0,
    this.undoCount = 0,
    this.redoCount = 0,
  });

  BgRemoverImageState copyWith({
    Uint8List? originalImage,
    Uint8List? maskImage,
    Uint8List? foregroundImage,
    Uint8List? processedImage,
    int? backgroundColor,
    Uint8List? backgroundImage,
    double? previewAspectRatio,
    BgRemoverProcessingStatus? status,
    String? errorMessage,
    double? progress,
    int? batchCompleted,
    int? batchTotal,
    int? undoCount,
    int? redoCount,
    bool clearOriginalImage = false,
    bool clearMaskImage = false,
    bool clearForegroundImage = false,
    bool clearProcessedImage = false,
    bool clearBackgroundColor = false,
    bool clearBackgroundImage = false,
    bool clearErrorMessage = false,
  }) {
    return BgRemoverImageState(
      originalImage: clearOriginalImage ? null : originalImage ?? this.originalImage,
      maskImage: clearMaskImage ? null : maskImage ?? this.maskImage,
      foregroundImage: clearForegroundImage ? null : foregroundImage ?? this.foregroundImage,
      processedImage: clearProcessedImage ? null : processedImage ?? this.processedImage,
      backgroundColor: clearBackgroundColor ? null : backgroundColor ?? this.backgroundColor,
      backgroundImage: clearBackgroundImage ? null : backgroundImage ?? this.backgroundImage,
      previewAspectRatio: previewAspectRatio ?? this.previewAspectRatio,
      status: status ?? this.status,
      errorMessage: clearErrorMessage ? null : errorMessage ?? this.errorMessage,
      progress: progress ?? this.progress,
      batchCompleted: batchCompleted ?? this.batchCompleted,
      batchTotal: batchTotal ?? this.batchTotal,
      undoCount: undoCount ?? this.undoCount,
      redoCount: redoCount ?? this.redoCount,
    );
  }

  bool get isBusy =>
      status == BgRemoverProcessingStatus.picking ||
      status == BgRemoverProcessingStatus.loadingModel ||
      status == BgRemoverProcessingStatus.generatingMask ||
      status == BgRemoverProcessingStatus.applyingMask ||
      status == BgRemoverProcessingStatus.batchProcessing;
}

class _BrushHistoryEntry {
  final Uint8List maskBytes;
  final Uint8List foregroundBytes;

  const _BrushHistoryEntry({
    required this.maskBytes,
    required this.foregroundBytes,
  });
}

class BgRemoverImageNotifier extends StateNotifier<BgRemoverImageState> {
  final BgRemoverAiEngine _aiEngine = BgRemoverAiEngine();
  bool _modelLoaded = false;

  final List<_BrushHistoryEntry> _undoHistory = [];
  final List<_BrushHistoryEntry> _redoHistory = [];

  BgRemoverImageNotifier() : super(const BgRemoverImageState()) {
    Future<void>.delayed(const Duration(milliseconds: 250), _loadModel);
  }

  Future<void> _loadModel() async {
    if (_modelLoaded) return;

    state = state.copyWith(
      status: BgRemoverProcessingStatus.loadingModel,
      clearErrorMessage: true,
    );

    try {
      await _aiEngine.initialize();
      _modelLoaded = true;
      state = state.copyWith(
        status: BgRemoverProcessingStatus.idle,
        clearErrorMessage: true,
      );
    } catch (e) {
      state = state.copyWith(
        status: BgRemoverProcessingStatus.error,
        errorMessage: 'Failed to load AI model: $e',
      );
    }
  }

  Future<void> pickImage() async => _pickImageFromSource(ImageSource.gallery);

  Future<void> pickImageFromCamera() async => _pickImageFromSource(ImageSource.camera);

  Future<void> _pickImageFromSource(ImageSource source) async {
    print(source == ImageSource.camera ? '📷 Opening camera...' : '📷 Picking image...');

    state = state.copyWith(
      status: BgRemoverProcessingStatus.picking,
      clearErrorMessage: true,
    );

    try {
      final picker = ImagePicker();
      final xFile = await picker.pickImage(source: source, imageQuality: 90);

      if (xFile == null) {
        state = state.copyWith(status: BgRemoverProcessingStatus.idle);
        return;
      }

      final rawBytes = await xFile.readAsBytes();
      _clearBrushHistory();

      // Affiche l'image immédiatement pour réduire la sensation de latence.
      state = state.copyWith(
        originalImage: rawBytes,
        status: BgRemoverProcessingStatus.idle,
        previewAspectRatio: 1.0,
        clearMaskImage: true,
        clearForegroundImage: true,
        clearProcessedImage: true,
        clearBackgroundColor: true,
        clearBackgroundImage: true,
        clearErrorMessage: true,
        progress: 0,
        batchCompleted: 0,
        batchTotal: 0,
        undoCount: 0,
        redoCount: 0,
      );

      _prepareSelectedImage(rawBytes);
      print('✅ Image picked: ${rawBytes.length} bytes');
    } catch (e) {
      state = state.copyWith(
        status: BgRemoverProcessingStatus.error,
        errorMessage: e.toString(),
      );
    }
  }

  Future<void> _prepareSelectedImage(Uint8List rawBytes) async {
    try {
      final prepared = await compute(BgRemoverImageProcessor.prepareForEditing, {
        'bytes': rawBytes,
        'maxDimension': BgRemoverConstants.maxImageDimension,
      });

      final bytes = prepared['bytes'] as Uint8List;
      final aspectRatio = prepared['aspectRatio'] as double;

      if (state.originalImage == null || state.maskImage != null || state.processedImage != null) {
        return;
      }

      state = state.copyWith(
        originalImage: bytes,
        previewAspectRatio: aspectRatio,
        status: BgRemoverProcessingStatus.idle,
      );
    } catch (_) {
      // En cas d'échec, on garde simplement l'image brute déjà affichée.
    }
  }

  void _clearBrushHistory() {
    _undoHistory.clear();
    _redoHistory.clear();
  }

  void _syncBrushHistoryState() {
    state = state.copyWith(
      undoCount: _undoHistory.length,
      redoCount: _redoHistory.length,
    );
  }

  void _pushUndoEntry(Uint8List maskBytes, Uint8List foregroundBytes) {
    _undoHistory.add(_BrushHistoryEntry(maskBytes: maskBytes, foregroundBytes: foregroundBytes));
    if (_undoHistory.length > 30) {
      _undoHistory.removeAt(0);
    }
    _redoHistory.clear();
  }

  Future<void> processImage({
    double sensitivity = 0.38,
    double edgeSoftness = 0.06,
    int edgeExpansion = 0,
    double detailBoost = 0.12,
    bool addShadow = false,
    int shadowBlur = 20,
  }) async {
    if (state.originalImage == null) {
      print('❌ Cannot process: no original image');
      return;
    }

    if (!_modelLoaded) {
      await _loadModel();
      if (!_modelLoaded) return;
    }

    try {
      print('🚀 Starting image processing...');

      state = state.copyWith(
        status: BgRemoverProcessingStatus.generatingMask,
        clearMaskImage: true,
        clearForegroundImage: true,
        clearProcessedImage: true,
        clearBackgroundColor: true,
        clearBackgroundImage: true,
        clearErrorMessage: true,
      );

      final original = state.originalImage!;
      final maskBytes = await _aiEngine.generateMask(original);
      state = state.copyWith(status: BgRemoverProcessingStatus.applyingMask);

      final processedBytes = await compute(BgRemoverImageProcessor.applyMaskAdvanced, {
        'originalBytes': original,
        'maskBytes': maskBytes,
        'sensitivity': sensitivity,
        'edgeSoftness': edgeSoftness,
        'edgeExpansion': edgeExpansion,
        'detailBoost': detailBoost,
        'addShadow': addShadow,
        'shadowBlur': shadowBlur,
      });

      _clearBrushHistory();
      state = state.copyWith(
        maskImage: maskBytes,
        foregroundImage: processedBytes,
        processedImage: processedBytes,
        status: BgRemoverProcessingStatus.done,
        clearBackgroundColor: true,
        clearBackgroundImage: true,
        clearErrorMessage: true,
        undoCount: 0,
        redoCount: 0,
      );
      print('🎉 Processing complete!');
    } catch (e, st) {
      print('❌ Processing error: $e');
      print('📜 Stack trace: $st');
      state = state.copyWith(
        status: BgRemoverProcessingStatus.error,
        errorMessage: '$e',
      );
    }
  }

  Future<List<Uint8List>> batchProcess(List<Uint8List> images) async {
    if (!_modelLoaded) {
      await _loadModel();
      if (!_modelLoaded) throw Exception('Model not loaded');
    }

    state = state.copyWith(
      status: BgRemoverProcessingStatus.batchProcessing,
      batchTotal: images.length,
      batchCompleted: 0,
      progress: 0.0,
      clearErrorMessage: true,
    );

    final results = <Uint8List>[];

    for (var i = 0; i < images.length; i++) {
      try {
        final prepared = await compute(BgRemoverImageProcessor.prepareForEditing, {
          'bytes': images[i],
          'maxDimension': BgRemoverConstants.maxImageDimension,
        });
        final imgBytes = prepared['bytes'] as Uint8List;
        final mask = await _aiEngine.generateMask(imgBytes);
        final processed = await compute(BgRemoverImageProcessor.applyMaskAdvanced, {
          'originalBytes': imgBytes,
          'maskBytes': mask,
          'sensitivity': 0.38,
          'edgeSoftness': 0.06,
          'edgeExpansion': 0,
          'detailBoost': 0.12,
          'addShadow': false,
          'shadowBlur': 0,
        });
        results.add(processed);
      } catch (e) {
        results.add(images[i]);
      }

      state = state.copyWith(
        batchCompleted: i + 1,
        progress: (i + 1) / images.length,
      );
    }

    state = state.copyWith(status: BgRemoverProcessingStatus.done);
    return results;
  }

  void applyBackground(int bgColor) {
    if (state.foregroundImage == null && state.processedImage == null) return;

    state = state.copyWith(
      processedImage: state.foregroundImage ?? state.processedImage,
      backgroundColor: bgColor,
      clearBackgroundImage: true,
      clearErrorMessage: true,
    );
  }

  void applyBackgroundImage(Uint8List bgBytes) {
    if (state.foregroundImage == null && state.processedImage == null) return;

    state = state.copyWith(
      processedImage: state.foregroundImage ?? state.processedImage,
      backgroundImage: bgBytes,
      clearBackgroundColor: true,
      clearErrorMessage: true,
    );
  }

  void clearPreviewBackground() {
    if (state.foregroundImage == null && state.processedImage == null) return;
    state = state.copyWith(
      processedImage: state.foregroundImage ?? state.processedImage,
      clearBackgroundColor: true,
      clearBackgroundImage: true,
      clearErrorMessage: true,
    );
  }

  Future<void> applyManualBrushStroke({
    required List<Map<String, double>> points,
    required double brushRadiusRatio,
    required bool restore,
    bool addShadow = false,
    int shadowBlur = 20,
  }) async {
    if (state.originalImage == null || state.maskImage == null) return;
    if (points.isEmpty) return;

    try {
      final previousMask = state.maskImage!;
      final previousForeground = state.foregroundImage ?? state.processedImage;
      if (previousForeground == null) return;

      state = state.copyWith(
        status: BgRemoverProcessingStatus.applyingMask,
        clearErrorMessage: true,
      );

      final result = await compute(BgRemoverImageProcessor.applyBrushStroke, {
        'originalBytes': state.originalImage!,
        'maskBytes': state.maskImage!,
        'points': points,
        'brushRadiusRatio': brushRadiusRatio,
        'restore': restore,
        'addShadow': addShadow,
        'shadowBlur': shadowBlur,
      });

      final updatedMask = result['maskBytes'] as Uint8List;
      final updatedForeground = result['foregroundBytes'] as Uint8List;

      _pushUndoEntry(previousMask, previousForeground);
      state = state.copyWith(
        maskImage: updatedMask,
        foregroundImage: updatedForeground,
        processedImage: updatedForeground,
        status: BgRemoverProcessingStatus.done,
        clearErrorMessage: true,
        undoCount: _undoHistory.length,
        redoCount: _redoHistory.length,
      );
    } catch (e, st) {
      print('❌ Brush error: $e');
      print('📜 Stack trace: $st');
      state = state.copyWith(
        status: BgRemoverProcessingStatus.error,
        errorMessage: '$e',
      );
    }
  }

  void undoManualBrush() {
    if (_undoHistory.isEmpty) return;
    final currentMask = state.maskImage;
    final currentForeground = state.foregroundImage ?? state.processedImage;
    final previous = _undoHistory.removeLast();

    if (currentMask != null && currentForeground != null) {
      _redoHistory.add(_BrushHistoryEntry(maskBytes: currentMask, foregroundBytes: currentForeground));
    }

    state = state.copyWith(
      maskImage: previous.maskBytes,
      foregroundImage: previous.foregroundBytes,
      processedImage: previous.foregroundBytes,
      status: BgRemoverProcessingStatus.done,
      undoCount: _undoHistory.length,
      redoCount: _redoHistory.length,
    );
  }

  void redoManualBrush() {
    if (_redoHistory.isEmpty) return;
    final currentMask = state.maskImage;
    final currentForeground = state.foregroundImage ?? state.processedImage;
    final next = _redoHistory.removeLast();

    if (currentMask != null && currentForeground != null) {
      _undoHistory.add(_BrushHistoryEntry(maskBytes: currentMask, foregroundBytes: currentForeground));
    }

    state = state.copyWith(
      maskImage: next.maskBytes,
      foregroundImage: next.foregroundBytes,
      processedImage: next.foregroundBytes,
      status: BgRemoverProcessingStatus.done,
      undoCount: _undoHistory.length,
      redoCount: _redoHistory.length,
    );
  }

  Future<void> applyBlurBackground(int blurRadius) async {
    if (state.originalImage == null || state.maskImage == null) return;

    try {
      state = state.copyWith(
        status: BgRemoverProcessingStatus.applyingMask,
        clearBackgroundColor: true,
        clearBackgroundImage: true,
        clearErrorMessage: true,
      );

      final result = await compute(BgRemoverImageProcessor.compositeWithBlur, {
        'originalBytes': state.originalImage!,
        'maskBytes': state.maskImage!,
        'blurRadius': blurRadius,
      });

      state = state.copyWith(
        processedImage: result,
        status: BgRemoverProcessingStatus.done,
        clearErrorMessage: true,
      );
    } catch (e) {
      state = state.copyWith(status: BgRemoverProcessingStatus.error, errorMessage: e.toString());
    }
  }

  Future<Uint8List?> buildExportImage() async {
    final subject = state.foregroundImage ?? state.processedImage;
    if (subject == null) return null;

    if (state.backgroundColor != null) {
      return compute(BgRemoverImageProcessor.compositeWithColor, {
        'subjectBytes': subject,
        'bgColor': state.backgroundColor!,
      });
    }

    if (state.backgroundImage != null) {
      return compute(BgRemoverImageProcessor.compositeWithImage, {
        'subjectBytes': subject,
        'bgBytes': state.backgroundImage!,
      });
    }

    return state.processedImage ?? subject;
  }

  void reset() {
    _clearBrushHistory();
    state = const BgRemoverImageState();
  }

  @override
  void dispose() {
    _aiEngine.dispose();
    super.dispose();
  }
}

final bgRemoverImageProvider = StateNotifierProvider<BgRemoverImageNotifier, BgRemoverImageState>((ref) {
  return BgRemoverImageNotifier();
});
