import 'package:xournalpp/widgets/app_info_dialog.dart';
import 'package:xournalpp/src/app_appearance.dart';
import 'package:flutter/material.dart';
import 'package:xournalpp/generated/l10n.dart';
import 'package:xournalpp/pages/WorkspacePage.dart';
import 'package:xournalpp/pages/OpenPage.dart';
import 'package:xournalpp/src/XppFile.dart';

class MainDrawer extends StatefulWidget {
  @override
  _MainDrawerState createState() => _MainDrawerState();
}

class _MainDrawerState extends State<MainDrawer> {
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
                      'OSI',
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
                  onTap: () => showOsiAppInfo(context),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
