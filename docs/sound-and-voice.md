# 사운드 & 보이스 종합 문서 (효과음 + 나레이터 + BGM + 캐릭터 대사)

게임에 필요한 **모든 소리**의 정본 목록 + 생성용 프롬프트:
1부 효과음(SFX) · 2부 나레이터(게임 진행 보이스) · 3부 BGM/앰비언스 · 4부 캐릭터 대사.
(구 `audio-effects.md`를 대체. 캐릭터 페르소나는 `characters.md` 참조)

## 파일 규격 (필수)
- **WAV, 44.1kHz / 16bit / 스테레오** — `TGostopAudio`(waveOut 8채널)가 이 포맷만 재생.
- 효과음 0.2~1.5초, 대사 1~3초 권장. 위치: `assets/audio/` (대사는 `assets/audio/voice/avatar_NN/`).
- 리소스 추가·변경 후 **build.ps1 실행**(→ `bin\assets` 동기화).

## 제작 도구
- **효과음(text-to-SFX)**: ElevenLabs Sound Effects, Stability Stable Audio — 아래 영문 프롬프트 사용. 무료 대안: freesound.org(CC0 검색).
- **대사(TTS)**: ElevenLabs(멀티링구얼 v2, 한국어 지원), Typecast(한국어 특화). 캐릭터마다 아래 보이스 프로필로 목소리를 만들고 대사를 입력.

---

# 1부. 효과음 (SFX)

## 1-1. 보유 중 (28종 — CC0 Kenney 팩 기반)

교체(품질 업그레이드)를 원할 때 아래 프롬프트로 재생성한다.

| 파일 | 트리거 | 생성 프롬프트 (영문) |
|------|--------|----------------------|
| card_deal | 딜 시작·셔플 | `rapid riffle shuffle of stiff plastic cards, crisp, 1 second` |
| card_place | 카드 놓기/딜 착지/릴 정지 | `single stiff card slapped down on a felt table, short sharp snap, 0.3s` |
| card_flip | 카드 뒤집기/선뽑기 공개 | `quick card flip with a light flick, subtle air whoosh, 0.25s` |
| card_capture | 바닥패 쓸어오기 | `cards sliding across felt and gathered into a hand, smooth swish, 0.6s` |
| ui_hover | 손패 호버 | `extremely short soft UI tick, gentle, 0.1s` |
| ui_click | 버튼/카드 클릭 | `clean UI button click, wooden tone, 0.15s` |
| ui_select | 선택 모드 진입 | `soft confirmation blip, two quick rising tones, 0.3s` |
| sfx_jjok | 쪽 | `playful short "pop" with a tiny bell, cheerful accent, 0.4s` |
| sfx_ttadak | 따닥 | `two rapid card slaps in quick succession, snappy, 0.4s` |
| sfx_sseul | 싹쓸이 | `long satisfying sweep of many cards across a table, whoosh, 0.8s` |
| sfx_bomb | 폭탄 | `cartoon bomb explosion, punchy but short, no debris tail, 0.7s` — **현재 파일은 절차 합성본(0.80s)**. 크랙(노이즈 파열) + 저역 붐(150→34Hz 하강 스윕) + 럼블 꼬리(2극 저역통과)를 tanh 소프트 클립으로 합쳐 만들었다. 원래 배포본이 0.16s로 스펙의 1/4이라 터지는 느낌이 없었다. |
| sfx_shake | 흔들기 | `cards rattling and shaking in a hand, tense tremble, 0.6s` |
| sfx_bbeok | 뻑(자뻑·연뻑·첫뻑) | `comedic deflating womp-womp, short trombone-like fail, 0.6s` |
| sfx_chongtong | 총통 | `dramatic gong hit with short reverb, announcement, 1s` |
| sfx_pi_steal | 피 뺏기/주기 | `quick snatch whoosh with a paper flick, mischievous, 0.4s` |
| sfx_go | 고 선언/선 확정 | `bold rising dramatic sting, three ascending notes, 0.8s` |
| sfx_stop | 스톱 선언 | `decisive stamp thud with a short bell, final, 0.6s` |
| sfx_gwang_sell | 광 판매 | `coins clinking into a pouch, brief jingle, 0.6s` |
| sfx_negotiate | 4인 협상 시작 | `soft traditional Korean gong with gentle tension, 0.8s` |
| sfx_coin | 동전 | `single coin drop and spin on wood, bright, 0.5s` |
| sfx_money_gain | 돈 획득 | `cheerful cash register cha-ching with coins, 0.7s` |
| sfx_money_lose | 돈 잃음 | `sad descending two-note womp with coin clatter, 0.7s` |
| sfx_bak | 피박/광박/고박 | `heavy dramatic drum hit with dark sting, ominous, 0.8s` |
| sfx_gostop_prompt | 고/스톱 선택 등장 | `attention chime, two bright notes, questioning feel, 0.5s` |
| win | 승리 | `short triumphant fanfare with Korean percussion flavor, 1.5s` |
| lose | 패배 | `gentle sad descending melody, consoling, 1.5s` |
| draw | 나가리(무승부) | `neutral flat chord with a soft gong, unresolved, 1s` |

## 1-2. 신규 필요 (이번 기능 추가분)

| 파일(안) | 트리거 (코드 연결점) | 생성 프롬프트 (영문) |
|----------|----------------------|----------------------|
| slot_spin | 대전 설정 슬롯머신 회전 루프 (`SlotTick`) | `fast mechanical slot machine reel spinning, ticking loop, seamless, 1s` |
| slot_stop | 릴 정지(현재 card_place 재사용) | `slot machine reel clunk stop with a small ding, 0.4s` |
| seon_decide | 선(先) 확정 발표 (`SeonEvaluate`, 현재 sfx_go 재사용) | `single traditional Korean buk drum hit with a short flourish, ceremonial, 0.8s` |
| seon_tie | 선뽑기 동점 재경합 (`SeonEvaluate` tie) | `quirky double boing with rising question tone, 0.5s` |
| bonus_open | 보너스 뽑기 더미 펼침 (`DrawBonusDraw` 진입) | `hand fanning out many cards face down in an arc, fluttery, 0.7s` |
| bonus_get | 보너스패 획득 (`pekCapture` 보너스) | `sparkly pickup chime, small treasure get, 0.5s` |
| bonus_buried | 조커 뻑 무더기에 묻힘 | `card slapped down then buried under a heavy pile, muffled thud, 0.6s` |
| stakes_double | 나가리 → 다음 판 판돈 ×2 (`BuildFinalSummary`) | `tense double drum hit with rising stakes sting, 0.8s` |
| voice_pop | 캐릭터 말풍선 등장(미구현 기능용) | `tiny speech bubble pop, cartoon, 0.15s` |
| avatar_pick | 아바타 선택 확정 | `friendly select chime with a soft whoosh, 0.4s` |

---

# 2부. 나레이터 (게임 진행 보이스)

아케이드 맞고 스타일의 **공통 진행 멘트**. 캐릭터 대사와 별개로, 이벤트를 외쳐주는 해설 목소리.

**나레이터 보이스 프로필**: 걸쭉하고 호탕한 중년 남성, 타격감 있는 짧은 외침
(`middle-aged Korean male arcade announcer, thick hearty voice, punchy energetic shouts, slight reverb`)

파일 배치: `assets/audio/ann/ann_*.wav` (0.5~2초, 어미는 짧고 강하게)

## 2-1. 게임 흐름 멘트

| 파일 | 트리거 (코드 연결점) | 스크립트 | 톤 |
|------|----------------------|----------|-----|
| ann_title | 타이틀 진입 | "고~스톱!" | 시그니처 콜, 길게 뽑기 |
| ann_match_start | 대전 설정 [시작] | "대전 시작!" | 힘차게 |
| ann_seon_pick | 선 뽑기 진입(`BeginSeonPick`) | "밤일낮장! 선을 정합니다!" | 안내 |
| ann_seon_day | 낮 판정 시 | "낮장! 높은 월이 선!" | 안내 |
| ann_seon_night | 밤 판정 시 | "밤일! 낮은 월이 선!" | 안내 |
| ann_seon_tie | 동점 재경합(`SeonEvaluate` tie) | "동점! 다시 뽑습니다!" | 긴장 |
| ann_seon_done | 선 확정(`SeonFinish`) | "선 결정!" | 발표 |
| ann_deal | 딜 시작(`BeginDealAnimation`) | "패 돌립니다~" | 여유 |
| ann_game_start | 플레이 시작(`StartPlay`) | "게임 시작!" | 힘차게 |
| ann_your_turn | 사람 차례(`AfterAction`) | "당신 차례!" | 짧게(빈도 높음 — 옵션) |
| ann_negotiate | 4인 협상(`StartNegotiation`) | "광 팔 사람~?" | 능청 |
| ann_gwang_sold | 광 판매(`ResolveNegotiation`) | "광 팔았습니다!" | 안내 |

## 2-2. 특수 이벤트 콜 (짧은 외침 — SFX와 함께 재생)

| 파일 | 트리거 | 스크립트 | 톤 |
|------|--------|----------|-----|
| ann_jjok | `pekJjok` | "쪽!" | 경쾌한 일갈 |
| ann_ttadak | `pekTtadak` | "따닥!" | 두 박자 타격 |
| ann_sseul | `pekSseul` | "싹~쓸이!" | 시원하게 쓸어내리듯 |
| ann_bbeok | `pekBbeok` | "뻑!" | 얼빠진 톤 |
| ann_cheotbbeok | `pekCheotbbeok` | "첫뻑!" | 놀림조 |
| ann_yeonbbeok | `pekYeonbbeok` | "연뻑!!" | 더 크게 |
| ann_jabbeok | `pekJabbeok` | "자~뻑!" | 감탄+놀림 |
| ann_bomb | `pekBomb` | "폭탄이야!!" | 폭발적으로 |
| ann_shake | `pekShake` | "흔들었습니다!" | 선언 |
| ann_chongtong | `pekChongtong` | "총통! 무효 판!" | 장중 |
| ann_pi_steal | `pekPiSteal` | "피 내놔!" | 능청 |
| ann_godori | 고도리 완성(점수 계산 시) | "고도리!" | 새 울음처럼 높게 |
| ann_bonus | 보너스패 획득 | "보너스!" | 반짝이게 |

## 2-3. 고/스톱 · 박 · 정산 멘트

| 파일 | 트리거 | 스크립트 | 톤 |
|------|--------|----------|-----|
| ann_gostop_ask | 고/스톱 선택 등장 | "고냐~ 스톱이냐~!" | 애태우듯 |
| ann_1go | 1고 선언 | "원고!" | 상승 |
| ann_2go | 2고 | "투고!" | 더 상승 |
| ann_3go | 3고 | "쓰리고!! 두 배!" | 폭발 |
| ann_4go | 4고 이상 | "포고!!! 미쳤다!!" | 절정 |
| ann_stop_call | 스톱 선언 | "스톱! 게임 끝!" | 단호 |
| ann_pibak | 정산 피박 | "피박!" | 묵직한 일갈 |
| ann_gwangbak | 정산 광박 | "광박!" | 묵직한 일갈 |
| ann_gobak | 정산 고박 | "고박!! 독박입니다!" | 놀림+충격 |
| ann_nagari | 나가리 | "나가리~!" | 김빠지게 길게 |
| ann_stakes2 | 판돈 이월 | "다음 판, 두 배!" | 긴장 조성 |
| ann_win | 사람 승리 | "승리! 축하합니다!" | 축포 |
| ann_lose | 사람 패배 | "아이고~ 다음 기회에!" | 위로 |
| ann_money_big | 큰 금액 정산(예: 5,000원↑) | "대박!!" | 환호 |

---

# 3부. BGM / 앰비언스

파일 배치: `assets/audio/bgm/` (OGG 권장 — 길이가 길어 용량 절약. 재생기는 추후 스트리밍 지원 필요)

| 파일 | 용도 | 생성 프롬프트 (영문) |
|------|------|----------------------|
| bgm_title | 타이틀 화면 루프 | `playful traditional Korean folk tune with gayageum and janggu drum, medium tempo, warm and inviting, seamless loop, 60s` |
| bgm_play | 인게임 기본 루프 | `laid-back Korean traditional lounge groove, soft gayageum plucks over subtle percussion, unobtrusive background for a card game, seamless loop, 90s` |
| bgm_tension | 고 선언 이후/3점 근접 | `tense Korean percussion build with janggu and buk drums, heartbeat pulse, rising suspense, seamless loop, 45s` |
| bgm_result_win | 승리 결과창 | `short celebratory Korean folk fanfare with samul nori percussion burst, joyful, 8s` |
| bgm_result_lose | 패배 결과창 | `melancholic short gayageum melody, gentle and consoling, 8s` |
| amb_room | 방 앰비언스(옵션) | `quiet cozy Korean room tone, faint clock tick and distant cicadas, very subtle, seamless loop, 60s` |

**구현 메모**: 현재 `TGostopAudio`(waveOut, 전체 로드)는 짧은 효과음 전용 — BGM 루프/스트리밍/크로스페이드는 별도 채널 구현 필요(로드맵).

---

# 4부. 캐릭터 대사 (보이스 스크립트)

## 4-1. 대사 슬롯 (이벤트 트리거)

| 슬롯 | 파일명 | 트리거 |
|------|--------|--------|
| go | go.wav | 고 선언(`DeclareGo`) |
| stop | stop.wav | 스톱 선언(`DeclareStop`) |
| happy | happy.wav | 쪽/따닥/싹쓸이/자뻑 성공(`pekJjok/pekTtadak/pekSseul/pekJabbeok`) |
| ouch | ouch.wav | 뻑을 냈거나 피를 뺏겼을 때(`pekBbeok`, 피 뺏긴 쪽) |
| win | win.wav | 승리(`gpFinished` + Winner=자신) |
| lose | lose.wav | 패배 |

파일 배치: `assets/audio/voice/avatar_01/go.wav` … `avatar_20/lose.wav` (20인 × 6 = 120파일)

## 4-2. 20인 보이스 프로필 + 대사

각 캐릭터: **TTS 보이스 지시문** → 6개 대사. (페르소나 근거는 `characters.md`)

### 01. 피주워요 — 보이스: 앳되고 들뜬 젊은 남성, 약간 소심, 빠른 말끝 (`young Korean male, excited but shy, light voice`)
- go: "고… 고 해볼게요!" / stop: "스, 스톱할게요!" / happy: "피다 피! 줍줍~"
- ouch: "아앗, 제 피…" / win: "제, 제가 이겼어요?!" / lose: "그래도 피는 많이 주웠어요…"

### 02. 못먹어도고 — 보이스: 우렁찬 청년, 기합 가득 (`energetic loud young Korean male, shouting spirit`)
- go: "못 먹어도 고!!" / stop: "…스톱은 처음이라 어색하네." / happy: "사나이는 직진!"
- ouch: "이 정도는 스크래치다!" / win: "기세가 다 했다!!" / lose: "어? 고박…? 그게 뭐죠?"

### 03. 광팔이 — 보이스: 능글맞은 중년 남성, 영업 톤 (`smooth-talking middle-aged Korean male salesman tone`)
- go: "조금만 더 남겨보죠. 고." / stop: "스톱! 정산합시다." / happy: "이건 남는 장사죠~"
- ouch: "손해가 막심한데요…" / win: "역시 계약은 성사되는 법." / lose: "이번 분기는 적자네요."

### 04. 흔들신사 — 보이스: 점잖은 노신사, 여유로운 저음 (`refined elderly Korean gentleman, calm low voice`)
- go: "실례지만, 고." / stop: "여기까지 하겠습니다." / happy: "신사는 두 배로 걸지요. 하하."
- ouch: "허허, 이런 실례가." / win: "즐거운 한 판이었습니다." / lose: "훌륭한 솜씨였소."

### 05. 동네타짜 — 보이스: 낮고 건조한 중년 남성, 짧게 끊는 말투 (`gravelly terse middle-aged Korean male, minimal`)
- go: "…고." / stop: "판은 내가 접는다. 스톱." / happy: "예상대로군."
- ouch: "…실수." / win: "다음엔 패 간수 잘해." / lose: "…오늘은 여기까지."

### 06. 초단콜렉터 — 보이스: 차분한 젊은 남성, 오타쿠 특유의 진지함 (`calm nerdy young Korean male, precise diction`)
- go: "수집이 덜 끝났습니다. 고." / stop: "컬렉션 완성. 스톱." / happy: "초단… 컴플리트."
- ouch: "제 컬렉션이…!" / win: "역시 수집은 배신하지 않아요." / lose: "희귀템을 놓쳤네요…"

### 07. 고도리헌터 — 보이스: 거친 야성적 중년 남성 (`rugged outdoorsy Korean male, hunter's whisper to shout`)
- go: "사냥은 끝나지 않았다. 고." / stop: "포획 완료. 스톱." / happy: "새 발견. 조준."
- ouch: "놓쳤다…!" / win: "다섯 점, 회수." / lose: "새들이 날아가 버렸군."

### 08. 쌍피장인 — 보이스: 과묵한 노년 남성, 느리고 묵직 (`slow weighty elderly Korean craftsman voice`)
- go: "아직… 덜 여물었어. 고." / stop: "이만하면 됐어. 스톱." / happy: "쌍피는… 예술이지."
- ouch: "쯧… 아까운 것." / win: "세월은 못 속이지." / lose: "젊은 사람이 제법이군."

### 09. 뻑전문가 — 보이스: 익살스런 노년 남성, 한탄+웃음 (`comical sighing elderly Korean male, self-mocking`)
- go: "에라 모르겠다, 고!" / stop: "이쯤에서 접자고." / happy: "이게 다 큰 그림이야… 자뻑!"
- ouch: "아이고 또 쌌네." / win: "뻑도 실력이다!" / lose: "내 이럴 줄 알았지…"

### 10. 화투도사 — 보이스: 신비로운 노인, 도사 어투, 느린 저음 (`mystical slow elderly Korean sage voice with echo feel`)
- go: "하늘이 더 가라 하는구나. 고." / stop: "하늘이 스톱하라 하는구나." / happy: "패에는 길이 있느니라."
- ouch: "흐름이… 흐트러졌군." / win: "오늘 자네 운은 여기까지." / lose: "천기도 가끔은 어긋나는 법."

### 11. 쪽쪽이 — 보이스: 발랄한 20대 여성, 애교 톤 (`bubbly cute young Korean female, aegyo tone`)
- go: "한 번만 더! 고!" / stop: "여기서 스톱~ 히히." / happy: "쪽! 헤헤, 봤어요?"
- ouch: "잉… 내 피…" / win: "꺄! 제가 이겼어요!" / lose: "칫, 다음엔 안 봐줘요!"

### 12. 싹쓸이요정 — 보이스: 장난기 많은 젊은 여성, 명랑 (`playful mischievous young Korean female, sing-song`)
- go: "기분이다, 고!" / stop: "오늘 장사 끝~ 스톱!" / happy: "쓸~어 담아요!"
- ouch: "어라? 바닥이 왜 이래!" / win: "바닥 청소 완료☆" / lose: "빗자루를 바꿔야겠어…"

### 13. 피박금지 — 보이스: 억척스러운 중년 여성, 시장 톤 (`feisty middle-aged Korean market lady, loud and firm`)
- go: "조금만 더 벌어야지. 고!" / stop: "됐어 됐어, 스톱!" / happy: "그 피 이리 내!"
- ouch: "피박만은 안 돼!!" / win: "장사 수완이 어디 가나~" / lose: "아이고 밑졌네 밑졌어!"

### 14. 고고고 — 보이스: 하이텐션 30대 여성, 응원 구호 톤 (`high-energy Korean female cheerleader chant`)
- go: "고! 고! 고!" / stop: "…어? 나 스톱한 거야?" / happy: "아자아자!"
- ouch: "노노노!" / win: "우승! 우승! 우승!" / lose: "멈추면 지는 건데… 멈췄네!"

### 15. 국진할멈 — 보이스: 온화한 할머니, 느긋한 웃음기 (`warm gentle Korean grandmother, soft chuckle`)
- go: "조금만 더 놀아볼까? 고." / stop: "이 늙은이는 여기까지." / happy: "어이쿠, 이게 쌍피가 되네?"
- ouch: "아이고, 내 국진이…" / win: "이 늙은이가 이겼네, 호호." / lose: "젊은 사람들 못 당하겠어."

### 16. 스톱은없다 — 보이스: 낮고 단호한 젊은 여성, 격투가 톤 (`fierce determined young Korean female fighter voice`)
- go: "4고. 불만 있나." / stop: "…전략적 후퇴다." / happy: "링에서도 판에서도 직진."
- ouch: "이 정도로는 안 쓰러져." / win: "KO승." / lose: "한 판 더. 지금 당장."

### 17. 자뻑여왕 — 보이스: 도도한 30대 여성, 여왕님 톤 (`haughty glamorous Korean female, queenly`)
- go: "여왕의 판이지, 고." / stop: "오늘 무대는 여기까지." / happy: "자뻑? 그것도 실력이야."
- ouch: "감히 내 피를?" / win: "역시 나야." / lose: "…카메라 꺼. 지금 당장."

### 18. 점백의달인 — 보이스: 차갑고 정확한 중년 여성, 기계적 (`cold precise Korean female accountant, flat tone`)
- go: "기대값 +240원. 고." / stop: "정산하죠. 스톱." / happy: "계산대로."
- ouch: "오차 발생. 재계산." / win: "장부는 거짓말하지 않습니다." / lose: "이 손실은… 공제 불가네요."

### 19. 판쓸이할매 — 보이스: 걸걸한 할머니, 능청+호탕 (`raspy hearty Korean grandmother, sly then booming laugh`)
- go: "아이고 나 잘 몰라~ 고." / stop: "요것만 받아갈게." / happy: "판은 쓸어야 제맛이지!"
- ouch: "어이쿠야, 요놈들 봐라?" / win: "시장바닥 50년이여~" / lose: "오늘은 자릿세 냈다 치지 뭐."

### 20. 옆집고수 — 보이스: 부드러운 할머니, 나긋하지만 서늘 (`soft gentle Korean grandmother with subtle chilling calm`)
- go: "차 식기 전에 끝내죠. 고." / stop: "심심풀이는 여기까지." / happy: "어머, 그거 필요했어요?"
- ouch: "찻잔이 흔들렸네." / win: "오늘도 심심풀이 잘 했네." / lose: "다음 찻자리가 기대되네요."

---

# 5부. 적용 절차

1. **효과음**: 프롬프트로 생성 → WAV(44.1k/16bit/스테레오) 변환 → `assets/audio/` 저장(기존 파일명 유지 시 코드 수정 불필요, 신규는 `TGostopAudio.Play('이름')` 배선 추가).
2. **대사**: TTS로 생성 → `assets/audio/voice/avatar_NN/<슬롯>.wav` → **보이스 재생 트리거는 미구현**(로드맵: `characters.md` §5) — 구현 시 `OnEvent`에서 화자 캐릭터의 슬롯 파일 재생.
3. `build.ps1` 실행(→ `bin\assets` 동기화).
