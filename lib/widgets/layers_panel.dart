import 'package:flutter/material.dart';
import 'package:xournalpp/controllers/canvas_controller.dart';

Future<void> showLayersPanel(
  BuildContext context,
  CanvasController controller,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  builder: (_) => SizedBox(
    height: MediaQuery.sizeOf(context).height * .65,
    child: LayersPanel(controller: controller),
  ),
);

class LayersPanel extends StatelessWidget {
  final CanvasController controller;
  const LayersPanel({super.key, required this.controller});
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final page = controller.activePageIndex.clamp(
        0,
        controller.file!.pages!.length - 1,
      );
      final layers = controller.file!.pages![page].layers!;
      return SafeArea(
        child: SizedBox(
          child: Column(
            children: [
              ListTile(
                title: Text('Livelli · pagina ${page + 1}'),
                subtitle: const Text(
                  'Il livello in cima copre quelli sottostanti.',
                ),
                trailing: IconButton(
                  tooltip: 'Aggiungi livello',
                  icon: const Icon(Icons.add),
                  onPressed: () => controller.addLayer(page),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: layers.length,
                  itemBuilder: (context, row) {
                    final index = layers.length - 1 - row;
                    final layer = layers[index];
                    return ListTile(
                      selected: controller.activeLayerIndex(page) == index,
                      leading: IconButton(
                        tooltip: layer.visible ? 'Nascondi' : 'Mostra',
                        icon: Icon(
                          layer.visible
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                        onPressed: () => controller.updateLayer(
                          page,
                          index,
                          visible: !layer.visible,
                        ),
                      ),
                      title: Tooltip(
                        message: layer.name,
                        child: Text(
                          layer.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                      selectedTileColor: Theme.of(context).colorScheme.primary
                          .withValues(alpha: .08),
                      onTap: () => controller.selectLayer(page, index),
                      subtitle: Text(
                        layer.locked
                            ? 'Bloccato'
                            : '${layer.content?.length ?? 0} elementi',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: layer.locked ? 'Sblocca' : 'Blocca',
                            icon: Icon(
                              layer.locked
                                  ? Icons.lock_outline
                                  : Icons.lock_open,
                            ),
                            onPressed: () => controller.updateLayer(
                              page,
                              index,
                              locked: !layer.locked,
                            ),
                          ),
                          PopupMenuButton<String>(
                            onSelected: (action) async {
                              if (action == 'up') {
                                controller.moveLayer(page, index, index + 1);
                              }
                              if (action == 'down') {
                                controller.moveLayer(page, index, index - 1);
                              }
                              if (action == 'delete') {
                                final confirmed = await showDialog<bool>(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: const Text('Elimina livello'),
                                    content: Text(
                                      'Eliminare “${layer.name}” e tutti i suoi elementi?',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(context, false),
                                        child: const Text('Annulla'),
                                      ),
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(context, true),
                                        child: const Text('Elimina'),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirmed == true &&
                                    controller.acceptsPluginEdits) {
                                  controller.deleteLayer(page, index);
                                }
                              }
                              if (action == 'rename') {
                                if (!context.mounted ||
                                    !controller.acceptsPluginEdits) {
                                  return;
                                }
                                final input = TextEditingController(
                                  text: layer.name,
                                );
                                final name = await showDialog<String>(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: const Text('Nome livello'),
                                    content: TextField(
                                      controller: input,
                                      autofocus: true,
                                      maxLength: 80,
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(context),
                                        child: const Text('Annulla'),
                                      ),
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(context, input.text),
                                        child: const Text('Salva'),
                                      ),
                                    ],
                                  ),
                                );
                                if (name != null &&
                                    controller.acceptsPluginEdits) {
                                  controller.updateLayer(
                                    page,
                                    index,
                                    name: name,
                                  );
                                }
                                // The closing route may still paint its TextField for one frame.
                                WidgetsBinding.instance.addPostFrameCallback(
                                  (_) => input.dispose(),
                                );
                              }
                            },
                            itemBuilder: (_) => [
                              const PopupMenuItem(
                                value: 'rename',
                                child: Text('Rinomina'),
                              ),
                              PopupMenuItem(
                                value: 'up',
                                enabled: index < layers.length - 1,
                                child: const Text('Porta avanti'),
                              ),
                              PopupMenuItem(
                                value: 'down',
                                enabled: index > 0,
                                child: const Text('Porta indietro'),
                              ),
                              PopupMenuItem(
                                value: 'delete',
                                enabled: layers.length > 1,
                                child: const Text('Elimina'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
