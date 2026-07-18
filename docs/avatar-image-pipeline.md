# 아바타 이미지 파이프라인 (배경 제거·크롭)

캐릭터 시트(여러 인물이 격자로 배열된 큰 이미지) 한 장에서 인물 20명을 잘라내
`assets/avatars/`에 쓰는 개별 PNG로 만드는 절차. 평상시·환호·슬픔 등 감정 상태별
시트를 추가할 때 이 문서의 스크립트를 그대로 재사용한다.

관련: [[characters.md]] §2(캐릭터 추가/교체 절차), [[gostop-card-assets]] 메모리의
"이미지 배경제거는 rembg" 항목.

---

## 1. 사전 준비

```powershell
pip install rembg onnxruntime
```

- 첫 실행 시 신경망 모델(`u2net.onnx`, 약 176MB)을 `~/.u2net/`에 자동 다운로드한다(1회, 인터넷 필요).
- 이후는 프로세스 안에서 세션(`new_session`)을 재사용하면 이미지 1장당 1초 미만.

**왜 rembg인가**: 단순히 "흰색과의 거리"로 알파를 계산하는 임계값 방식은 안티에일리어싱된
경계(예: 어두운 머리카락과 흰 배경이 섞인 회색조 픽셀)를 색상 디컨태미네이션 없이 반투명
처리해버려서, 어두운 UI 배경에 합성하면 **머리카락 등 경계에 흰색 잔광(halo)**이 남는다.
rembg(u2net 신경망 매팅)는 이 문제가 없다. 자세한 배경은 프로젝트 메모리 참고.

---

## 2. 소스 시트 규격(이 프로젝트의 현재 자료)

- 원본: `assets/avatars/raw/sheet_{normal,cheer,sad}.png` — 각 2048×2048, 흰 배경
- 격자: **5열 × 4행 = 20명**, 셀 크기 `2048/5 = 409.6` × `2048/4 = 512`(정확히 나누어떨어지지
  않으므로 반올림 크롭)
- 인물 정사각 크롭: 각 셀에서 **너비와 같은 높이의 정사각형**을, 셀 상단에서
  `top_frac = 0.15 × (셀높이 − 셀너비)`만큼 내려온 위치에서 잘라낸다.
  - 이 `top_frac=0.15` 값은 기존 원형 크롭 아바타(`avatar_01.png`)와 픽셀 차이가
    거의 없도록(RGB 평균오차 ~2.7/255) 역산해서 찾은 값이다. 시트 레이아웃이 같으면
    그대로 재사용하면 된다.
  - 인덱스 `idx`(1~20) → `row = (idx-1) // 5`, `col = (idx-1) % 5`.

다른 시트(다른 인원수·다른 격자)를 쓴다면 `COLS`/`ROWS`/`TOP_FRAC`만 바꾸면 된다.

---

## 3. 전체 스크립트

시트 한 장을 20명으로 잘라 배경을 제거하고 128×128로 저장한다. 실제로 평상시·환호·슬픔
3개 시트를 처리할 때 쓴 코드 그대로다.

```python
from PIL import Image
from rembg import remove, new_session
import os

ASSETS = r"C:\works\projects\gostop\assets"
AVDIR = os.path.join(ASSETS, "avatars")
STATEDIR = os.path.join(AVDIR, "states")

COLS, ROWS = 5, 4          # 시트 격자
TOP_FRAC = 0.15            # 셀 안에서 정사각 크롭을 시작할 세로 위치(비율)
OUT_SIZE = 128              # 최종 저장 크기(기존 아바타 해상도와 통일)


def crop_square(img, cellw, cellh, row, col, top_frac=TOP_FRAC):
    """격자 셀 (row, col)에서 셀 너비와 같은 변의 정사각형을 잘라낸다."""
    x0 = col * cellw
    y0 = row * cellh + top_frac * (cellh - cellw)
    return img.crop((int(round(x0)), int(round(y0)),
                      int(round(x0 + cellw)), int(round(y0 + cellw))))


def process_sheet(sheet_path, out_pattern, out_dir, session):
    """시트 1장을 COLS×ROWS명으로 잘라 배경 제거 후 저장한다.

    out_pattern 예: "avatar_{:02d}.png" 또는 "avatar_{:02d}_cheer.png"
    (인덱스는 1부터 시작, row-major: idx = row*COLS + col + 1)
    """
    sheet = Image.open(sheet_path).convert("RGB")
    w, h = sheet.size
    cellw, cellh = w / COLS, h / ROWS

    os.makedirs(out_dir, exist_ok=True)
    for idx in range(1, COLS * ROWS + 1):
        row, col = (idx - 1) // COLS, (idx - 1) % COLS
        crop = crop_square(sheet, cellw, cellh, row, col)
        matted = remove(crop, session=session)          # 배경 제거(RGBA)
        matted = matted.resize((OUT_SIZE, OUT_SIZE), Image.LANCZOS)
        matted.save(os.path.join(out_dir, out_pattern.format(idx)))


if __name__ == "__main__":
    session = new_session("u2net")   # 세션 재사용 → 이미지당 처리 속도 대폭 단축

    process_sheet(
        os.path.join(AVDIR, "raw", "sheet_normal.png"),
        "avatar_{:02d}.png", AVDIR, session)

    process_sheet(
        os.path.join(AVDIR, "raw", "sheet_cheer.png"),
        "avatar_{:02d}_cheer.png", STATEDIR, session)

    process_sheet(
        os.path.join(AVDIR, "raw", "sheet_sad.png"),
        "avatar_{:02d}_sad.png", STATEDIR, session)

    print("done")
```

3개 시트(60장) 처리에 세션 재사용 시 약 18초 걸렸다(로컬 CPU 추론 기준).

**중요**: 결과물은 **사각형 + 투명 배경**으로 저장하고 원형 마스크는 씌우지 않는다.
원형으로 보여줄 필요가 있는 화면은 앱(Delphi) 쪽에서 처리한다(현재는 원형 클리핑도
쓰지 않고 사각형 그대로 표시 — `Gostop.Board.pas`의 `DrawPlayerPanel`/`DrawGameOver` 등 참고).

---

## 4. 검증(halo 유무 확인)

밝은/흰 배경에서는 halo가 안 보이므로, **반드시 어두운 배경에 합성**해서 눈으로 확인한다.

```python
from PIL import Image

im = Image.open(r"C:\works\projects\gostop\assets\avatars\avatar_01.png").convert("RGBA")
big = im.resize((512, 512), Image.NEAREST)
bg = Image.new("RGBA", (512, 512), (20, 30, 20, 255))   # 앱 패널 배경과 비슷한 어두운 색
bg.alpha_composite(big)
bg.save(r"C:\scratch\check.png")   # 열어서 경계에 흰 테두리가 없는지 확인
```

여러 장을 한 번에 훑어볼 땐 격자로 합쳐서 확인하면 빠르다:

```python
from PIL import Image
import os

def make_grid(get_path, count, cols, cell=128, bg_color=(20, 30, 20, 255)):
    rows = (count + cols - 1) // cols
    grid = Image.new("RGBA", (cell * cols, cell * rows), bg_color)
    for i in range(1, count + 1):
        im = Image.open(get_path(i)).convert("RGBA")
        r, c = (i - 1) // cols, (i - 1) % cols
        grid.alpha_composite(im, (c * cell, r * cell))
    return grid

AVDIR = r"C:\works\projects\gostop\assets\avatars"
grid = make_grid(lambda i: os.path.join(AVDIR, f"avatar_{i:02d}.png"), 20, 5)
grid.save(r"C:\scratch\grid_normal.png")
```

---

## 5. 새 아바타·새 감정 상태 추가할 때

1. 같은 격자 규격(또는 §2 방식대로 새 `COLS`/`ROWS`/`TOP_FRAC` 산정)으로 시트를 준비해
   `assets/avatars/raw/sheet_<상태명>.png`로 저장.
2. §3 스크립트의 `process_sheet(...)` 호출을 하나 추가(출력 파일명 패턴만 바꿔서).
3. `assets/characters.json`의 각 캐릭터 `images` 필드에 새 상태 경로를 추가
   (`Gostop.Characters.pas`의 `CheerImageOf`/`SadImageOf`처럼 조회 함수도 필요하면 추가).
4. `Gostop.Board.pas`의 `LoadAvatarPool`이 `assets\avatars`의 `avatar_*.png`를 정렬해
   로드하고, **같은 인덱스로** `characters.json`의 상태 이미지 경로를 찾아 나란히 로드한다
   (파일 순서 = JSON 인덱스 순서라는 프로젝트 불변식 유지 필수 — `docs/characters.md` §1 참조).
5. `build.ps1` 실행(→ `bin\assets` 동기화 필수, `.png`는 robocopy 대상에서 제외되지 않음).
