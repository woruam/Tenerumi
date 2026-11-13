import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:xournalpp/src/app_appearance.dart';

/// Apre direttamente un URL o termine di ricerca all'interno del browser in-app (Custom Tabs/InAppWebView).
Future<bool> launchInAppWeb(String input) async {
  final trimmed = input.trim();
  if (trimmed.isEmpty) return false;

  Uri uri;
  if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
    uri = Uri.parse(trimmed);
  } else if (trimmed.contains('.') && !trimmed.contains(' ')) {
    // Probabile dominio web digitato senza schema (es: wikipedia.org)
    uri = Uri.parse('https://$trimmed');
  } else {
    // Termine di ricerca -> query Google
    uri = Uri.parse('https://www.google.com/search?q=${Uri.encodeComponent(trimmed)}');
  }

  try {
    return await launchUrl(
      uri,
      mode: LaunchMode.inAppWebView,
    );
  } catch (_) {
    // Fallback su modalità di default della piattaforma
    try {
      return await launchUrl(uri, mode: LaunchMode.platformDefault);
    } catch (_) {
      return false;
    }
  }
}

/// Mostra un dialogo di ricerca rapida per consultare il web senza uscire dall'app.
Future<void> showInAppBrowserDialog(BuildContext context, [String? initialQuery]) async {
  await showDialog<void>(
    context: context,
    builder: (ctx) => _InAppBrowserDialog(initialQuery: initialQuery),
  );
}

class _InAppBrowserDialog extends StatefulWidget {
  final String? initialQuery;
  const _InAppBrowserDialog({this.initialQuery});

  @override
  State<_InAppBrowserDialog> createState() => _InAppBrowserDialogState();
}

class _InAppBrowserDialogState extends State<_InAppBrowserDialog> {
  late final TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialQuery ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _submit([String? overrideText]) async {
    final query = overrideText ?? _controller.text;
    if (query.trim().isEmpty) return;
    Navigator.of(context).pop();

    final success = await launchInAppWeb(query);
    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Impossibile aprire il browser per la ricerca selezionata.'),
        ),
      );
    }
  }

  void _openShortcut(String baseUrl, String query) {
    if (query.trim().isEmpty) {
      _submit(baseUrl);
    } else {
      _submit('$baseUrl${Uri.encodeComponent(query.trim())}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      shape: AppAppearance.panelShape,
      title: Row(
        children: [
          Icon(Icons.travel_explore_outlined, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Ricerca Web & Browser',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Apri una finestra web integrata per effettuare ricerche, consultare fonti e formule senza uscire dall\'applicazione.',
                style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey[400]),
              ),
              const SizedBox(height: 16),

              TextField(
                controller: _controller,
                focusNode: _focusNode,
                autofocus: true,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  hintText: 'Cerca su Google o inserisci un URL…',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _controller.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _controller.clear();
                            setState(() {});
                          },
                        )
                      : null,
                  border: const OutlineInputBorder(),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
                onChanged: (_) => setState(() {}),
              ),

              const SizedBox(height: 16),
              Text(
                'Scorciatoie di ricerca:',
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),

              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ActionChip(
                    avatar: const Icon(Icons.search, size: 16),
                    label: const Text('Google'),
                    onPressed: () => _openShortcut(
                      'https://www.google.com/search?q=',
                      _controller.text,
                    ),
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.menu_book_outlined, size: 16),
                    label: const Text('Wikipedia'),
                    onPressed: () => _openShortcut(
                      'https://it.wikipedia.org/wiki/Special:Search?search=',
                      _controller.text,
                    ),
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.school_outlined, size: 16),
                    label: const Text('Google Scholar'),
                    onPressed: () => _openShortcut(
                      'https://scholar.google.com/scholar?q=',
                      _controller.text,
                    ),
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.calculate_outlined, size: 16),
                    label: const Text('WolframAlpha'),
                    onPressed: () => _openShortcut(
                      'https://www.wolframalpha.com/input?i=',
                      _controller.text,
                    ),
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.language, size: 16),
                    label: const Text('Treccani'),
                    onPressed: () => _openShortcut(
                      'https://www.treccani.it/vocabolario/ricerca/',
                      _controller.text,
                    ),
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
          child: const Text('Annulla'),
        ),
        FilledButton.icon(
          icon: const Icon(Icons.open_in_browser, size: 18),
          label: const Text('Naviga / Cerca'),
          onPressed: () => _submit(),
        ),
      ],
    );
  }
}
