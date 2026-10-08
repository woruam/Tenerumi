"""Run after the Flutter export test; requires Poppler, Pillow and pypdf."""
import json
import shutil
import subprocess
from pathlib import Path
from PIL import Image, ImageChops, ImageStat
from pypdf import PdfReader

folder = Path(__file__).resolve().parent
subprocess.run([shutil.which("pdftoppm"), "-r", "288", "-singlefile", "-png",
                str(folder / "pdf-quality.pdf"), str(folder / "pdf-quality-rendered")], check=True)
page = PdfReader(folder / "pdf-quality.pdf").pages[0]
commands = page.get_contents().get_data()
assert commands.count(b" c ") >= 40, "Ink must contain vector curves"
assert commands.count(b"W* n") == 6, "Overlapping erasures must keep independent clips"
states = page["/Resources"]["/ExtGState"].values()
assert any(float(state["/ca"]) == 0.5 for state in states), "Highlighter opacity lost"
rendered = Image.open(folder / "pdf-quality-rendered.png").convert("RGB")
reference = Image.open(folder / "pdf-quality-reference.png").convert("RGB")
assert rendered.size == reference.size == (640, 720)
checks = {}
for name, point in {"pressure_ink": (200, 120), "erased_overlap": (320, 240),
                    "remaining_ink": (100, 240), "highlighter_overlap": (320, 400),
                    "later_layer": (500, 600), "hidden_layer": (40, 40)}.items():
    actual, expected = rendered.getpixel(point), reference.getpixel(point)
    assert max(abs(a-b) for a,b in zip(actual, expected)) <= 2, (name, actual, expected)
    checks[name] = {"pdf": actual, "canvas": expected}
mean_difference = ImageStat.Stat(ImageChops.difference(rendered, reference)).mean
assert max(mean_difference) < 2, mean_difference
result = {"vector_curve_commands": commands.count(b" c "),
          "erasure_clips": commands.count(b"W* n"), "render_dpi": 288,
          "mean_channel_difference": mean_difference, "pixel_checks": checks}
(folder / "pdf-quality-comparison.json").write_text(json.dumps(result, indent=2)+"\n", encoding="utf-8")
print(json.dumps(result, indent=2))
