import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/image_provider.dart';
import '../services/gallery_service.dart';

class BgRemoverBatchScreen extends ConsumerStatefulWidget {
  const BgRemoverBatchScreen({super.key});

  @override
  ConsumerState<BgRemoverBatchScreen> createState() => _BgRemoverBatchScreenState();
}

class _BgRemoverBatchScreenState extends ConsumerState<BgRemoverBatchScreen> {
  List<Uint8List> _selectedImages = [];
  List<Uint8List> _processedImages = [];

  Future<void> _pickMultiple() async {
    final result = await FilePicker.pickFiles(
      type: FileType.image,
      allowMultiple: true,
      withData: true,
    );

    if (result != null) {
      final images = <Uint8List>[];
      for (final file in result.files) {
        if (file.bytes != null) images.add(file.bytes!);
      }
      setState(() {
        _selectedImages = images;
        _processedImages = [];
      });
    }
  }

  Future<void> _processAll() async {
    if (_selectedImages.isEmpty) return;
    final results = await ref.read(bgRemoverImageProvider.notifier).batchProcess(_selectedImages);
    setState(() => _processedImages = results);
  }

  Future<void> _saveAll() async {
    var saved = 0;
    for (var i = 0; i < _processedImages.length; i++) {
      final ok = await BgRemoverGalleryService.saveToGallery(_processedImages[i], name: 'batch_$i');
      if (ok) saved++;
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('✅ Saved $saved/${_processedImages.length} images')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(bgRemoverImageProvider);
    final isProcessing = state.status == BgRemoverProcessingStatus.batchProcessing;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Batch Processing'),
        actions: [
          if (_processedImages.isNotEmpty)
            TextButton.icon(
              onPressed: _saveAll,
              icon: const Icon(Icons.save_alt),
              label: const Text('Save All'),
            ),
        ],
      ),
      body: Column(
        children: [
          if (isProcessing)
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A22),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Text('Processing', style: TextStyle(fontWeight: FontWeight.bold)),
                      const Spacer(),
                      Text('${state.batchCompleted}/${state.batchTotal}'),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: state.progress,
                      minHeight: 6,
                      backgroundColor: Colors.white10,
                    ),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: isProcessing ? null : _pickMultiple,
                    icon: const Icon(Icons.folder_open),
                    label: const Text('Select Images'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _selectedImages.isNotEmpty && !isProcessing ? _processAll : null,
                    icon: const Icon(Icons.auto_awesome),
                    label: const Text('Process All'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF6C5CE7),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _processedImages.isNotEmpty
                ? _buildGrid(_processedImages, 'Processed')
                : _selectedImages.isNotEmpty
                    ? _buildGrid(_selectedImages, 'Selected')
                    : const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.collections_outlined, size: 80, color: Colors.white24),
                            SizedBox(height: 16),
                            Text(
                              'Select multiple images to batch process',
                              style: TextStyle(color: Colors.white54),
                            ),
                          ],
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildGrid(List<Uint8List> images, String title) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            '$title (${images.length})',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: images.length,
            itemBuilder: (context, index) {
              return ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  color: const Color(0xFF1A1A22),
                  child: Image.memory(images[index], fit: BoxFit.cover),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
