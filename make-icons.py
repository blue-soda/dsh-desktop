"""Regenerate the DeepSeek Harness Desktop icons from the source artwork.

Usage:
    python make-icons.py [source.png] [--mode head|full] [--margin 0.02]

Modes:
    head (default)  crop a square window around the character's head, so the face
                    stays readable at 16 px
    full            crop to the whole character's opaque bounding box

Both modes then tighten to the content's opaque bounding box plus `margin`, and
write these sizes:
    tray-windows.ico   16 20 24 32 40 48 64            tray / status area
    icon-windows.ico   16 20 24 32 40 48 64 128 256    window + taskbar
    icon-windows.png   1024                            About panel
    dsh-desktop.ico    (same sizes as icon-windows.ico) desktop shortcut

Outputs default to the repository checkout and %USERPROFILE%\\bin; override the
checkout with DSH_REPO.
"""

import os
import sys
from PIL import Image

DEFAULT_SOURCE = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'source.png')
DEFAULT_REPO = r'C:\Workspace\deepseek-harness'
DEFAULT_BIN = os.path.join(os.environ.get('USERPROFILE', ''), 'bin')

TRAY_SIZES = [16, 20, 24, 32, 40, 48, 64]
WINDOW_SIZES = [16, 20, 24, 32, 40, 48, 64, 128, 256]

# Head window, as a fraction of the square canvas: edge length, then the centre.
HEAD_EDGE = 0.58
HEAD_CENTRE = (0.50, 0.36)


def square_canvas(source):
    """Centre-pad the artwork onto a transparent square canvas."""
    im = Image.open(source).convert('RGBA')
    side = max(im.size)
    canvas = Image.new('RGBA', (side, side), (0, 0, 0, 0))
    canvas.paste(im, ((side - im.width) // 2, (side - im.height) // 2), im)
    return canvas


def tighten(image, margin):
    """Crop to the opaque bounding box plus `margin`, keeping the result square."""
    bbox = image.getchannel('A').getbbox()
    if bbox is None:
        raise SystemExit('artwork is fully transparent')
    left, top, right, bottom = bbox
    cx, cy = (left + right) / 2, (top + bottom) / 2
    edge = min(max(right - left, bottom - top) * (1 + margin * 2), max(image.size))
    half = edge / 2
    x = max(0, min(image.width - round(edge), round(cx - half)))
    y = max(0, min(image.height - round(edge), round(cy - half)))
    return image.crop((x, y, x + round(edge), y + round(edge)))


def build(source, margin, mode):
    canvas = square_canvas(source)
    side = canvas.width
    if mode == 'head':
        edge = round(side * HEAD_EDGE)
        cx, cy = round(side * HEAD_CENTRE[0]), round(side * HEAD_CENTRE[1])
        x = max(0, min(side - edge, cx - edge // 2))
        y = max(0, min(side - edge, cy - edge // 2))
        window = canvas.crop((x, y, x + edge, y + edge))
        print(f'head window: {edge}px at ({x},{y}) on a {side}px canvas')
        crop = tighten(window, margin)
    else:
        crop = tighten(canvas, margin)
    print(f'{mode} mode -> {crop.size} (glyph fills ~{1 / (1 + margin * 2):.0%} of the tile)')
    return crop


def main():
    argv = sys.argv[1:]
    source = None
    mode = 'head'
    margin = 0.02
    index = 0
    while index < len(argv):
        argument = argv[index]
        if argument == '--mode':
            mode = argv[index + 1]
            index += 2
        elif argument == '--margin':
            margin = float(argv[index + 1])
            index += 2
        elif argument.startswith('--'):
            raise SystemExit(f'unknown option {argument}')
        elif source is None:
            source = argument
            index += 1
        else:
            raise SystemExit(f'unexpected argument {argument}')
    if source is None:
        source = DEFAULT_SOURCE
    if mode not in ('head', 'full'):
        raise SystemExit("--mode accepts 'head' or 'full'")

    repo = os.environ.get('DSH_REPO', DEFAULT_REPO)
    resources = os.path.join(repo, 'apps', 'desktop', 'resources')
    if not os.path.isdir(resources):
        raise SystemExit(f'repository resources not found: {resources}')

    icon = build(source, margin, mode)

    icon.save(os.path.join(resources, 'tray-windows.ico'), format='ICO',
              sizes=[(s, s) for s in TRAY_SIZES])
    icon.save(os.path.join(resources, 'icon-windows.ico'), format='ICO',
              sizes=[(s, s) for s in WINDOW_SIZES])
    icon.resize((1024, 1024), Image.LANCZOS).save(os.path.join(resources, 'icon-windows.png'))
    print('wrote tray-windows.ico, icon-windows.ico, icon-windows.png')

    shortcut = os.path.join(DEFAULT_BIN, 'dsh-desktop.ico')
    if os.path.isdir(DEFAULT_BIN):
        icon.save(shortcut, format='ICO', sizes=[(s, s) for s in WINDOW_SIZES])
        print('wrote', shortcut)


if __name__ == '__main__':
    main()
