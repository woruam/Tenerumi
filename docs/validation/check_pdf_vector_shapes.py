"""Run after document_export_test.dart; requires Poppler, Pillow and pypdf."""
import json
import shutil
import subprocess
from pathlib import Path
from PIL import Image, ImageChops, ImageStat
from pypdf import PdfReader

folder = Path(__file__).resolve().parent
subprocess.run([shutil.which("pdftoppm"), "-r", "288", "-singlefile", "-png",
                str(folder / "pdf-vector-shapes.pdf"),
                str(folder / "pdf-vector-shapes-rendered")], check=True)
page = PdfReader(folder / "pdf-vector-shapes.pdf").pages[0]
assert len(page.images) == 0, "Paper, shapes and bundled text must be vector"
assert "OSI \u00e0\u00e8\u00ec\u00f2\u00f9" in page.extract_text()
rendered = Image.open(folder / "pdf-vector-shapes-rendered.png").convert("RGB")
reference = Image.open(folder / "pdf-vector-shapes-reference.png").convert("RGB")
assert rendered.size == reference.size == (640, 720)
difference = ImageStat.Stat(ImageChops.difference(rendered, reference)).mean
assert max(difference) < 3, difference
result = {"images": len(page.images), "text": page.extract_text(),
          "mean_channel_difference": difference, "render_dpi": 288}
(folder / "pdf-vector-shapes-comparison.json").write_text(
    json.dumps(result, indent=2) + "\n", encoding="utf-8")
print(json.dumps(result, indent=2))
