import 'package:xournalpp/l10n/app_localizations.dart';
import 'package:xournalpp/src/app_brand.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

Future<void> showTenerumiAppInfo(BuildContext context) async {
  final l10n = context.l10n;
  String version = '0.5';
  String? build;
  try {
    final info = await PackageInfo.fromPlatform();
    if (info.version.isNotEmpty) {
      version = info.version.endsWith('.0')
          ? info.version.substring(0, info.version.length - 2)
          : info.version;
    }
    build = info.buildNumber;
  } catch (_) {
    // Metadata can be unavailable on unsupported hosts or in previews.
  }
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.appInfoTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Image.asset(AppBrand.logo, width: 80, height: 80, cacheWidth: 240),
            const SizedBox(height: 12),
            Text(
              AppBrand.name,
              style: Theme.of(context).textTheme.displaySmall,
            ),
            const SizedBox(height: 8),
            Text(l10n.versionLabel(version)),
            if (build != null && build.isNotEmpty) Text(l10n.buildLabel(build)),
            const SizedBox(height: 16),
            Text(l10n.devVersion),
            const SizedBox(height: 8),
            Text(l10n.appDescription),
            const SizedBox(height: 16),
            Text(l10n.appAttribution),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => showLicensePage(
            context: context,
            applicationName: AppBrand.name,
            applicationVersion: version,
          ),
          child: Text(l10n.licenses),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.close),
        ),
      ],
    ),
  );
}
