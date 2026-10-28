"""Build platform icons from the supplied logo, preserving its artwork/alpha.

Requires Pillow. Run from any directory: python tool/generate_brand_icons.py
"""
from pathlib import Path
from PIL import Image, ImageOps

ROOT = Path(__file__).resolve().parents[1]
source = Image.open(ROOT / "branding/Tenerumi.png").convert("RGBA")
content = source.crop(source.getbbox())
content = ImageOps.contain(content, (960, 960), Image.Resampling.LANCZOS)
icon = Image.new("RGBA", (1024, 1024))
icon.alpha_composite(content, ((1024 - content.width) // 2, (1024 - content.height) // 2))


def png(image, path, size):
    target = ROOT / path
    target.parent.mkdir(parents=True, exist_ok=True)
    image.resize((size, size), Image.Resampling.LANCZOS).save(target, optimize=True)


png(icon, "assets/tenerumi-icon.png", 1024)
res = "android/app/src/main/res"
for density, size, foreground_size in [
    ("mdpi", 48, 108), ("hdpi", 72, 162), ("xhdpi", 96, 216),
    ("xxhdpi", 144, 324), ("xxxhdpi", 192, 432),
]:
    png(icon, f"{res}/mipmap-{density}/ic_launcher.png", size)
    # Android adaptive icons use a 108dp layer; keep artwork in its safe area.
    foreground = Image.new("RGBA", (foreground_size, foreground_size))
    inner = icon.resize((foreground_size * 2 // 3,) * 2, Image.Resampling.LANCZOS)
    foreground.alpha_composite(inner, ((foreground_size - inner.width) // 2,) * 2)
    png(foreground, f"{res}/drawable-{density}/ic_launcher_foreground.png", foreground_size)

ico = ROOT / "windows/runner/resources/app_icon.ico"
ico.parent.mkdir(parents=True, exist_ok=True)
icon.save(ico, format="ICO", sizes=[(n, n) for n in (16, 24, 32, 48, 64, 128, 256)])
for name, size in [("favicon.png", 32), ("apple-touch-icon.png", 180),
                   ("icons/Icon-192.png", 192), ("icons/Icon-512.png", 512)]:
    png(icon, f"web/{name}", size)
