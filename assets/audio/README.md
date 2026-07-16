# 고스톱 오디오 에셋

게임 효과음. 각 효과는 `.ogg`(작음)와 `.wav`(PCM 16-bit·44.1kHz, 저지연·최대호환) 두 형식으로 제공한다.
효과↔상황 매핑과 훅 지점은 `docs/audio-effects.md` 참조.

## 라이선스 / 출처

모든 파일은 **CC0 (퍼블릭 도메인)** — 자유 사용, 출처 표기 불필요(예의상 명기).

- 출처: **Kenney** — https://kenney.nl
- 사용 팩:
  - Casino Audio — https://kenney.nl/assets/casino-audio (카드/칩/주사위)
  - Interface Sounds — https://kenney.nl/assets/interface-sounds (UI)
  - Impact Sounds — https://kenney.nl/assets/impact-sounds (임팩트/벨)

## 매핑 (게임 효과 → 원본 파일)

| 파일 | 원본(팩/파일) | 용도 |
|---|---|---|
| card_deal | casino / card-shuffle | 딜링(새 게임) |
| card_place | casino / card-place-1 | 손패 놓기 |
| card_flip | casino / card-slide-2 | 더미 뒤집기 |
| card_capture | casino / card-slide-7 | 먹기(가져가기) '씁~~' 슬라이드 |
| ui_hover | interface / tick_001 | 손패 호버 |
| ui_click | interface / click_001 | 클릭/버튼 |
| ui_select | interface / select_001 | 선택 진입 |
| sfx_jjok | interface / pluck_001 | 쪽 |
| sfx_ttadak | impact / impactWood_medium_000 | 따닥 |
| sfx_sseul | casino / chips-handle-1 | 싹쓸이 |
| sfx_bomb | impact / impactMetal_heavy_000 | 폭탄 |
| sfx_shake | casino / dice-shake-1 | 흔들기 |
| sfx_bbeok | impact / impactSoft_heavy_000 | 뻑/자뻑/연뻑/첫뻑 |
| sfx_chongtong | impact / impactBell_heavy_000 | 총통 |
| sfx_pi_steal | casino / card-slide-1 | 피 뺏기 |
| sfx_gostop_prompt | interface / question_001 | 고/스톱 대기 |
| sfx_go | interface / confirmation_001 | 고 |
| sfx_stop | interface / confirmation_003 | 스톱 |
| win | impact / impactBell_heavy_002 | 승리 |
| lose | interface / error_004 | 패배 |
| draw | interface / bong_001 | 나가리 |
| sfx_money_gain | casino / chips-collide-2 | 돈 획득 |
| sfx_money_lose | interface / toggle_002 | 돈 차감 |
| sfx_bak | impact / impactMetal_medium_000 | 박(피/광/고박) |
| sfx_coin | casino / chip-lay-1 | 광값 선불(동전) |
| sfx_gwang_sell | interface / confirmation_004 | 광팔기 성립 |
| sfx_negotiate | interface / question_002 | 협상 시작 |

## 교체

마음에 안 드는 효과는 같은 이름으로 다른 CC0 파일을 덮어쓰면 된다(래퍼는 파일명만 참조).
원본 팩에는 대안이 많다(card-place-1..4, card-slide-1..8, impactMetal/Wood/Bell 각 5종 등).
