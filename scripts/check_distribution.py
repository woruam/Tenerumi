"""Fail closed on forbidden plugin engines and unexpected APK signing identity."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import zipfile

p = argparse.ArgumentParser()
p.add_argument('--apk')
p.add_argument('--apksigner')
p.add_argument('--profile', choices=['stable', 'experimental'], default='stable')
p.add_argument('--size-report', help='Flutter --analyze-size JSON, to verify Dart feature exclusion')
args = p.parse_args()
lock = Path('pubspec.lock').read_text(encoding='utf-8')
assert not re.search(r'^  (fjs|flutter_js|flutter_javascript|quickjs|javascriptcore):', lock, re.M), 'Forbidden plugin engine dependency'
if args.apk:
    with zipfile.ZipFile(args.apk) as apk:
        assert not any(re.search(r'(fjs|quickjs|duktape|javascriptcore|libv8)', name, re.I) for name in apk.namelist()), 'Forbidden engine in APK'
        if args.profile == 'stable':
            # Native OCR and its bundled models must be absent, not just hidden.
            assert not any(re.search(r'(mlkit|text[_-]?recognition|tesseract)', name, re.I) for name in apk.namelist()), 'Experimental OCR asset in public APK'
            for name in apk.namelist():
                if re.fullmatch(r'classes\d*\.dex', name):
                    dex = apk.read(name)
                    assert b'Lcom/google/mlkit/' not in dex, 'Experimental MLKit code in public APK'
                    assert b'Lonline/xournal/mobile/PluginOcr;' not in dex, 'Experimental OCR channel in public APK'
    if args.apksigner:
        expected = re.sub('[^0-9a-f]', '', os.environ.get('OSIPP_RELEASE_CERTSHA256', '').lower())
        assert len(expected) == 64, 'Expected release certificate missing'
        result = subprocess.run([args.apksigner, 'verify', '--verbose', '--print-certs', args.apk], check=True, capture_output=True, text=True)
        certs = re.findall(r'certificate SHA-256 digest: ([a-fA-F0-9]+)', result.stdout)
        assert len(certs) == 1 and certs[0].lower() == expected, 'Unexpected APK signer'
        assert 'Android Debug' not in result.stdout, 'Debug certificate forbidden for release'
if args.size_report and args.profile == 'stable':
    report = json.loads(Path(args.size_report).read_text(encoding='utf-8'))
    modules = set()
    def walk(node, app_path=None):
        name = node.get('n', node.get('name', ''))
        if name == 'package:xournalpp':
            app_path = ''
        elif app_path is not None:
            app_path = f'{app_path}/{name}'.lstrip('/')
            modules.add(app_path)
        for child in node.get('children', []):
            walk(child, app_path)
    walk(report)
    assert 'main.dart' in modules, 'Size report has no OSI Dart modules'
    forbidden = (
        'plugins', 'src/note_backup.dart', 'widgets/note_backup_dialog.dart',
        'widgets/PomodoroTimer.dart', 'widgets/pomodoro_progress_icon.dart',
        'widgets/note_flashcards_panel.dart',
    )
    for module in forbidden:
        assert not any(path == module or path.startswith(module + '/') for path in modules), f'Experimental Dart module in public snapshot: {module}'
print('Distribution checks passed')
