# Local Android file picker 2.0.1 patch

Runtime sources copied from the installed pub.dev `android_file_picker` 2.0.1
package, retaining its original LICENSE and README. The root application pins
this implementation through a path dependency override. Workspace resolution
was removed from the copied package and publishing is disabled.

The Android save result now returns `renamedUri.toString()` rather than
`renamedUri.path`. Returning only the path discards the content provider authority
and URI scheme, decodes document IDs and makes the result unusable for the
application's verified streaming PDF/ZIP export. Do not try to reconstruct a
content URI from a path or treat `/document/...` as a filesystem path.

The patch applies to all Android save dialogs, including note and JSON export.
Picker cancellation, byte writes, provider renaming and grants otherwise retain
the upstream behavior. The application keeps its existing bounded copy and
integrity verification after staged PDF/ZIP exports.

When upgrading the dependency, verify that upstream preserves the full URI in
the native save reply before removing this override. Recheck local Downloads
and cloud document providers on a real Android device, including cancellation,
percent-encoded names and failed writes. Automated app tests simulate provider
replies and do not substitute for a device/provider test.
