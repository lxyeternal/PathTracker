"""Frames app screenshots for the App Store: 1320 x 2868 (6.9-inch iPhone), a headline and a
line under it on a soft gradient, the screen below with rounded corners and a shadow.

    python3 AppStore/tools/frame.py <shots dir> <out dir> <zh|en>
Shots are 1.png ... 6.png in the order below."""
import sys
from PIL import Image, ImageDraw, ImageFilter, ImageFont

W, H = 1320, 2868
SRC, OUT, LANG = sys.argv[1], sys.argv[2], sys.argv[3]

CAPTIONS = {
    "zh": [
        ("全天自动记录", "口袋里的手机，记下你走过的每一条路"),
        ("你去过的每座城市", "国境描边，城市发光，标着待了几天"),
        ("点亮中国，点亮世界", "34 个省份和世界各国，一眼看到去过哪里"),
        ("一年，一个故事", "年度足迹，把这一年去过的地方讲给你听"),
        ("这一年，你走了多远", "数字会跳动，地球会转"),
        ("插画奖牌", "23 枚里程碑，铜、银、金、铂金"),
    ],
    "en": [
        ("It records itself", "The phone in your pocket remembers every road"),
        ("Every city you've been", "Countries outlined, cities glowing, days counted"),
        ("Light up the world", "China's provinces and every country, at a glance"),
        ("Your year, as a story", "Year in Footprints tells you where you've been"),
        ("How far you went", "Numbers that count up, a globe that turns"),
        ("Illustrated medals", "23 milestones in bronze, silver, gold and platinum"),
    ],
}
# Top and bottom of each background, light to deeper.
COLORS = [((232, 243, 255), (196, 222, 255)), ((255, 241, 228), (255, 214, 186)),
          ((255, 244, 222), (255, 222, 168)), ((226, 226, 255), (190, 186, 250)),
          ((222, 240, 255), (176, 210, 250)), ((255, 236, 226), (250, 204, 190))]

def font(size, bold):
    paths = (["/System/Library/Fonts/STHeiti Medium.ttc", "/System/Library/Fonts/Hiragino Sans GB.ttc"]
             if LANG == "zh" else ["/System/Library/Fonts/SFNS.ttf"])
    for path in paths:
        try:
            f = ImageFont.truetype(path, size)
            if LANG == "en":
                try: f.set_variation_by_name("Bold" if bold else "Medium")
                except Exception: pass
            return f
        except OSError:
            continue
    return ImageFont.load_default()

def gradient(top, bottom):
    img = Image.new("RGB", (W, H))
    d = ImageDraw.Draw(img)
    for y in range(H):
        t = y / (H - 1)
        d.line([(0, y), (W, y)], fill=tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)))
    return img

def centered(draw, y, text, f, fill):
    w = draw.textlength(text, font=f)
    draw.text(((W - w) / 2, y), text, font=f, fill=fill)

for i, (title, line) in enumerate(CAPTIONS[LANG], start=1):
    canvas = gradient(*COLORS[i - 1]).convert("RGBA")
    d = ImageDraw.Draw(canvas)
    centered(d, 170, title, font(104, True), (24, 24, 30))
    centered(d, 330, line, font(54, False), (70, 70, 84))

    shot = Image.open(f"{SRC}/{i}.png").convert("RGBA")
    width = 1060
    shot = shot.resize((width, int(shot.height * width / shot.width)), Image.LANCZOS)
    radius = 110
    mask = Image.new("L", shot.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, shot.width - 1, shot.height - 1], radius=radius, fill=255)
    x, y = (W - width) // 2, 520
    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle([x, y + 24, x + width, y + shot.height + 24], radius=radius, fill=(0, 0, 0, 70))
    canvas = Image.alpha_composite(canvas, shadow.filter(ImageFilter.GaussianBlur(40)))
    # A thin dark bezel so the screen reads as a phone.
    bezel = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(bezel).rounded_rectangle([x - 14, y - 14, x + width + 14, y + shot.height + 14], radius=radius + 14, fill=(20, 20, 24, 255))
    canvas = Image.alpha_composite(canvas, bezel)
    canvas.paste(shot, (x, y), mask)
    canvas.convert("RGB").save(f"{OUT}/{i}.jpg", quality=90, optimize=True)
    print(f"{OUT}/{i}.jpg")
