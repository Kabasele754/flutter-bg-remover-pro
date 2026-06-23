import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/image_provider.dart';
import '../bg_remover_routes.dart';

class BgRemoverHomeScreen extends ConsumerWidget {
  const BgRemoverHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(bgRemoverImageProvider);

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxHeight < 650;

            return SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.all(compact ? 16 : 24),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: (constraints.maxHeight - (compact ? 32 : 48)).clamp(0, double.infinity),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(height: compact ? 10 : 36),
                    _Header(compact: compact),
                    SizedBox(height: compact ? 20 : 42),
                    _buildModelStatus(state),
                    SizedBox(height: compact ? 18 : 28),

                    _buildActionCard(
                      context,
                      compact: compact,
                      icon: Icons.photo_library_outlined,
                      title: 'Single Image',
                      subtitle: 'Remove background from one photo',
                      gradient: const [Color(0xFF6C5CE7), Color(0xFFA29BFE)],
                      onTap: () => _handlePickImage(context, ref),
                      enabled: _canStartAction(state),
                    ),
                    SizedBox(height: compact ? 12 : 16),

                    _buildActionCard(
                      context,
                      compact: compact,
                      icon: Icons.collections_outlined,
                      title: 'Batch Process',
                      subtitle: 'Process multiple images at once',
                      gradient: const [Color(0xFF00B894), Color(0xFF55EFC4)],
                      onTap: () => Navigator.pushNamed(context, BgRemoverRoutes.batch),
                      enabled: _canStartAction(state),
                    ),
                    SizedBox(height: compact ? 12 : 16),

                    _buildActionCard(
                      context,
                      compact: compact,
                      icon: Icons.camera_alt_outlined,
                      title: 'Take Photo',
                      subtitle: 'Capture and process instantly',
                      gradient: const [Color(0xFFFD79A8), Color(0xFFFDCB6E)],
                      onTap: () => _handlePickImage(context, ref, fromCamera: true),
                      enabled: _canStartAction(state),
                    ),

                    SizedBox(height: compact ? 20 : 28),
                    _buildStatusBanner(state),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  bool _canStartAction(BgRemoverImageState state) {
    return state.status == BgRemoverProcessingStatus.idle ||
        state.status == BgRemoverProcessingStatus.done ||
        state.status == BgRemoverProcessingStatus.error;
  }

  Widget _buildModelStatus(BgRemoverImageState state) {
    final isReady = state.status == BgRemoverProcessingStatus.idle ||
        state.status == BgRemoverProcessingStatus.done ||
        state.status == BgRemoverProcessingStatus.error;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isReady
            ? const Color(0xFF00B894).withOpacity(0.15)
            : Colors.orange.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isReady ? const Color(0xFF00B894) : Colors.orange,
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isReady ? Icons.check_circle : Icons.hourglass_empty,
            color: isReady ? const Color(0xFF00B894) : Colors.orange,
            size: 18,
          ),
          const SizedBox(width: 8),
          Text(
            isReady ? 'AI Model Ready' : 'Loading model...',
            style: TextStyle(
              color: isReady ? const Color(0xFF00B894) : Colors.orange,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionCard(
    BuildContext context, {
    required bool compact,
    required IconData icon,
    required String title,
    required String subtitle,
    required List<Color> gradient,
    required VoidCallback onTap,
    required bool enabled,
  }) {
    return Opacity(
      opacity: enabled ? 1.0 : 0.5,
      child: Material(
        color: const Color(0xFF1A1A22),
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: EdgeInsets.all(compact ? 14 : 20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white10),
            ),
            child: Row(
              children: [
                Container(
                  padding: EdgeInsets.all(compact ? 12 : 14),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: gradient),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: Colors.white, size: compact ? 22 : 26),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: compact ? 16 : 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(color: Colors.white54, fontSize: 13),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_ios, color: Colors.white38, size: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBanner(BgRemoverImageState state) {
    if (state.status == BgRemoverProcessingStatus.loadingModel) {
      return const _LoadingBanner(text: 'Loading AI model...');
    }
    if (state.status == BgRemoverProcessingStatus.picking) {
      return const _LoadingBanner(text: 'Opening image picker...');
    }
    if (state.status == BgRemoverProcessingStatus.generatingMask) {
      return const _LoadingBanner(text: '🧠 AI analyzing image...');
    }
    if (state.status == BgRemoverProcessingStatus.applyingMask) {
      return const _LoadingBanner(text: '✨ Refining edges...');
    }
    if (state.status == BgRemoverProcessingStatus.error && state.errorMessage != null) {
      return _ErrorBanner(message: state.errorMessage!);
    }
    return const SizedBox.shrink();
  }

  Future<void> _handlePickImage(
    BuildContext context,
    WidgetRef ref, {
    bool fromCamera = false,
  }) async {
    final notifier = ref.read(bgRemoverImageProvider.notifier);

    if (fromCamera) {
      await notifier.pickImageFromCamera();
    } else {
      await notifier.pickImage();
    }

    if (context.mounted && ref.read(bgRemoverImageProvider).originalImage != null) {
      Navigator.pushNamed(context, BgRemoverRoutes.editor);
    }
  }
}

class _Header extends StatelessWidget {
  final bool compact;
  const _Header({required this.compact});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: EdgeInsets.all(compact ? 10 : 12),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF6C5CE7), Color(0xFFA29BFE)],
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(Icons.auto_awesome, color: Colors.white, size: compact ? 24 : 28),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'BG Remover',
                style: TextStyle(
                  fontSize: compact ? 24 : 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Text(
                'Powered by U2Net AI',
                style: TextStyle(color: Colors.white54, fontSize: 13),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LoadingBanner extends StatelessWidget {
  final String text;
  const _LoadingBanner({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF6C5CE7), Color(0xFFA29BFE)],
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: const TextStyle(fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.redAccent.withOpacity(0.15),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.redAccent),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.redAccent),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Colors.redAccent, fontSize: 12),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
