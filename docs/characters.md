# 고스톱 캐릭터 시스템 종합 문서

게임 내 등장인물(플레이어 캐릭터) 20인의 **정본 문서**.
아바타 이미지 → 닉네임 → 페르소나 → AI 성향 → 대사가 하나의 캐릭터로 묶이는 전체 체계를 정의한다.
(구 `avatar-prompts.md`, `avatar-personas.md`를 통합·대체)

> **데이터 원본은 `assets/characters.json`.** 이름·능력치·페르소나(나이/직업·성격·성향·대사)·이미지
> 경로가 전부 이 JSON에 있으며, `Gostop.Characters.pas`가 지연 로드해 코드에서 조회한다.
> 본 문서 §4는 그 JSON을 만든 원본 자료(사람이 읽는 서사·이미지 프롬프트)이자 사람이 보는 참고 문서다.
> **캐릭터를 추가/수정할 땐 `assets/characters.json`을 고치고, 필요하면 본 문서도 함께 갱신할 것.**

---

## 1. 캐릭터 시스템 개요

캐릭터 1명 = 다음 5요소의 결합:

| 요소 | 내용 | 현재 구현 |
|------|------|-----------|
| **아바타** | 원형 128×128 PNG, 상태별 3장(`assets/avatars/avatar_NN.png` 평상시, `avatars/states/avatar_NN_{cheer,sad}.png` 환호·슬픔) | ✅ 풀 로드·표시(정산창 승자=환호/패자=슬픔) |
| **닉네임** | `characters.json`의 `name` | ✅ 패널·결과·이벤트 표시 |
| **페르소나** | `characters.json`의 `ageJob`/`personality`/`playstyle`(본 문서 §4가 원본) | ✅ JSON 저장(코드 조회 함수 있음, 화면 표시는 미구현) |
| **AI 성향** | 난이도(스킬)·고 성향·공격/방어 가중 | ⚠️ 난이도만(대전 설정 수동) |
| **대사** | `characters.json`의 `quotes`(3개, 본 문서 §4가 원본) | ✅ JSON 저장(말풍선 표시는 미구현) |

### 게임 내 흐름 (현재)
1. **대전 설정 다이얼로그**: 슬롯머신 연출로 AI 시트에 캐릭터 랜덤 배정(한 게임 내 중복 금지). 사람은 시트 선택 또는 관전.
2. 배정된 캐릭터의 **아바타+닉네임**이 패널·선 뽑기·결과창·이벤트 텍스트 전반에 표시.
3. 게임 종료 정산창: 승자는 환호(cheer) 아바타, 패자는 슬픔(sad) 아바타로 표시.
4. AI 난이도는 시트별 수동 지정(초급30/중급50/고급70/최상90).

### 코드 연동 지점
- `assets\characters.json`: 20인 정본 데이터(이름·능력치·페르소나·대사·이미지 경로). **단일 진실 공급원.**
- `src\engine\Gostop.Characters.pas`: JSON을 지연 로드해 조회 함수 제공(`NameOf`/`StatOf`/`AgeJobOf`/`PersonalityOf`/`PlaystyleOf`/`QuoteOf`/`CheerImageOf`/`SadImageOf` 등).
- `src\engine\Gostop.Board.pas`: `LoadAvatarPool`/`FSeatAvatar`(아바타 3풀: 평상시·환호·슬픔), `FSeatSkill`(난이도), `SeatDisplayName`(표시명), `BuildFinalSummary`/`DrawGameOver`(정산창 승자·패자 아바타).
- 아바타 파일 순서(`avatar_NN.png` 정렬) = JSON `index` 순서 = 본 문서 캐릭터 번호. **셋의 순서를 항상 일치시킬 것.**

---

## 2. 캐릭터 추가/교체 절차

1. **이미지**: 1:1(1024²) 상반신·투명배경으로 생성(§4의 프롬프트) → `assets/avatars/raw/avatar_NN.png`.
2. **크롭**: 얼굴 중심 정사각 128×128로 가공(원 마스크는 앱이 로드 시 적용) → `assets/avatars/avatar_NN.png`
   (평상시), `assets/avatars/states/avatar_NN_{cheer,sad}.png`(환호·슬픔, 같은 크롭 규칙).
3. **정본 데이터**: `assets/characters.json`에 항목 추가/수정(이름·능력치·`ageJob`/`personality`/`playstyle`/
   `quotes`/`images`). `Gostop.Characters.pas`는 코드 수정 없이 자동 반영(지연 로드).
4. **페르소나·대사**: 본 문서 §4에 카드 추가(JSON 작성의 원본 자료로 사용).
5. `build.ps1` 실행(→ `bin\assets` 동기화 필수).

### 이미지 생성 요령 (같은 얼굴 방지)
- **한 장씩 개별 생성**(그리드 금지), 캐릭터마다 **새 대화/새 시드**.
- 프롬프트에 나이·얼굴형·체형·헤어·의상 색을 **구체적으로 명시**(§4의 프롬프트가 그 형식).
- 그래도 닮으면 문장 끝에 `completely unique face, unlike any previous image` 추가.

---

## 3. 캐릭터 능력치 (✅ 구현됨)

### 3-1. 능력치 5종 — 각자 합계 100 (평균 20, 범위 5~40)

| 스탯 | 게임 반영 |
|------|-----------|
| **수읽기** | AI 몬테카를로 수읽기 깊이 (수읽기+침착 → 스킬 = 합×1.25) |
| **침착** | 실수율 억제 (스킬의 다른 축) |
| **배짱** | `TAiPlayer.GoBias`(20~90) — 고/스톱 판단을 고 쪽으로 기울임 |
| **욕심** | `TAiPlayer.Greed`(20~90) — 높으면 득점 우선, 낮으면 방어(견제) 우선 |
| **운** | 판별 운 굴림의 기반치(아래 §3-3) |

### 3-2. 20인 능력치표 (`assets/characters.json`의 `stats`)

| # | 캐릭터 | 수읽기 | 침착 | 배짱 | 욕심 | 운 | 유도 스킬 |
|---|--------|-----:|-----:|-----:|-----:|---:|------:|
| 1 | 피주워요 | 10 | 15 | 10 | 25 | **40** | 31 |
| 2 | 못먹어도고 | 10 | 10 | **40** | 30 | 10 | 25 |
| 3 | 광팔이 | 25 | 25 | 15 | 25 | 10 | 63 |
| 4 | 흔들신사 | 25 | 20 | 30 | 15 | 10 | 56 |
| 5 | 동네타짜 | **35** | 30 | 15 | 15 | 5 | 81 |
| 6 | 초단콜렉터 | 20 | 25 | 10 | **35** | 10 | 56 |
| 7 | 고도리헌터 | 25 | 15 | 25 | 30 | 5 | 50 |
| 8 | 쌍피장인 | 25 | 30 | 15 | 20 | 10 | 69 |
| 9 | 뻑전문가 | 10 | 5 | 25 | 20 | **40** | 19 |
| 10 | 화투도사 | **40** | 25 | 15 | 10 | 10 | 81 |
| 11 | 쪽쪽이 | 10 | 15 | 20 | 25 | 30 | 31 |
| 12 | 싹쓸이요정 | 15 | 10 | 30 | 30 | 15 | 31 |
| 13 | 피박금지 | 20 | 30 | 10 | 10 | 30 | 63 |
| 14 | 고고고 | 10 | 10 | **40** | 25 | 15 | 25 |
| 15 | 국진할멈 | 30 | 25 | 10 | 15 | 20 | 69 |
| 16 | 스톱은없다 | 15 | 15 | **40** | 25 | 5 | 38 |
| 17 | 자뻑여왕 | 20 | 15 | 30 | 25 | 10 | 44 |
| 18 | 점백의달인 | **40** | 30 | 10 | 15 | 5 | 87 |
| 19 | 판쓸이할매 | 30 | 20 | 25 | 20 | 5 | 63 |
| 20 | 옆집고수 | **35** | **35** | 10 | 10 | 10 | 87 |

- 대전 설정의 난이도 기본값은 **[고유]** — 캐릭터 유도 스킬 사용. 초급~최상 선택 시 스킬만 오버라이드(배짱·욕심은 항상 캐릭터 고유).
- 실측: 배짱 90 vs 20 → 600판 총 고 횟수 645 vs 216 (3배 차).

### 3-3. 운 시스템 (✅ 구현됨 — 검토 결과 포함)

- **판별 운 굴림**: 새 판마다 `운 스탯×2 ± 15`(5~99). 사람도 **선택한 아바타의 운 스탯**을 따른다. 패널 전적 행에 ★1~5로 표시.
- **반영 방식 — 뒤집기 흐름 보정**(`TTurnEngine.PlayerLuck`): 더미를 뒤집을 때 운이 높으면 **맨 위 2장 중 유리한 쪽**(바닥 매칭·보너스)이, 낮으면 불리한 쪽이 올라오도록 은밀히 교환(확률 = |운−50|%). 뒷면이라 관측 불가, 시뮬·검증기는 미설정(순수 확률).
- **실측 효과**: 동일 실력 AI, 운 90 vs 10 → **승률 62.6%**(800판). 운 50:50이면 무보정.
- **검토 후 폐기한 방식**: 딜 직후 "좋은 손패를 운 높은 쪽에 배정" — 배정 자체는 정확(83%)했으나 **시작 손패 품질은 승패 예측력이 없음이 실측됨**(품질 우위 승률 46%, 선 승률 50%) → 승률이 안 움직여 미채택(`TDealer.LuckReassign`/`HandQuality`는 실험 유틸로 유지).

### 3-4. 대사 트리거 (미구현)
`TPlayEvent` 수신 시 해당 캐릭터의 대사를 아바타 옆 말풍선으로 2초 표시 (`sound-and-voice.md` §4).

| 트리거 | 대사 슬롯 |
|--------|-----------|
| 쪽/따닥/싹쓸이 성공 | 기쁨 대사 |
| 뻑/피 뺏김 | 탄식 대사 |
| 고 선언 | 고 대사 |
| 스톱 선언/승리 | 마무리 대사 |

---

## 4. 캐릭터 로스터 20인

각 카드: 프로필 → 고스톱 성향(고 성향 ★1~5, 추천 난이도) → 대사 → 이미지 프롬프트(독립 완결형, 공통 프리픽스 없음).

---

### 01. 피주워요 — 19세 · 재수생
- **성격**: 뭐든 줍는 게 취미. 피 한 장에도 세상을 다 가진 듯 기뻐한다. 순진하고 소심.
- **성향**: 피만 판다. 점수 나면 무조건 스톱. **고 ★☆☆☆☆ · 초급(30)** · Greed 30
- **대사**: "피다 피! 줍줍~" / "이것도 제 거죠…?" / "스, 스톱할게요!"
```
A skinny 19-year-old Korean boy with messy curly black hair and freckles, buck-toothed eager grin, oversized gray hoodie, joyfully holding up one single Korean hwatu flower card like a precious treasure. Cheerful webtoon-style illustration, upper body, transparent background, square format.
```

### 02. 못먹어도고 — 25세 · 헬스트레이너
- **성격**: 인생 좌우명이 닉네임. 계산 없이 기세로 산다. 지고도 웃는 대인배.
- **성향**: 점수만 나면 무조건 고. 피박 위기에도 고. **고 ★★★★★ · 중급(50)** · Greed 90
- **대사**: "못 먹어도 고!!" / "사나이는 직진!" / "어? 고박…? 그게 뭐죠?"
```
Hot-blooded 25-year-old Korean man, square jaw, military buzz cut, thick black eyebrows, red fighting-spirit headband, white sporty shirt, fist raised and eyes on fire, gripping hwatu cards in the other hand. Dynamic comic-book portrait from the waist up, isolated on transparent background, 1:1.
```

### 03. 광팔이 — 45세 · 보험영업 부장
- **성격**: 뭐든 팔아치우는 영업의 신. 광 모으기보다 광 팔기가 이득이라 믿는다.
- **성향**: 4인전 광팔기 기회를 노림. 참가하면 실속형 3점 스톱. **고 ★★☆☆☆ · 고급(70)** · Greed 50
- **대사**: "광 삽니다~ 아니, 팝니다~" / "이건 남는 장사죠." / "스톱! 정산합시다."
```
Portrait of a chubby 45-year-old Korean card salesman: slicked-back oily hair, thin mustache, gold-rimmed glasses with a coin glint, shiny blue suit and gold tie, winking slyly while fanning out three shining "gwang" hwatu cards. Glossy cartoon style, bust shot, no background, square.
```

### 04. 흔들신사 — 58세 · 은퇴한 은행지점장
- **성격**: 매너 좋고 여유롭지만 배수 욕심이 있다. 흔들 기회는 절대 안 놓친다.
- **성향**: 같은 월 3장이면 반드시 흔든다. 배수 걸리면 과감히 고. **고 ★★★★☆ · 고급(70)** · Greed 70
- **대사**: "흔들고 가겠습니다, 하하." / "신사는 두 배로 걸지요." / "실례지만, 고."
```
A tall, slim 58-year-old Korean gentleman wearing a brown fedora and a brown checked three-piece suit with a pocket-watch chain, bushy gray mustache, refined smile, elegantly shaking three hwatu flower cards in one gloved hand. Classic storybook illustration, upper body only, transparent backdrop, 1:1 ratio.
```

### 05. 동네타짜 — 50세 · 직업불명
- **성격**: 경로당~복덕방을 평정한 실전파. 말수 적고 눈빛으로 압박.
- **성향**: 상대 패를 외우는 방어형. 확신 없으면 스톱, 서면 3고. **고 ★★★☆☆ · 최상(90)** · Greed 60
- **대사**: "……" / "그 패, 내려놓지 그래." / "판은 내가 접는다. 스톱."
```
Stocky 50-year-old Korean hustler with a white crew cut, square face, small scar on his cheek, black sunglasses, toothpick in the corner of his mouth, black leather jacket, smug poker face, shuffling hwatu cards with one hand. Gritty cartoon portrait, chest-up, cut out on transparency, square image.
```

### 06. 초단콜렉터 — 30세 · 문구 덕후 개발자
- **성격**: 수집벽. 초단 셋이 모이는 순간의 희열로 산다.
- **성향**: 초단(4·5·7월 띠) 집착. 완성하면 만족하고 스톱. **고 ★★☆☆☆ · 중급(50)** · Greed 40
- **대사**: "초단… 컴플리트." / "그 띠, 제 겁니다만." / "컬렉션이 완성됐으니 스톱."
```
A round-faced 30-year-old Korean collector with neatly parted hair, thick horn-rimmed glasses, knitted sweater vest with a bow tie and white cotton gloves, proudly presenting three red-ribbon hwatu cards like rare stamps. Soft pastel comic illustration, upper torso, transparent background, 1:1.
```

### 07. 고도리헌터 — 40세 · 조류 사진작가
- **성격**: 새만 보면 눈이 돌아간다. 매복형 사냥꾼 기질.
- **성향**: 2·4·8월 열끗 최우선. 고도리 완성 전엔 스톱 없음. **고 ★★★★☆ · 고급(70)** · Greed 70
- **대사**: "새 발견. 조준." / "고도리 완성까지 스톱은 없다." / "다섯 점, 회수."
```
Rugged sun-tanned 40-year-old Korean man in a khaki hunting vest and feathered hunter's hat, bushy beard, binoculars hanging on his chest, sharp hawk-like focus, fanning three bird-themed hwatu cards. Adventure-comic style bust portrait, isolated subject with no background, square.
```

### 08. 쌍피장인 — 65세 · 전직 목수
- **성격**: 과묵한 장인. 쌍피 한 장의 가치를 아는 사람. 서두르지 않는다.
- **성향**: 고가치 피 위주 실속 플레이. 피박 걸리면 1고. **고 ★★★☆☆ · 고급(70)** · Greed 50
- **대사**: "쌍피는… 예술이지." / "급할 것 없네." / "이만하면 됐어. 스톱."
```
A bald 65-year-old Korean craftsman with white side hair and deep forehead wrinkles, artisan headband and apron over modern hanbok work clothes, reverently holding up a double-junk hwatu card with both hands as if it were a masterpiece. Warm hand-drawn animation still, waist-up, transparent PNG, 1:1.
```

### 09. 뻑전문가 — 70세 · 경로당 총무
- **성격**: 손대는 판마다 뻑. 본인도 알고 자학개그로 승화하는 미워할 수 없는 캐릭터.
- **성향**: 뻑 다발, 가끔 자뻑 대박. 판단 들쑥날쑥. **고 ★★★☆☆(무작위) · 초급(30)** · Greed 50
- **대사**: "아이고 또 쌌네." / "이게 다 큰 그림이야… 자뻑!" / "뻑도 실력이다!"
```
Comical 70-year-old balding Korean man with round glasses sliding down his nose, saggy tired eyes, flustered crying-smile and a giant sweat drop, worn brown vest, hwatu cards slipping and scattering out of his hands. Gag-manhwa style upper-body drawing, transparent background, square frame.
```

### 10. 화투도사 — 80세 · 산에서 내려온 노인
- **성격**: 화투 60년. 패의 흐름을 읽는다(고 주장). 도사 어투.
- **성향**: 남은 패 계산 정확, 이길 판만 고른다. **고 ★★★☆☆ · 최상(90)** · Greed 55
- **대사**: "패에는 길이 있느니라." / "오늘 자네 운은 여기까지." / "하늘이 스톱하라 하는구나."
```
An 80-year-old Korean taoist sage with long flowing white hair and beard, black traditional gat hat and gray dopo robe, serene half-closed eyes, a single hwatu card glowing and floating above his open palm. Mystical ink-and-color illustration, bust composition, isolated on transparency, 1:1.
```

### 11. 쪽쪽이 — 20세 · 대학생
- **성격**: 애교 만렙. 쪽 하나로 온 동네 자랑. 지면 금방 시무룩.
- **성향**: 쪽·따닥 이벤트에 목숨. 재미 우선. **고 ★★★☆☆ · 초급(30)** · Greed 60
- **대사**: "쪽! 헤헤, 봤어요?" / "피 주세요~ 네?" / "한 번만 더! 고!"
```
Adorable 20-year-old Korean girl with a heart-shaped face, twin braided pigtails tied with pink ribbons, rosy blush, bright pink hanbok, winking and blowing a kiss surrounded by tiny hearts, hwatu cards held to her chest. Cute shoujo-style cartoon, upper body, transparent background, square.
```

### 12. 싹쓸이요정 — 24세 · 편의점 알바
- **성격**: 밝고 장난기 가득. 바닥이 비는 순간이 인생의 낙.
- **성향**: 싹쓸이 각이 보이면 올인. 성공하면 기고만장 고. **고 ★★★★☆ · 중급(50)** · Greed 75
- **대사**: "쓸~어 담아요!" / "바닥 청소 완료☆" / "기분이다, 고!"
```
A playful 24-year-old Korean woman with a silver bob haircut and mischievous cat-like eyes, sky-blue hanbok sparkling with fairy dust, gleefully sweeping an entire pile of hwatu cards toward herself with both arms. Whimsical fantasy cartoon, waist-up, cut out with no background, 1:1 aspect.
```

### 13. 피박금지 — 48세 · 시장 반찬가게 사장
- **성격**: 억척스럽고 방어적. 피박 안 당하는 게 최우선.
- **성향**: 피 확보 전까지 초조. 방어·견제 위주, 웬만하면 스톱. **고 ★☆☆☆☆ · 중급(50)** · Greed 20
- **대사**: "피박만은 안 돼!" / "그 피 이리 내." / "됐어 됐어, 스톱!"
```
A plump 48-year-old Korean auntie with a tight brown perm, fierce narrowed eyes, arms crossed in a firm X "forbidden" gesture, yellow hanbok, a small stack of junk hwatu cards guarded behind her. Bold flat-color caricature, chest-up view, transparent backdrop, square canvas.
```

### 14. 고고고 — 35세 · 필라테스 강사
- **성격**: 에너지 과잉 응원단장 출신. 뭐든 외치고 본다.
- **성향**: 분위기 타면 못 멈춘다. 2고까지 자동. **고 ★★★★★ · 중급(50)** · Greed 85
- **대사**: "고! 고! 고!" / "멈추면 지는 거야!" / "아자아자!"
```
Energetic 35-year-old Korean woman with a long straight ponytail, mouth wide open in an excited cheer, red tracksuit, cheerleading pom-pom in one hand and hwatu cards in the other, speed lines bursting around her. Sporty anime-style half-body shot, transparent background, 1:1.
```

### 15. 국진할멈 — 68세 · 화초 가꾸는 할머니
- **성격**: 온화하지만 국진 한 장으로 판을 뒤집는 노련미.
- **성향**: 국진 활용(열끗↔쌍피)의 달인. 조용히 쌓고 결정적일 때 스톱. **고 ★★☆☆☆ · 고급(70)** · Greed 45
- **대사**: "국진이는 내 새끼야." / "어이쿠, 이게 쌍피가 되네?" / "이 늙은이가 이겼네, 호호."
```
A 68-year-old Korean grandmother with silver hair in a traditional bun fixed by a binyeo hairpin, deep smile wrinkles around her eyes, forest-green hanbok, slyly holding up the chrysanthemum hwatu card between two fingers like a hidden ace. Gentle folk-art style portrait, upper body, isolated transparent background, square.
```

### 16. 스톱은없다 — 27세 · 격투기 선수
- **성격**: 후퇴를 모르는 승부사. 지면 바로 "한 판 더".
- **성향**: 3고·4고 불사. 고박 최다 보유자. **고 ★★★★★ · 고급(70)** · Greed 95
- **대사**: "스톱? 그런 건 없다." / "링에서도 판에서도 직진." / "4고. 불만 있나."
```
Intense 27-year-old Korean woman with long dark-red hair blowing in the wind, burning determined eyes, black leather jacket, clenched fist, gripping hwatu cards so hard they bend, an unstoppable aura around her. Dramatic action-comic bust portrait, no background, 1:1 format.
```

### 17. 자뻑여왕 — 38세 · 인플루언서
- **성격**: 근거 있는(?) 자신감. 자기가 낸 뻑도 자기가 먹는 여왕님.
- **성향**: 화려한 플레이 선호(자뻑·폭탄). 잘 풀리면 폭주 고. **고 ★★★★☆ · 고급(70)** · Greed 80
- **대사**: "역시 나야." / "자뻑? 그것도 실력이야." / "여왕의 판이지, 고."
```
Glamorous 38-year-old Korean woman with wavy golden-brown hair, bold makeup and red lips, a small golden crown, purple power suit, chin raised in a self-adoring queen pose with sparkles everywhere, holding hwatu cards like a royal scepter. Luxurious fashion-cartoon illustration, upper body, transparent background, square.
```

### 18. 점백의달인 — 52세 · 세무사
- **성격**: 모든 걸 숫자로 환산하는 냉철파. 점백 기대값 암산이 특기.
- **성향**: 기대값 플러스일 때만 고. 박 확률 계산 정확. **고 ★★★☆☆(계산형) · 최상(90)** · Greed 50
- **대사**: "기대값 +240원. 고." / "그 수는 마이너스입니다." / "정산하죠. 스톱."
```
A shrewd 52-year-old Korean woman with hair in a tight bun and reading glasses slid down her nose, navy modern hanbok, wooden abacus in one hand and hwatu cards in the other, thin calculating smile. Detailed slice-of-life manhwa portrait, waist-up, cut out on transparency, 1:1.
```

### 19. 판쓸이할매 — 75세 · 전설의 시장 할매
- **성격**: 시장통에서 다진 실전 감각. 웃는 얼굴로 판돈을 쓸어간다.
- **성향**: 초반 약한 척, 후반 몰아치기. 상대 시드가 마를 때까지 고. **고 ★★★★☆ · 최상(90)** · Greed 85
- **대사**: "아이고 나 잘 몰라~ (스윽)" / "요것만 받아갈게." / "판은 쓸어야 제맛이지!"
```
A 75-year-old Korean grandmother with a tight gray perm and a gold-tooth grin, flower-patterned monpe pants and a padded vest, rolling up her sleeves triumphantly over a swept-up pile of hwatu cards and coins. Humorous rural-comic style, upper body, transparent background, square image.
```

### 20. 옆집고수 — 72세 · 평범한(?) 이웃
- **성격**: 온화한 미소의 정체불명 고수. 본인은 "심심풀이"라 주장.
- **성향**: 빈틈 없음. 상대가 모으는 걸 보고 길목을 끊는다. 무리수 없음. **고 ★★☆☆☆ · 최상(90)** · Greed 40
- **대사**: "차 한잔하고 하지." / "어머, 그거 필요했어요?" / "오늘도 심심풀이 잘 했네."
```
A gentle-looking 72-year-old Korean grandmother with soft short white hair and round glasses, beige cardigan, calmly sipping tea — but her eyes over the teacup rim are razor-sharp like a hidden master, hwatu cards stacked neatly in front of her. Cozy yet subtly tense cartoon portrait, bust view, isolated on transparent background, 1:1.
```

---

## 5. 로드맵

| 단계 | 내용 | 상태 |
|------|------|------|
| 1 | 아바타 풀 + 닉네임 + 슬롯머신 배정 + 시트/관전 | ✅ 완료 |
| 2 | 닉네임 차별화 아바타 이미지 재생성(§4 프롬프트) | 🔲 이미지 생성 대기 |
| 3 | 능력치 5종(합100) + AI 자동 주입 + 판별 운(뒤집기 보정) | ✅ 완료(§3) |
| 4 | 이벤트 말풍선(캐릭터 대사) | 🔲 |
| 5 | 캐릭터별 전적/상성 기록 | 🔲 아이디어 |
