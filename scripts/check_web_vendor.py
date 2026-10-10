from pathlib import Path
import hashlib
import json
root = Path('web/vendor/pdfjs')
manifest = json.loads((root / 'integrity.json').read_text())
assert manifest['version'] == '4.6.82'
for name, expected in manifest['files'].items():
    assert hashlib.sha256((root / name).read_bytes()).hexdigest() == expected, name
assert set(manifest['files']) == {str(p.relative_to(root)).replace('\\', '/') for p in root.rglob('*') if p.is_file() and p.name != 'integrity.json'}
print('Bundled PDF.js integrity verified')
