"""켜는 장면에 쓸 그림과 글자 조각을 만든다 (손으로 그리지 않는다).

    python tools/make-assets.py

안드로이드 앱의 tools/make-launch.py 와 같은 규칙이다. 원본은 패밀리 디자인 정본(이 저장소 옆 폴더 Q-Design)에 있다.
  · 붓 Q 그림: source/brand/logo-dark.png(은빛 Q · 어두운 바탕용) · logo-light.png(검은 칠 Q · 밝은 바탕용).
    둘레의 빈 여백을 걷어 두 그림의 크기 · 자리를 맞춘다(켜는 장면의 자리 값이 이 오린 그림 기준이다).
  · 글자 «Q-ATELIER»: 웹 로그인 화면과 같은 JetBrains Mono 400 에서 그 글자들만 떼어 온다(OFL 1.1 · 사용 허가 파일을 함께 넣는다).
앱 아이콘은 여기서 만들지 않는다. 네 제품 아이콘을 만드는 Q-Design tools/app-icons.mjs 가 AppIcon-1024.png 를 쓴다.
"""
import os
import shutil

from fontTools import subset
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
DESIGN = os.path.join(os.path.dirname(REPO), "Q-Design")
OUT = os.path.join(REPO, "QAtelier", "Resources")

BRAND = os.path.join(DESIGN, "source", "brand")
FONT = os.path.join(DESIGN, "source", "fonts", "jetbrains-mono-400-latin.woff2")
FONT_LICENSE = os.path.join(os.path.dirname(REPO), "Q-Atelier", "public", "fonts", "jetbrains-mono", "LICENSE.txt")
WORDMARK = "Q-ATELIER"
WIDTH = 360  # 120pt 로 그리는 자리의 3배 화면 한 장. 2배 화면(아이패드)은 줄여 그린다

for src, name in (("logo-dark.png", "launch-q-on-dark.png"), ("logo-light.png", "launch-q-on-light.png")):
    im = Image.open(os.path.join(BRAND, src)).convert("RGBA")
    im = im.crop(im.getchannel("A").getbbox())
    h = round(im.height * WIDTH / im.width)
    im = im.resize((WIDTH, h), Image.LANCZOS)
    out = os.path.join(OUT, name)
    im.save(out, "PNG", optimize=True)
    print(f"{name}: {WIDTH}x{h} · {os.path.getsize(out)} 바이트")

font_out = os.path.join(OUT, "wordmark-mono.ttf")
opts = subset.Options()
opts.flavor = None  # woff2 → ttf(iOS 가 읽는 형식)
opts.hinting = False
opts.layout_features = []
f = subset.load_font(FONT, opts)
s = subset.Subsetter(opts)
s.populate(text=WORDMARK)
s.subset(f)
subset.save_font(f, font_out, opts)
print(f"wordmark-mono.ttf: «{WORDMARK}» 글자만 · {os.path.getsize(font_out)} 바이트")

shutil.copyfile(FONT_LICENSE, os.path.join(OUT, "JetBrainsMono-OFL.txt"))
print("JetBrainsMono-OFL.txt: 사용 허가 파일 복사")
