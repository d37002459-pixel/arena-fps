"""Генератор бесшовных текстур для Arena FPS (цвет + карта нормалей).

Запуск: python3 tools/gen_textures.py  -> пишет PNG в textures/
Все текстуры процедурные, бесшовные (тайлятся), без сторонних ассетов.
"""
import os
import numpy as np
from PIL import Image
from scipy import ndimage

OUT = os.path.join(os.path.dirname(__file__), "..", "textures")
os.makedirs(OUT, exist_ok=True)
rng = np.random.default_rng(1337)


# ---------------------------------------------------------------- шум

def fbm(n, octaves=5, base=4, persistence=0.5, seed=None):
    """Бесшовный фрактальный шум 0..1 (сумма размытых по кругу шумов)."""
    r = np.random.default_rng(seed) if seed is not None else rng
    out = np.zeros((n, n))
    amp, total = 1.0, 0.0
    sigma = n / base / 2.0
    for _ in range(octaves):
        layer = ndimage.gaussian_filter(r.random((n, n)), sigma, mode="wrap")
        layer = (layer - layer.min()) / (np.ptp(layer) + 1e-9)
        out += layer * amp
        total += amp
        amp *= persistence
        sigma /= 2.0
        if sigma < 0.5:
            sigma = 0.5
    out /= total
    return (out - out.min()) / (np.ptp(out) + 1e-9)


def blur(a, s):
    return ndimage.gaussian_filter(a, s, mode="wrap")


def norm01(a):
    return (a - a.min()) / (np.ptp(a) + 1e-9)


def grain_field(n, seed, along="y", freq=9.0):
    """Прямые волокна дерева вдоль оси along с лёгкой волнистостью."""
    r = np.random.default_rng(seed)
    big = (n / 3, n / 40) if along == "y" else (n / 40, n / 3)
    small = (n / 10, 0.7) if along == "y" else (0.7, n / 10)
    warp = norm01(blur(r.random((n, n)), big))
    fib = norm01(blur(r.random((n, n)), small))
    y, x = np.mgrid[0:n, 0:n] / n
    across = x if along == "y" else y
    rings = np.sin((across + warp * 0.35) * 2 * np.pi * freq) * 0.5 + 0.5
    rings = rings ** 1.6
    return rings, fib


def grain(n, s=0.6):
    g = blur(rng.random((n, n)), s)
    return (g - g.min()) / (np.ptp(g) + 1e-9)


def normal_from_height(h, strength):
    dx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * 0.5
    dy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * 0.5
    nx, ny, nz = -dx * strength, dy * strength, np.ones_like(h)
    l = np.sqrt(nx * nx + ny * ny + nz * nz)
    n = np.stack([nx / l, ny / l, nz / l], -1)
    return n * 0.5 + 0.5


def save(name, rgb, height=None, nstrength=4.0):
    rgb = np.clip(rgb, 0, 1)
    Image.fromarray((rgb * 255).astype(np.uint8), "RGB").save(os.path.join(OUT, name + ".png"))
    if height is not None:
        n = normal_from_height(height, nstrength * height.shape[0] / 512)
        Image.fromarray((n * 255).astype(np.uint8), "RGB").save(os.path.join(OUT, name + "_n.png"))
    print("ok", name)


def col(c):
    return np.array(c, dtype=float).reshape(1, 1, 3)


def mix(a, b, t):
    t = t[..., None] if t.ndim == 2 else t
    return a * (1 - t) + b * t


def cells_rows(n, rows, cols_per_row, offset=0.5, jitter=0.0):
    """Кладка: id блока, локальные координаты внутри блока (0..1) для каждой точки."""
    y, x = np.mgrid[0:n, 0:n] / n
    row = np.floor(y * rows).astype(int)
    shift = (row % 2) * offset / cols_per_row
    xs = (x + shift) % 1.0
    colw = np.floor(xs * cols_per_row).astype(int)
    lx = (xs * cols_per_row) % 1.0
    ly = (y * rows) % 1.0
    ident = row * 1000 + colw
    return ident, lx, ly


def per_id(ident, seed):
    r = np.random.default_rng(seed)
    u, inv = np.unique(ident, return_inverse=True)
    vals = r.random(len(u))
    return vals[inv].reshape(ident.shape)


def bevel(lx, ly, w_x, w_y, gap_x, gap_y):
    """Высота блока со скруглёнными краями: 0 в шве, 1 в центре."""
    ex = np.minimum(lx, 1 - lx)
    ey = np.minimum(ly, 1 - ly)
    bx = np.clip((ex - gap_x) / w_x, 0, 1)
    by = np.clip((ey - gap_y) / w_y, 0, 1)
    return np.sqrt(np.minimum(bx, by))


# ---------------------------------------------------------------- текстуры

def sand(n=512):
    low = fbm(n, 4, 2, seed=1)
    mid = fbm(n, 5, 8, seed=2)
    y, x = np.mgrid[0:n, 0:n] / n
    warp = fbm(n, 3, 3, seed=3) * 2.0
    ripple = np.sin((x * 9 + y * 4 + warp) * 2 * np.pi) * 0.5 + 0.5
    ripple = ripple ** 2 * (0.4 + 0.6 * fbm(n, 3, 3, seed=4))
    g = grain(n, 0.5)
    h = ripple * 0.5 + mid * 0.6 + g * 0.25
    base = mix(col([0.80, 0.66, 0.46]), col([0.72, 0.56, 0.37]), low)
    rgb = base * (0.86 + 0.14 * mid[..., None]) * (0.9 + 0.1 * g[..., None]) * (0.94 + 0.08 * ripple[..., None])
    # редкие камушки
    pebbles = (grain(n, 1.2) > 0.86).astype(float) * (fbm(n, 2, 6, seed=5) > 0.5)
    rgb = mix(rgb, col([0.5, 0.44, 0.36]), pebbles * 0.7)
    h += pebbles * 0.6
    save("sand", rgb, h, 3.0)


def paving(n=512):
    # плиты 4x4 на тайл, ряды со сдвигом и случайной шириной
    ident, lx, ly = cells_rows(n, 4, 3, offset=0.37)
    v = per_id(ident, 11)
    v2 = per_id(ident, 12)
    b = bevel(lx, ly, 0.06, 0.08, 0.012, 0.016)
    noise = fbm(n, 5, 8, seed=13)
    chips = np.clip((fbm(n, 4, 16, seed=14) - 0.7) * 4, 0, 1)
    h = b * (0.8 + 0.2 * noise) - chips * 0.25 * b
    stone = mix(col([0.70, 0.62, 0.50]), col([0.58, 0.50, 0.40]), v)
    stone = mix(stone, col([0.76, 0.70, 0.60]), (v2 > 0.8).astype(float) * 0.5)
    rgb = stone * (0.82 + 0.25 * noise[..., None]) * (0.92 + 0.08 * grain(n)[..., None])
    grout = col([0.42, 0.36, 0.28])
    rgb = mix(grout * (0.9 + 0.2 * noise[..., None]), rgb, np.clip(b * 3, 0, 1))
    rgb *= (0.88 + 0.12 * np.clip(b * 2, 0, 1))[..., None]
    save("paving", rgb, h, 5.0)


def sandstone(n=512):
    # крупные блоки: 4 ряда, 2 блока в ряд (тайл 2 м -> блок 1 x 0.5 м)
    ident, lx, ly = cells_rows(n, 4, 2, offset=0.5)
    v = per_id(ident, 21)
    b = bevel(lx, ly, 0.05, 0.1, 0.008, 0.016)
    noise = fbm(n, 6, 8, seed=22)
    erosion = fbm(n, 4, 4, seed=23)
    pits = (grain(n, 0.8) > 0.8).astype(float)
    # обкрошенные края
    edge = np.clip(1 - b, 0, 1)
    crumble = (edge * (fbm(n, 4, 24, seed=24))) > 0.35
    h = b * 0.9 + noise * 0.25 - pits * 0.1 - crumble * 0.3
    stone = mix(col([0.86, 0.72, 0.52]), col([0.76, 0.58, 0.38]), v)
    stone = mix(stone, col([0.66, 0.50, 0.33]), erosion * 0.5)
    rgb = stone * (0.85 + 0.2 * noise[..., None]) * (0.95 + 0.05 * grain(n)[..., None])
    rgb = mix(rgb, rgb * 0.8, pits * 0.6)
    mortar = col([0.70, 0.62, 0.50])
    rgb = mix(mortar * (0.85 + 0.2 * noise[..., None]), rgb, np.clip(b * 4, 0, 1) * (1 - crumble * 0.6))
    save("sandstone", rgb, h, 5.0)


def plaster(n=512):
    noise = fbm(n, 6, 4, seed=31)
    stains = fbm(n, 4, 2, seed=32)
    fine = grain(n, 0.7)
    h = noise * 0.6 + fine * 0.3
    # трещины: случайные блуждания
    crack = np.zeros((n, n))
    r = np.random.default_rng(33)
    for _ in range(9):
        p = r.random(2) * n
        a = r.random() * 2 * np.pi
        for _ in range(r.integers(40, 140)):
            a += r.normal(0, 0.45)
            p = (p + np.array([np.cos(a), np.sin(a)]) * 1.5) % n
            crack[int(p[1]), int(p[0])] = 1
    crack = np.clip(blur(crack, 0.6) * 4, 0, 1)
    # облупленные места с кирпичом
    peel = np.clip((fbm(n, 5, 4, seed=34) - 0.72) * 8, 0, 1)
    bid, blx, bly = cells_rows(n, 16, 8)
    brick_b = bevel(blx, bly, 0.1, 0.2, 0.03, 0.06)
    brick = mix(col([0.55, 0.40, 0.30]), col([0.62, 0.48, 0.34]), per_id(bid, 35)) * (0.8 + 0.3 * brick_b[..., None])
    wall = mix(col([0.90, 0.84, 0.72]), col([0.80, 0.72, 0.60]), stains)
    rgb = wall * (0.9 + 0.12 * noise[..., None]) * (0.96 + 0.04 * fine[..., None])
    rgb = mix(rgb, rgb * 0.55, crack * 0.8)
    rgb = mix(rgb, brick, peel)
    h = h * (1 - peel) + (brick_b * 0.3 - 0.4) * peel - crack * 0.4
    save("plaster", rgb, h, 3.0)


def wood_planks(n=512, name="wood", tint=(0.55, 0.38, 0.22), planks=5):
    y, x = np.mgrid[0:n, 0:n] / n
    pid = np.floor(x * planks).astype(int)
    lx = (x * planks) % 1.0
    pv = per_id(pid, 41)
    rings, streak = grain_field(n, 42, "y", 22.0)
    edge = np.minimum(lx, 1 - lx)
    gap = np.clip((edge - 0.015) / 0.04, 0, 1)
    knots = np.clip((fbm(n, 3, 10, seed=44) - 0.8) * 6, 0, 1)
    base = col(tint)
    rgb = base * (0.75 + 0.35 * pv[..., None]) * (0.8 + 0.25 * rings[..., None]) * (0.85 + 0.25 * streak[..., None])
    rgb = mix(rgb, rgb * 0.5, knots)
    rgb *= (0.35 + 0.65 * gap)[..., None]
    weather = fbm(n, 4, 3, seed=45)
    rgb = mix(rgb, col([0.55, 0.52, 0.47]) * (0.8 + 0.3 * streak[..., None]), weather * 0.35)
    h = gap * 0.8 + rings * 0.1 + streak * 0.15 - knots * 0.2
    save(name, rgb, h, 4.0)


def crate(n=512):
    """Грань ящика: рамка из досок, диагональ, гвозди. UV 0..1 на грань."""
    y, x = np.mgrid[0:n, 0:n] / n
    planks = 4
    pid = np.floor(y * planks).astype(int)
    ly = (y * planks) % 1.0
    pv = per_id(pid, 51)
    grainv, streak = grain_field(n, 52, "x", 26.0)
    warp = fbm(n, 4, 4, seed=55)
    wood = col([0.62, 0.45, 0.26]) * (0.8 + 0.3 * pv[..., None]) * (0.82 + 0.2 * grainv[..., None]) * (0.85 + 0.25 * streak[..., None])
    gap = np.clip((np.minimum(ly, 1 - ly) - 0.02) / 0.05, 0, 1)
    h = gap * 0.5 + streak * 0.1
    rgb = wood * (0.45 + 0.55 * gap)[..., None]
    # рамка
    fw = 0.13
    frame = (x < fw) | (x > 1 - fw) | (y < fw) | (y > 1 - fw)
    # диагональ
    d = np.abs((x - y)) / np.sqrt(2)
    diag = (d < fw * 0.5) & ~frame
    board = frame | diag
    gv, _ = grain_field(n, 56, "y", 30.0)
    gh, _ = grain_field(n, 57, "x", 30.0)
    fgrain = np.where((x < fw) | (x > 1 - fw), gv, gh)
    fgrain = np.where(diag, np.sin(((x - y) * 0.7 + warp * 0.2) * 2 * np.pi * 30) * 0.5 + 0.5, fgrain)
    fwood = col([0.68, 0.50, 0.30]) * (0.82 + 0.2 * fgrain[..., None]) * (0.85 + 0.2 * streak[..., None])
    # кромки рамки
    ex = np.minimum.reduce([np.abs(x - fw), np.abs(x - (1 - fw)), np.abs(y - fw), np.abs(y - (1 - fw))])
    fedge = np.clip(ex / 0.012, 0, 1)
    dedge = np.clip(np.abs(d - fw * 0.5) / 0.012, 0, 1)
    outer = np.clip(np.minimum.reduce([x, 1 - x, y, 1 - y]) / 0.01, 0, 1)
    shade = np.where(frame, fedge * outer, np.where(diag, dedge, 1.0))
    rgb = np.where(board[..., None], fwood * (0.55 + 0.45 * shade[..., None]), rgb)
    h = np.where(board, 1.0 + 0.3 * shade, h)
    # гвозди
    for cx in (fw / 2, 1 - fw / 2):
        for cy in (fw / 2, 0.5, 1 - fw / 2):
            for (px, py) in ((cx, cy), (cy, cx)):
                r2 = (x - px) ** 2 + (y - py) ** 2
                m = r2 < (0.012 ** 2)
                rgb[m] = [0.25, 0.24, 0.22]
                h[m] += 0.3
    # потёртость
    wear = fbm(n, 4, 3, seed=54)
    rgb = mix(rgb, rgb * 0.7, wear * 0.4)
    save("crate", rgb, h, 5.0)


def metal(n=512):
    """Гофрированный крашеный металл с ржавчиной."""
    y, x = np.mgrid[0:n, 0:n] / n
    corr = np.sin(x * 2 * np.pi * 10) * 0.5 + 0.5
    rust = np.clip((fbm(n, 6, 10, seed=61) - 0.62) * 4, 0, 1)
    streaks = blur(np.random.default_rng(62).random((n, n)), (10, 0.5))
    streaks = (streaks - streaks.min()) / np.ptp(streaks)
    paint = col([0.42, 0.52, 0.50]) * (0.88 + 0.15 * fbm(n, 4, 4, seed=63)[..., None])
    rust_c = mix(col([0.50, 0.28, 0.14]), col([0.35, 0.20, 0.10]), fbm(n, 4, 16, seed=64))
    rgb = mix(paint, rust_c, np.clip(rust + streaks * 0.3 - 0.15, 0, 1))
    rgb *= (0.75 + 0.3 * corr)[..., None]
    h = corr * 1.0 + rust * 0.08
    save("metal", rgb, h, 6.0)


def concrete(n=512):
    noise = fbm(n, 6, 4, seed=71)
    pores = (grain(n, 0.5) > 0.83).astype(float)
    stains = fbm(n, 3, 2, seed=72)
    rgb = mix(col([0.66, 0.64, 0.60]), col([0.56, 0.54, 0.50]), stains) * (0.88 + 0.18 * noise[..., None])
    rgb = mix(rgb, rgb * 0.6, pores * 0.7)
    # опалубка
    y, x = np.mgrid[0:n, 0:n] / n
    seam = np.clip(np.abs(((y * 3) % 1.0) - 0.5) * 2, 0, 1)
    seam = 1 - np.clip((1 - seam) / 0.02, 0, 1) * 0.0 + 0
    lines = np.clip((np.minimum((y * 3) % 1.0, 1 - (y * 3) % 1.0)) / 0.006, 0, 1)
    rgb *= (0.8 + 0.2 * lines)[..., None]
    h = noise * 0.5 - pores * 0.3 + lines * 0.2
    save("concrete", rgb, h, 3.0)


def sandbags(n=512):
    ident, lx, ly = cells_rows(n, 4, 2, offset=0.5)
    v = per_id(ident, 81)
    ex = np.minimum(lx, 1 - lx) * 2
    ey = np.minimum(ly, 1 - ly) * 2
    bag = np.sqrt(np.clip(1 - (1 - ex) ** 4, 0, 1) * np.clip(1 - (1 - ey) ** 2, 0, 1))
    y, x = np.mgrid[0:n, 0:n]
    weave = (np.sin(x * 1.3) * np.sin(y * 1.3)) * 0.5 + 0.5
    wrinkle = fbm(n, 5, 16, seed=82)
    base = mix(col([0.74, 0.66, 0.50]), col([0.66, 0.58, 0.44]), v)
    rgb = base * (0.55 + 0.45 * bag[..., None]) * (0.92 + 0.08 * weave[..., None]) * (0.85 + 0.25 * wrinkle[..., None])
    h = bag * 1.0 + wrinkle * 0.15 + weave * 0.03
    save("sandbags", rgb, h, 5.0)


def gunmetal(n=256):
    noise = fbm(n, 5, 8, seed=91)
    scr = np.zeros((n, n))
    r = np.random.default_rng(92)
    for _ in range(60):
        p = r.random(2) * n
        a = r.random() * np.pi
        for t in range(r.integers(6, 30)):
            q = (p + np.array([np.cos(a), np.sin(a)]) * t) % n
            scr[int(q[1]), int(q[0])] = 1
    scr = blur(scr, 0.4)
    rgb = col([0.21, 0.21, 0.22]) * (0.8 + 0.35 * noise[..., None])
    rgb = mix(rgb, col([0.42, 0.42, 0.43]), np.clip(scr * 2, 0, 1) * 0.6)
    h = noise * 0.3 - scr * 0.3
    save("gunmetal", rgb, h, 2.0)


def gunwood(n=256):
    y, x = np.mgrid[0:n, 0:n] / n
    rings, streak = grain_field(n, 101, "x", 14.0)
    rgb = col([0.48, 0.22, 0.10]) * (0.75 + 0.3 * rings[..., None]) * (0.85 + 0.25 * streak[..., None])
    wear = np.clip((fbm(n, 4, 6, seed=103) - 0.65) * 3, 0, 1)
    rgb = mix(rgb, col([0.62, 0.40, 0.22]), wear * 0.6)
    save("gunwood", rgb, rings * 0.15 + streak * 0.2, 2.0)


def camo(n=256):
    """Пустынный камуфляж с плетением ткани."""
    a = fbm(n, 4, 3, seed=111)
    b = fbm(n, 4, 4, seed=112)
    c = fbm(n, 4, 6, seed=113)
    rgb = np.ones((n, n, 3)) * col([0.76, 0.68, 0.52])
    rgb = mix(rgb, col([0.60, 0.50, 0.36]), (a > 0.55).astype(float))
    rgb = mix(rgb, col([0.46, 0.40, 0.30]), (b > 0.62).astype(float))
    rgb = mix(rgb, col([0.84, 0.78, 0.64]), (c > 0.7).astype(float))
    y, x = np.mgrid[0:n, 0:n]
    weave = ((np.sin(x * 2.1) * 0.5 + 0.5) * (np.sin(y * 2.1 + 1.0) * 0.5 + 0.5))
    rgb *= (0.88 + 0.12 * weave)[..., None]
    folds = fbm(n, 4, 4, seed=114)
    rgb *= (0.9 + 0.12 * folds)[..., None]
    save("camo", rgb, weave * 0.4 + folds * 0.5, 2.0)


def fabric(n=256):
    """Светлая ткань для навесов (тонируется цветом вершин)."""
    y, x = np.mgrid[0:n, 0:n]
    weave = ((np.sin(x * 1.6) * 0.5 + 0.5) * (np.sin(y * 1.6 + 1.0) * 0.5 + 0.5))
    stains = fbm(n, 4, 2, seed=121)
    stripes = (((x / n * 6) % 1.0) < 0.5).astype(float)
    rgb = np.ones((n, n, 3)) * (0.82 + 0.18 * stripes[..., None])
    rgb *= (0.9 + 0.1 * weave)[..., None] * (0.85 + 0.2 * stains[..., None])
    save("fabric", rgb, weave * 0.5, 1.5)


def grime(n=256):
    g = fbm(n, 5, 3, seed=131)
    Image.fromarray((g * 255).astype(np.uint8), "L").convert("RGB").save(os.path.join(OUT, "grime.png"))
    print("ok grime")


def palm_leaf(n=256):
    """Лист пальмы с альфой: стебель по центру, перья в стороны."""
    img = np.zeros((n, n, 4))
    y, x = np.mgrid[0:n, 0:n] / n
    # лист идёт снизу (v=1) вверх (v=0)
    t = 1 - y
    width = np.sin(np.clip(t, 0, 1) * np.pi) ** 0.7 * 0.48
    dx = np.abs(x - 0.5)
    inside = dx < width
    # прорези между перьями
    feather = np.sin((t * 18 + dx * 10) * 2 * np.pi) > -0.55
    a = (inside & (feather | (dx < 0.02))).astype(float)
    shade = 0.75 + 0.25 * (1 - dx / 0.5)
    green = np.stack([0.28 * shade, 0.42 * shade, 0.16 * shade], -1)
    green = mix(green, col([0.45, 0.42, 0.20]), np.clip((t - 0.75) * 3, 0, 1) * (dx / 0.5))
    stem = (dx < 0.015).astype(float)
    green = mix(green, col([0.40, 0.36, 0.20]), stem)
    img[..., :3] = green
    img[..., 3] = a
    Image.fromarray((img * 255).astype(np.uint8), "RGBA").save(os.path.join(OUT, "palm_leaf.png"))
    print("ok palm_leaf")


if __name__ == "__main__":
    sand()
    paving()
    sandstone()
    plaster()
    wood_planks()
    crate()
    metal()
    concrete()
    sandbags()
    gunmetal()
    gunwood()
    camo()
    fabric()
    grime()
    palm_leaf()
