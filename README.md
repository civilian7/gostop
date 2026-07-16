# 고스톱 (Go-Stop)

한국 전통 화투 게임 **고스톱**. Delphi FMX 기반 게임 코어 + 화투 이미지 에셋.

## 구조

```
src/                     게임 코어
  Gostop.Cards.pas       카드 데이터 모델 · 48장 정본 테이블
  Gostop.Deck.pas        덱 생성 · 셔플(LCG/시드/CSPRNG) · 드로우
  Gostop.Deal.pas        딜링(2인 10/8 · 3인 7/6) · 재분배 판정
  Gostop.Score.pas       족보 점수 · 고/피박/광박 정산 · 룰 옵션
  Gostop.Play.pas        턴 엔진(전체 룰) · 게임 상태
  Gostop.AI.pas          능력치 0~100 몬테카를로 AI
  Gostop.Assets.pas      에셋 경로 탐색
  Gostop.CardImages.pas  FMX 비트맵 캐시 로더
assets/hwatu/            화투 이미지(PNG 600×978 · SVG) · 조커 · 뒷장 · 라이선스
```

## 구현 기능

- **카드/덱/딜링**: 48장 모델, 표준 분배, 보너스패 옵션
- **전체 룰**: 먹기 · 뻑 · 따닥 · 쓸 · 쪽 · 자뻑 · 연뻑 · 첫뻑 · 흔들기 · 폭탄 · 카드빚 · 총통 · 고/스톱
- **점수**: 광 · 열끗(고도리) · 띠(홍/청/초단) · 피(쌍피) · 정산(피박/광박, 고·흔들 배수)
- **셔플**: Fisher–Yates + Windows `BCryptGenRandom`(CSPRNG, 편향 없음), 시드 셔플(재현용)
- **AI**: 능력치 하나로 4축 연동(실수·무작위성 / 고·스톱 EV / 결정화 몬테카를로 수읽기 / 방어)

## 빌드

- Delphi 13 (RAD Studio 37.0), 타깃 Win64
- 코어 RTL 유닛은 `dcc64`로 독립 컴파일 가능 (이미지 로더만 FMX 의존)

## 라이선스

- 코드: 프로젝트 소유
- 기본 48장 이미지: Wikimedia Commons **CC BY-SA 4.0** (`assets/hwatu/attribution.tsv`)
- 조커 · 뒷장 이미지: 자체 제작(자유 사용)
