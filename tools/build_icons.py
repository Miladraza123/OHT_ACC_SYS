#!/usr/bin/env python3
"""OHT Solutions ke logo se app ke saare 15 icons bana deta hai.

    python3 tools/build_icons.py [logo.png]

Default source: tools/logo-master.png

KYA HOTA HAI

Source logo mein teen cheezein hain — upar bara "OHT" mark, us ke neeche
"OHT Solutions", aur sab se neeche tagline. Icon mein sirf **upar wala
mark** jata hai. Baqi do jaan boojh kar chhor diye jate hain: 16px ya
32px par wo harf parhe hi nahi jate, sirf dhundla dhabba ban jate hain.

Script khud dhoond leti hai ke mark kahan khatam hota hai — ink wali
rows ke darmiyan jo pehla khali faasla aata hai, wahan tak.

Rang: safed mark navy background par, blue accent bar apne rang mein.

Zaroorat: pip install pillow numpy

ICON BADALNE KE BAAD — sw.js ka CACHE_VERSION barhana LAZMI hai, warna
purane device par purana icon cache mein para rahega.
"""
import os
import sys

from PIL import Image
import numpy as np

NAVY  = (10, 31, 60)      # background
WHITE = (255, 255, 255)   # mark
BLUE  = (0, 169, 254)     # accent bar — apne rang mein rehta hai

HERE = os.path.dirname(os.path.abspath(__file__))
OUT  = os.path.join(os.path.dirname(HERE), 'icons')

PAD_NORMAL   = 0.14   # aam icons
PAD_TIGHT    = 0.08   # browser tab — wahan jagah bohat kam hai
PAD_MASKABLE = 0.20   # Android icon ko kaat deta hai, is liye zyada hasha


def load_mark(path):
    """Logo se sirf upar wala mark nikalta hai. Deta hai (alpha, blue-mask)."""
    a = np.asarray(Image.open(path).convert('RGB')).astype(np.float32)
    ink = a.mean(2) < 225

    # Ink wali rows ke bands — pehla band hi mark hai
    rows = ink.sum(1) > 3
    bands, start, prev = [], 0, False
    for y, cur in enumerate(rows):
        if cur and not prev:
            start = y
        if prev and not cur:
            bands.append((start, y))
        prev = cur
    if prev:
        bands.append((start, len(rows)))
    if not bands:
        raise SystemExit('Logo mein kuch mila hi nahi — file theek hai?')
    y0, y1 = bands[0]

    cols = np.nonzero(ink[y0:y1].sum(0) > 0)[0]
    x0, x1 = int(cols.min()), int(cols.max()) + 1

    m = a[y0:y1, x0:x1]
    alpha  = 1.0 - m.min(2) / 255.0                       # safed = 0, ink = 1
    isblue = (m[:, :, 2] > 140) & (m[:, :, 2] - m[:, :, 0] > 60)
    return alpha, isblue


def render(alpha, isblue, size, pad):
    h, w = alpha.shape
    rgba = np.zeros((h, w, 4), np.uint8)
    col  = np.empty((h, w, 3), np.uint8)
    col[:] = WHITE
    col[isblue] = BLUE
    rgba[:, :, :3] = col
    rgba[:, :, 3]  = (alpha * 255).clip(0, 255).astype(np.uint8)

    mark = Image.fromarray(rgba, 'RGBA')
    box  = int(size * (1 - 2 * pad))
    sc   = min(box / w, box / h)
    mark = mark.resize((max(1, int(w * sc)), max(1, int(h * sc))), Image.LANCZOS)

    out = Image.new('RGBA', (size, size), NAVY + (255,))
    out.alpha_composite(mark, ((size - mark.width) // 2, (size - mark.height) // 2))
    return out.convert('RGB')     # koi transparency nahi — iOS peeche kala bhar deta hai


def bump_icon_version():
    """manifest.json aur chhe HTML pages mein icon ka "?v=" number aik barha deta hai.

    Yeh qadam chhorna sab se aam ghalti hai: icons badal jate hain magar
    pata wahi rehta hai, is liye phone purana icon hi dikhata rehta hai.
    Naya pata dekh kar hi Android manifest dobara parhta hai aur home
    screen ka icon khud badalta hai.
    """
    import json
    import re

    root = os.path.dirname(HERE)
    man_path = os.path.join(root, 'manifest.json')

    with open(man_path, encoding='utf-8') as f:
        man = json.load(f)

    cur = 0
    for ic in man.get('icons', []):
        m = re.search(r'\?v=(\d+)', ic.get('src', ''))
        if m:
            cur = max(cur, int(m.group(1)))
    new = cur + 1

    for ic in man.get('icons', []):
        ic['src'] = ic['src'].split('?')[0] + '?v=%d' % new
    with open(man_path, 'w', encoding='utf-8') as f:
        f.write(json.dumps(man, indent=2, ensure_ascii=False) + '\n')

    pages = ['index.html', 'client1-index.html', 'client1-masters.html',
             'client1-billing.html', 'client1-cutting.html', 'client1-daily-ledger.html']
    icon_re = re.compile(r'(href=")(icons/[A-Za-z0-9._-]+)(?:\?v=\d+)?(")')
    man_re  = re.compile(r'(href=")(manifest\.json)(?:\?v=\d+)?(")')
    for name in pages:
        fp = os.path.join(root, name)
        if not os.path.exists(fp):
            continue
        with open(fp, encoding='utf-8') as f:
            t = f.read()
        t = icon_re.sub(lambda mo: '%s%s?v=%d%s' % (mo.group(1), mo.group(2), new, mo.group(3)), t)
        t = man_re.sub(lambda mo: '%s%s?v=%d%s' % (mo.group(1), mo.group(2), new, mo.group(3)), t)
        with open(fp, 'w', encoding='utf-8') as f:
            f.write(t)

    return new


def main():
    src = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, 'logo-master.png')
    alpha, isblue = load_mark(src)
    os.makedirs(OUT, exist_ok=True)

    def save(img, name):
        img.save(os.path.join(OUT, name), 'PNG', optimize=True)
        print('  %-24s %dx%d' % (name, img.width, img.height))

    for s in (48, 72, 96, 128, 144, 152, 192, 384, 512):
        save(render(alpha, isblue, s, PAD_NORMAL), 'icon-%d.png' % s)

    for s in (192, 512):
        save(render(alpha, isblue, s, PAD_MASKABLE), 'icon-maskable-%d.png' % s)

    save(render(alpha, isblue, 180, PAD_NORMAL), 'apple-touch-icon.png')
    save(render(alpha, isblue, 16,  PAD_TIGHT),  'favicon-16.png')
    save(render(alpha, isblue, 32,  PAD_TIGHT),  'favicon-32.png')

    render(alpha, isblue, 48, PAD_TIGHT).save(
        os.path.join(OUT, 'favicon.ico'), 'ICO', sizes=[(16, 16), (32, 32), (48, 48)])
    print('  %-24s 16+32+48' % 'favicon.ico')

    v = bump_icon_version()
    print('\n  icon ka pata ab ?v=%d — manifest aur chhe pages mein laga diya' % v)
    print('\nHo gaya — 15 files. Ab sirf sw.js ka CACHE_VERSION barhana baqi hai.')


if __name__ == '__main__':
    main()
