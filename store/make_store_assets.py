"""Google Play 등록용 이미지를 만든다.

  python3 store/make_store_assets.py

- store/play/screenshots/*.png : 휴대전화 스크린샷 1080 × 1920 (9:16, 문구 + 앱 화면)
- store/play/feature_graphic.png : 그래픽 이미지 1024 × 500
- store/play/icon_512.png : 고해상도 아이콘 512 × 512

앱 화면 원본은 store/play/raw/ 의 iOS 시뮬레이터 캡처다 (1206 × 2622).
그대로는 비율이 2:1을 넘어서 Play가 받지 않으므로 9:16 틀 안에 넣는다.
렌더링은 Chrome headless로 하고, 글꼴은 앱과 같은 Pretendard를 쓴다.
"""
import pathlib
import subprocess
import tempfile

from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / 'store' / 'play'
RAW = OUT / 'raw'
FONTS = ROOT / 'assets' / 'fonts'
CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'

SHOTS = [
    ('01_scan', '04_review_kr.png', '영수증 한 장 찍으면 끝',
     '품목·금액·세금까지 자동으로 정리해요'),
    ('02_any_country', '03_review_vn.png', '어느 나라 영수증이든 한국어로',
     '베트남·일본·태국 영수증도 품목 이름을 한국어로 보여줘요'),
    ('03_check', '05_review_us_bottom.png', '세금·팁·봉사료까지 검산',
     '품목 합계와 총액이 맞는지 바로 알려줘요'),
    ('04_home', '06_home.png', '여행 지출을 한눈에',
     '나라마다 다른 통화도 따로 모아 보여줘요'),
    ('05_fast', '01_analyzing.png', '찍으면 몇 초 만에 정리',
     '어두운 바탕에 놓고 찍으면 더 정확해요'),
]

FONT_CSS = f"""
@font-face {{ font-family: P; font-weight: 500; src: url('file://{FONTS}/Pretendard-Medium.otf'); }}
@font-face {{ font-family: P; font-weight: 700; src: url('file://{FONTS}/Pretendard-Bold.otf'); }}
* {{ margin: 0; box-sizing: border-box; }}
body {{ font-family: P, sans-serif; color: #213A16; }}
"""


def render(html: str, width: int, height: int, out: pathlib.Path) -> None:
    with tempfile.TemporaryDirectory() as tmp:
        page = pathlib.Path(tmp) / 'page.html'
        page.write_text(html, encoding='utf-8')
        shot = pathlib.Path(tmp) / 'shot.png'
        subprocess.run(
            [CHROME, '--headless=new', '--disable-gpu', '--hide-scrollbars',
             '--force-device-scale-factor=1', f'--window-size={width},{height}',
             '--allow-file-access-from-files', '--virtual-time-budget=3000',
             f'--screenshot={shot}', page.as_uri()],
            check=True, capture_output=True)
        # Play는 투명도 없는 PNG/JPEG를 원한다
        Image.open(shot).convert('RGB').crop((0, 0, width, height)).save(out)


def screenshot_html(raw: pathlib.Path, title: str, subtitle: str) -> str:
    return f"""<!doctype html><html><head><meta charset="utf-8"><style>{FONT_CSS}
body {{ width: 1080px; height: 1920px; overflow: hidden;
       background: linear-gradient(170deg, #F4FAEE 0%, #DFF3D3 100%); }}
.text {{ padding: 120px 80px 0; text-align: center; }}
h1 {{ font-size: 78px; font-weight: 700; letter-spacing: -2px; line-height: 1.2; }}
p {{ margin-top: 28px; font-size: 40px; font-weight: 500; color: #3F7A2A; line-height: 1.4; }}
.phone {{ position: absolute; left: 50%; top: 400px; transform: translateX(-50%);
         width: 660px; border-radius: 64px; overflow: hidden; background: #fff;
         border: 14px solid #213A16; box-shadow: 0 40px 80px rgba(33, 58, 22, .28); }}
.phone img {{ display: block; width: 100%; }}
</style></head><body>
<div class="text"><h1>{title}</h1><p>{subtitle}</p></div>
<div class="phone"><img src="{raw.as_uri()}"></div>
</body></html>"""


def feature_graphic_html(icon: pathlib.Path, phone: pathlib.Path) -> str:
    return f"""<!doctype html><html><head><meta charset="utf-8"><style>{FONT_CSS}
body {{ width: 1024px; height: 500px; overflow: hidden; position: relative;
       background: linear-gradient(120deg, #F4FAEE 0%, #CFEDBE 100%); }}
.icon {{ position: absolute; left: 72px; top: 150px; width: 200px; height: 200px;
        border-radius: 46px; box-shadow: 0 18px 40px rgba(33, 58, 22, .22); }}
.name {{ position: absolute; left: 310px; top: 140px; font-size: 92px; font-weight: 700;
        letter-spacing: -2px; }}
.tag {{ position: absolute; left: 314px; top: 276px; font-size: 36px; font-weight: 500;
       color: #3F7A2A; line-height: 1.35; }}
.phone {{ position: absolute; right: 56px; top: 64px; width: 230px; border-radius: 30px;
         overflow: hidden; border: 7px solid #213A16; transform: rotate(6deg);
         box-shadow: 0 24px 48px rgba(33, 58, 22, .25); }}
.phone img {{ display: block; width: 100%; }}
</style></head><body>
<img class="icon" src="{icon.as_uri()}">
<div class="name">여행N</div>
<div class="tag">영수증 찍으면 끝나는<br>여행 가계부</div>
<div class="phone"><img src="{phone.as_uri()}"></div>
</body></html>"""


def main() -> None:
    shots_dir = OUT / 'screenshots'
    shots_dir.mkdir(parents=True, exist_ok=True)
    for name, raw, title, subtitle in SHOTS:
        render(screenshot_html(RAW / raw, title, subtitle), 1080, 1920,
               shots_dir / f'{name}.png')

    icon = ROOT / 'assets' / 'icon' / 'app_icon.png'
    render(feature_graphic_html(icon, RAW / '04_review_kr.png'), 1024, 500,
           OUT / 'feature_graphic.png')
    Image.open(icon).convert('RGB').resize((512, 512), Image.LANCZOS).save(
        OUT / 'icon_512.png')
    print('saved to', OUT)


if __name__ == '__main__':
    main()
