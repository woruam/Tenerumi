"""Fail closed on forbidden plugin engines and unexpected APK signing identity."""
import argparse
import os
from pathlib import Path
import re
import subprocess
import zipfile

p = argparse.ArgumentParser()
p.add_argument('--apk')
p.add_argument('--apksigner')
args = p.parse_args()
lock = Path('pubspec.lock').read_text(encoding='utf-8')
assert not re.search(r'^  (fjs|flutter_js|flutter_javascript|quickjs|javascriptcore):', lock, re.M), 'Forbidden plugin engine dependency'
if args.apk:
    with zipfile.ZipFile(args.apk) as apk:
        assert not any(re.search(r'(fjs|quickjs|duktape|javascriptcore|libv8)', name, re.I) for name in apk.namelist()), 'Forbidden engine in APK'
    if args.apksigner:
        expected = re.sub('[^0-9a-f]', '', os.environ.get('OSIPP_RELEASE_CERTSHA256', '').lower())
        assert len(expected) == 64, 'Expected release certificate missing'
        result = subprocess.run([args.apksigner, 'verify', '--verbose', '--print-certs', args.apk], check=True, capture_output=True, text=True)
        certs = re.findall(r'certificate SHA-256 digest: ([a-fA-F0-9]+)', result.stdout)
        assert len(certs) == 1 and certs[0].lower() == expected, 'Unexpected APK signer'
        assert 'Android Debug' not in result.stdout, 'Debug certificate forbidden for release'
print('Distribution checks passed')
