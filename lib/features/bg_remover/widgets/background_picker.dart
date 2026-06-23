import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

class BgRemoverBackgroundPicker extends StatelessWidget {
  final ValueChanged<int> onColorSelected;
  final ValueChanged<Uint8List> onImageSelected;
  final ValueChanged<int> onBlurSelected;
  final VoidCallback onReset;

  const BgRemoverBackgroundPicker({
    super.key,
    required this.onColorSelected,
    required this.onImageSelected,
    required this.onBlurSelected,
    required this.onReset,
  });

  static const List<int> presetColors = [
    0xFFFFFFFF,
    0xFF000000,
    0xFFF5F5F5,
    0xFFE8F1FF,
    0xFFFFE4E1,
    0xFFEAFBF2,
    0xFFFFD700,
    0xFFFF69B4,
    0xFF00CED1,
    0xFF8A2BE2,
    0xFFFF8C00,
  ];

  static const List<_StudioPreset> studioPresets = [
    _StudioPreset('Grey', [0xFFF2F2F2, 0xFFDADADA], Icons.stay_current_portrait),
    _StudioPreset('Blue', [0xFFE8F1FF, 0xFFBCD8FF], Icons.badge),
    _StudioPreset('Beige', [0xFFF7F0E8, 0xFFE5D5C5], Icons.wb_sunny_outlined),
    _StudioPreset('Purple', [0xFFEDE6FF, 0xFFC4B5FD], Icons.auto_awesome),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Quick colors',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white70),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: onReset,
              icon: const Icon(Icons.layers_clear, size: 18),
              label: const Text('Transparent'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: presetColors.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final color = presetColors[index];
              return GestureDetector(
                onTap: () => onColorSelected(color),
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: Color(color),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white24, width: 2),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 14),
        const Text(
          'Studio premium',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white70),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 82,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: studioPresets.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final preset = studioPresets[index];
              return GestureDetector(
                onTap: () async {
                  final bytes = await _buildGradientBackground(preset.colors[0], preset.colors[1]);
                  onImageSelected(bytes);
                },
                child: Container(
                  width: 86,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: preset.colors.map((e) => Color(e)).toList(),
                    ),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(preset.icon, color: Colors.black87, size: 18),
                      const Spacer(),
                      Text(
                        preset.label,
                        style: const TextStyle(
                          color: Colors.black87,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            _buildOptionButton(
              icon: Icons.blur_on,
              label: 'Blur',
              onTap: () => onBlurSelected(15),
            ),
            const SizedBox(width: 8),
            _buildOptionButton(
              icon: Icons.image,
              label: 'Custom',
              onTap: () async {
                final picker = ImagePicker();
                final file = await picker.pickImage(source: ImageSource.gallery);
                if (file != null) {
                  final bytes = await file.readAsBytes();
                  onImageSelected(bytes);
                }
              },
            ),
            const SizedBox(width: 8),
            _buildOptionButton(
              icon: Icons.badge,
              label: 'Passport',
              onTap: () => onColorSelected(0xFFE8F1FF),
            ),
          ],
        ),
      ],
    );
  }

  Future<Uint8List> _buildGradientBackground(int color1, int color2) async {
    final image = img.Image(width: 1200, height: 1600, numChannels: 4);
    final c1 = img.ColorRgba8((color1 >> 16) & 0xFF, (color1 >> 8) & 0xFF, color1 & 0xFF, 255);
    final c2 = img.ColorRgba8((color2 >> 16) & 0xFF, (color2 >> 8) & 0xFF, color2 & 0xFF, 255);

    for (var y = 0; y < image.height; y++) {
      final t = y / (image.height - 1);
      final r = (c1.r + (c2.r - c1.r) * t).round();
      final g = (c1.g + (c2.g - c1.g) * t).round();
      final b = (c1.b + (c2.b - c1.b) * t).round();
      for (var x = 0; x < image.width; x++) {
        image.setPixelRgba(x, y, r, g, b, 255);
      }
    }

    final cx = image.width / 2;
    final cy = image.height * 0.32;
    final maxRadius = image.width * 0.75;
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        final dx = x - cx;
        final dy = y - cy;
        final d = (dx * dx + dy * dy) / (maxRadius * maxRadius);
        final glow = (1.0 - d).clamp(0.0, 1.0) * 0.18;
        final p = image.getPixel(x, y);
        final rr = (p.r + (255 - p.r) * glow).round().clamp(0, 255);
        final gg = (p.g + (255 - p.g) * glow).round().clamp(0, 255);
        final bb = (p.b + (255 - p.b) * glow).round().clamp(0, 255);
        image.setPixelRgba(x, y, rr, gg, bb, 255);
      }
    }

    return Uint8List.fromList(img.encodeJpg(image, quality: 95));
  }

  Widget _buildOptionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: Material(
        color: const Color(0xFF25252F),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: Colors.white, size: 20),
                const SizedBox(height: 4),
                Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StudioPreset {
  final String label;
  final List<int> colors;
  final IconData icon;

  const _StudioPreset(this.label, this.colors, this.icon);
}
