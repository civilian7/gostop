# 아바타 이미지 파이프라인 (배경 제거·크롭)

캐릭터 시트(여러 인물이 격자로 배열된 큰 이미지) 한 장에서 인물 20명을 잘라내
`assets/avatars/`에 쓰는 개별 PNG로 만드는 절차, 그리고 사진 한 장짜리 캐릭터
교체 절차. 평상시·환호·슬픔 등 감정 상태별 시트를 추가하거나 캐릭터 1명의 사진만
바꿀 때 이 문서의 스크립트(`scripts/avatar_bg_remove.py`)를 그대로 재사용한다.

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

## 3. 스크립트: `scripts/avatar_bg_remove.py`

시트를 자르는 것도, 이미 한 장짜리인 인물 사진(정사각이 아니어도 됨 — 중앙 기준으로
자동 정사각 크롭)을 처리하는 것도 같은 스크립트 하나로 한다. 두 서브커맨드:

```powershell
# 단일 파일 — 인물 사진 한 장을 128x128 정사각·배경투명 PNG로
python scripts/avatar_bg_remove.py single <입력경로> <출력경로>
python scripts/avatar_bg_remove.py single input.png output.png --size 256   # 크기 지정

# 격자 시트 — 5열x4행(20명) 등 여러 인물이 격자로 배열된 시트 1장을 일괄 처리
python scripts/avatar_bg_remove.py sheet <시트경로> <출력폴더> "<파일명패턴>"
python scripts/avatar_bg_remove.py sheet assets/avatars/raw/sheet_normal.png assets/avatars "avatar_{:02d}.png"
python scripts/avatar_bg_remove.py sheet assets/avatars/raw/sheet_cheer.png assets/avatars/states "avatar_{:02d}_cheer.png"
python scripts/avatar_bg_remove.py sheet assets/avatars/raw/sheet_sad.png assets/avatars/states "avatar_{:02d}_sad.png"
```

`sheet` 모드는 격자가 5×4가 아니면 `--cols`/`--rows`, 크롭 시작 위치가 다르면
`--top-frac`으로 조정한다(§2 참조). 3개 시트(60장) 처리에 세션 재사용 시 약 18초
걸렸다(로컬 CPU 추론 기준). `single` 모드는 이미 avatar_NN.png로 만들어진 캐릭터를
한 명만 새 사진으로 교체하고 싶을 때 쓴다(격자 좌표 계산 없이 그 사진 자체를
중앙 기준 정사각 크롭 → 배경 제거).

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

**감정 상태를 통째로 추가**(예: 20명 전원의 "화남" 상태 신설)할 때:

1. 같은 격자 규격(또는 §2 방식대로 새 `COLS`/`ROWS`/`TOP_FRAC` 산정)으로 시트를 준비해
   `assets/avatars/raw/sheet_<상태명>.png`로 저장.
2. `python scripts/avatar_bg_remove.py sheet assets/avatars/raw/sheet_<상태명>.png assets/avatars/states "avatar_{:02d}_<상태명>.png"` 실행.
3. `assets/characters.json`의 각 캐릭터 `images` 필드에 새 상태 경로를 추가
   (`Gostop.Characters.pas`의 `CheerImageOf`/`SadImageOf`처럼 조회 함수도 필요하면 추가).
4. `Gostop.Board.pas`의 `LoadAvatarPool`이 `assets\avatars`의 `avatar_*.png`를 정렬해
   로드하고, **같은 인덱스로** `characters.json`의 상태 이미지 경로를 찾아 나란히 로드한다
   (파일 순서 = JSON 인덱스 순서라는 프로젝트 불변식 유지 필수 — `docs/characters.md` §1 참조).
5. `build.ps1` 실행(→ `bin\assets` 동기화 필수, `.png`는 robocopy 대상에서 제외되지 않음).

**캐릭터 1명의 사진만 교체**할 때(격자 시트 없이 사진 한 장만 있는 경우):

1. `python scripts/avatar_bg_remove.py single <새 사진> assets/avatars/avatar_NN.png` 실행
   (상태별로도 동일하게 `assets/avatars/states/avatar_NN_{cheer,sad}.png`).
2. `build.ps1` 실행.
