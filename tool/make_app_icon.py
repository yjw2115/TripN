"""앱 아이콘 원본에서 iOS용 꽉 찬 정사각형과 Android 적응형 아이콘 레이어를 만든다.

  python3 tool/make_app_icon.py <원본 이미지> assets/icon [--preview]   (numpy, pillow 필요)
  dart run flutter_launcher_icons

원본은 흰 여백 위에 둥근 초록 사각형이 있는 그림이다. 바탕 그라데이션을 다항식으로 맞춰
여백·모서리를 채우고, Android 전경은 그 바탕 위에 다시 얹으면 원본이 되도록 알파를 만든다.
"""
import sys
import numpy as np
from PIL import Image, ImageFilter

src, out = sys.argv[1], sys.argv[2]
img = np.asarray(Image.open(src).convert('RGB')).astype(np.float64)
H, W, _ = img.shape
r, g, b = img[..., 0], img[..., 1], img[..., 2]

# 1) 초록 둥근 사각형 영역
green = (g - r > 25) & (g - b > 15)
ys, xs = np.nonzero(green)
x0, x1, y0, y1 = xs.min(), xs.max() + 1, ys.min(), ys.max() + 1
size = max(x1 - x0, y1 - y0)
cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
X0, Y0 = int(round(cx - size / 2)), int(round(cy - size / 2))
crop = img[Y0:Y0 + size, X0:X0 + size]

# 사각형 내부 마스크: 초록 픽셀의 볼록 영역을 행 단위로 채운 뒤 가장자리 광택 띠를 깎는다
inside = np.zeros((size, size), bool)
gm = green[Y0:Y0 + size, X0:X0 + size]
for y in range(size):
    row = np.nonzero(gm[y])[0]
    if len(row):
        inside[y, row.min():row.max() + 1] = True
erode = 14
im_inside = Image.fromarray((inside * 255).astype(np.uint8)).filter(ImageFilter.MinFilter(2 * erode + 1))
core = np.asarray(im_inside) > 127

# 2) 바탕 그라데이션을 2차 다항식으로 맞춘다 (물체 픽셀은 반복해서 제외)
yy, xx = np.mgrid[0:size, 0:size] / (size - 1)
def basis(x, y):
    return np.stack([np.ones_like(x), x, y, x * x, x * y, y * y], -1)
A = basis(xx, yy)
mask = core.copy()
for _ in range(6):
    coef, *_ = np.linalg.lstsq(A[mask], crop[mask], rcond=None)
    model = A @ coef
    res = np.linalg.norm(crop - model, axis=-1)
    thr = np.percentile(res[core], 55)
    mask = core & (res < max(thr, 4.0))
model = np.clip(A @ coef, 0, 255)
res = np.linalg.norm(crop - model, axis=-1)
print('background fit residual (median px):', round(float(np.median(res[mask])), 2))

# 3) iOS/기본 아이콘: 사각형 바깥(흰 여백·모서리·광택 띠)은 바탕으로 채운다
soft = np.asarray(im_inside.filter(ImageFilter.GaussianBlur(3))).astype(np.float64)[..., None] / 255
full = crop * soft + model * (1 - soft)
Image.fromarray(full.round().astype(np.uint8)).resize((1024, 1024), Image.LANCZOS).save(f'{out}/app_icon.png')

# 4) Android 전경: 바탕과 다른 정도로 알파를 만들고, 바탕 위에 다시 얹으면 원본이 되도록 색을 복원한다
# 바탕과 확실히 다른 물체는 불투명하게, 미세한 차이는 원본을 재현할 수 있는 최소 알파로 둔다.
# (알파가 너무 작으면 복원한 색이 0~255를 넘어 잘리면서 얼룩이 생긴다)
src_full = full
res_full = np.linalg.norm(src_full - model, axis=-1)
seg = np.clip((res_full - 18.0) / (40.0 - 18.0), 0, 1)
diff = src_full - model
need = np.where(diff > 0, diff / np.maximum(255 - model, 1), -diff / np.maximum(model, 1)).max(-1)
alpha = np.clip(np.maximum(seg, need), 0, 1)
alpha = np.ceil(alpha * 255) / 255
a3 = np.maximum(alpha[..., None], 1 / 255)
fg = np.clip((src_full - (1 - a3) * model) / a3, 0, 255)
err = np.abs(a3 * fg + (1 - a3) * model - src_full).max()
print('max reconstruction error (px):', round(float(err), 2))
fg_rgba = np.dstack([fg, alpha * 255]).round().astype(np.uint8)

# 적응형 아이콘은 108dp 중 가운데 72dp만 보이고 원형 마스크면 더 잘린다.
# 원본 아이콘 전체를 캔버스의 66%로 줄여 그림이 어떤 마스크에서도 남게 한다.
canvas = 1024
scale = 0.66
inner = int(round(canvas * scale))
# 투명도가 있는 이미지는 premultiplied 상태로 줄여야 색이 번지지 않는다
fg_img = (Image.fromarray(fg_rgba, 'RGBA').convert('RGBa')
          .resize((inner, inner), Image.LANCZOS).convert('RGBA'))
fg_canvas = Image.new('RGBA', (canvas, canvas), (0, 0, 0, 0))
off = (canvas - inner) // 2
fg_canvas.paste(fg_img, (off, off))  # 빈 캔버스라 마스크 없이 그대로 붙인다
fg_canvas.save(f'{out}/android_foreground.png')

# 배경: 같은 그라데이션을 캔버스 전체로 늘려 그린다 (가장자리는 맞춘 범위 밖이라 값을 잘라 쓴다)
cyy, cxx = np.mgrid[0:canvas, 0:canvas]
u = ((cxx - off) / inner).clip(-0.1, 1.1)
v = ((cyy - off) / inner).clip(-0.1, 1.1)
bg = np.clip(basis(u, v) @ coef, 0, 255)
Image.fromarray(bg.round().astype(np.uint8)).save(f'{out}/android_background.png')

# 확인용 미리보기 (--preview): iOS 모서리, Android 원형·둥근사각형 마스크
if '--preview' in sys.argv:
    def rounded_mask(n, radius):
        m = Image.new('L', (n, n), 0)
        from PIL import ImageDraw
        ImageDraw.Draw(m).rounded_rectangle([0, 0, n - 1, n - 1], radius=radius, fill=255)
        return m
    from PIL import ImageDraw
    prev = Image.new('RGB', (3 * 560 + 40, 600), (255, 255, 255))
    ios = Image.open(f'{out}/app_icon.png').resize((512, 512), Image.LANCZOS)
    prev.paste(ios, (24, 44), rounded_mask(512, int(512 * 0.2237)))
    comp = Image.alpha_composite(Image.open(f'{out}/android_background.png').convert('RGBA'), fg_canvas)
    vis = int(canvas * 72 / 108)
    cut = comp.crop(((canvas - vis) // 2,) * 2 + ((canvas + vis) // 2,) * 2).resize((512, 512), Image.LANCZOS)
    circle = Image.new('L', (512, 512), 0); ImageDraw.Draw(circle).ellipse([0, 0, 511, 511], fill=255)
    prev.paste(cut, (584, 44), circle)
    prev.paste(cut, (1144, 44), rounded_mask(512, int(512 * 0.3)))
    d = ImageDraw.Draw(prev)
    for x, t in [(24, 'iOS'), (584, 'Android circle'), (1144, 'Android squircle')]:
        d.text((x, 12), t, fill=(60, 60, 60))
    prev.save(f'{out}/preview.png')
print('saved', out)
