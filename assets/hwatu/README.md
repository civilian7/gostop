# 화투 이미지 리소스 (Hwatu Card Assets)

고스톱(Go-Stop) 게임용 화투패 이미지 세트. 한국 화투 스타일.

## 구성

| 폴더 | 기본 48장 | 조커(보너스패) | 뒷장 | 기타 | 합계 |
|------|:--------:|:-------------:|:----:|:----:|:----:|
| `png/` | 48 | 4 | 5 | - | 57 |
| `svg/` | 48 | 4 | 5 | 5 | 62 |

- **PNG**: **600 × 978 px 균일**, 투명 배경(알파). 전 카드(앞면·조커·뒷장) 동일 규격. 대부분의 게임 프레임워크에서 바로 사용.
- **SVG**: 벡터 원본(viewBox `103.2 × 168.2`). 확대해도 깨지지 않음.
- **기타(SVG 전용)**: `*_flipped.svg` 4장(뒤집힌 변형), `overview.svg` 1장(전체 몽타주 — 카드 아님). 게임에서 카드 목록을 로드할 때는 이 5개를 제외할 것.

## 파일명 규칙

기본 카드: `<month>_<type>[_n].png`

- **month**: `january` ~ `december` (1월~12월)
- **type**: 하나후다 용어 → 한국 화투 족보 대응
  - `hikari` = **광(光)**
  - `tane` = **열끗(십, 10점짜리 동물/사물)**
  - `tanzaku` = **띠(단, 5점짜리 리본)**
  - `kasu` = **피(껍데기)** — 같은 월에 여러 장이면 `_1`, `_2`, `_3`

## 월별 구성 (한국 화투 기준)

| 월 | 이름 | 광 | 열끗 | 띠 | 피 | 파일 |
|:--:|------|:--:|:--:|:--:|:--:|------|
| 1 | 송학(솔) | ● | | ● | 2 | `january_hikari`, `january_tanzaku`, `january_kasu_1/2` |
| 2 | 매조(매화) | | ● | ● | 2 | `february_tane`, `february_tanzaku`, `february_kasu_1/2` |
| 3 | 벚꽃(사쿠라) | ● | | ● | 2 | `march_hikari`, `march_tanzaku`, `march_kasu_1/2` |
| 4 | 흑싸리 | | ● | ● | 2 | `april_tane`, `april_tanzaku`, `april_kasu_1/2` |
| 5 | 난초 | | ● | ● | 2 | `may_tane`, `may_tanzaku`, `may_kasu_1/2` |
| 6 | 모란 | | ● | ● | 2 | `june_tane`, `june_tanzaku`, `june_kasu_1/2` |
| 7 | 홍싸리 | | ● | ● | 2 | `july_tane`, `july_tanzaku`, `july_kasu_1/2` |
| 8 | 공산(팔공산) | ● | ● | | 2 | `august_hikari`, `august_tane`, `august_kasu_1/2` |
| 9 | 국화(국진) | | ● | ● | 2 | `september_tane`, `september_tanzaku`, `september_kasu_1/2` |
| 10 | 단풍 | | ● | ● | 2 | `october_tane`, `october_tanzaku`, `october_kasu_1/2` |
| 11 | 오동(똥) | ● | | | 3 | `november_hikari`, `november_kasu_1/2/3` |
| 12 | 비 | ● | ● | ● | 1 | `december_hikari`, `december_tane`, `december_tanzaku`, `december_kasu` |

> 참고: 이 세트는 한국 화투 관례대로 **11월=오동, 12월=비**로 구성되어 있습니다.

### 특수 족보 (게임 로직 참고)

- **고도리(5점)**: `february_tane`(매조·새), `april_tane`(흑싸리·새), `august_tane`(공산·기러기)
- **홍단(3점)**: `january_tanzaku`, `february_tanzaku`, `march_tanzaku` (붉은 띠)
- **청단(3점)**: `june_tanzaku`, `september_tanzaku`, `october_tanzaku` (푸른 띠)
- **초단(3점)**: `april_tanzaku`, `may_tanzaku`, `july_tanzaku` (풀 띠)
- **비광**: `december_hikari` — 3광 계산 시 비광 포함이면 2점
- **쌍피 취급(관례)**: `september_tane`(국진)를 쌍피로 쓰는 규칙, `november_kasu`/`december_kasu` 등은 룰 설정에 따름

## 조커 (보너스패)

`bonus_*` — 기본 48장과 톤을 맞춰 **자체 제작**한 오리지널 이미지(라이선스 자유).

| 파일 | 값 | 용도 |
|------|:--:|------|
| `bonus_ssangpi_1` | 2 | 쌍피 |
| `bonus_ssangpi_2` | 2 | 쌍피 (색상 변형) |
| `bonus_sampi` | 3 | 3피 |
| `bonus_joker` | 2 | 예비/조커 |

> 표준 고스톱 보너스패 구성은 **쌍피 2장 + 3피 1장(총 3장)**, 룰에 따라 최대 4장. 필요 없는 장은 로드에서 제외하세요.

## 뒷장 (Card Backs)

`back_*` — 앞면과 동일한 카드 실루엣으로 **자체 제작**(라이선스 자유). 실물 화투 뒷장처럼 **붉은 바탕에 촘촘한 대각선 다이아몬드 누빔 그물무늬**(엠보싱 질감)가 카드를 꽉 채우고, 얇은 테두리 + 라운드 모서리. 전통 주홍을 기본으로 색상 변형 제공.

| 파일 | 색상 |
|------|------|
| `back_red` | 전통 주홍/빨강 — 기본 |
| `back_blue` | 남색 |
| `back_green` | 진녹색 |
| `back_purple` | 자주(플럼) |
| `back_black` | 먹색 |

> 게임에서는 보통 뒷장 1종을 선택해 전체 덱에 적용합니다. 색상 테마 옵션으로 노출해도 좋습니다.

## 출처 및 라이선스

- **기본 48장 + SVG 기타**: [Wikimedia Commons — Category:Hwatu](https://commons.wikimedia.org/wiki/Category:Hwatu)
  - 라이선스: **CC BY-SA 4.0** (파일별 상세는 `attribution.tsv` 참조)
  - 재배포·공개 시 **출처 표기(Attribution)** 및 **동일 조건 공유(ShareAlike)** 필요
- **조커 4장(`bonus_*`)**: 본 프로젝트에서 자체 제작. 자유 사용.
- **뒷장 5장(`back_*`)**: 본 프로젝트에서 자체 제작. 자유 사용.

전체 파일별 저작자·라이선스·원본 링크: [`attribution.tsv`](./attribution.tsv)

## PNG 재생성 방법

SVG를 수정한 뒤 PNG를 다시 뽑으려면 headless Chrome 사용:

```
chrome --headless --disable-gpu --hide-scrollbars ^
  --force-device-scale-factor=1 --default-background-color=00000000 ^
  --window-size=600,978 --screenshot=out.png wrapper.html
```

(`wrapper.html`은 SVG를 `width:600px; height:978px`로 감싼 HTML. 전 카드 동일 규격 600×978)
