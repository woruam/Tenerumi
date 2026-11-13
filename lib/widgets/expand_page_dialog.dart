import 'package:flutter/material.dart';
import 'package:xournalpp/controllers/canvas_controller.dart';
import 'package:xournalpp/src/XppPageSize.dart';
import 'package:xournalpp/src/app_appearance.dart';

/// Mostra il dialogo modale per espandere rapidamente il foglio (in basso e/o a destra)
/// oppure per specificare dimensioni personalizzate in pt o mm.
Future<void> showExpandPageDialog(
  BuildContext context,
  CanvasController controller, [
  int? pageIndex,
]) async {
  final int targetIndex = pageIndex ?? controller.activePageIndex;
  if (controller.file?.pages == null ||
      targetIndex < 0 ||
      targetIndex >= controller.file!.pages!.length) {
    return;
  }

  await showDialog<void>(
    context: context,
    builder: (ctx) => _ExpandPageDialog(
      controller: controller,
      pageIndex: targetIndex,
    ),
  );
}

class _ExpandPageDialog extends StatefulWidget {
  final CanvasController controller;
  final int pageIndex;

  const _ExpandPageDialog({
    required this.controller,
    required this.pageIndex,
  });

  @override
  State<_ExpandPageDialog> createState() => _ExpandPageDialogState();
}

class _ExpandPageDialogState extends State<_ExpandPageDialog> {
  static const double _ptToMm = 0.352778;
  static const double _mmToPt = 1 / _ptToMm;

  late TextEditingController _widthController;
  late TextEditingController _heightController;
  bool _useMm = false;

  late double _currentWidth;
  late double _currentHeight;

  @override
  void initState() {
    super.initState();
    final page = widget.controller.file!.pages![widget.pageIndex];
    final size = page.pageSize ?? XppPageSize.a4;
    _currentWidth = size.width;
    _currentHeight = size.height;
    _initTextControllers();
  }

  void _initTextControllers() {
    final w = _useMm ? _currentWidth * _ptToMm : _currentWidth;
    final h = _useMm ? _currentHeight * _ptToMm : _currentHeight;
    _widthController = TextEditingController(text: w.toStringAsFixed(1));
    _heightController = TextEditingController(text: h.toStringAsFixed(1));
  }

  @override
  void dispose() {
    _widthController.dispose();
    _heightController.dispose();
    super.dispose();
  }

  void _applyQuickExpand({double deltaWidth = 0.0, double deltaHeight = 0.0}) {
    widget.controller.expandPage(
      widget.pageIndex,
      deltaWidth: deltaWidth,
      deltaHeight: deltaHeight,
    );
    Navigator.of(context).pop();
    _showFeedbackSnackBar();
  }

  void _applyCustomDimensions() {
    final rawW = double.tryParse(_widthController.text.replaceAll(',', '.'));
    final rawH = double.tryParse(_heightController.text.replaceAll(',', '.'));
    if (rawW == null || rawH == null || rawW <= 10 || rawH <= 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Inserisci dimensioni valide (superiori a 10).')),
      );
      return;
    }

    final double widthPt = _useMm ? rawW * _mmToPt : rawW;
    final double heightPt = _useMm ? rawH * _mmToPt : rawH;

    widget.controller.resizePage(
      widget.pageIndex,
      width: widthPt,
      height: heightPt,
    );
    Navigator.of(context).pop();
    _showFeedbackSnackBar();
  }

  void _showFeedbackSnackBar() {
    final page = widget.controller.file!.pages![widget.pageIndex];
    final size = page.pageSize ?? XppPageSize.a4;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Foglio ${widget.pageIndex + 1} ridimensionato a '
          '${size.width.toStringAsFixed(0)} × ${size.height.toStringAsFixed(0)} pt '
          '(${(size.width * _ptToMm).toStringAsFixed(0)} × ${(size.height * _ptToMm).toStringAsFixed(0)} mm)',
        ),
        action: SnackBarAction(
          label: 'Annulla',
          onPressed: widget.controller.undo,
        ),
      ),
    );
  }

  void _setPreset(double widthPt, double heightPt) {
    setState(() {
      _currentWidth = widthPt;
      _currentHeight = heightPt;
      final w = _useMm ? _currentWidth * _ptToMm : _currentWidth;
      final h = _useMm ? _currentHeight * _ptToMm : _currentHeight;
      _widthController.text = w.toStringAsFixed(1);
      _heightController.text = h.toStringAsFixed(1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final int totalPages = widget.controller.file?.pages?.length ?? 1;

    return AlertDialog(
      shape: AppAppearance.panelShape,
      title: Row(
        children: [
          Icon(Icons.aspect_ratio_outlined, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Espandi Pagina (${widget.pageIndex + 1} di $totalPages)',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Aggiungi spazio al foglio per continuare a scrivere senza cambiare pagina, '
                'oppure imposta dimensioni personalizzate.',
                style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey[400]),
              ),
              const SizedBox(height: 16),

              // --- AZIONI RAPIDE ---
              Text(
                'Espansione Rapida',
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.south, size: 18),
                    label: const Text('In basso (+300 pt)'),
                    onPressed: () => _applyQuickExpand(deltaHeight: 300),
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.east, size: 18),
                    label: const Text('A destra (+300 pt)'),
                    onPressed: () => _applyQuickExpand(deltaWidth: 300),
                  ),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.open_in_full, size: 18),
                    label: const Text('Entrambi (+300 pt)'),
                    onPressed: () => _applyQuickExpand(deltaWidth: 300, deltaHeight: 300),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  ActionChip(
                    avatar: const Icon(Icons.add, size: 16),
                    label: const Text('+25% Altezza'),
                    onPressed: () => _applyQuickExpand(deltaHeight: _currentHeight * 0.25),
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.add, size: 16),
                    label: const Text('+50% Altezza'),
                    onPressed: () => _applyQuickExpand(deltaHeight: _currentHeight * 0.50),
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.add, size: 16),
                    label: const Text('+25% Larghezza'),
                    onPressed: () => _applyQuickExpand(deltaWidth: _currentWidth * 0.25),
                  ),
                ],
              ),

              const Divider(height: 32),

              // --- DIMENSIONI PERSONALIZZATE ---
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 4,
                children: [
                  Text(
                    'Dimensioni Personalizzate',
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('pt', style: TextStyle(fontWeight: !_useMm ? FontWeight.bold : FontWeight.normal)),
                      Switch(
                        value: _useMm,
                        onChanged: (val) {
                          setState(() {
                            _useMm = val;
                            _initTextControllers();
                          });
                        },
                      ),
                      Text('mm', style: TextStyle(fontWeight: _useMm ? FontWeight.bold : FontWeight.normal)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),

              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _widthController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: 'Larghezza (${_useMm ? "mm" : "pt"})',
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _heightController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: 'Altezza (${_useMm ? "mm" : "pt"})',
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Preset standard
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 6,
                runSpacing: 4,
                children: [
                  Text('Preset:', style: theme.textTheme.bodySmall),
                  ActionChip(
                    label: const Text('A4'),
                    onPressed: () => _setPreset(595.28, 841.89),
                  ),
                  ActionChip(
                    label: const Text('A3'),
                    onPressed: () => _setPreset(841.89, 1190.55),
                  ),
                  ActionChip(
                    label: const Text('Letter'),
                    onPressed: () => _setPreset(612.0, 792.0),
                  ),
                  ActionChip(
                    label: const Text('Inverti L/A'),
                    onPressed: () => _setPreset(_currentHeight, _currentWidth),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Chiudi'),
        ),
        FilledButton(
          onPressed: _applyCustomDimensions,
          child: const Text('Applica Dimensioni'),
        ),
      ],
    );
  }
}
