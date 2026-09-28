"""깃허브 맥의 시뮬레이터 촬영 결과(ios-shots)를 사람이 볼 수 있게 정리한다.

    gh run download <실행 번호> -R lierline/Q-Atelier-iOS -n ios-shots -D <폴더>
    python tools/shots.py <폴더>/out

결과는 <폴더>/out/_view 에 쓴다.
  · <기기>-<모드>.png: 켠 뒤 정해 둔 때에 찍은 화면을 시간 순으로 한 줄에
  · <기기>-<모드>.gif · .mp4 · -strip.png: 8배 느리게 녹화한 켜는 장면(scripts/shoot.sh)을 실제 속도로 되돌린 것.
    장면 구간(붓 Q 첫 획 조금 전 ~ 사이트 첫 화면)만 8배 빠르게 돌리고 그 뒤에 실제 시간 1초를 붙인다.
    띠(-strip)는 실제 시간 0.1초 간격
  · <기기>.gif: 밝은 · 어두운 모드 장면을 나란히
장면 길이(첫 획 ~ 사이트 첫 화면)와 장면 안에서 가장 길게 멈춘 때도 찍어 준다. 부하가 큰 깃허브 맥에서 잰 값이라
실제 기기와 다르다.
"""
import glob
import os
import re
import sys

import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFont

SLOW = 8  # scripts/shoot.sh 의 SLOW
PAPER = (250, 249, 246)
INK = (40, 38, 34)


def font(size):
    for path in ("C:/Windows/Fonts/malgun.ttf", "/System/Library/Fonts/AppleSDGothicNeo.ttc"):
        if os.path.exists(path):
            return ImageFont.truetype(path, size)
    return ImageFont.load_default()


def sheets(root, out):
    """<이름>-<초>s.png 를 이름마다 한 줄로"""
    label_font = font(22)
    groups = {}
    for p in glob.glob(os.path.join(root, "*.png")):
        m = re.match(r"(.+)-([0-9.]+)s\.png$", os.path.basename(p))
        if m:
            groups.setdefault(m.group(1), []).append((float(m.group(2)), p))
    for name, shots in sorted(groups.items()):
        tiles = []
        for sec, p in sorted(shots):
            im = Image.open(p).convert("RGB")
            w = round(im.width * 520 / im.height)
            tile = Image.new("RGB", (w, 554), (128, 128, 128))
            tile.paste(im.resize((w, 520), Image.LANCZOS), (0, 34))
            ImageDraw.Draw(tile).text((6, 4), f"{sec:g}초", fill=(255, 255, 255), font=label_font)
            tiles.append(tile)
        sheet = Image.new("RGB", (sum(t.width for t in tiles) + 8 * (len(tiles) - 1), 554), (60, 60, 60))
        x = 0
        for t in tiles:
            sheet.paste(t, (x, 0))
            x += t.width + 8
        sheet.save(os.path.join(out, f"{name}.png"))
        print(f"{name}.png · {len(tiles)} 장")


def read_frames(path):
    cap = cv2.VideoCapture(path)
    frames = []
    while True:
        ok, f = cap.read()
        if not ok:
            break
        frames.append((cap.get(cv2.CAP_PROP_POS_MSEC) / 1000.0, f))
    cap.release()
    return frames


def speedup(src, prefix):
    """느린 녹화를 실제 속도로 되돌린다. 만든 MP4 경로(못 읽으면 None)"""
    frames = read_frames(src)
    if not frames:
        print(f"{os.path.basename(src)}: 영상을 못 읽음(녹화가 끊겼을 수 있음)")
        return None
    h, w = frames[0][1].shape[:2]
    print(f"{os.path.basename(src)}: {len(frames)} 장 · {frames[-1][0]:.2f}초 · {w}x{h}")

    def small(f):
        return cv2.resize(cv2.cvtColor(f, cv2.COLOR_BGR2GRAY), (w // 4, h // 4), interpolation=cv2.INTER_AREA).astype(np.int16)

    def ink(g, y0, y1, x0, x1):
        """자리 안에서 바탕(화면 전체의 가운뎃값)과 40 넘게 다른 점의 수"""
        H, W = g.shape
        part = g[int(H * y0):int(H * y1), int(W * x0):int(W * x1)]
        return int((np.abs(part - int(np.median(g))) > 40).sum())

    smalls = [small(f) for _, f in frames]
    # 장면이 시작된 때: 상태 표시줄 아래가 민바탕인데 가운데(붓 Q 자리)에 획이 생긴 첫 장.
    # 홈 화면 · 앱이 열리며 커지는 동안은 가운데 밖에도 무늬가 있어 걸리지 않는다
    mark = next((i for i, g in enumerate(smalls)
                 if ink(g, 0.08, 0.30, 0, 1) + ink(g, 0.65, 0.95, 0, 1) <= 3 and ink(g, 0.33, 0.62, 0.25, 0.75) >= 3), None)
    if mark is None:
        print("  붓 Q 가 나타나는 장을 못 찾음")
        return None
    t_mark = frames[mark][0]
    # 사이트 첫 화면: 장면이 거의 끝난 뒤 위쪽(사이트의 Q 로고 · 테마 단추 자리)에 무늬가 생긴 첫 장. 켜는 장면은 그 자리가 비어 있다
    page = next((i for i in range(mark + 1, len(frames))
                 if frames[i][0] >= t_mark + 0.9 * SLOW and ink(smalls[i], 0.06, 0.22, 0.05, 0.95) >= 20), None)
    if page is None:
        print("  사이트 첫 화면을 못 찾음 · 영상 끝까지 씀")
        page = len(frames) - 1
    t_page = frames[page][0]

    # 장면이 멈칫했는지: 장면 구간에서 같은 장이 이어진 가장 긴 길이(실제 시간으로)
    longest = run = 0
    for i in range(mark + 1, page):
        run = run + 1 if np.abs(smalls[i] - smalls[i - 1]).max() <= 2 else 0
        longest = max(longest, run)
    fps = len(frames) / max(frames[-1][0], 1e-6)
    print(f"  장면 길이(첫 획 ~ 사이트 첫 화면) {(t_page - t_mark) / SLOW:.2f}초 · "
          f"가장 길게 멈춘 때 {longest / fps / SLOW * 1000:.0f}ms")

    t0 = max(frames[0][0], t_mark - 0.15 * SLOW)  # 첫 획 전 0.15초(실제 시간)부터
    times = [t for t, _ in frames]

    def at(t):
        j = int(np.searchsorted(times, t, side="right")) - 1
        return frames[max(0, min(j, len(frames) - 1))][1]

    def build(rate):
        out = []
        k = 0
        while t0 + k / rate * SLOW <= t_page + 0.3 * SLOW:  # 사이트가 들어선 뒤 걷히는 끝까지는 빠르게
            out.append(at(t0 + k / rate * SLOW))
            k += 1
        tail = t0 + k / rate * SLOW
        out += [at(tail + m / rate) for m in range(rate)]  # 그 뒤는 실제 시간 1초
        return out

    mp4 = prefix + ".mp4"
    writer = cv2.VideoWriter(mp4, cv2.VideoWriter_fourcc(*"mp4v"), 60, (w, h))
    for f in build(60):
        writer.write(f)
    writer.release()

    gw = 390
    gh = round(h * gw / w)
    imgs = [Image.fromarray(cv2.cvtColor(cv2.resize(f, (gw, gh), interpolation=cv2.INTER_AREA), cv2.COLOR_BGR2RGB))
            .quantize(colors=128, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE) for f in build(30)]
    imgs[0].save(prefix + ".gif", save_all=True, append_images=imgs[1:], duration=33, loop=0, optimize=True)

    tiles = [cv2.resize(at(t0 + k * 0.1 * SLOW), (180, round(h * 180 / w)), interpolation=cv2.INTER_AREA) for k in range(17)]
    cv2.imwrite(prefix + "-strip.png", np.hstack(tiles))
    return mp4


def pair(light, dark, dst, width):
    """밝은 · 어두운 장면(실제 속도 MP4)을 나란히 붙인 GIF. 짧은 쪽은 마지막 장을 늘인다"""
    def frames(path):
        out = []
        for i, (_, f) in enumerate(read_frames(path)):
            if i % 2 == 0:  # 60장/초 → 30장/초
                h = round(f.shape[0] * width / f.shape[1])
                out.append(cv2.cvtColor(cv2.resize(f, (width, h), interpolation=cv2.INTER_AREA), cv2.COLOR_BGR2RGB))
        return out

    a, b = frames(light), frames(dark)
    n = max(len(a), len(b))
    a += [a[-1]] * (n - len(a))
    b += [b[-1]] * (n - len(b))
    gap, top, margin = 20, 34, 16
    label_font = font(17)
    imgs = []
    for fa, fb in zip(a, b):
        c = Image.new("RGB", (margin * 2 + width * 2 + gap, top + max(fa.shape[0], fb.shape[0]) + margin), PAPER)
        d = ImageDraw.Draw(c)
        d.text((margin, 8), "밝은 모드", font=label_font, fill=INK)
        d.text((margin + width + gap, 8), "어두운 모드", font=label_font, fill=INK)
        c.paste(Image.fromarray(fa), (margin, top))
        c.paste(Image.fromarray(fb), (margin + width + gap, top))
        imgs.append(c.quantize(colors=160, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE))
    imgs[0].save(dst, save_all=True, append_images=imgs[1:], duration=33, loop=0, optimize=True)
    print(f"{os.path.basename(dst)} · {len(imgs)} 장")


root = sys.argv[1]
out = os.path.join(root, "_view")
os.makedirs(out, exist_ok=True)
sheets(root, out)
fast = {}
for src in sorted(glob.glob(os.path.join(root, f"*-launch-x{SLOW}.mp4"))):
    key = os.path.basename(src)[:-len(f"-launch-x{SLOW}.mp4")]
    made = speedup(src, os.path.join(out, key))
    if made:
        fast[key] = made
for device in sorted({k.rsplit("-", 1)[0] for k in fast}):
    if f"{device}-light" in fast and f"{device}-dark" in fast:
        pair(fast[f"{device}-light"], fast[f"{device}-dark"], os.path.join(out, f"{device}.gif"), 300 if device == "phone" else 330)
