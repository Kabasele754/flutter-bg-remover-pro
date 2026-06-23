import 'package:flutter/material.dart';

class BgLoadingOverlay extends StatelessWidget {
  final String? text;

  const BgLoadingOverlay({super.key, this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withOpacity(0.18),
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF15151D).withOpacity(0.92),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white10),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              if (text != null) ...[
                const SizedBox(height: 10),
                Text(text!, style: const TextStyle(color: Colors.white70)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
