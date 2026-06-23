import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/image_provider.dart';
import '../services/gallery_service.dart';
import '../services/image_processor.dart';
import '../widgets/background_picker.dart';
import '../widgets/before_after_slider.dart';

enum _ManualBrushMode { restore, erase }
enum _MaskPreset { clean, balanced, detailed }
enum _ManualCanvasMode { navigate, paint }
enum _ControlPanel { background, brush, settings, export, tips }

enum _ExportPreset {
  pngTransparent,
  jpgWhite,
  jpgColor,
  hd,
  compressed,
  passport,
}

class BgRemoverEditorScreen extends ConsumerStatefulWidget {
  const BgRemoverEditorScreen({super.key});

  @override
  ConsumerState<BgRemoverEditorScreen> createState() => _BgRemoverEditorScreenState();
}

class _BgRemoverEditorScreenState extends ConsumerState<BgRemoverEditorScreen> {
  bool _showBeforeAfter = false;
  bool _addShadow = false;
  bool _panelExpanded = true;
  bool _exportBusy = false;
  bool _exportPreviewLoading = false;

  _ControlPanel _activePanel = _ControlPanel.background;
  _ManualBrushMode _brushMode = _ManualBrushMode.restore;
  _ManualCanvasMode _canvasMode = _ManualCanvasMode.navigate;
  _MaskPreset _preset = _MaskPreset.balanced;

  double _brushRadiusRatio = 0.035;
  final List<Map<String, double>> _pendingBrushPoints = [];
  final List<Offset> _pendingDisplayPoints = [];
  Offset? _brushCursorPosition;

  final TransformationController _transformationController = TransformationController();

  double _sensitivity = 0.38;
  double _edgeSoftness = 0.06;
  int _edgeExpansion = 0;
  double _detailBoost = 0.12;
  int _shadowBlur = 20;

  final Map<_ExportPreset, String> _exportPreviewSizes = {};

  bool get _brushPanelActive => _activePanel == _ControlPanel.brush;

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(bgRemoverImageProvider);
    final height = MediaQuery.sizeOf(context).height;
    final compact = height < 700;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            ref.read(bgRemoverImageProvider.notifier).reset();
            Navigator.pop(context);
          },
        ),
        title: const Text('Editor'),
        actions: [
          if (state.processedImage != null)
            IconButton(
              icon: const Icon(Icons.ios_share),
              onPressed: _showExportOptionsSheet,
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: Container(
                width: double.infinity,
                margin: EdgeInsets.all(compact ? 10 : 16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white10),
                ),
                clipBehavior: Clip.antiAlias,
                child: _buildPreview(state),
              ),
            ),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: _panelExpanded ? height * 0.60 : 100),
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: _buildControlsPanel(state, compact: compact),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlsPanel(BgRemoverImageState state, {required bool compact}) {
    final isProcessing = state.status == BgRemoverProcessingStatus.generatingMask ||
        state.status == BgRemoverProcessingStatus.applyingMask ||
        state.status == BgRemoverProcessingStatus.loadingModel;
    final hasProcessed = state.processedImage != null;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(14, compact ? 10 : 12, 14, 14),
      decoration: const BoxDecoration(
        color: Color(0xFF15151D),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  _panelExpanded ? 'Tools panel' : 'Open tools',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  _panelExpanded ? Icons.expand_more : Icons.expand_less,
                  color: Colors.white70,
                ),
                onPressed: () => setState(() => _panelExpanded = !_panelExpanded),
              ),
            ],
          ),
          _buildTopQuickStrip(hasProcessed: hasProcessed, isProcessing: isProcessing),
          if (_panelExpanded) ...[
            const SizedBox(height: 10),
            if (hasProcessed)
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: _buildActivePanel(state, isProcessing: isProcessing),
              ),
            if (hasProcessed) const SizedBox(height: 12),
            if (state.originalImage != null)
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: (state.status == BgRemoverProcessingStatus.idle ||
                              state.status == BgRemoverProcessingStatus.error ||
                              state.status == BgRemoverProcessingStatus.done) &&
                          !_exportBusy
                      ? _runProcessing
                      : null,
                  icon: isProcessing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : Icon(hasProcessed ? Icons.refresh : Icons.auto_awesome),
                  label: Text(
                    isProcessing
                        ? 'Processing...'
                        : hasProcessed
                            ? 'Reprocess'
                            : 'Remove Background',
                  ),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    backgroundColor: const Color(0xFF6C5CE7),
                  ),
                ),
              ),
            if (state.status == BgRemoverProcessingStatus.error && state.errorMessage != null) ...[
              const SizedBox(height: 10),
              Text(
                state.errorMessage!,
                style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildTopQuickStrip({required bool hasProcessed, required bool isProcessing}) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: [
          _buildQuickChip(
            icon: Icons.compare_arrows,
            active: _showBeforeAfter,
            enabled: hasProcessed && !_brushPanelActive,
            onTap: () => setState(() => _showBeforeAfter = !_showBeforeAfter),
          ),
          _buildQuickChip(
            icon: Icons.wallpaper,
            active: _activePanel == _ControlPanel.background,
            enabled: hasProcessed,
            onTap: () => _selectPanel(_ControlPanel.background),
          ),
          _buildQuickChip(
            icon: Icons.brush,
            active: _activePanel == _ControlPanel.brush,
            enabled: hasProcessed && !isProcessing,
            onTap: () => _selectPanel(_ControlPanel.brush),
          ),
          _buildQuickChip(
            icon: Icons.tune,
            active: _activePanel == _ControlPanel.settings,
            enabled: true,
            onTap: () => _selectPanel(_ControlPanel.settings),
          ),
          _buildQuickChip(
            icon: Icons.ios_share,
            active: _activePanel == _ControlPanel.export,
            enabled: hasProcessed,
            onTap: () => _selectPanel(_ControlPanel.export),
          ),
          _buildQuickChip(
            icon: Icons.lightbulb_outline,
            active: _activePanel == _ControlPanel.tips,
            enabled: true,
            onTap: () => _selectPanel(_ControlPanel.tips),
          ),
          _buildQuickChip(
            icon: Icons.filter_drama,
            active: _addShadow,
            enabled: !isProcessing,
            onTap: () => setState(() => _addShadow = !_addShadow),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickChip({
    required IconData icon,
    required bool active,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Opacity(
        opacity: enabled ? 1 : 0.4,
        child: Material(
          color: active ? const Color(0xFF6C5CE7) : const Color(0xFF24242E),
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: enabled ? onTap : null,
            child: Container(
              width: 42,
              height: 40,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: active ? const Color(0xFF8E7CF0) : Colors.white10),
              ),
              child: Icon(icon, size: 18, color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _selectPanel(_ControlPanel panel) async {
    setState(() {
      _activePanel = panel;
      if (panel == _ControlPanel.brush) {
        _showBeforeAfter = false;
      } else {
        _canvasMode = _ManualCanvasMode.navigate;
        _clearPendingBrushStroke();
      }
    });
    if (panel == _ControlPanel.export) {
      await _prepareExportPreviewSizes();
    }
  }

  Widget _buildActivePanel(BgRemoverImageState state, {required bool isProcessing}) {
    switch (_activePanel) {
      case _ControlPanel.background:
        return KeyedSubtree(
          key: const ValueKey('background'),
          child: _buildBackgroundPanel(state),
        );
      case _ControlPanel.brush:
        return KeyedSubtree(
          key: const ValueKey('brush'),
          child: _buildBrushPanel(state, isProcessing: isProcessing),
        );
      case _ControlPanel.settings:
        return KeyedSubtree(
          key: const ValueKey('settings'),
          child: _buildSettingsCard(isProcessing: isProcessing),
        );
      case _ControlPanel.export:
        return KeyedSubtree(
          key: const ValueKey('export'),
          child: _buildExportPanel(),
        );
      case _ControlPanel.tips:
        return const KeyedSubtree(
          key: ValueKey('tips'),
          child: _TipsPanel(),
        );
    }
  }

  Widget _buildBackgroundPanel(BgRemoverImageState state) {
    if (state.maskImage == null) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1B1B25),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: BgRemoverBackgroundPicker(
        onColorSelected: (color) => ref.read(bgRemoverImageProvider.notifier).applyBackground(color),
        onImageSelected: (bytes) => ref.read(bgRemoverImageProvider.notifier).applyBackgroundImage(bytes),
        onBlurSelected: (radius) => ref.read(bgRemoverImageProvider.notifier).applyBlurBackground(radius),
        onReset: () => ref.read(bgRemoverImageProvider.notifier).clearPreviewBackground(),
      ),
    );
  }

  Widget _buildBrushPanel(BgRemoverImageState state, {required bool isProcessing}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF211C2F),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF6C5CE7).withOpacity(0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Brush tools', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 10),
          Row(
            children: [
              _buildIconModeButton(
                icon: Icons.pan_tool_alt,
                active: _canvasMode == _ManualCanvasMode.navigate,
                accent: const Color(0xFF74B9FF),
                onTap: isProcessing
                    ? null
                    : () => setState(() {
                          _canvasMode = _ManualCanvasMode.navigate;
                          _clearPendingBrushStroke();
                        }),
              ),
              const SizedBox(width: 8),
              _buildIconModeButton(
                icon: Icons.edit,
                active: _canvasMode == _ManualCanvasMode.paint,
                accent: const Color(0xFFFFD166),
                onTap: isProcessing ? null : () => setState(() => _canvasMode = _ManualCanvasMode.paint),
              ),
              const SizedBox(width: 12),
              _buildIconModeButton(
                icon: Icons.add_circle_outline,
                active: _brushMode == _ManualBrushMode.restore,
                accent: const Color(0xFF00E5A8),
                onTap: isProcessing ? null : () => setState(() => _brushMode = _ManualBrushMode.restore),
              ),
              const SizedBox(width: 8),
              _buildIconModeButton(
                icon: Icons.remove_circle_outline,
                active: _brushMode == _ManualBrushMode.erase,
                accent: const Color(0xFFFF4D6D),
                onTap: isProcessing ? null : () => setState(() => _brushMode = _ManualBrushMode.erase),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: state.undoCount > 0 && !isProcessing
                      ? () => ref.read(bgRemoverImageProvider.notifier).undoManualBrush()
                      : null,
                  icon: const Icon(Icons.undo, size: 16),
                  label: Text('Undo ${state.undoCount}'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: state.redoCount > 0 && !isProcessing
                      ? () => ref.read(bgRemoverImageProvider.notifier).redoManualBrush()
                      : null,
                  icon: const Icon(Icons.redo, size: 16),
                  label: Text('Redo ${state.redoCount}'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _resetZoom,
                  icon: const Icon(Icons.center_focus_strong, size: 16),
                  label: const Text('Reset'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: isProcessing ? null : _applyAutoFixEdges,
                  icon: const Icon(Icons.auto_fix_high, size: 16),
                  label: const Text('Auto Fix'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Brush size • ${(_brushRadiusRatio * 100).round()}%',
            style: const TextStyle(fontSize: 12, color: Colors.white70),
          ),
          Slider(
            value: _brushRadiusRatio,
            min: 0.01,
            max: 0.10,
            divisions: 18,
            onChanged: isProcessing ? null : (v) => setState(() => _brushRadiusRatio = v),
          ),
        ],
      ),
    );
  }

  Widget _buildIconModeButton({
    required IconData icon,
    required bool active,
    required Color accent,
    required VoidCallback? onTap,
  }) {
    return Material(
      color: active ? accent.withOpacity(0.18) : const Color(0xFF2A2538),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: active ? accent : Colors.white12),
          ),
          child: Icon(icon, color: active ? accent : Colors.white70, size: 22),
        ),
      ),
    );
  }

  Widget _buildSettingsCard({required bool isProcessing}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A22),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Mask refinement', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 10),
          _buildPresetSelector(isProcessing: isProcessing),
          const SizedBox(height: 10),
          _buildSliderRow(
            title: 'Keep details',
            valueText: _sensitivity.toStringAsFixed(2),
            slider: Slider(
              value: _sensitivity,
              min: 0.20,
              max: 0.60,
              divisions: 40,
              onChanged: isProcessing ? null : (v) => setState(() => _sensitivity = v),
            ),
            help: 'Higher removes more background.',
          ),
          _buildSliderRow(
            title: 'Edge softness',
            valueText: _edgeSoftness.toStringAsFixed(2),
            slider: Slider(
              value: _edgeSoftness,
              min: 0.02,
              max: 0.16,
              divisions: 28,
              onChanged: isProcessing ? null : (v) => setState(() => _edgeSoftness = v),
            ),
            help: 'Softens edges naturally.',
          ),
          _buildSliderRow(
            title: 'Expand subject',
            valueText: _edgeExpansion.toString(),
            slider: Slider(
              value: _edgeExpansion.toDouble(),
              min: -2,
              max: 4,
              divisions: 6,
              onChanged: isProcessing ? null : (v) => setState(() => _edgeExpansion = v.round()),
            ),
            help: 'Positive values recover hair or arms.',
          ),
          _buildSliderRow(
            title: 'Detail boost',
            valueText: _detailBoost.toStringAsFixed(2),
            slider: Slider(
              value: _detailBoost,
              min: 0.0,
              max: 0.35,
              divisions: 35,
              onChanged: isProcessing ? null : (v) => setState(() => _detailBoost = v),
            ),
            help: 'Boosts weak mask areas.',
          ),
          if (_addShadow)
            _buildSliderRow(
              title: 'Shadow blur',
              valueText: '$_shadowBlur px',
              slider: Slider(
                value: _shadowBlur.toDouble(),
                min: 4,
                max: 40,
                divisions: 18,
                onChanged: isProcessing ? null : (v) => setState(() => _shadowBlur = v.round()),
              ),
              help: 'Used when shadow is enabled.',
            ),
        ],
      ),
    );
  }

  Widget _buildPresetSelector({required bool isProcessing}) {
    return Row(
      children: [
        Expanded(
          child: _buildPresetChip(
            label: 'Clean',
            selected: _preset == _MaskPreset.clean,
            onTap: isProcessing ? null : () => _applyPreset(_MaskPreset.clean),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildPresetChip(
            label: 'Balanced',
            selected: _preset == _MaskPreset.balanced,
            onTap: isProcessing ? null : () => _applyPreset(_MaskPreset.balanced),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildPresetChip(
            label: 'Detailed',
            selected: _preset == _MaskPreset.detailed,
            onTap: isProcessing ? null : () => _applyPreset(_MaskPreset.detailed),
          ),
        ),
      ],
    );
  }

  Widget _buildPresetChip({
    required String label,
    required bool selected,
    required VoidCallback? onTap,
  }) {
    return Material(
      color: selected ? const Color(0xFF6C5CE7).withOpacity(0.22) : const Color(0xFF25252F),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: selected ? const Color(0xFF6C5CE7) : Colors.white12),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: selected ? Colors.white : Colors.white70,
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _applyPreset(_MaskPreset preset) {
    setState(() {
      _preset = preset;
      switch (preset) {
        case _MaskPreset.clean:
          _sensitivity = 0.46;
          _edgeSoftness = 0.05;
          _edgeExpansion = -1;
          _detailBoost = 0.06;
          break;
        case _MaskPreset.balanced:
          _sensitivity = 0.38;
          _edgeSoftness = 0.06;
          _edgeExpansion = 0;
          _detailBoost = 0.12;
          break;
        case _MaskPreset.detailed:
          _sensitivity = 0.30;
          _edgeSoftness = 0.08;
          _edgeExpansion = 1;
          _detailBoost = 0.20;
          break;
      }
    });
  }

  Widget _buildSliderRow({
    required String title,
    required String valueText,
    required Widget slider,
    required String help,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(title, style: const TextStyle(fontSize: 12, color: Colors.white70)),
            const Spacer(),
            Text(valueText, style: const TextStyle(fontSize: 12, color: Colors.white54)),
          ],
        ),
        slider,
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(help, style: const TextStyle(fontSize: 11, color: Colors.white38)),
        ),
      ],
    );
  }

  Widget _buildExportPanel() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A22),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('Export options', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              ),
              if (_exportPreviewLoading)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Save or share with the best format for WhatsApp, Facebook, shop, passport or document use.',
            style: TextStyle(fontSize: 12, color: Colors.white70, height: 1.35),
          ),
          const SizedBox(height: 10),
          _buildExportTile(
            title: 'PNG transparent',
            subtitle: 'Transparent background',
            preset: _ExportPreset.pngTransparent,
            icon: Icons.layers,
          ),
          _buildExportTile(
            title: 'JPG white background',
            subtitle: 'Document or print ready',
            preset: _ExportPreset.jpgWhite,
            icon: Icons.description_outlined,
          ),
          _buildExportTile(
            title: 'JPG color background',
            subtitle: 'Uses selected color or premium studio background',
            preset: _ExportPreset.jpgColor,
            icon: Icons.palette_outlined,
          ),
          _buildExportTile(
            title: 'HD export',
            subtitle: 'Best quality output',
            preset: _ExportPreset.hd,
            icon: Icons.hd,
          ),
          _buildExportTile(
            title: 'Compressed export',
            subtitle: 'Smaller file for social sharing',
            preset: _ExportPreset.compressed,
            icon: Icons.photo_size_select_small,
          ),
          _buildExportTile(
            title: 'Passport mode',
            subtitle: 'Portrait on 35×45 style canvas',
            preset: _ExportPreset.passport,
            icon: Icons.badge_outlined,
          ),
        ],
      ),
    );
  }

  Widget _buildExportTile({
    required String title,
    required String subtitle,
    required _ExportPreset preset,
    required IconData icon,
  }) {
    final previewText = _exportPreviewSizes[preset] ?? (_exportPreviewLoading ? 'Calculating...' : 'Tap export');
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF24242E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFF6C5CE7).withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 20, color: const Color(0xFFA29BFE)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(subtitle, style: const TextStyle(fontSize: 11.5, color: Colors.white54)),
                const SizedBox(height: 4),
                Text(previewText, style: const TextStyle(fontSize: 11, color: Color(0xFFA29BFE))),
              ],
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: _exportBusy ? null : () => _handleExportAction(preset, share: false),
            icon: const Icon(Icons.download_rounded),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: _exportBusy ? null : () => _handleExportAction(preset, share: true),
            icon: const Icon(Icons.share_outlined),
          ),
        ],
      ),
    );
  }

  Future<void> _prepareExportPreviewSizes() async {
    final state = ref.read(bgRemoverImageProvider);
    if (state.processedImage == null || _exportPreviewLoading) return;

    setState(() => _exportPreviewLoading = true);
    try {
      final Map<_ExportPreset, String> previewMap = {};
      for (final preset in _ExportPreset.values) {
        final result = await compute(BgRemoverImageProcessor.exportRendered, _buildExportArgs(state, preset));
        previewMap[preset] = 'Preview size: ${_formatBytes(result['byteLength'] as int)}';
      }
      if (mounted) {
        setState(() {
          _exportPreviewSizes
            ..clear()
            ..addAll(previewMap);
        });
      }
    } catch (_) {
      // Ignore preview sizing failure and keep panel usable.
    } finally {
      if (mounted) setState(() => _exportPreviewLoading = false);
    }
  }

  String _formatBytes(int value) {
    if (value < 1024) return '$value B';
    if (value < 1024 * 1024) return '${(value / 1024).toStringAsFixed(1)} KB';
    return '${(value / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  Future<void> _showExportOptionsSheet() async {
    await _selectPanel(_ControlPanel.export);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF15151D),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                ),
                Row(
                  children: [
                    const Expanded(
                      child: Text('Ultra Premium Export',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
                    ),
                    if (_exportPreviewLoading)
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'Choose the right format and share directly. File-size previews help you know what is best for WhatsApp, Facebook, store or passport use.',
                  style: TextStyle(fontSize: 12, color: Colors.white70, height: 1.35),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: MediaQuery.of(context).size.height * 0.70,
                  child: SingleChildScrollView(
                    child: _buildExportPanel(),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _handleExportAction(_ExportPreset preset, {required bool share}) async {
    final state = ref.read(bgRemoverImageProvider);
    final subject = state.foregroundImage ?? state.processedImage;
    if (subject == null) return;

    setState(() => _exportBusy = true);
    try {
      final export = await compute(BgRemoverImageProcessor.exportRendered, _buildExportArgs(state, preset));
      final bytes = export['bytes'] as Uint8List;
      final extension = export['extension'] as String;
      final mimeType = export['mimeType'] as String;
      final fileName = _makeExportFileName(preset, extension);

      bool success;
      if (share) {
        success = await BgRemoverGalleryService.shareImage(
          bytes,
          fileName: fileName,
          mimeType: mimeType,
          text: 'Exported from Bg Remover Pro',
        );
      } else {
        success = await BgRemoverGalleryService.saveToGallery(
          bytes,
          name: fileName.replaceAll('.$extension', ''),
          extension: extension,
        );
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success
              ? (share ? '✅ Share opened' : '✅ Saved to gallery')
              : '❌ Export failed'),
          backgroundColor: success ? const Color(0xFF00B894) : Colors.redAccent,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Export error: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) setState(() => _exportBusy = false);
    }
  }

  String _makeExportFileName(_ExportPreset preset, String extension) {
    final now = DateTime.now();
    final stamp =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
    return 'bgremover_${preset.name}_$stamp.$extension';
  }

  Map<String, dynamic> _buildExportArgs(BgRemoverImageState state, _ExportPreset preset) {
    final subject = state.foregroundImage ?? state.processedImage!;
    switch (preset) {
      case _ExportPreset.pngTransparent:
        return {
          'subjectBytes': subject,
          'format': 'png',
        };
      case _ExportPreset.jpgWhite:
        return {
          'subjectBytes': subject,
          'format': 'jpg',
          'quality': 95,
          'fallbackColor': 0xFFFFFFFF,
        };
      case _ExportPreset.jpgColor:
        return {
          'subjectBytes': subject,
          'format': 'jpg',
          'quality': 95,
          'backgroundColor': state.backgroundColor,
          'backgroundImageBytes': state.backgroundImage,
          'fallbackColor': 0xFFEAF0FF,
        };
      case _ExportPreset.hd:
        return {
          'subjectBytes': subject,
          'format': state.backgroundColor == null && state.backgroundImage == null ? 'png' : 'jpg',
          'quality': 100,
          'backgroundColor': state.backgroundColor,
          'backgroundImageBytes': state.backgroundImage,
        };
      case _ExportPreset.compressed:
        return {
          'subjectBytes': subject,
          'format': 'jpg',
          'quality': 72,
          'maxDimension': 1280,
          'backgroundColor': state.backgroundColor,
          'backgroundImageBytes': state.backgroundImage,
          'fallbackColor': 0xFFFFFFFF,
        };
      case _ExportPreset.passport:
        return {
          'subjectBytes': subject,
          'format': 'jpg',
          'quality': 96,
          'canvasWidth': 1050,
          'canvasHeight': 1350,
          'subjectScale': 0.88,
          'alignY': 0.12,
          'backgroundColor': state.backgroundColor ?? 0xFFE8F1FF,
          'backgroundImageBytes': state.backgroundImage,
          'fallbackColor': 0xFFE8F1FF,
        };
    }
  }

  Widget _buildPreview(BgRemoverImageState state) {
    final isLoading = state.status == BgRemoverProcessingStatus.generatingMask ||
        state.status == BgRemoverProcessingStatus.applyingMask ||
        state.status == BgRemoverProcessingStatus.loadingModel;

    if (isLoading && state.processedImage == null && state.originalImage == null) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('AI is working its magic...', style: TextStyle(color: Colors.white70)),
          ],
        ),
      );
    }

    if (_brushPanelActive && state.processedImage != null && state.originalImage != null) {
      return _buildManualBrushPreview(state, isLoading: isLoading);
    }

    if (_showBeforeAfter && state.originalImage != null && state.processedImage != null) {
      return BgRemoverBeforeAfterSlider(
        beforeImage: state.originalImage!,
        afterImage: state.processedImage!,
        afterBackgroundColor: state.backgroundColor,
        afterBackgroundImage: state.backgroundImage,
      );
    }

    if (state.processedImage != null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          _buildProcessedPreview(state),
          if (isLoading) _buildOverlayLoader(),
        ],
      );
    }

    if (state.originalImage != null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          _buildCheckerboard(
            child: Center(
              child: Image.memory(state.originalImage!, fit: BoxFit.contain, gaplessPlayback: true),
            ),
          ),
          if (state.status == BgRemoverProcessingStatus.picking) _buildOverlayLoader(),
        ],
      );
    }

    return const Center(child: Text('No image'));
  }

  Widget _buildManualBrushPreview(BgRemoverImageState state, {required bool isLoading}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final box = Size(constraints.maxWidth, constraints.maxHeight);
        final imageRect = _imageRectForContain(box, state.previewAspectRatio);
        final canvasSize = Size(imageRect.width, imageRect.height);
        final displayRadius = (canvasSize.shortestSide * _brushRadiusRatio).clamp(6.0, 90.0).toDouble();
        final paintEnabled = _canvasMode == _ManualCanvasMode.paint && !isLoading;

        return Stack(
          fit: StackFit.expand,
          children: [
            Container(color: const Color(0xFF101018)),
            Center(
              child: InteractiveViewer(
                transformationController: _transformationController,
                minScale: 1.0,
                maxScale: 6.0,
                clipBehavior: Clip.none,
                boundaryMargin: const EdgeInsets.all(180),
                panEnabled: true,
                scaleEnabled: true,
                child: SizedBox(
                  width: canvasSize.width,
                  height: canvasSize.height,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _buildProcessedPreviewCanvas(state),
                      IgnorePointer(
                        ignoring: !paintEnabled,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onPanStart: (details) => _recordBrushPoint(details.localPosition, canvasSize),
                          onPanUpdate: (details) => _recordBrushPoint(details.localPosition, canvasSize),
                          onPanEnd: (_) => _commitBrushStroke(),
                          onPanCancel: _clearPendingBrushStroke,
                          child: CustomPaint(
                            painter: _BrushStrokePainter(
                              points: List<Offset>.from(_pendingDisplayPoints),
                              radius: displayRadius,
                              restore: _brushMode == _ManualBrushMode.restore,
                              cursorPosition: paintEnabled ? _brushCursorPosition : null,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              top: 10,
              left: 10,
              child: _buildIconBadge(
                _canvasMode == _ManualCanvasMode.navigate ? Icons.pan_tool_alt : Icons.edit,
                _canvasMode == _ManualCanvasMode.navigate ? const Color(0xFF74B9FF) : const Color(0xFFFFD166),
              ),
            ),
            Positioned(
              top: 10,
              right: 10,
              child: _buildIconBadge(
                _brushMode == _ManualBrushMode.restore
                    ? Icons.add_circle_outline
                    : Icons.remove_circle_outline,
                _brushMode == _ManualBrushMode.restore ? const Color(0xFF00E5A8) : const Color(0xFFFF4D6D),
              ),
            ),
            if (isLoading) _buildOverlayLoader(),
          ],
        );
      },
    );
  }

  Widget _buildIconBadge(IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.55),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white24),
      ),
      child: Icon(icon, size: 18, color: color),
    );
  }

  Widget _buildOverlayLoader() {
    return Container(
      color: Colors.black.withOpacity(0.18),
      child: const Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      ),
    );
  }

  Widget _buildProcessedPreviewCanvas(BgRemoverImageState state) {
    final foreground = Image.memory(state.processedImage!, fit: BoxFit.fill, gaplessPlayback: true);

    if (state.backgroundColor != null) {
      return Container(color: Color(state.backgroundColor!), child: foreground);
    }

    if (state.backgroundImage != null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Image.memory(state.backgroundImage!, fit: BoxFit.cover, gaplessPlayback: true),
          foreground,
        ],
      );
    }

    return _buildCheckerboard(child: foreground);
  }

  Rect _imageRectForContain(Size box, double aspectRatio) {
    final ratio = aspectRatio <= 0 ? 1.0 : aspectRatio;
    final boxRatio = box.width / box.height;
    double width;
    double height;
    if (boxRatio > ratio) {
      height = box.height;
      width = height * ratio;
    } else {
      width = box.width;
      height = width / ratio;
    }
    final left = (box.width - width) / 2;
    final top = (box.height - height) / 2;
    return Rect.fromLTWH(left, top, width, height);
  }

  void _recordBrushPoint(Offset localPosition, Size canvasSize) {
    if (_canvasMode != _ManualCanvasMode.paint) return;
    if (localPosition.dx < 0 ||
        localPosition.dy < 0 ||
        localPosition.dx > canvasSize.width ||
        localPosition.dy > canvasSize.height) {
      return;
    }

    final nx = (localPosition.dx / canvasSize.width).clamp(0.0, 1.0).toDouble();
    final ny = (localPosition.dy / canvasSize.height).clamp(0.0, 1.0).toDouble();

    setState(() {
      _pendingBrushPoints.add({'x': nx, 'y': ny});
      _pendingDisplayPoints.add(localPosition);
      _brushCursorPosition = localPosition;
    });
  }

  Future<void> _commitBrushStroke() async {
    if (_canvasMode != _ManualCanvasMode.paint) return;
    if (_pendingBrushPoints.isEmpty) return;

    final points = List<Map<String, double>>.from(_pendingBrushPoints);
    _clearPendingBrushStroke();

    await ref.read(bgRemoverImageProvider.notifier).applyManualBrushStroke(
          points: points,
          brushRadiusRatio: _brushRadiusRatio,
          restore: _brushMode == _ManualBrushMode.restore,
          addShadow: _addShadow,
          shadowBlur: _shadowBlur,
        );
  }

  void _clearPendingBrushStroke() {
    if (_pendingBrushPoints.isEmpty && _pendingDisplayPoints.isEmpty && _brushCursorPosition == null) {
      return;
    }
    setState(() {
      _pendingBrushPoints.clear();
      _pendingDisplayPoints.clear();
      _brushCursorPosition = null;
    });
  }

  Widget _buildProcessedPreview(BgRemoverImageState state) {
    final foreground = Center(
      child: Image.memory(state.processedImage!, fit: BoxFit.contain, gaplessPlayback: true),
    );

    if (state.backgroundColor != null) {
      return Container(color: Color(state.backgroundColor!), child: foreground);
    }
    if (state.backgroundImage != null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Image.memory(state.backgroundImage!, fit: BoxFit.cover, gaplessPlayback: true),
          foreground,
        ],
      );
    }
    return _buildCheckerboard(child: foreground);
  }

  Widget _buildCheckerboard({required Widget child}) {
    return Container(
      color: const Color(0xFF1A1A22),
      child: CustomPaint(
        painter: _CheckerPainter(),
        child: SizedBox.expand(child: child),
      ),
    );
  }

  void _resetZoom() {
    _transformationController.value = Matrix4.identity();
  }

  Future<void> _applyAutoFixEdges() async {
    setState(() {
      _edgeSoftness = (_edgeSoftness + 0.01).clamp(0.02, 0.16);
      if (_brushMode == _ManualBrushMode.erase) {
        _sensitivity = (_sensitivity + 0.03).clamp(0.20, 0.60);
      } else {
        _detailBoost = (_detailBoost + 0.03).clamp(0.0, 0.35);
      }
    });
    await _runProcessing();
  }

  Future<void> _runProcessing() async {
    _clearPendingBrushStroke();
    _resetZoom();
    _canvasMode = _ManualCanvasMode.navigate;
    await ref.read(bgRemoverImageProvider.notifier).processImage(
          sensitivity: _sensitivity,
          edgeSoftness: _edgeSoftness,
          edgeExpansion: _edgeExpansion,
          detailBoost: _detailBoost,
          addShadow: _addShadow,
          shadowBlur: _shadowBlur,
        );
    if (mounted) setState(() {});
  }
}

class _TipsPanel extends StatelessWidget {
  const _TipsPanel();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF17212E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Important tips', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          SizedBox(height: 8),
          _TipBullet('Use one tool panel at a time to keep the screen clean and avoid too much scrolling.'),
          _TipBullet('Brush panel lets you zoom first, then paint only when the edit icon is active.'),
          _TipBullet('Compare mode now keeps before and after aligned with the same framing.'),
          _TipBullet('Export panel shows file-size previews and offers premium options including passport mode.'),
        ],
      ),
    );
  }
}

class _TipBullet extends StatelessWidget {
  final String text;
  const _TipBullet(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 3),
            child: Icon(Icons.circle, size: 7, color: Color(0xFFFFD166)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 12, color: Colors.white70, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}

class _BrushStrokePainter extends CustomPainter {
  final List<Offset> points;
  final double radius;
  final bool restore;
  final Offset? cursorPosition;

  _BrushStrokePainter({
    required this.points,
    required this.radius,
    required this.restore,
    this.cursorPosition,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final fillPaint = Paint()
      ..color = (restore ? const Color(0xFF00E5A8) : const Color(0xFFFF4D6D)).withOpacity(0.22)
      ..style = PaintingStyle.fill;
    final borderPaint = Paint()
      ..color = restore ? const Color(0xFF00E5A8) : const Color(0xFFFF4D6D)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    if (points.isNotEmpty) {
      for (final point in points) {
        canvas.drawCircle(point, radius, fillPaint);
        canvas.drawCircle(point, radius, borderPaint);
      }
      if (points.length > 1) {
        final linePaint = Paint()
          ..color = (restore ? const Color(0xFF00E5A8) : const Color(0xFFFF4D6D)).withOpacity(0.8)
          ..strokeWidth = radius * 1.15
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..style = PaintingStyle.stroke;
        final path = Path()..moveTo(points.first.dx, points.first.dy);
        for (final point in points.skip(1)) {
          path.lineTo(point.dx, point.dy);
        }
        canvas.drawPath(path, linePaint);
      }
    }

    if (cursorPosition != null) {
      final cursorFill = Paint()
        ..color = Colors.white.withOpacity(0.08)
        ..style = PaintingStyle.fill;
      final cursorBorder = Paint()
        ..color = restore ? const Color(0xFF00E5A8) : const Color(0xFFFF4D6D)
        ..strokeWidth = 1.8
        ..style = PaintingStyle.stroke;
      canvas.drawCircle(cursorPosition!, radius, cursorFill);
      canvas.drawCircle(cursorPosition!, radius, cursorBorder);
    }
  }

  @override
  bool shouldRepaint(covariant _BrushStrokePainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.radius != radius ||
        oldDelegate.restore != restore ||
        oldDelegate.cursorPosition != cursorPosition;
  }
}

class _CheckerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const squareSize = 16.0;
    final lightPaint = Paint()..color = const Color(0xFF2A2A35);
    final darkPaint = Paint()..color = const Color(0xFF1F1F28);
    for (double y = 0; y < size.height; y += squareSize) {
      for (double x = 0; x < size.width; x += squareSize) {
        final isLight = ((x ~/ squareSize) + (y ~/ squareSize)) % 2 == 0;
        canvas.drawRect(
          Rect.fromLTWH(x, y, squareSize, squareSize),
          isLight ? lightPaint : darkPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
