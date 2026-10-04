#!/usr/bin/env python3
"""Renderuje zrzuty ekranow z harnessu (plik previewDump) do PNG fontem CC: Tweaked.

Uzycie: python3 tests/render_preview.py <plik_zrzutu> <term_font.png> <katalog_wyjsciowy> [skala]
Font: projects/core/src/main/resources/assets/computercraft/textures/gui/term_font.png z repo CC: Tweaked.
"""
import re
import sys
from pathlib import Path

from PIL import Image

FW, FH = 6, 9  # rozmiar glifu (FixedWidthFontRenderer)


def load_font(path):
    im = Image.open(path).convert("RGBA")
    glyphs = []
    for i in range(256):
        c, r = i % 16, i // 16
        g = im.crop((1 + c * 8, 1 + r * 11, 1 + c * 8 + FW, 1 + r * 11 + FH))
        glyphs.append(g.getchannel("A"))
    return glyphs


def parse(path):
    data = Path(path).read_bytes().split(b"\n")
    screens, i = [], 0
    while i < len(data):
        line = data[i]
        if line.startswith(b"@@SCREEN "):
            m = re.match(rb"@@SCREEN (.*) (\d+) (\d+)$", line)
            title, w, h = m.group(1).decode("latin-1"), int(m.group(2)), int(m.group(3))
            pal = [int(x, 16) for x in data[i + 1].split()]
            rows = []
            for y in range(h):
                base = i + 2 + y * 3
                rows.append((data[base], data[base + 1].decode(), data[base + 2].decode()))
            screens.append((title, w, h, pal, rows))
            i += 2 + h * 3
        else:
            i += 1
    return screens


def render(screen, glyphs, scale):
    title, w, h, pal, rows = screen
    rgb = [((p >> 16) & 255, (p >> 8) & 255, p & 255) for p in pal]
    img = Image.new("RGB", (w * FW, h * FH))
    for y, (text, fg, bg) in enumerate(rows):
        for x in range(w):
            ch = text[x] if x < len(text) else 32
            f = int(fg[x], 16) if x < len(fg) else 0
            b = int(bg[x], 16) if x < len(bg) else 15
            cell = Image.new("RGB", (FW, FH), rgb[b])
            cell.paste(Image.new("RGB", (FW, FH), rgb[f]), (0, 0), glyphs[ch])
            img.paste(cell, (x * FW, y * FH))
    if scale != 1:
        img = img.resize((img.width * scale, img.height * scale), Image.NEAREST)
    return title, img


def main():
    dump, font, out = sys.argv[1], sys.argv[2], Path(sys.argv[3])
    scale = int(sys.argv[4]) if len(sys.argv) > 4 else 2
    out.mkdir(parents=True, exist_ok=True)
    glyphs = load_font(font)
    for screen in parse(dump):
        title, img = render(screen, glyphs, scale)
        name = re.sub(r"[^A-Za-z0-9_-]+", "_", title).strip("_") or "screen"
        img.save(out / f"{name}.png")
        print(out / f"{name}.png", img.size)


if __name__ == "__main__":
    main()
