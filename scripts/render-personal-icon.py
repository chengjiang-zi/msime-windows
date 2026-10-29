"""Render the personal icon from its SVG source (requires PySide6 and Pillow)."""

from io import BytesIO
from pathlib import Path

from PIL import Image
from PySide6.QtCore import QByteArray, QBuffer, QIODevice, QRectF
from PySide6.QtGui import QImage, QPainter
from PySide6.QtSvg import QSvgRenderer

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "server/assets/settings/chengjiang.svg"
PNG = ROOT / "server/assets/settings/chengjiang.png"
ICONS = (
    ROOT / "server/src/resource/ChengjiangIME.ico",
    ROOT / "windows/image/chengjiang.ico",
)
SIZES = (16, 20, 24, 28, 32, 36, 40, 44, 48, 64, 128, 256)

renderer = QSvgRenderer(QByteArray(SOURCE.read_bytes()))
if not renderer.isValid():
    raise RuntimeError("Personal icon SVG is invalid")
image = QImage(1024, 1024, QImage.Format.Format_ARGB32_Premultiplied)
image.fill(0)
painter = QPainter(image)
painter.setRenderHint(QPainter.RenderHint.Antialiasing)
renderer.render(painter, QRectF(0, 0, 1024, 1024))
painter.end()
buffer = QBuffer()
if not buffer.open(QIODevice.OpenModeFlag.WriteOnly) or not image.save(buffer, "PNG"):
    raise RuntimeError("Failed to render personal icon")
rendered = Image.open(BytesIO(bytes(buffer.data()))).convert("RGBA")
rendered.resize((440, 440), Image.Resampling.LANCZOS).save(PNG, format="PNG")
for destination in ICONS:
    rendered.save(destination, format="ICO", sizes=[(size, size) for size in SIZES])
