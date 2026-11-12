"""Renders the app icon (concept A, Receipt) to PNGs for flutter_launcher_icons.

Run: python tool/make_icons.py   (needs PyMuPDF: pip install pymupdf)
Outputs in assets/icon/:
  icon_daily.png    full icon on brand green (#024944), for older Android versions
  icon_capture.png  same on black, so ET Capture is easy to tell apart
  foreground.png    receipt only, on transparent, sized for the adaptive-icon safe zone
"""
import pathlib
import pymupdf

OUT = pathlib.Path(__file__).resolve().parent.parent / "assets" / "icon"
RECEIPT = """
  <path d="M160 104h192v296l-32-22-32 22-32-22-32 22-32-22-32 22z" fill="#FFFFFF"/>
  <g stroke="{ink}" stroke-width="22" stroke-linecap="round">
    <line x1="211" y1="179" x2="301" y2="179"/>
    <line x1="211" y1="233" x2="269" y2="233"/>
    <line x1="211" y1="287" x2="301" y2="287"/>
  </g>"""


def svg(background: str | None, ink: str, scale: float = 1.0) -> str:
    # Scale around the centre (256, 252) so the receipt stays centred.
    t = f"translate({256 * (1 - scale)} {252 * (1 - scale)}) scale({scale})"
    bg = f'<rect width="512" height="512" fill="{background}"/>' if background else ""
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 512 512">'
            f'{bg}<g transform="{t}">{RECEIPT.format(ink=ink)}</g></svg>')


def render(markup: str, name: str) -> None:
    doc = pymupdf.open(stream=markup.encode(), filetype="svg")
    pix = doc[0].get_pixmap(alpha=True)
    pix.save(OUT / name)
    print(name, pix.width, pix.height)


OUT.mkdir(parents=True, exist_ok=True)
render(svg("#024944", "#024944"), "icon_daily.png")
render(svg("#000000", "#000000"), "icon_capture.png")
# Adaptive icons crop to the middle ~66%; 0.8 keeps the receipt inside it with margin.
# The receipt lines are drawn in the same colour as that app's adaptive background.
render(svg(None, "#024944", 0.8), "foreground.png")
render(svg(None, "#000000", 0.8), "foreground_capture.png")
