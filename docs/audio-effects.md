# 고스톱 오디오 이펙트 정리

게임에서 사용할 사운드 효과를 상황(트리거) · 코드 연결점 · 성격 · 우선순위로 정리한다.
구현은 아직 안 함(목록/설계). 파일은 `assets/audio/` 에 두고, `TGostopAudio` 래퍼(SCAudio 컴포넌트)로 재생한다.

---

## 1. 통합 방식(설계)

- **에셋 위치**: `assets/audio/` (짧은 효과는 `.wav`=저지연 권장, 배경/긴 것은 `.ogg`).
- **래퍼**: `Gostop.Audio` 유닛의 `TGostopAudio` 싱글턴 — `SCAudio` 컴포넌트로 재생.
  - `PlaySfx(const AName: string)` — 이름으로 단발 재생(짧은 효과 겹침 허용).
  - `PlayEventSound(const AKind: TPlayEventKind)` — 엔진 이벤트 → 사운드 매핑.
  - `MasterVolume`, `Muted`(설정 토글), 카테고리별 볼륨(UI/SFX/BGM).
- **훅 지점**(이미 있는 코드에 붙이면 됨):
  - 특수 상황: `TGostopBoard` 의 `FEngine.OnEvent`(현재 `FTurnEvents` 수집 지점) → `PlayEventSound`.
  - 카드 동작: 애니메이션 단계 `AnimApplyStageStart/End`(놓기=1, 뒤집기=2, 먹기=4).
  - UI: `MouseMove`(호버), `MouseDown`(클릭/선택/버튼).
  - 게임 종료: `BuildFinalSummary` / `AfterAction`(gpFinished) → 승/패/무.
  - 협상: `StartNegotiation` / `ResolveNegotiation`.
- **폴리포니**: 짧은 UI·카드음은 겹침 허용. 임팩트(폭탄·총통·승리)는 단일 채널 우선(직전 것 컷).
- **동기화**: 특수 배너(`DrawEffectBanner`)와 사운드를 같은 타이밍에.

---

## 2. UI / 인터랙션

| 상황 | 코드 연결점 | 성격 | 우선순위 | 파일(안) |
|---|---|---|---|---|
| 손패 호버(올라옴) | `MouseMove` 호버 인덱스 변경 | 아주 짧은 tick | 낮 | `ui_hover.wav` |
| 카드/버튼 클릭 | `MouseDown`(손패·버튼) | 짧은 click | 중 | `ui_click.wav` |
| 바닥 2장 선택 진입 | 선택 모드(`FChoosing`) 진입 | 안내 blip | 낮 | `ui_select.wav` |
| 다음게임 | 다음게임 버튼 | click 재사용 | 낮 | `ui_click.wav` |

## 3. 카드 동작

| 상황 | 코드 연결점 | 성격 | 우선순위 | 파일(안) |
|---|---|---|---|---|
| 딜링(새 게임) | `NewGame`/`StartPlay` | 카드 촤르륵(여러 장) | 중 | `card_deal.wav` |
| 손패 놓기 | 애니 stage 1 안착 | 툭 놓는 소리 | 중 | `card_place.wav` |
| 더미 뒤집기 | 애니 stage 2(플립) | 뒤집는 소리 | 중 | `card_flip.wav` |
| 먹기(획득더미로) | 애니 stage 4 | 쓸어담기/촥 | 중 | `card_capture.wav` |

## 4. 특수 족보 / 상황 (배너와 동기)

| 상황 | 이벤트 | 성격 | 우선순위 | 파일(안) |
|---|---|---|---|---|
| 쪽 | `pekJjok` | 경쾌한 임팩트 | 상 | `sfx_jjok.wav` |
| 따닥 | `pekTtadak` | 딱딱 두 번 | 상 | `sfx_ttadak.wav` |
| 싹쓸이 | `pekSseul` | 쓸어담는 화려한 | 상 | `sfx_sseul.wav` |
| 폭탄 | `pekBomb` | 강한 폭발 임팩트 | 최상 | `sfx_bomb.wav` |
| 흔들기 | `pekShake` | 긴장감/드럼 | 상 | `sfx_shake.wav` |
| 뻑 / 자뻑 / 연뻑 / 첫뻑 | `pekBbeok` `pekJabbeok` `pekYeonbbeok` `pekCheotbbeok` | 막히는/실망 or 반전 | 상 | `sfx_bbeok.wav` (자뻑은 별도 `sfx_jabbeok.wav` 고려) |
| 총통 | `pekChongtong` | 팡파레(승부 결정) | 최상 | `sfx_chongtong.wav` |
| 피 뺏기 | `pekPiSteal` | 짧고 잦음 → 작게/생략옵션 | 낮 | `sfx_pi_steal.wav` |

## 5. 게임 흐름

| 상황 | 코드 연결점 | 성격 | 우선순위 | 파일(안) |
|---|---|---|---|---|
| 고/스톱 대기 알림 | `gpAwaitingGoStop` 진입(`DrawGoStopPrompt`) | 결정 촉구음 | 상 | `sfx_gostop_prompt.wav` |
| 고 선언 | `pekGo` | 외침/강조 | 상 | `sfx_go.wav` |
| 스톱 선언 | `pekStop` | 마무리 | 상 | `sfx_stop.wav` |
| 승리(나) | 종료·`Winner=나` | 팡파레(밝음) | 최상 | `win.ogg` |
| 패배 | 종료·패배 | 하강음 | 상 | `lose.ogg` |
| 나가리(무승부) | 종료·`Winner<0` | 허탈/중립 | 중 | `draw.wav` |

## 6. 4인 광팔기

| 상황 | 코드 연결점 | 성격 | 우선순위 | 파일(안) |
|---|---|---|---|---|
| 협상 시작 | `StartNegotiation` | 안내음 | 중 | `sfx_negotiate.wav` |
| 참가/포기·광팔기 선택 | 협상 버튼 | click | 낮 | `ui_click.wav` |
| 광팔기 성립 | `FGwang.Sold` | 강조음 | 중 | `sfx_gwang_sell.wav` |
| 광값 선불(동전) | 광값 지급 정산 | 동전 소리 | 중 | `sfx_coin.wav` |

## 7. 정산 / 머니

| 상황 | 코드 연결점 | 성격 | 우선순위 | 파일(안) |
|---|---|---|---|---|
| 돈 획득(승자) | `BuildFinalSummary` 정산 | 동전 쨍그랑 | 상 | `sfx_money_gain.wav` |
| 돈 차감(패자) | 정산 | 낮은 차임 | 중 | `sfx_money_lose.wav` |
| 박(피박/광박/고박) | 정산 플래그 | 강조 스팅어 | 상 | `sfx_bak.wav` |

## 8. 배경(선택)

| 상황 | 성격 | 우선순위 | 파일(안) |
|---|---|---|---|
| 배경음악 | 잔잔한 국악/재즈 루프 | 낮 | `bgm_loop.ogg` |
| 앰비언스 | 찻집/시장 소음(옵션) | 낮 | `amb_room.ogg` |

---

## 9. 우선 구현 순서(제안)

1. **핵심 피드백**: `card_place` · `card_flip` · `card_capture` · `ui_click` (게임이 살아있는 느낌)
2. **특수 상황**: `sfx_bomb` · `sfx_sseul` · `sfx_jjok` · `sfx_ttadak` · `sfx_shake` · `sfx_bbeok` · `sfx_chongtong` (배너와 동기)
3. **게임 흐름**: `sfx_go` · `sfx_stop` · `win` · `lose` · `draw` · `sfx_gostop_prompt`
4. **머니/광팔기**: `sfx_money_gain` · `sfx_coin` · `sfx_bak` · `sfx_gwang_sell`
5. **분위기**: `card_deal` · `ui_hover` · `bgm_loop`(옵션)

## 10. 기술 메모

- **포맷**: 짧은 효과 `.wav`(PCM, 낮은 지연). 배경/긴 것 `.ogg`(용량).
- **길이**: UI/카드음 50~200ms, 특수 300~800ms, 승리/총통 1~2s.
- **음량 밸런스**: 잦은 것(호버·피뺏기)은 작게, 임팩트(폭탄·총통·승리)는 크게. 카테고리별 볼륨 노출.
- **설정**: 마스터 음소거 토글 + 볼륨 슬라이더(폼 메뉴). BGM on/off 별도.
- **성능**: 사운드는 워커/디바이스 콜백에서 재생하되 UI 스레드 블록 금지(SCAudio 내부 처리 확인).
