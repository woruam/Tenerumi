import 'package:xournalpp/src/app_appearance.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:xournalpp/generated/l10n.dart';
import 'package:xournalpp/pages/WorkspacePage.dart';
import 'package:xournalpp/pages/OpenPage.dart';
import 'package:xournalpp/src/XppFile.dart';

class MainDrawer extends StatefulWidget {
  @override
  _MainDrawerState createState() => _MainDrawerState();
}

class _MainDrawerState extends State<MainDrawer> {
  PackageInfo? info;

  @override
  void initState() {
    PackageInfo.fromPlatform()
        .then((value) => setState(() => info = value))
        .catchError((e) {});
    super.initState();
  }

  void _launch(String url) {
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Hero(
      tag: MainDrawer,
      child: Drawer(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          mainAxisSize: MainAxisSize.min,
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Semantics(
                  // unnecessary information for screen readers etc.
                  hidden: true,
                  child: UserAccountsDrawerHeader(
                    accountName: Text(
                      'Xournal++',
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                    ),
                    accountEmail: Text(
                      S.of(context).mobileEditionUnofficial,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    currentAccountPicture: Image.asset('assets/xournalpp.png'),
                    decoration: BoxDecoration(
                      color: AppAppearance.panel,
                      border: const Border(
                        bottom: BorderSide(color: AppAppearance.border),
                      ),
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.home),
                  title: Text(S.of(context).home),
                  onTap: () => Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (context) => OpenPage()),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.folder),
                  title: Text(S.of(context).open),
                  onTap: () => XppFile.openAndEdit(context: context),
                ),
                ListTile(
                  leading: const Icon(Icons.insert_drive_file),
                  title: Text(S.of(context).newFile),
                  onTap: () => Navigator.of(context).pushReplacement(
                    MaterialPageRoute(
                      builder: (context) => WorkspacePage(
                        initialFile: XppFile.empty(background: Colors.white),
                      ),
                    ),
                  ),
                ),
                const Divider(),
              ],
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.info),
                  title: Text(S.of(context).about),
                  onTap: () => showAboutDialog(
                    context: context,
                    applicationName: S.of(context).aboutXournalMobileEdition,
                    applicationVersion:
                        'Version ${info?.version} build ${info?.buildNumber}',
                    applicationIcon: Image.asset(
                      'assets/xournalpp.png',
                      scale: 8,
                    ),
                    applicationLegalese:
                        'Community revival of Xournal++ Mobile',
                    children: [
                      Image.asset('assets/feature-banner.png', scale: 2),
                      OutlinedButton(
                        onPressed: () =>
                            _launch('https://github.com/xournalpp/xournalpp'),
                        child: Text(S.of(context).aboutXournal),
                      ),
                      OutlinedButton(
                        onPressed: () => _launch(
                          'https://github.com/xournalpp/xournalpp_mobile',
                        ),
                        child: Text(S.of(context).sourceCode),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
