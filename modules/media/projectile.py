"""Draws projectile.gif, the animation in modules/projectile.lan: a body thrown
at v = 20 m/s and θ = 50° under g = 9.81 m/s², in real time, with its range
R = v² sin(2θ)/g and the top of its flight. Needs ImageMagick's `convert`.

    python3 modules/media/projectile.py
"""

import math
import os
import subprocess
import tempfile

V, THETA, G = 20.0, math.radians(50), 9.81
T = 2 * V * math.sin(THETA) / G               # time of flight
R = V**2 * math.sin(2 * THETA) / G            # range
H = (V * math.sin(THETA)) ** 2 / (2 * G)      # greatest height
FRAMES, DELAY = 40, 8                         # 40 frames of 0.08 s: 3.2 s, about T

W, HGT, M = 480, 230, 30                      # picture size and margin, pixels
S = (W - 2 * M) / R                           # pixels per metre
BG, FG, PATH, BALL, NOTE = "#16181d", "#c9c7c0", "#4a4f5c", "#ffa94d", "#8d8b84"


def px(x, y):
    return M + x * S, HGT - M - y * S


def point(t):
    return V * math.cos(THETA) * t, V * math.sin(THETA) * t - G * t**2 / 2


def polyline(ts):
    return " ".join("%.1f,%.1f" % px(*point(t)) for t in ts)


def frame(k, path):
    t = T * k / (FRAMES - 1)
    whole = polyline([T * i / 80 for i in range(81)])
    trail = polyline([t * i / 40 for i in range(41)])
    bx, by = px(*point(t))
    gx0, gy = px(0, 0)
    gx1, _ = px(R, 0)
    tx, ty = px(R / 2, H)
    draw = [
        f"stroke {FG} stroke-width 1.5 line {gx0 - 10},{gy} {gx1 + 10},{gy}",
        f"fill none stroke {PATH} stroke-width 1.5 stroke-dasharray 4 4 polyline {whole}",
        f"fill none stroke {BALL} stroke-width 2 polyline {trail}",
        f"fill {BALL} stroke none circle {bx:.1f},{by:.1f} {bx + 6:.1f},{by:.1f}",
        f"stroke {NOTE} stroke-width 1 stroke-dasharray 2 3 line {tx},{ty} {tx},{gy}",
    ]
    text = [
        ("+%d+%d" % (gx1 - 70, gy + 18), f"R = {R:.1f} m"),
        ("+%d+%d" % (tx + 6, ty - 6), f"H = {H:.1f} m"),
        ("+%d+%d" % (M, 20), f"t = {t:.2f} s"),
    ]
    # one -draw each: a dash pattern would carry over to the next primitive
    cmd = ["convert", "-size", f"{W}x{HGT}", f"xc:{BG}"]
    for d in draw:
        cmd += ["-draw", d]
    for pos, s in text:
        cmd += ["-fill", NOTE, "-pointsize", "13", "-annotate", pos, s]
    subprocess.run(cmd + [path], check=True)


with tempfile.TemporaryDirectory() as d:
    names = [os.path.join(d, "f%02d.png" % k) for k in range(FRAMES)]
    for k, name in enumerate(names):
        frame(k, name)
    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "projectile.gif")
    # hold the last frame for a second before it starts again
    subprocess.run(["convert", "-delay", str(DELAY), *names[:-1], "-delay", "100", names[-1], "-loop", "0", "-layers", "Optimize", out], check=True)
    print(out, os.path.getsize(out), "bytes")
