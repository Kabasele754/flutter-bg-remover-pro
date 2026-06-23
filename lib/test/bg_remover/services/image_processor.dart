import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

class BgRemoverImageProcessor {
  static Map<String, dynamic> prepareForEditing(Map<String, dynamic> args) {
    final Uint8List bytes = args['bytes'] as Uint8List;
    final int maxDimension = (args['maxDimension'] ?? 1800) as int;

    final image = img.decodeImage(bytes);
    if (image == null) throw Exception('Decode failed');

    img.Image output = image;
    final longest = math.max(image.width, image.height);

    if (longest > maxDimension) {
      final scale = maxDimension / longest;
      final width = math.max(1, (image.width * scale).round());
      final height = math.max(1, (image.height * scale).round());
      output = img.copyResize(
        image,
        width: width,
        height: height,
        interpolation: img.Interpolation.cubic,
      );
    }

    final resultBytes = Uint8List.fromList(img.encodeJpg(output, quality: 92));
    return {
      'bytes': resultBytes,
      'width': output.width,
      'height': output.height,
      'aspectRatio': output.width / output.height,
    };
  }

  static Uint8List applyMaskAdvanced(Map<String, dynamic> args) {
    final Uint8List originalBytes = args['originalBytes'];
    final Uint8List maskBytes = args['maskBytes'];

    final double sensitivity = (args['sensitivity'] ?? 0.38) as double;
    final double edgeSoftness = (args['edgeSoftness'] ?? 0.06) as double;
    final int edgeExpansion = (args['edgeExpansion'] ?? 0) as int;
    final double detailBoost = (args['detailBoost'] ?? 0.12) as double;
    final bool addShadow = args['addShadow'] ?? false;
    final int shadowBlur = args['shadowBlur'] ?? 20;

    final original = img.decodeImage(originalBytes);
    var mask = img.decodeImage(maskBytes);
    if (original == null || mask == null) throw Exception('Decode failed');

    if (mask.width != original.width || mask.height != original.height) {
      mask = img.copyResize(
        mask,
        width: original.width,
        height: original.height,
        interpolation: img.Interpolation.cubic,
      );
    }

    mask = _prepareMask(
      mask,
      edgeExpansion: edgeExpansion,
      edgeSoftness: edgeSoftness,
    );

    final output = img.Image(
      width: original.width,
      height: original.height,
      numChannels: 4,
    );

    final low = (sensitivity - edgeSoftness).clamp(0.0, 1.0).toDouble();
    final high = (sensitivity + edgeSoftness).clamp(0.0, 1.0).toDouble();
    final gamma = (1.0 - detailBoost.clamp(0.0, 0.75)).clamp(0.35, 1.0).toDouble();

    for (var y = 0; y < original.height; y++) {
      for (var x = 0; x < original.width; x++) {
        final maskValue = mask.getPixel(x, y).r / 255.0;
        final boosted = math.pow(maskValue.clamp(0.0, 1.0), gamma).toDouble();
        var alphaNormalized = _smoothStep(low, high, boosted);

        if (alphaNormalized < 0.08) {
          alphaNormalized = 0.0;
        }

        final alpha = (alphaNormalized * 255).round().clamp(0, 255);
        final pixel = original.getPixel(x, y);
        output.setPixelRgba(x, y, pixel.r, pixel.g, pixel.b, alpha);
      }
    }

    if (addShadow) {
      return Uint8List.fromList(_addDropShadow(output, shadowBlur));
    }

    return Uint8List.fromList(img.encodePng(output));
  }

  /// Retouche manuelle du masque.
  /// - restore = true : récupère une partie supprimée.
  /// - restore = false : efface un reste du background.
  static Map<String, Uint8List> applyBrushStroke(Map<String, dynamic> args) {
    final Uint8List originalBytes = args['originalBytes'] as Uint8List;
    final Uint8List maskBytes = args['maskBytes'] as Uint8List;
    final List<dynamic> points = args['points'] as List<dynamic>;
    final double brushRadiusRatio = (args['brushRadiusRatio'] ?? 0.035) as double;
    final bool restore = args['restore'] as bool? ?? true;
    final bool addShadow = args['addShadow'] as bool? ?? false;
    final int shadowBlur = args['shadowBlur'] as int? ?? 20;

    final original = img.decodeImage(originalBytes);
    var mask = img.decodeImage(maskBytes);
    if (original == null || mask == null) throw Exception('Decode failed');

    if (mask.width != original.width || mask.height != original.height) {
      mask = img.copyResize(
        mask,
        width: original.width,
        height: original.height,
        interpolation: img.Interpolation.cubic,
      );
    }

    mask = img.grayscale(mask);
    final radius = math.max(4, (math.min(mask.width, mask.height) * brushRadiusRatio).round());

    final normalizedPoints = points
        .map((p) {
          if (p is Map) {
            final x = (p['x'] as num?)?.toDouble();
            final y = (p['y'] as num?)?.toDouble();
            if (x == null || y == null) return null;
            return math.Point<double>(
              x.clamp(0.0, 1.0).toDouble(),
              y.clamp(0.0, 1.0).toDouble(),
            );
          }
          return null;
        })
        .whereType<math.Point<double>>()
        .toList();

    if (normalizedPoints.isNotEmpty) {
      for (var i = 0; i < normalizedPoints.length; i++) {
        final current = normalizedPoints[i];
        final cx = (current.x * (mask.width - 1)).round();
        final cy = (current.y * (mask.height - 1)).round();
        _drawSoftCircle(mask, cx, cy, radius, restore: restore);

        if (i > 0) {
          final previous = normalizedPoints[i - 1];
          final px = (previous.x * (mask.width - 1)).round();
          final py = (previous.y * (mask.height - 1)).round();
          _drawSoftLine(mask, px, py, cx, cy, radius, restore: restore);
        }
      }
    }

    final foreground = _applyExactMask(original, mask);
    final foregroundBytes = addShadow
        ? Uint8List.fromList(_addDropShadow(foreground, shadowBlur))
        : Uint8List.fromList(img.encodePng(foreground));

    return {
      'maskBytes': Uint8List.fromList(img.encodePng(mask)),
      'foregroundBytes': foregroundBytes,
    };
  }

  static void _drawSoftLine(
    img.Image mask,
    int x1,
    int y1,
    int x2,
    int y2,
    int radius, {
    required bool restore,
  }) {
    final dx = x2 - x1;
    final dy = y2 - y1;
    final distance = math.sqrt(dx * dx + dy * dy);
    final steps = math.max(1, (distance / math.max(1, radius * 0.45)).ceil());

    for (var i = 0; i <= steps; i++) {
      final t = i / steps;
      final x = (x1 + dx * t).round();
      final y = (y1 + dy * t).round();
      _drawSoftCircle(mask, x, y, radius, restore: restore);
    }
  }

  static void _drawSoftCircle(
    img.Image mask,
    int cx,
    int cy,
    int radius, {
    required bool restore,
  }) {
    final r2 = radius * radius;
    final inner = radius * 0.62;
    final inner2 = inner * inner;

    final minX = (cx - radius).clamp(0, mask.width - 1).toInt();
    final maxX = (cx + radius).clamp(0, mask.width - 1).toInt();
    final minY = (cy - radius).clamp(0, mask.height - 1).toInt();
    final maxY = (cy + radius).clamp(0, mask.height - 1).toInt();

    for (var y = minY; y <= maxY; y++) {
      for (var x = minX; x <= maxX; x++) {
        final dx = x - cx;
        final dy = y - cy;
        final d2 = dx * dx + dy * dy;
        if (d2 > r2) continue;

        double strength;
        if (d2 <= inner2) {
          strength = 1.0;
        } else {
          final d = math.sqrt(d2);
          strength = 1.0 - ((d - inner) / math.max(1.0, radius - inner));
          strength = strength.clamp(0.0, 1.0).toDouble();
        }

        final current = mask.getPixel(x, y).r.toInt();
        final paintValue = (255 * strength).round().clamp(0, 255);
        final newValue = restore
            ? math.max(current, paintValue)
            : math.min(current, 255 - paintValue);

        mask.setPixelRgba(x, y, newValue, newValue, newValue, 255);
      }
    }
  }

  static img.Image _applyExactMask(img.Image original, img.Image mask) {
    final output = img.Image(
      width: original.width,
      height: original.height,
      numChannels: 4,
    );

    for (var y = 0; y < original.height; y++) {
      for (var x = 0; x < original.width; x++) {
        final p = original.getPixel(x, y);
        final alpha = mask.getPixel(x, y).r.toInt().clamp(0, 255);
        output.setPixelRgba(x, y, p.r, p.g, p.b, alpha);
      }
    }

    return output;
  }

  static img.Image _prepareMask(
    img.Image mask, {
    required int edgeExpansion,
    required double edgeSoftness,
  }) {
    var result = img.grayscale(mask);

    final blurRadius = math.max(1, (edgeSoftness * 22).round());
    result = img.gaussianBlur(result, radius: blurRadius);

    if (edgeExpansion > 0) {
      for (var i = 0; i < edgeExpansion; i++) {
        result = _dilate(result);
      }
    } else if (edgeExpansion < 0) {
      for (var i = 0; i < edgeExpansion.abs(); i++) {
        result = _erode(result);
      }
    }

    return result;
  }

  static img.Image _dilate(img.Image source) {
    final out = img.Image(width: source.width, height: source.height, numChannels: 3);

    for (var y = 0; y < source.height; y++) {
      for (var x = 0; x < source.width; x++) {
        var maxVal = 0;
        for (var ky = -1; ky <= 1; ky++) {
          for (var kx = -1; kx <= 1; kx++) {
            final nx = (x + kx).clamp(0, source.width - 1).toInt();
            final ny = (y + ky).clamp(0, source.height - 1).toInt();
            final v = source.getPixel(nx, ny).r.toInt();
            if (v > maxVal) maxVal = v;
          }
        }
        out.setPixelRgba(x, y, maxVal, maxVal, maxVal, 255);
      }
    }

    return out;
  }

  static img.Image _erode(img.Image source) {
    final out = img.Image(width: source.width, height: source.height, numChannels: 3);

    for (var y = 0; y < source.height; y++) {
      for (var x = 0; x < source.width; x++) {
        var minVal = 255;
        for (var ky = -1; ky <= 1; ky++) {
          for (var kx = -1; kx <= 1; kx++) {
            final nx = (x + kx).clamp(0, source.width - 1).toInt();
            final ny = (y + ky).clamp(0, source.height - 1).toInt();
            final v = source.getPixel(nx, ny).r.toInt();
            if (v < minVal) minVal = v;
          }
        }
        out.setPixelRgba(x, y, minVal, minVal, minVal, 255);
      }
    }

    return out;
  }

  static double _smoothStep(double edge0, double edge1, double x) {
    if (edge1 <= edge0) return x >= edge1 ? 1.0 : 0.0;
    var t = ((x - edge0) / (edge1 - edge0)).clamp(0.0, 1.0).toDouble();
    t = t * t * (3.0 - 2.0 * t);
    return t;
  }

  static List<int> _addDropShadow(img.Image subject, int blur) {
    final padding = blur * 2;
    final shadowCanvas = img.Image(
      width: subject.width + padding * 2,
      height: subject.height + padding * 2,
      numChannels: 4,
    );

    final shadowOffset = 10;
    for (var y = 0; y < subject.height; y++) {
      for (var x = 0; x < subject.width; x++) {
        final pixel = subject.getPixel(x, y);
        final alpha = pixel.a;
        if (alpha > 0) {
          shadowCanvas.setPixelRgba(
            x + padding + shadowOffset,
            y + padding + shadowOffset,
            0,
            0,
            0,
            (alpha * 0.5).toInt(),
          );
        }
      }
    }

    final blurredShadow = img.gaussianBlur(shadowCanvas, radius: blur);
    img.compositeImage(blurredShadow, subject, dstX: padding, dstY: padding);

    return img.encodePng(blurredShadow);
  }

  static Uint8List compositeWithColor(Map<String, dynamic> args) {
    final Uint8List subjectBytes = args['subjectBytes'];
    final int bgColor = args['bgColor'];

    final subject = img.decodeImage(subjectBytes);
    if (subject == null) throw Exception('Decode failed');

    final bg = img.Image(
      width: subject.width,
      height: subject.height,
      numChannels: 4,
    );
    img.fill(
      bg,
      color: img.ColorRgba8(
        (bgColor >> 16) & 0xFF,
        (bgColor >> 8) & 0xFF,
        bgColor & 0xFF,
        255,
      ),
    );

    img.compositeImage(bg, subject);
    return Uint8List.fromList(img.encodePng(bg));
  }

  static Uint8List compositeWithImage(Map<String, dynamic> args) {
    final Uint8List subjectBytes = args['subjectBytes'];
    final Uint8List bgBytes = args['bgBytes'];

    final subject = img.decodeImage(subjectBytes);
    var bg = img.decodeImage(bgBytes);
    if (subject == null || bg == null) throw Exception('Decode failed');

    bg = img.copyResize(
      bg,
      width: subject.width,
      height: subject.height,
      interpolation: img.Interpolation.cubic,
    );

    img.compositeImage(bg, subject);
    return Uint8List.fromList(img.encodePng(bg));
  }

  static Uint8List compositeWithBlur(Map<String, dynamic> args) {
    final Uint8List originalBytes = args['originalBytes'];
    final Uint8List maskBytes = args['maskBytes'];
    final int blurRadius = args['blurRadius'];

    final original = img.decodeImage(originalBytes);
    var mask = img.decodeImage(maskBytes);
    if (original == null || mask == null) throw Exception('Decode failed');

    if (mask.width != original.width || mask.height != original.height) {
      mask = img.copyResize(mask, width: original.width, height: original.height);
    }

    final blurred = img.gaussianBlur(
      img.copyResize(original, width: original.width, height: original.height),
      radius: blurRadius,
    );

    for (var y = 0; y < original.height; y++) {
      for (var x = 0; x < original.width; x++) {
        final maskVal = mask.getPixel(x, y).r;
        if (maskVal > 128) {
          final sharpPixel = original.getPixel(x, y);
          blurred.setPixelRgba(x, y, sharpPixel.r, sharpPixel.g, sharpPixel.b, 255);
        }
      }
    }

    return Uint8List.fromList(img.encodePng(blurred));
  }


  static Map<String, dynamic> exportRendered(Map<String, dynamic> args) {
    final Uint8List subjectBytes = args['subjectBytes'] as Uint8List;
    final Uint8List? backgroundImageBytes = args['backgroundImageBytes'] as Uint8List?;
    final int? backgroundColor = args['backgroundColor'] as int?;
    final int fallbackColor = (args['fallbackColor'] ?? 0xFFFFFFFF) as int;
    final String format = (args['format'] ?? 'png') as String;
    final int quality = (args['quality'] ?? 95) as int;
    final int maxDimension = (args['maxDimension'] ?? 0) as int;
    final int canvasWidth = (args['canvasWidth'] ?? 0) as int;
    final int canvasHeight = (args['canvasHeight'] ?? 0) as int;
    final double subjectScale = (args['subjectScale'] ?? 1.0) as double;
    final double alignY = (args['alignY'] ?? 0.0) as double;

    final subject = img.decodeImage(subjectBytes);
    if (subject == null) throw Exception('Decode failed');

    final int baseWidth = canvasWidth > 0 ? canvasWidth : subject.width;
    final int baseHeight = canvasHeight > 0 ? canvasHeight : subject.height;

    img.Image output;

    if (backgroundImageBytes != null) {
      final bgDecoded = img.decodeImage(backgroundImageBytes);
      if (bgDecoded == null) throw Exception('Background decode failed');
      output = img.copyResize(
        bgDecoded,
        width: baseWidth,
        height: baseHeight,
        interpolation: img.Interpolation.cubic,
      );
    } else if (format == 'png' && backgroundColor == null && canvasWidth == 0 && canvasHeight == 0) {
      output = img.Image(width: baseWidth, height: baseHeight, numChannels: 4);
    } else {
      final color = backgroundColor ?? fallbackColor;
      output = img.Image(width: baseWidth, height: baseHeight, numChannels: 4);
      img.fill(
        output,
        color: img.ColorRgba8(
          (color >> 16) & 0xFF,
          (color >> 8) & 0xFF,
          color & 0xFF,
          255,
        ),
      );
    }

    img.Image composedSubject = subject;
    if (canvasWidth > 0 || canvasHeight > 0 || subjectScale != 1.0) {
      final scale = math.min(baseWidth / subject.width, baseHeight / subject.height) * subjectScale;
      final resizedWidth = math.max(1, (subject.width * scale).round());
      final resizedHeight = math.max(1, (subject.height * scale).round());
      composedSubject = img.copyResize(
        subject,
        width: resizedWidth,
        height: resizedHeight,
        interpolation: img.Interpolation.cubic,
      );
      final dstX = ((baseWidth - resizedWidth) / 2).round();
      final freeY = baseHeight - resizedHeight;
      final normalizedY = ((alignY + 1) / 2).clamp(0.0, 1.0);
      final dstY = (freeY * normalizedY).round();
      img.compositeImage(output, composedSubject, dstX: dstX, dstY: dstY);
    } else {
      img.compositeImage(output, composedSubject);
    }

    if (maxDimension > 0) {
      final longest = math.max(output.width, output.height);
      if (longest > maxDimension) {
        final scale = maxDimension / longest;
        output = img.copyResize(
          output,
          width: math.max(1, (output.width * scale).round()),
          height: math.max(1, (output.height * scale).round()),
          interpolation: img.Interpolation.cubic,
        );
      }
    }

    Uint8List data;
    String mimeType;
    String extension;
    if (format == 'jpg' || format == 'jpeg') {
      data = Uint8List.fromList(img.encodeJpg(output, quality: quality));
      mimeType = 'image/jpeg';
      extension = 'jpg';
    } else {
      data = Uint8List.fromList(img.encodePng(output));
      mimeType = 'image/png';
      extension = 'png';
    }

    return {
      'bytes': data,
      'mimeType': mimeType,
      'extension': extension,
      'width': output.width,
      'height': output.height,
      'byteLength': data.length,
    };
  }

}
