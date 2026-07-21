unit Gostop.Board;

interface

{$REGION 'uses'}
uses
  System.SysUtils,
  System.Classes,
  System.Types,
  System.UITypes,
  System.DateUtils,
  System.IOUtils,
  System.IniFiles,
  System.Math,
  System.Math.Vectors,
  System.Diagnostics,
  System.Generics.Collections,
  Winapi.Windows,
  Winapi.ShellAPI,
  FMX.Types,
  FMX.Controls,
  FMX.Graphics,
  FMX.Edit,
  Gostop.Cards,
  Gostop.Deck,
  Gostop.Shodang,
  Gostop.Deal,
  Gostop.Score,
  Gostop.Play,
  Gostop.Setup,
  Gostop.AI,
  Gostop.Characters,
  Gostop.Settings,
  Gostop.Board.Layout,
  Gostop.Board.Animation,
  Gostop.Board.Avatar,
  Gostop.Board.CardRender,
  Gostop.Board.Widgets,
  Gostop.Board.OverlayRender,
  Gostop.Canvas.Helper,
  Gostop.Fonts,
  Gostop.FourPlayer,
  Gostop.CardImages,
  Gostop.Audio,
  Gostop.Assets,
  Gostop.SaveGame,
  Gostop.Board.Settlement;
{$ENDREGION}

type
  /// <summary>선 뽑기(밤일낮장) 진행 단계.</summary>
  TSeonStep = (
    seReveal,    // 각 자리 카드 공개 대기(AI 자동·사람 클릭)
    seDecide,    // 선 확정 후 잠시 표시
    seTie        // 동점 → 재경합 대기
  );

  // TDlgBtnKind 는 Gostop.Board.Widgets 유닛으로 이동(버튼 렌더러가 소유). uses 로 참조한다.
  // TDealFly 는 Gostop.Board.Animation 유닛으로 이동(딜 애니가 소유). uses 로 참조한다.

  /// <summary>
  ///   한 자리의 획득 패 부채 배치값. 그리기와 좌표 질의가 같은 값을 쓰도록 한 곳에서 계산한다.
  ///   가로형이면 A=왼쪽 X·B=오른쪽 X·C=위쪽 Y, 세로형이면 A=열 중심 X·B=위 Y·C=아래 Y.
  /// </summary>
  TCapturedFanSpec = record
    Vertical: Boolean;    // True=좌/우 자리(회전 부채)
    Scale: Single;        // 카드 크기 배율
    Angle: Single;        // 회전각(세로형만, 90/270)
    A: Single;
    B: Single;
    C: Single;
    AnchorEnd: Boolean;   // 가로=오른쪽 앵커, 세로=아래 앵커
    Reverse: Boolean;     // 그룹 순서 반전(세로형 P4)
    BadgeDir: Integer;    // 장수 배지를 붙일 방향(세로형, +1=오른쪽 -1=왼쪽)
  end;

  /// <summary>
  ///   고스톱 플레이 보드(FMX 커스텀 컨트롤). 2/3/4인 모드·좌석 배치(반시계)·렌더링·클릭 입력·AI 진행·
  ///   4인 광팔기 협상·고/스톱을 모두 담당한다. 사람은 항상 아래 자리, 나머지는 AI.
  /// </summary>
  TGostopBoard = class(TControl, IAnimationHost)
  private
    FImages: TCardImageCache;
    FFeltTile: TBitmap;
    FAvatars: array [TSeatPos] of TBitmap;      // 자리별 아바타(절차 생성 폴백)
    FAvatarPool: TObjectList<TBitmap>;          // 파일 아바타 풀(assets\avatars, 지연 로드)
    FAvatarCheerPool: TObjectList<TBitmap>;     // 환호(승리) 상태 풀. FAvatarPool과 인덱스 정렬(없으면 nil)
    FAvatarSadPool: TObjectList<TBitmap>;       // 슬픔(패배) 상태 풀. FAvatarPool과 인덱스 정렬(없으면 nil)
    FAvatarAngryPool: TObjectList<TBitmap>;     // 화남(패배·박 당함) 상태 풀. FAvatarPool과 인덱스 정렬(없으면 nil)
    FSkillAvatarPool: TObjectList<TBitmap>;     // AI 난이도 카드 전용 인물 풀(assets\avatars\difficulty, 4장 고정)
    FSeatAvatar: array [TSeatPos] of Integer;   // 자리별 배정(풀 인덱스, -1=미배정)
    FHumanAvatarIdx: Integer;                   // 사람이 고른 아바타(-1=랜덤). 매치 간 유지
    FAvatarPicking: Boolean;                    // 아바타 선택 오버레이 표시 중
    FAvatarRects: TList<TRectF>;                // 선택 오버레이 아바타 rect
    FMyAvatarRect: TRectF;                      // 내 패널 아바타 rect(클릭 → 선택 열기)

    // 버튼 공용 호버/눌림 상태(모든 버튼이 참조 — 실시간 마우스 위치·좌클릭 유지 여부)
    FMousePos: TPointF;
    FMouseDown: Boolean;

    // 일시정지(스페이스바) — 모든 진행 타이머가 이 플래그를 확인해 멈춘다
    FPaused: Boolean;
    FAutoPlay: Boolean;   // 이번 판 한정 — 켜져 있으면 내 턴도 AI가 대신 진행

    // 하단 컨트롤 바(게임레벨·일시정지·자동·소리·게임속도) — 항상 고정 표시
    FGameSpeed: Single;        // 애니·AI 대기 속도 배율(0.5~2.0)
    FVolDragging: Boolean;     // 볼륨 노브 드래그 중
    FSpdDragging: Boolean;     // 속도 노브 드래그 중
    FMuteRect: TRectF;
    FVolTrackRect: TRectF;
    FSpeedRect: TRectF;        // 속도 슬라이더 히트 영역
    FBtnPauseBar: TRectF;      // 하단 컨트롤 바의 일시정지/재개 버튼
    FBtnAutoBar: TRectF;       // 하단 컨트롤 바의 자동(이번 판 AI 대신) 버튼
    FBtnMenuNew: TRectF;        // 타이틀 '새게임' 버튼
    FBtnMenuExit: TRectF;
    FBtnMenuContinue: TRectF;  // 타이틀 '이어서 하기' 버튼(저장 파일 없으면 비활성 표시)
    FBtnMenuManual: TRectF;    // 타이틀 '사용설명서' 버튼(help\ 문서를 브라우저로 열기)
    FBtnMenuRules: TRectF;     // 타이틀 '고스톱룰' 버튼(help\ 문서를 브라우저로 열기)
    FBtnMenuInfo: TRectF;      // 타이틀 '프로그램정보' 버튼
    FCreditRect: TRectF;       // 우하단 제작자 크레딧(클릭=GitHub)
    FOnExitRequest: TNotifyEvent;

    // 프로그램 정보 다이얼로그(타이틀 화면 전용 오버레이)
    FInfoOpen: Boolean;
    FBtnInfoClose: TRectF;

    // 게임 룰·플레이어 설정('새게임' 다이얼로그 1단계: 인원수+룰+닉네임+아바타, INI 유지)
    FConfig: TGameConfig;        // 게임 룰·플레이어 설정(피박/광박/고박/보너스/금액/시드/난이도/닉네임)
    FNickEdit: TEdit;            // 닉네임 입력용(설정창에서만 표시, IME 지원)
    FSettingsOpen: Boolean;      // 설정창 표시 중
    FCfgRects: array [0 .. 8] of TRectF;   // 설정 행 값 영역(0~6=토글, 7=닉네임, 8=아바타)
    FCfgCountRects: array [0 .. 2] of TRectF;  // 상단 인원수 카드(맞고/삼파전/광팔어유) 클릭 영역
    FCfgSkillRects: array [0 .. 3] of TRectF;  // 상단 AI 난이도 카드(병아리/선수/타짜/신의손) 클릭 영역
    FBtnCfgCancel: TRectF;      // 설정창 '취소'(타이틀로 복귀)
    FBtnCfgNext: TRectF;        // 설정창 '다음'(대전 설정 다이얼로그로 진행)

    // 대전 설정 다이얼로그: 슬롯머신 연출로 AI 배정, 내 시트(P1~PN) 선택, 관전 모드
    FMatchSetupOpen: Boolean;
    FSetupCount: Integer;                        // 시작할 인원(2/3/4)
    FSetupHumanRow: Integer;                     // 내 시트 행(0-기반), -1 = 관전(전원 AI)
    FSetupAvatar: array [0 .. 3] of Integer;     // 행별 배정 아바타(릴 타깃)
    FSlotDisp: array [0 .. 3] of Integer;        // 릴에 현재 표시 중인 아바타
    FSlotRemain: array [0 .. 3] of Integer;      // 남은 스핀 스텝(0=정지)
    FSlotTick: Integer;
    FSlotTimer: TTimer;
    FBtnSetupStart: TRectF;
    FBtnSetupCancel: TRectF;
    FBtnSetupSpin: TRectF;                       // 다시 돌리기
    FBtnSetupWatch: TRectF;                      // 관전 모드 토글

    // 매치 배치(대전 설정 결과, 매치 동안 유지)
    FSpectator: Boolean;                         // 관전 모드(사람 없음, 전원 AI)
    FRowPos: array [0 .. 3] of TSeatPos;         // 시트 행 → 물리 위치(내 시트 = 아래)
    FSeatSkill: array [TSeatPos] of Integer;     // 자리별 AI 난이도
    FSeatLuckRoll: array [TSeatPos] of Integer;  // 이번 판 운 굴림(0=미굴림, 5~99)
    FGame: TGameState;
    FEngine: TTurnEngine;
    FAiObjects: TObjectList<TAiPlayer>;
    FAgents: TArray<IPlayerAgent>;   // 게임 인덱스 → 에이전트(사람 자리는 nil)
    FAiTimer: TTimer;
    FPlayerCount: Integer;
    FAiSkill: Integer;
    FHumanIndex: Integer;            // 사람의 게임 인덱스(-1이면 사람 빠짐/관전)
    FBackColor: string;
    FStatus: string;
    FResultRows: TArray<TResultRow>;
    FResultTitle: string;   // 정산창 제목(판돈 배수 안내, 없으면 빈 문자열) — FStakes 갱신 전 값 보존
    FAwaitingGoStop: Boolean;

    // 정산창 머니 카운트 애니메이션(승자=백단위로 차오름/패자=백단위로 깎임, 모든 줄이 동시 시작·종료)
    // 순서: 정산창 등장 → 1초 대기 → 카운트 애니메이션(FMoneyCountT) → 끝나야 다음 판 카운트다운·버튼 활성화
    FMoneyCountDelay: Single;     // 카운트 시작 전 남은 대기 시간(초)
    FMoneyCountT: Single;         // 0~1, 진행도
    FMoneyCountTimer: TTimer;
    FMoneyTickAcc: Single;        // 동전 소리 재생 간격 누적(초)
    FGameOverReady: Boolean;      // 카운트 애니메이션 종료 후 True — 자동진행 카운트다운·버튼 활성화
    FGameOverPending: Boolean;    // 판은 끝났으나 진행 중인 연출(배너·흔들림)이 있어 정산창을 미루는 중

    // 4인 광팔기
    FNegotiating: Boolean;
    FTable4: TTableState;
    FSeatMap: TArray<Integer>;       // 게임 인덱스 → 물리 좌석(0..3)
    FSitOutSeat: Integer;
    FGwang: TGwangSale;

    // 시드머니·전적(물리 자리별로 판 간 지속)
    FStakes: Integer;   // 판돈 배수(나가리 시 다음 판 ×2로 이월, 승부 나면 1로 복귀)
    FMoney: array [TSeatPos] of Integer;
    FWins: array [TSeatPos] of Integer;
    FLosses: array [TSeatPos] of Integer;
    FGaveUpLast: array [TSeatPos] of Boolean;    // 연사: 직전 게임 포기 여부(4인, 좌석별)

    // 쇼당(3인): 활성 상태·관련 플레이어(게임 인덱스)
    FShodangActive: Boolean;                     // 쇼당 성립·정산 대기(수락자 승리 시 거절자 독박)
    FShodangCaller: Integer;                     // 쇼당 건 사람
    FShodangAccepter: Integer;                   // 수락자(밀어줄 대상)
    FShodangDecliner: Integer;                   // 거절자(독박 대상)
    FBtnShodang: TRectF;                         // 쇼당 걸기 버튼 영역

    FShodangPending: Boolean;                    // AI 쇼당 → 사람 수락/거절 대기
    FShodangPendCaller: Integer;                 // 쇼당 건 AI
    FShodangPendAiOpp: Integer;                  // 다른 상대(AI) 인덱스
    FShodangPendAiAccept: Boolean;               // 다른 상대(AI) 수락 여부(선결정)
    FShodangCards: TArray<string>;               // 공개할 위협 패(AssetId)
    FBtnShodangYes: TRectF;                      // 받기(수락)
    FBtnShodangNo: TRectF;                       // 거절
    FBtnJoin: TRectF;
    FBtnGiveUp: TRectF;
    FBtnNext: TRectF;
    FGameOverTimer: TTimer;     // 게임종료 팝업 방치 시 자동진행 카운트다운
    FGameOverRemain: Single;    // 남은 시간(초, 실수 — 숫자 축소 애니메이션용)
    FGameOverSw: TStopwatch;    // 카운트다운을 벽시계로 재기 위한 스톱워치
    FGameOverLastSec: Double;   // 직전 틱에서 읽은 경과 초(일시정지 구간을 빼기 위함)
    FBtnGo: TRectF;
    FBtnStop: TRectF;
    FNextStartPos: TSeatPos;   // 선(P1)의 물리 위치. 반시계로 P1→P2→P3→P4 배정
    FHumanLogical: Integer;    // 4인에서 사람의 논리 좌석(0=선,1=P2,2=P3,3=P4)
    FNegIsSell: Boolean;       // 협상 버튼이 광팔기(True) / 참가·포기(False)
    FNegAnimTimer: TTimer;     // 협상 광 패 흔들림 애니(주기적 Repaint)
    FNegAnimPhase: Single;     // 흔들림 위상(0~2π 누적)

    // 흔들기·폭탄 연출: 바닥패·뒷패가 좌우로 진동한다. 실제 진행은 TShakeAnimation(매니저)이 맡고
    // 여기서는 참조만 둔다(오프셋 조회·정산 지연 판정용). 없으면 nil.
    FShakeAnim: TShakeAnimation;

    // 4인: 광을 팔거나 죽어서 빠지는 자리의 손패가 뒷패로 합쳐지는 연출
    FFoldTimer: TTimer;
    FFoldT: Single;               // 진행도 0~1. 1 이상이면 연출 없음
    FFoldPos: TSeatPos;           // 빠지는 자리(물리)
    FFoldFrom: TArray<TPointF>;   // 카드별 출발점
    FFoldAngle: TArray<Single>;   // 카드별 출발 각도
    FFoldSold: Boolean;           // True=광 팔고 빠짐, False=포기(죽음)
    FFoldOnDone: TProc;
    FFoldPendingCount: Integer;   // 협상에서 정해진 빠지는 자리의 손패 장수(연출 대기분)
    FFoldPendingPos: TSeatPos;

    // 광 판매 발표 오버레이(협상 후 광을 판 경우: 판 광 패 + 광값 이동 표시)
    FGwangShow: Boolean;
    FGwangCards: TArray<THwatuCard>;   // 판매자가 판 광 패
    FGwangTimer: TTimer;               // 발표 후 자동 진행

    // 오링(파산) 좌석 신규 플레이어 교체 연출(최대 동시 2명, 화면 밖에서 등장→빈자리로)
    FReplacingSeats: TArray<TSeatPos>;   // 이번에 교체 중인 물리 좌석(1~2명)
    FReplaceNewAvatar: TArray<Integer>;  // FReplacingSeats와 인덱스 대응하는 신규 아바타
    FReplaceProgress: Single;            // 등장 애니 진행률(0~1)
    FReplaceTimer: TTimer;
    FReplacePendingStartPos: TSeatPos;   // 애니 완료 후 이어갈 NewGame의 선 위치

    // 선 뽑기(밤일낮장) — 새 매치 시작 시 각자 카드 1장을 뒤집어 선 결정
    FGiriPhase: Boolean;                           // 기리(딜 전 말번 커팅) 진행 중
    FGiriDeck: TDeck;                              // 기리 대기 중인 셔플 덱(딜 직전)
    FGiriProceed: TProc;                           // 기리 결정 후 실제 딜 진행
    FGiriRects: TList<TRectF>;                     // 기리 카드 클릭 영역
    FBtnTung: TRectF;                              // 퉁(컷 안 함) 버튼
    FGiriAiTimer: TTimer;                          // AI(또는 관전) 말번의 기리를 화면에 보여준 뒤 자동 결정하는 지연 타이머
    FGiriClosing: Boolean;                         // 컷(또는 퉁) 결정 후, 덱이 그 지점으로 모이는 연출 진행 중
    FGiriCloseT: Single;                           // 위 연출 진행률(0~1)
    FGiriCloseTimer: TTimer;
    FGiriClosePt: TPointF;                         // 카드들이 모여드는 지점(클릭한 카드 또는 퉁 버튼 위치)
    FGiriPendingCut: Integer;                      // 연출이 끝나면 실제로 적용할 컷 인덱스(-1=퉁)
    FGiriSplitting: Boolean;                       // 컷일 때: 모은 뒤 좌우로 갈라 자리를 바꾸는 연출 진행 중
    FGiriSplitT: Single;                           // 위 연출 진행률(0~1)
    FGiriAiHoverStep: Integer;                      // AI 말번이 결정 전에 카드를 훑어보는 연출 단계(0=아직 안 봄)

    FSeonPicking: Boolean;                         // 선 뽑기 진행 중
    FSeonStep: TSeonStep;                          // 현재 단계
    FSeonIsDay: Boolean;                           // 낮(큰 월=선) / 밤(작은 월=선)
    FSeonDeck: TDeck;                              // 뽑기용 셔플 덱(48장)
    FSeonWinner: Integer;                          // 확정된 선 물리위치(Ord), -1=미결정
    FSeonTicks: Integer;                           // 현재 단계 경과 틱(지연용)
    FSeonHumanTimeoutTicks: Integer;                // 사람 카드만 남아 대기 중인 경과 틱(방치 시 자동 공개)
    FSeonTimer: TTimer;                            // AI 자동 공개·단계 페이싱
    FSeonCard: array [TSeatPos] of THwatuCard;     // 각 물리 위치가 뒤집은 카드
    FSeonHasCard: array [TSeatPos] of Boolean;     // 이번 라운드 경합자(카드 배정됨)
    FSeonRevealed: array [TSeatPos] of Boolean;    // 앞면 공개됨
    FSeonRect: array [TSeatPos] of TRectF;         // 각 카드 rect(사람 클릭 히트)

    // 보너스 뽑기(뒷패 펼쳐 고르기) UI + 가져오기 비행 애니메이션
    FBonusRects: TList<TRectF>;   // 펼쳐진 뒷패 카드 rect(인덱스 = 뒷패 인덱스)
    FPickActive: Boolean;         // 고른 카드 비행 중
    FPickIndex: Integer;
    FPickFrom: TPointF;
    FPickTo: TPointF;
    FPickT: Single;
    FPickTimer: TTimer;
    FBtnQuit: TRectF;             // 게임 종료 팝업 '중지' 버튼

    // 국진(9월 열끗) → 쌍피 이동 연출. 게임이 끝나고 정산이 국진을 쌍피로 해석했을 때,
    // 획득 더미 안에서 열끗 무리 → 피 무리로 카드가 옮겨가는 걸 보여준다.
    // 국진은 덱에 한 장뿐이라 대상은 항상 카드 1장·플레이어 1명이다.
    FGukjinAsPi: array [TSeatPos] of Boolean;   // 이 자리의 국진을 피 무리로 그릴지(이동 완료 후 True)
    FGukjinMoveActive: Boolean;                 // 이동 연출 진행 중
    FGukjinMoveDone: Boolean;                   // 이번 판에서 이동 판정을 이미 했는지(중복 시작 방지)
    FGukjinMoveSeat: TSeatPos;                  // 이동 중인 자리
    FGukjinMovePileIndex: Integer;              // Captured 안에서의 국진 인덱스(더미에서 뺄 대상)
    FGukjinMoveFrom: TRectF;                    // 열끗 자리
    FGukjinMoveTo: TRectF;                      // 피 자리
    FGukjinMoveT: Single;                       // 0~1 진행도
    FGukjinMoveTimer: TTimer;

    // 애니메이션 매니저 — 등록된 연출들을 단일 타이머로 구동한다(Gostop.Board.Animation).
    // 보드가 비대해져 개별 연출을 점진 이관 중이며, 나가리(무승부)가 첫 입주자다.
    // 나가리는 손패 소진·쇼당 모두 Winner<0 로 정산 직전 한 지점에서 시작된다.
    FAnimMgr: TAnimationManager;
    FNagariAnim: TNagariAnimation;   // 진행 중인 나가리 연출(없으면 nil). 바닥패 스킵·정산 지연 판정에 쓴다
    FNagariAnimDone: Boolean;        // 이번 판에서 이미 나가리 연출을 시작했는지(중복 방지)

    // 표준 다이얼로그(DrawStdDialog) 등장 팝인 애니메이션 — 모든 팝업에 공용
    FDialogPopTimer: TTimer;
    FDialogPopT: Single;         // 0~1, 현재 다이얼로그의 등장 진행도(1=정착)
    FDialogPopKey: string;       // 마지막에 그린 다이얼로그 식별 키(제목+크기) — 바뀌면 새로 등장한 것으로 판단
    FDialogPreMatrix: TMatrix;   // DrawStdDialog 진입 전 매트릭스(EndStdDialog에서 복원)

    // 딜(패 돌리기) 단계 게이팅 플래그(입력·렌더 가드). 실제 연출은 TDealAnimation(매니저)
    FDealing: Boolean;

    // 셔플 연출(딜 직전) 단계 게이팅 플래그(입력·렌더 가드). 실제 연출은 TShuffleAnimation(매니저)
    FShuffling: Boolean;

    // 단계 애니메이션(놓기→뒤집기→먹기)
    FDisplay: TGameState;            // 애니 중 표시용 상태(진행 중일 때만, 아니면 nil)
    FAnimTimer: TTimer;
    FAnimStage: Integer;            // 0=없음,1=놓기,2=뒤집기,3=멈춤,4=먹기
    FEffectStage: Integer;          // 뻑·따닥 등 효과 배너를 띄울 단계(실제 결과가 눈에 보이는 시점에 맞춤)
    FAnimT: Single;                 // 현재 단계 진행(0~1)
    FAnimActor: Integer;
    FAnimPlayed: TArray<THwatuCard>;
    FAnimDrawn: TArray<THwatuCard>;
    FAnimCaptured: TArray<THwatuCard>;
    FAnimStealCount: Integer;       // 이번 먹기 단계에서 상대 획득더미에서 뺏어온 피 장수(0=없음)
    FAnimDrawSoundIdx: Integer;     // 뒤집기 단계에서 소리를 재생한 마지막 카드 인덱스(보너스 재뒤집기 다중 카드용)
    FAnimPlayedFrom: TPointF;
    FAnimDrawnFrom: TPointF;
    FFlySources: TArray<TPointF>;
    FFlyTargets: TArray<TPointF>;
    FFlyIsPi: TArray<Boolean>;        // 먹기 단계에서 이 카드가 "상대에게서 뺏어온 피"인지(2단 비행용)
    FCaptureConvergePt: TPointF;      // 뺏은 피가 1단계로 모이는 지점(싼 무더기가 있던 자리)
    FRestCards: TArray<THwatuCard>;   // 먹히기 직전 짝 위에 얹혀 대기하는 카드(낸/뒤집은 패)
    FRestPts: TArray<TPointF>;
    FAnimDone: TProc;
    FClickRect: TRectF;             // 사람이 클릭한 손패 rect(놓기 애니 출발점)

    // 특수 상황(쪽·따닥·싹쓸이·폭탄·흔들기·뻑·총통 등) 배너
    FTurnEvents: TList<TPlayEvent>;
    FEffectText: string;
    FEffectTimer: TTimer;
    // 한 턴에 이벤트가 여러 개 겹치면(예: 보너스패로 "한장 더~" 뜬 뒤 다시 뒤집어 뻑 발생) 한꺼번에
    // 합쳐 보여주지 않고 순서대로 하나씩, 사이에 짧은 공백을 두고 보여준다
    FEffectQueue: TArray<string>;
    FEffectQueueIdx: Integer;
    FEffectGap: Boolean;
    FTurnSpecialKind: TPlayEventKind;   // 이번 턴 대표 특수 이벤트(먹기 단계에 재생)
    FTurnSpecialPri: Integer;
    // 좌석별 자기완결 아바타 액터(표정 상태·전환 애니를 스스로 관리). 화난 표정 등은
    // FAvatarActors[pos].HoldExpression 명령만 하면 지정시간 뒤 알아서 평상시로 돌아온다.
    FAvatarActors: array [TSeatPos] of TAvatarActor;

    // 캐릭터 말풍선(턴 시작마다 일정 확률로 그 좌석 캐릭터의 대사를 잠깐 띄움)
    FSpeechText: string;
    FSpeechSeat: TSeatPos;
    FSpeechTimer: TTimer;
    FLastSpeechGameIndex: Integer;   // 마지막으로 말풍선을 시도한 게임 인덱스(같은 턴 중복 방지)

    // 입력/렌더 보조
    FHandRects: TList<TRectF>;
    FHandIndexMap: TList<Integer>;
    FFloorRects: TList<TRectF>;
    FFloorIndexMap: TList<Integer>;
    FChoosing: Boolean;
    FChooseHandIndex: Integer;
    FChooseMonth: Integer;
    FFlipChoosing: Boolean;            // 뒤집기 선택 대기(가져갈 패 고르기)
    FFlipOptAssets: array [0 .. 1] of string;
    FHoverHand: Integer;
    FHoverBonus: Integer;
    FHoverGiri: Integer;

    FOnStateChanged: TNotifyEvent;
    FOnGameOver: TNotifyEvent;

    procedure AiTimerTick(Sender: TObject);
    procedure ClearGame(const ADeleteSave: Boolean = True);
    procedure GenerateFeltTile;
    procedure AfterAction;
    procedure StartPlay;
    procedure SetupAgentsAndEngine(const AFreshDeal: Boolean);
    function  CanSaveGame: Boolean;
    procedure SaveCurrentGame;
    procedure SaveMatchSnapshot;
    function  LoadSavedGame: Boolean;
    function  CanResumeMatch: Boolean;
    procedure StartNegotiation;
    procedure StartNegotiationDeal;
    procedure BeginNegotiationPrompt;
    function  SeatPosOfLogical(const ALogical: Integer): TSeatPos;
    function  IsHumanSeat(const ALogical: Integer): Boolean;
    function  AiGiveUp(const ALogicalSeat: Integer): Boolean;
    procedure ResolveNegotiation(const AP2Give, AP3Give, AP4Sell: Boolean);
    procedure BeginSitOutFold(const APos: TSeatPos; const ACount: Integer; const ASold: Boolean; const AOnDone: TProc);
    procedure FoldSitOutThenPlay;
    procedure FoldTimerTick(Sender: TObject);
    procedure DrawSitOutFold;
    procedure DrawGwangSale;
    procedure GwangTimerTick(Sender: TObject);
    procedure FinishGwangSale;
    function  ActivePhysicalSeats: TArray<TSeatPos>;
    function  PickReplacementAvatar(const AExtraExclude: Integer): Integer;
    function  SeatAvatarRect(const APos: TSeatPos): TRectF;
    procedure BeginSeatReplacement(const AStartPos: TSeatPos);
    procedure ReplaceTimerTick(Sender: TObject);
    procedure DrawSeatReplacement;
    procedure NegAnimTick(Sender: TObject);
    procedure ProceedAfterSeon;
    procedure BeginSeonPick;
    function  MalbeonPos: TSeatPos;
    procedure RequestGiri(const ADeck: TDeck; const AProceed: TProc);
    procedure ResolveGiri(const ACutIndex: Integer);
    procedure GiriAiTimerTick(Sender: TObject);
    procedure BeginGiriClose(const APendingCut: Integer);
    procedure GiriCloseTimerTick(Sender: TObject);
    procedure FanDialogGeometry(out APanelW, ACardW, ACardH, AStep, AHalfSpread, AArcDrop, AAvColW, ATopPad: Single);
    procedure DrawGiri;
    function  SeonActivePositions: TArray<TSeatPos>;
    function  SeonPosLabel(const APos: TSeatPos): string;
    procedure SeonDealRound;
    procedure SeonRevealPos(const APos: TSeatPos);
    procedure SeonCheckRoundComplete;
    procedure SeonEvaluate;
    procedure SeonFinish;
    procedure SeonTimerTick(Sender: TObject);
    procedure DrawSeonPick;
    procedure BeginShuffleEffect(const AOnDone: TProc);
    procedure BeginDealAnimation(const AFloor: TArray<THwatuCard>; const ACounts: TArray<Integer>; const AOnDone: TProc);
    function  DealDeckPoint: TPointF;
    procedure StartBonusPick(const AStockIndex: Integer);
    procedure PickTick(Sender: TObject);
    procedure DrawBonusDraw;
    procedure BuildFinalSummary;
    function  PresentationBusy: Boolean;
    procedure MaybeBeginGameOver;
    procedure PlayChosen(const AHandIndex: Integer; const AFloorChoice: Integer);
    procedure AutoStopIfLastCard;
    procedure EnterFlipChoice;
    function RState: TGameState;
    procedure StartTurnAnimation(const ABefore: TGameState; const AOnDone: TProc);
    procedure AnimTick(Sender: TObject);
    procedure ComputeDrawWindows(out AWinStart, AFlyEnd, AWinEnd: TArray<Single>; out ATotalMs: Single);
    procedure AnimAdvanceStage;
    procedure AnimApplyStageStart(const AStage: Integer);
    procedure AnimApplyStageEnd(const AStage: Integer);
    procedure FinishAnimation;
    procedure DrawFlyers;
    procedure DrawFlyerCard(const ACenter: TPointF; const AAssetId: string; const AFlip: Boolean;
      const AProgress: Single; const ASquashY: Single = 1.0);
    procedure DrawEffectBanner;
    procedure BeginNagariAnim;
    // IAnimationHost 구현(Gostop.Board.Animation) — 나머지(CenterRegion·CardSize·ShakeOffsetX·
    // DrawCardRotated·BeginShakeEffect)는 기존 메서드가 그대로 인터페이스 계약을 만족한다.
    function  GetCanvas: TCanvas;
    function  GetGameSpeed: Single;
    procedure PlaySound(const AName: string);
    procedure RequestRepaint;
    procedure BeginShakeEffect(const AAmplitude: Single = 1.0);
    function  ShakeOffsetX: Single;
    procedure ForceSpeech(const ASeat: TSeatPos; const AText: string);
    procedure MaybeShowSpeech;
    procedure SpeechTimerTick(Sender: TObject);
    procedure DrawSpeechBubble;
    procedure EffectTimerTick(Sender: TObject);
    procedure CollectTurnEffects;
    procedure QueueEffect(const AText: string);
    procedure ShowNextQueuedEffect;
    procedure PlayTurnSound;
    function CapturedAnchor(const AActor: Integer): TPointF;
    function FloorMatchOrdinal(const AFloorIndex, AMonth: Integer): Integer;
    function CanCaptureCard(const ACard: THwatuCard): Boolean;
    function PhysicalPos(const AGameIndex: Integer): TSeatPos;
    function SeatLabel(const APhysicalSeat: Integer): string;
    function LogicalSeatOf(const APos: TSeatPos): Integer;
    function CardSize: TSizeF;
    procedure DrawFront(const R: TRectF; const AAssetId: string);
    procedure DrawBack(const R: TRectF);
    procedure DrawLabel(const R: TRectF; const AText: string; const AColor: TAlphaColor;
      const ASize: Single; const ABold: Boolean = False);
    procedure DrawCapturedFan(const APile: TList<THwatuCard>; const AX, ARight, AY, AScale: Single;
      const AAnchorRight: Boolean = False; const AGukjinAsPi: Boolean = False; const ASkipPileIndex: Integer = -1);
    procedure DrawCapturedFanV(const APile: TList<THwatuCard>; const ACX, ATopY, ABottomY, AScale, AAngle: Single;
      const AAnchorBottom: Boolean = False; const AReverse: Boolean = False; const ABadgeDir: Integer = 1;
      const AGukjinAsPi: Boolean = False; const ASkipPileIndex: Integer = -1);
    function  CapturedFanLayout(const APile: TList<THwatuCard>; const AX, ARight, AScale: Single;
      const AAnchorRight, AGukjinAsPi: Boolean; out ASeq: TArray<Integer>): TArray<Single>;
    function  CapturedFanLayoutV(const APile: TList<THwatuCard>; const ATopY, ABottomY, AScale: Single;
      const AAnchorBottom, AReverse, AGukjinAsPi: Boolean; out ASeq: TArray<Integer>): TArray<Single>;
    procedure DrawCapturedCount(const ACenterX, ACenterY: Single; const ACount: Integer);
    function  CapturedBadgeSize: TSizeF;
    function  CapturedSequence(const APile: TList<THwatuCard>; const AGukjinAsPi: Boolean = False): TArray<Integer>;
    function  CapturedFanSpec(const APos: TSeatPos; const AIsHuman: Boolean): TCapturedFanSpec;
    procedure BeginGukjinMove;
    procedure GukjinMoveTick(Sender: TObject);
    procedure DrawGukjinMove;
    function  GukjinSlotRect(const AGameIndex, APileIndex: Integer; const AGukjinAsPi: Boolean): TRectF;
    procedure DrawCardRotated(const ACenterX, ACenterY, ACardW, ACardH, AAngle: Single; const AAssetId: string; const ABack: Boolean);
    procedure DrawHumanHand(const ARegion: TRectF);
    procedure DrawHandList(const AHand: TList<THwatuCard>; const ARegion: TRectF; const AInteractive: Boolean;
      const ARaiseIds: TArray<string> = nil);
    procedure DrawPlayerPanel(const APos: TSeatPos);
    procedure DrawPanels;
    procedure GenerateAvatars;
    procedure LoadAvatarPool;
    procedure LoadSkillAvatarPool;
    function  LoadStateAvatar(const AFile: string): TBitmap;
    function  ResultAvatarBitmap(const AAvatarIdx: Integer; const AIsWinner, AIsPenalized: Boolean): TBitmap;
    function  NormalAvatarBitmap(const AAvatarIdx: Integer): TBitmap;
    procedure AssignAvatars;
    procedure SetHumanAvatar(const AIndex: Integer);
    procedure DrawAvatarPicker;
    procedure DrawControlBar;
    procedure PaintGame;
    procedure DrawPauseOverlay;
    procedure DrawTitleMenu;
    procedure DrawProgramInfo;
    procedure OpenHelpDoc(const AFileName: string);
    procedure DrawSettings;
    procedure DrawCfgToggle(const ARect: TRectF; const AOn: Boolean);
    procedure DrawCfgValueButton(const ARect: TRectF; const AText: string);
    // 선택형 아바타 카드 렌더는 Gostop.Board.CardRender(TSelectCardRender)로 분리됨
    procedure CycleCfg(const AIndex: Integer);
    function  CfgScore: TScoreOptions;
    function  CfgRules: TRuleSet;
    function  CfgDeckOptions: TDeckOptions;
    function  SettingsPath: string;
    procedure LoadSettings;
    procedure SaveSettings;
    procedure BeginNickEdit(const ARow: TRectF);
    procedure ApplyNickEdit;
    procedure NickEditKeyDown(Sender: TObject; var Key: Word; var KeyChar: WideChar; Shift: TShiftState);
    procedure OpenMatchSetup(const ACount: Integer);
    procedure DrawMatchSetup;
    procedure StartMatchFromSetup;
    procedure StartSlotSpin(const AOnlyRow: Integer = -1);
    procedure SlotTick(Sender: TObject);
    procedure ComputeRowPos;
    function  PickUnusedAvatar: Integer;
    function  AvatarName(const AIndex: Integer): string;
    function  AvatarStat(const AIndex: Integer; const AStat: Integer): Integer;
    procedure RollSeatLuck;
    function  SeatDisplayName(const APos: TSeatPos): string;
    procedure SetVolumeFromX(const AX: Single);
    procedure SetSpeedFromX(const AX: Single);
    function  PlayerPanelRect(const APos: TSeatPos): TRectF;
    function  SeatCardArea(const APos: TSeatPos): TRectF;
    function PlayerAtPos(const APos: TSeatPos): Integer;
    procedure DrawOpponent(const AGameIndex: Integer; const APos: TSeatPos; const ARegion: TRectF);
    procedure DrawCenter(const ARegion: TRectF);
    function FloorLayout(const AFloor: TList<THwatuCard>): TArray<TRectF>;
    function CardCenterInFloor(const AFloor: TList<THwatuCard>; const AAssetId: string): TPointF;
    function IsCapturedAsset(const AAssetId: string): Boolean;
    function FloorMonthCenter(const AMonth: Integer): TPointF;
    procedure DrawRegion(const ARegion: TRectF; const AHighlight: Boolean);
    function SeatRegion(const APos: TSeatPos): TRectF;
    function CenterRegion: TRectF;
    procedure DrawNegotiation;
    procedure DrawGameOver;
    procedure GameOverContinue;
    procedure GameOverQuit;
    procedure GameOverTimerTick(Sender: TObject);
    procedure DrawGoStopPrompt;
    procedure DrawShodangButton;
    function  HumanCanShodang: Boolean;
    procedure HumanCallShodang;
    procedure AiExecuteTurn;
    procedure AiCallShodang(const ACaller: Integer);
    procedure ResolveShodang(const ACaller, AOppA, AOppB: Integer; const AAccA, AAccB: Boolean);
    procedure HumanRespondShodang(const AAccept: Boolean);
    procedure DrawShodangPrompt;
    function  DrawStdDialog(const ATitle: string; const AWidth, AHeight: Single): TRectF;
    procedure EndStdDialog;
    procedure DialogPopTick(Sender: TObject);
    procedure MoneyCountTick(Sender: TObject);
    function  AdjustColor(const AColor: TAlphaColor; const ADelta: Integer): TAlphaColor;
    function  IsHot(const ARect: TRectF): Boolean;
    function  IsPressed(const ARect: TRectF): Boolean;
    function  DrawStdButton(const ARect: TRectF; const ACaption: string; const AKind: TDlgBtnKind;
      const AEnabled: Boolean = True; const AFontSize: Single = 17): TRectF;

    // MouseDown 디스패치 분기(화면/상태별로 분리 — 각자 원래 항상 Exit로 끝나던 블록 그대로)
    procedure MouseDownGiri(const LPoint: TPointF);
    procedure MouseDownShodangPrompt(const LPoint: TPointF);
    procedure MouseDownTitleArea(const LPoint: TPointF);
    procedure MouseDownSettingsDialog(const LPoint: TPointF);
    procedure MouseDownMatchSetupDialog(const LPoint: TPointF);
    procedure MouseDownTitleButtons(const LPoint: TPointF);
    procedure MouseDownProgramInfo(const LPoint: TPointF);
    procedure MouseDownAvatarPicker(const LPoint: TPointF);
    procedure MouseDownSeonPick(const LPoint: TPointF);
    procedure MouseDownBonusDraw(const LPoint: TPointF);
    procedure MouseDownGameOver(const LPoint: TPointF);
    procedure MouseDownGoStopPrompt(const LPoint: TPointF);
    procedure MouseDownFlipChoice(const LPoint: TPointF);
    procedure MouseDownNegotiation(const LPoint: TPointF);
    procedure MouseDownFloorChoice(const LPoint: TPointF);
    procedure MouseDownPlayHand(const LPoint: TPointF);
  protected
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Single); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Single); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Single); override;
    procedure DoMouseLeave; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    /// <summary>새 게임을 시작합니다.</summary>
    /// <param name="APlayerCount">플레이어 수(2/3/4). 4인은 광팔기 협상 후 3인이 친다.</param>
    /// <param name="AiSkill">AI 능력치(0~100).</param>
    /// <param name="AStartPos">선(먼저 두는 자리). 기본은 위(P1). '다음게임'에서 이전 승자 자리를 넘긴다.</param>
    /// <param name="ANewMatch">새 매치면 True(시드머니·전적 리셋). '다음게임'은 False로 이어간다.</param>
    procedure NewGame(const APlayerCount: Integer = 2; const AiSkill: Integer = 70; const AStartPos: TSeatPos = spTop; const ANewMatch: Boolean = True);
    /// <summary>사람이 '고'를 선언합니다(고/스톱 대기 중일 때만).</summary>
    procedure HumanGo;
    /// <summary>사람이 '스톱'을 선언합니다(고/스톱 대기 중일 때만).</summary>
    procedure HumanStop;
    /// <summary>일시정지 상태를 켜고 끕니다(스페이스바 등 외부 단축키에서 호출).</summary>
    procedure TogglePause;
    /// <summary>이번 판 한정 자동 진행(내 턴도 AI가 대신 결정)을 켜고 끕니다.</summary>
    procedure ToggleAutoPlay;
    /// <summary>현재 텍스트 입력(닉네임 편집 등)이 포커스를 갖고 있는지 — 단축키가 타이핑을 가로채지 않도록.</summary>
    function IsTextInputActive: Boolean;

    /// <summary>현재 상태 안내 문구.</summary>
    property StatusText: string read FStatus;
    /// <summary>사람이 고/스톱을 선택해야 하는 상태인지.</summary>
    property AwaitingGoStop: Boolean read FAwaitingGoStop;
    /// <summary>뒷장 색(red/blue/green/purple/black).</summary>
    property BackColor: string read FBackColor write FBackColor;
    /// <summary>타이틀 메뉴의 '종료' 클릭 시(폼이 닫기 처리).</summary>
    property OnExitRequest: TNotifyEvent read FOnExitRequest write FOnExitRequest;
    /// <summary>상태가 바뀔 때(폼이 버튼·상태표시 갱신용).</summary>
    property OnStateChanged: TNotifyEvent read FOnStateChanged write FOnStateChanged;
    /// <summary>게임이 끝났을 때.</summary>
    property OnGameOver: TNotifyEvent read FOnGameOver write FOnGameOver;
  end;

implementation

const
  GWANG_UNIT_PRICE = 1;      // 광 1개당 단가(광값 = 광개수 × 단가)
  // PANEL_W/PANEL_H는 Gostop.Board.Layout 유닛에 있음(uses로 참조)
  AI_SKILL_LABELS: array [0 .. 3] of string = ('병아리', '선수', '타짜', '신의손');
  AI_SKILL_VALUES: array [0 .. 3] of Integer = (30, 50, 70, 100);
  GAME_MODE_LABELS: array [2 .. 4] of string = ('맞고', '삼파전', '광팔어유');   // 2/3/4인 모드 별칭
  GAME_OVER_COUNTDOWN_SECONDS = 5.0;   // 게임종료 팝업 방치 시 자동진행까지의 대기 시간(초)
  MONEY_TICK_INTERVAL = 0.09;          // 정산 금액이 오르는 동안 동전 소리 간격(초)

// 군용담요 텍스처용 결정론적 섬유 잡음(-32..31). 좌표 해시 기반(Random 미사용).
function FeltNoise(const AX, AY: Integer): Integer;
begin
  var LH: Cardinal := (Cardinal(AX) * 73856093) xor (Cardinal(AY) * 19349663);
  LH := (LH xor (LH shr 13)) * 1274126177;
  LH := LH xor (LH shr 16);
  Result := Integer(LH and $3F) - 32;
end;

// 카드 정렬 키: 월(보너스=맨 뒤) → 종류(광·열끗·띠·피·보너스) → 순번
function CardSortKey(const ACard: THwatuCard): Integer;
begin
  var LMonth := ACard.Month;
  if LMonth <= 0 then
  begin
    LMonth := 13;
  end;

  var LKindRank := 4;
  case ACard.Kind of
    hkBright:
      begin
        LKindRank := 0;
      end;
    hkAnimal:
      begin
        LKindRank := 1;
      end;
    hkRibbon:
      begin
        LKindRank := 2;
      end;
    hkJunk:
      begin
        LKindRank := 3;
      end;
    hkBonus:
      begin
        LKindRank := 4;
      end;
  end;

  Result := LMonth * 100 + LKindRank * 10 + ACard.Ordinal;
end;

// 획득 더미 그룹: 0=광, 1=열끗, 2=띠, 3=피(피+보너스)
// AGukjinAsPi=True 면 (전환권이 남은) 국진을 피 무리로 본다 — 정산에서 쌍피로 해석됐을 때의 표시용.
function CapturedGroup(const ACard: THwatuCard; const AGukjinAsPi: Boolean = False): Integer;
begin
  if AGukjinAsPi and ACard.IsGukjin and (not ACard.GukjinLocked) then
  begin
    Exit(3);
  end;

  case ACard.Kind of
    hkBright:
      begin
        Result := 0;
      end;
    hkAnimal:
      begin
        Result := 1;
      end;
    hkRibbon:
      begin
        Result := 2;
      end;
  else
    begin
      Result := 3;
    end;
  end;
end;

function SortedIndices(const AList: TList<THwatuCard>): TArray<Integer>;
begin
  SetLength(Result, AList.Count);
  for var I := 0 to AList.Count - 1 do
  begin
    Result[I] := I;
  end;

  for var I := 1 to High(Result) do
  begin
    var LIdx := Result[I];
    var LKey := CardSortKey(AList[LIdx]);
    var J := I - 1;
    while (J >= 0) and (CardSortKey(AList[Result[J]]) > LKey) do
    begin
      Result[J + 1] := Result[J];
      Dec(J);
    end;

    Result[J + 1] := LIdx;
  end;
end;

// AAfter에 없는(=빠져나간) ABefore의 카드들(AssetId 기준, 카드마다 고유)
function CardsRemoved(const ABefore, AAfter: TList<THwatuCard>): TArray<THwatuCard>;
begin
  var LSeen := TDictionary<string, Boolean>.Create;
  try
    for var LCard in AAfter do
    begin
      LSeen.AddOrSetValue(LCard.AssetId, True);
    end;

    var LList := TList<THwatuCard>.Create;
    try
      for var LCard in ABefore do
      begin
        if not LSeen.ContainsKey(LCard.AssetId) then
        begin
          LList.Add(LCard);
        end;
      end;

      Result := LList.ToArray;
    finally
      LList.Free;
    end;
  finally
    LSeen.Free;
  end;
end;

// ABefore에 없던(=새로 들어온) AAfter의 카드들
function CardsAdded(const ABefore, AAfter: TList<THwatuCard>): TArray<THwatuCard>;
begin
  Result := CardsRemoved(AAfter, ABefore);
end;

// AssetId로 목록에서 카드 1장 제거(있으면 True)
function RemoveCardByAsset(const AList: TList<THwatuCard>; const AAssetId: string): Boolean;
begin
  for var I := 0 to AList.Count - 1 do
  begin
    if AList[I].AssetId = AAssetId then
    begin
      AList.Delete(I);
      Exit(True);
    end;
  end;

  Result := False;
end;

// 턴 대표 사운드 우선순위(단일 채널이라 한 턴에 하나만 낸다). 0 = 특수 아님
function EventSoundPriority(const AKind: TPlayEventKind): Integer;
begin
  case AKind of
    pekBomb:
      begin
        Result := 100;
      end;
    pekChongtong:
      begin
        Result := 95;
      end;
    pekSambbeok:
      begin
        Result := 90;
      end;
    pekSseul:
      begin
        Result := 80;
      end;
    pekTtadak:
      begin
        Result := 75;
      end;
    pekJjok:
      begin
        Result := 70;
      end;
    pekShake:
      begin
        Result := 65;
      end;
    pekBbeok, pekJabbeok, pekYeonbbeok, pekCheotbbeok:
      begin
        Result := 60;
      end;
    pekReverseGo:
      begin
        Result := 85;   // 역고는 판을 뒤집는 선언이라 고/스톱보다 크게 알린다
      end;
    pekGo, pekStop:
      begin
        Result := 50;
      end;
  else
    begin
      Result := 0;
    end;
  end;
end;

// 특수 상황 이벤트 → 배너 문구('' = 배너 없음)
function EventEffectLabel(const AKind: TPlayEventKind): string;
begin
  case AKind of
    pekJjok:
      begin
        Result := '쪽!';
      end;
    pekTtadak:
      begin
        Result := '따닥!';
      end;
    pekSseul:
      begin
        Result := '싹쓸이!';
      end;
    pekBomb:
      begin
        Result := '폭탄!';
      end;
    pekShake:
      begin
        Result := '흔들기!';
      end;
    pekReverseGo:
      begin
        Result := '역고!';
      end;
    pekBbeok:
      begin
        Result := '뻑!';
      end;
    pekJabbeok:
      begin
        Result := '자뻑!';
      end;
    pekYeonbbeok:
      begin
        Result := '연뻑!';
      end;
    pekCheotbbeok:
      begin
        Result := '첫뻑!';
      end;
    pekSambbeok:
      begin
        Result := '쓰리뻑!';
      end;
    pekChongtong:
      begin
        Result := '총통!';
      end;
    // pekBonusCapture는 배너 없음 — 뒤집기 중 조커는 "한장 더~"가 즉시 뜨고,
    // 손에서 낸 조커는 뒷패 고르기 다이얼로그가 떠서 별도 배너가 중복·잉여가 됨
    pekGo:
      begin
        Result := '고!';
      end;
  else
    begin
      Result := '';
    end;
  end;
end;

procedure SortIndexList(const AList: TList<THwatuCard>; const AIndices: TList<Integer>);
begin
  for var I := 1 to AIndices.Count - 1 do
  begin
    var LIdx := AIndices[I];
    var LKey := CardSortKey(AList[LIdx]);
    var J := I - 1;
    while (J >= 0) and (CardSortKey(AList[AIndices[J]]) > LKey) do
    begin
      AIndices[J + 1] := AIndices[J];
      Dec(J);
    end;

    AIndices[J + 1] := LIdx;
  end;
end;

{$REGION 'TGostopBoard'}
constructor TGostopBoard.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  HitTest := True;
  FBackColor := 'red';
  FHoverHand := -1;
  FHoverBonus := -1;
  FHoverGiri := -1;
  FPlayerCount := 2;
  FAiSkill := 70;
  FStatus := '새 게임을 시작하세요';
  FGiriRects := TList<TRectF>.Create;
  FGiriAiTimer := TTimer.Create(Self);
  FGiriAiTimer.Interval := 1100;
  FGiriAiTimer.Enabled := False;
  FGiriAiTimer.OnTimer := GiriAiTimerTick;
  FGukjinMoveTimer := TTimer.Create(Self);
  FGukjinMoveTimer.Interval := 16;   // ~60fps
  FGukjinMoveTimer.Enabled := False;
  FGukjinMoveTimer.OnTimer := GukjinMoveTick;
  FGiriCloseTimer := TTimer.Create(Self);
  FGiriCloseTimer.Interval := 16;   // ~60fps
  FGiriCloseTimer.Enabled := False;
  FGiriCloseTimer.OnTimer := GiriCloseTimerTick;
  FHandRects := TList<TRectF>.Create;
  FHandIndexMap := TList<Integer>.Create;
  FFloorRects := TList<TRectF>.Create;
  FFloorIndexMap := TList<Integer>.Create;
  FAiObjects := TObjectList<TAiPlayer>.Create(True);
  FImages := TCardImageCache.Create;
  FAiTimer := TTimer.Create(Self);
  FAiTimer.Interval := 650;
  FAiTimer.Enabled := False;
  FAiTimer.OnTimer := AiTimerTick;
  FAnimTimer := TTimer.Create(Self);
  FAnimTimer.Interval := 16;   // ~60fps
  FAnimTimer.Enabled := False;
  FAnimTimer.OnTimer := AnimTick;
  FTurnEvents := TList<TPlayEvent>.Create;
  FEffectTimer := TTimer.Create(Self);
  FEffectTimer.Interval := 1500;
  FEffectTimer.Enabled := False;
  FEffectTimer.OnTimer := EffectTimerTick;
  FSpeechTimer := TTimer.Create(Self);
  FSpeechTimer.Interval := 3200;
  FSpeechTimer.Enabled := False;
  FSpeechTimer.OnTimer := SpeechTimerTick;
  FLastSpeechGameIndex := -1;
  FSeonTimer := TTimer.Create(Self);
  FSeonTimer.Interval := 600;
  FSeonTimer.Enabled := False;
  FSeonTimer.OnTimer := SeonTimerTick;
  FDialogPopTimer := TTimer.Create(Self);
  FDialogPopTimer.Interval := 16;   // ~60fps
  FDialogPopTimer.Enabled := False;
  FDialogPopTimer.OnTimer := DialogPopTick;
  FMoneyCountTimer := TTimer.Create(Self);
  FMoneyCountTimer.Interval := 16;   // ~60fps
  FMoneyCountTimer.Enabled := False;
  FMoneyCountTimer.OnTimer := MoneyCountTick;
  FBonusRects := TList<TRectF>.Create;
  FPickTimer := TTimer.Create(Self);
  FPickTimer.Interval := 16;   // ~60fps
  FPickTimer.Enabled := False;
  FPickTimer.OnTimer := PickTick;
  FAvatarRects := TList<TRectF>.Create;
  FHumanAvatarIdx := -1;
  for var LP := spTop to spRight do
  begin
    FSeatAvatar[LP] := -1;
    FSeatSkill[LP] := 70;
  end;

  FSlotTimer := TTimer.Create(Self);
  FSlotTimer.Interval := 45;
  FSlotTimer.Enabled := False;
  FSlotTimer.OnTimer := SlotTick;
  FGwangTimer := TTimer.Create(Self);
  FGwangTimer.Interval := 2600;   // 광 판매 발표 표시 시간
  FGwangTimer.Enabled := False;
  FGwangTimer.OnTimer := GwangTimerTick;
  FReplaceTimer := TTimer.Create(Self);
  FReplaceTimer.Interval := 16;   // ~60fps
  FReplaceTimer.Enabled := False;
  FReplaceTimer.OnTimer := ReplaceTimerTick;
  FGameOverTimer := TTimer.Create(Self);
  FGameOverTimer.Interval := 16;   // ~60fps(숫자 축소 애니메이션용)
  FGameOverTimer.Enabled := False;
  FGameOverTimer.OnTimer := GameOverTimerTick;
  FNegAnimTimer := TTimer.Create(Self);
  FNegAnimTimer.Interval := 33;   // ~30fps 흔들림
  FNegAnimTimer.Enabled := False;
  FNegAnimTimer.OnTimer := NegAnimTick;
  FShakeAnim := nil;

  FAnimMgr := TAnimationManager.Create(Self);   // Self 를 IAnimationHost 로 전달
  for var LP := Low(TSeatPos) to High(TSeatPos) do
  begin
    FAvatarActors[LP] := TAvatarActor.Create(FAnimMgr);   // 매니저 생성 뒤에 주입
  end;
  FNagariAnim := nil;
  FFoldTimer := TTimer.Create(Self);
  FFoldTimer.Interval := 16;    // ~60fps
  FFoldTimer.Enabled := False;
  FFoldTimer.OnTimer := FoldTimerTick;
  FFoldT := 1;                  // 연출 없음 상태로 시작
  FSetupHumanRow := 0;
  FRowPos[0] := spTop;
  FRowPos[1] := spBottom;
  FRowPos[2] := spLeft;
  FRowPos[3] := spRight;

  FGameSpeed := 1.0;

  // 게임 룰 기본값(설정창에서 변경 가능)
  FConfig.Reset;

  Randomize;   // 아바타 랜덤 배정·AI 연출용(덱 셔플은 별도 보안 난수 사용)
  LoadSettings;   // INI(gostop.ini)에서 룰·볼륨·배속·아바타 복원
end;

destructor TGostopBoard.Destroy;
begin
  ClearGame(False);   // 앱 종료에 의한 정리 — 저장 파일은 보존('이어하기'가 살아있어야 함)
  for var LP := spTop to spRight do
  begin
    FreeAndNil(FAvatars[LP]);
  end;

  FreeAndNil(FAiObjects);
  FreeAndNil(FTurnEvents);
  FreeAndNil(FBonusRects);
  FreeAndNil(FAvatarRects);
  FreeAndNil(FAvatarPool);
  FreeAndNil(FAvatarCheerPool);
  FreeAndNil(FAvatarSadPool);
  FreeAndNil(FAvatarAngryPool);
  FreeAndNil(FSkillAvatarPool);
  FreeAndNil(FFeltTile);
  FreeAndNil(FImages);
  FreeAndNil(FFloorIndexMap);
  FreeAndNil(FFloorRects);
  FreeAndNil(FHandIndexMap);
  FreeAndNil(FHandRects);
  FreeAndNil(FGiriRects);
  FreeAndNil(FGiriDeck);
  for var LP := Low(TSeatPos) to High(TSeatPos) do
  begin
    FAvatarActors[LP].Free;
  end;

  FNagariAnim := nil;         // 매니저가 소유(OwnsObjects) — 아래 매니저 해제 시 함께 정리
  FreeAndNil(FAnimMgr);
  inherited Destroy;
end;

procedure TGostopBoard.ClearGame(const ADeleteSave: Boolean);
begin
  FAiTimer.Enabled := False;
  FAnimTimer.Enabled := False;
  if Assigned(FEffectTimer) then
  begin
    FEffectTimer.Enabled := False;
  end;

  // 기리 대기 상태 정리(대기 중 취소 시 덱 누수 방지)
  FGiriPhase := False;
  FGiriProceed := nil;
  FGiriAiTimer.Enabled := False;
  FGiriClosing := False;
  FGiriSplitting := False;
  FGiriCloseTimer.Enabled := False;
  FreeAndNil(FGiriDeck);

  // 쇼당 상태 정리
  FShodangActive := False;
  FShodangPending := False;

  // 잔상·스테일 상태 리셋(타이틀 복귀 시 배너·고/스톱 플래그 잔존 방지)
  FAwaitingGoStop := False;
  FEffectText := '';
  FEffectQueue := nil;
  FEffectQueueIdx := 0;
  FEffectGap := False;
  if Assigned(FEffectTimer) then
  begin
    FEffectTimer.Enabled := False;
  end;

  for var LP := Low(TSeatPos) to High(TSeatPos) do
  begin
    if Assigned(FAvatarActors[LP]) then
    begin
      FAvatarActors[LP].Reset;   // 표정 평상시로(홀드 애니는 아래 FAnimMgr.Clear 가 제거)
    end;
  end;
  FSpeechText := '';
  if Assigned(FSpeechTimer) then
  begin
    FSpeechTimer.Enabled := False;
  end;

  FLastSpeechGameIndex := -1;
  FResultRows := nil;
  FResultTitle := '';
  if Assigned(FSeonTimer) then
  begin
    FSeonTimer.Enabled := False;
  end;

  FSeonPicking := False;
  FreeAndNil(FSeonDeck);
  FDealing := False;     // 실제 딜 애니는 아래 FAnimMgr.Clear 가 정리
  FShuffling := False;   // 실제 셔플 애니는 아래 FAnimMgr.Clear 가 정리
  if Assigned(FPickTimer) then
  begin
    FPickTimer.Enabled := False;
  end;

  FPickActive := False;
  FAvatarPicking := False;
  FAnimStage := 0;
  FAnimDone := nil;
  FreeAndNil(FDisplay);
  FChoosing := False;
  FFlipChoosing := False;
  FNegotiating := False;
  if Assigned(FNegAnimTimer) then
  begin
    FNegAnimTimer.Enabled := False;
  end;

  FShakeAnim := nil;   // 흔들림 오프셋 제거(실제 애니는 아래 FAnimMgr.Clear 가 정리)
  if Assigned(FFoldTimer) then
  begin
    FFoldTimer.Enabled := False;
  end;

  FFoldT := 1;
  FFoldOnDone := nil;
  FFoldFrom := nil;
  FFoldAngle := nil;
  FGameOverPending := False;

  // 국진 → 쌍피 이동 상태도 판마다 초기화(안 하면 다음 판에서 이동을 건너뛰거나 표시가 남는다)
  if Assigned(FGukjinMoveTimer) then
  begin
    FGukjinMoveTimer.Enabled := False;
  end;

  FGukjinMoveActive := False;
  FGukjinMoveDone := False;
  for var LP := Low(TSeatPos) to High(TSeatPos) do
  begin
    FGukjinAsPi[LP] := False;
  end;

  // 나가리 연출 등 진행 중인 애니메이션도 판마다 초기화(잔상·중복 시작 방지)
  if Assigned(FAnimMgr) then
  begin
    FAnimMgr.Clear;
  end;

  FNagariAnim := nil;
  FNagariAnimDone := False;

  if Assigned(FGwangTimer) then
  begin
    FGwangTimer.Enabled := False;
  end;

  FGwangShow := False;
  if Assigned(FReplaceTimer) then
  begin
    FReplaceTimer.Enabled := False;
  end;

  if Assigned(FGameOverTimer) then
  begin
    FGameOverTimer.Enabled := False;
  end;

  if Assigned(FMoneyCountTimer) then
  begin
    FMoneyCountTimer.Enabled := False;
  end;
  FGameOverReady := False;

  FReplacingSeats := nil;
  FHoverHand := -1;
  FHoverBonus := -1;
  FHoverGiri := -1;
  FAgents := nil;
  if Assigned(FAiObjects) then
  begin
    FAiObjects.Clear;
  end;

  FreeAndNil(FEngine);
  FreeAndNil(FGame);
  FreeAndNil(FTable4);

  // 타이틀 복귀·새 게임 시작 등 진행 중 게임이 사라지는 경로에서는 저장 파일도 함께 정리.
  // 단, 소멸자에서 정리 목적으로 호출될 때는 지우면 안 됨(앱을 그냥 닫은 것 — '이어하기'가
  // 살아있어야 함) → ADeleteSave=False로 호출
  if ADeleteSave then
  begin
    TGostopSaveGame.Delete;
  end;
end;

procedure TGostopBoard.GenerateFeltTile;
const
  TILE = 128;
  BASE_R = 40;   // 기본 올리브-그린(군용담요 울)
  BASE_G = 66;
  BASE_B = 48;
begin
  FFeltTile := TBitmap.Create(TILE, TILE);
  var LData: TBitmapData;
  if FFeltTile.Map(TMapAccess.Write, LData) then
  begin
    try
      for var Y := 0 to TILE - 1 do
      begin
        for var X := 0 to TILE - 1 do
        begin
          var LShade := FeltNoise(X, Y) + (((X + Y) mod 4) - 2) * 5;
          var LR := EnsureRange(BASE_R + LShade, 0, 255);
          var LG := EnsureRange(BASE_G + LShade, 0, 255);
          var LB := EnsureRange(BASE_B + LShade, 0, 255);
          LData.SetPixel(X, Y, $FF000000 or (Cardinal(LR) shl 16) or (Cardinal(LG) shl 8) or Cardinal(LB));
        end;
      end;
    finally
      FFeltTile.Unmap(LData);
    end;
  end;
end;

function TGostopBoard.SeatLabel(const APhysicalSeat: Integer): string;
begin
  // 논리 좌석(0=선) → 물리 위치의 표시 이름(나=닉네임, AI=아바타 닉네임)
  Result := SeatDisplayName(TSeatPos((Ord(FNextStartPos) + APhysicalSeat) mod 4));
end;

// 물리 위치의 선 기준 논리 좌석(0=선). 4인 역할 판정용
function TGostopBoard.LogicalSeatOf(const APos: TSeatPos): Integer;
begin
  Result := (Ord(APos) - Ord(FNextStartPos) + 4) mod 4;
end;

function TGostopBoard.PhysicalPos(const AGameIndex: Integer): TSeatPos;
begin
  // 2/3인: 대전 설정의 시트 행(P1..PN) = 게임 인덱스 → 물리 위치(내 시트=아래)
  if FPlayerCount <= 3 then
  begin
    Result := FRowPos[EnsureRange(AGameIndex, 0, 3)];
    Exit;
  end;

  // 4인: 게임 인덱스 → 논리 좌석(FSeatMap) → 선(FNextStartPos) 기준 반시계 물리 위치
  Result := TSeatPos((Ord(FNextStartPos) + FSeatMap[AGameIndex]) mod 4);
end;

procedure TGostopBoard.NewGame(const APlayerCount: Integer; const AiSkill: Integer; const AStartPos: TSeatPos; const ANewMatch: Boolean);
begin
  ClearGame;
  FPlayerCount := EnsureRange(APlayerCount, 2, 4);
  FAiSkill := AiSkill;
  FNextStartPos := AStartPos;
  FAwaitingGoStop := False;
  FShodangActive := False;   // 쇼당 상태 초기화(매 게임)
  FShodangPending := False;

  // 새 매치면 시드머니·전적·판돈 배수 리셋
  if ANewMatch then
  begin
    FStakes := 1;
    for var LP := spTop to spRight do
    begin
      FMoney[LP] := FConfig.SeedMoney;
      FWins[LP] := 0;
      FLosses[LP] := 0;
      FGaveUpLast[LP] := False;   // 연사 추적 초기화
    end;
  end;

  // 아바타 배정은 대전 설정 다이얼로그가 담당 — 미배정(직접 호출 등)일 때만 폴백 랜덤
  if FSeatAvatar[spBottom] < 0 then
  begin
    AssignAvatars;
  end;

  // 판별 운 굴림(캐릭터 운 스탯 기반, 새 판마다) — 딜 보정과 패널 표시에 사용
  RollSeatLuck;

  // 새 매치는 '밤일낮장'으로 선을 뽑는다. '다음게임'(이어가기)은 승자가 선이므로 바로 진행.
  if ANewMatch then
  begin
    BeginSeonPick;
  end
  else
  begin
    ProceedAfterSeon;
  end;
end;

// 말번(마지막 차례) 물리 위치: 이번 판 선(FNextStartPos) 바로 앞(반시계 역방향) 좌석 = 한 바�퀴 돌아
// 선에게 넘어가기 직전 마지막으로 도는 사람. 인원수별 활성 좌석 순환(반시계: 위→왼쪽→아래→오른쪽,
// 2인은 왼쪽 자리를 건너뜀)에서 선의 바로 이전 자리를 찾는다.
// 주의: PhysicalPos(FPlayerCount - 1)로 계산하던 이전 방식은 2/3인에서 PhysicalPos가 매치 시작 시
// 고정된 FRowPos(=항상 사람이 마지막 행)만 참조해, 실제 이번 판 선이 누구든 상관없이 항상 사람
// 좌석을 말번으로 잘못 골랐다(맞고에서 사람이 선이어도 기리 화면에 사람이 뽑히던 버그).
function TGostopBoard.MalbeonPos: TSeatPos;
begin
  var LCycle: TArray<TSeatPos>;
  case FPlayerCount of
    2:
      begin
        LCycle := [spTop, spBottom];
      end;
    3:
      begin
        LCycle := [spTop, spLeft, spBottom];
      end;
  else
    begin
      LCycle := [spTop, spLeft, spBottom, spRight];
    end;
  end;

  var LSeonIdx := 0;
  for var I := 0 to High(LCycle) do
  begin
    if LCycle[I] = FNextStartPos then
    begin
      LSeonIdx := I;
      Break;
    end;
  end;

  Result := LCycle[(LSeonIdx - 1 + Length(LCycle)) mod Length(LCycle)];
end;

// 기리: 딜 직전 말번에게 덱 커팅 권리. 기리 자체는 매번 실행되고(카드 장수가 너무 적을 때만 예외),
// 말번이 사람이든 AI든 화면에 부채꼴로 펼쳐 보여준다. 사람은 직접 클릭해서 컷/퉁을 고르고,
// AI(또는 관전)는 잠시 보여준 뒤 자동으로 결정한다(그 결정 확률은 GiriAiTimerTick 참조 — 컷 60%/퉁 40%).
procedure TGostopBoard.RequestGiri(const ADeck: TDeck; const AProceed: TProc);
begin
  FGiriDeck := ADeck;
  FGiriProceed := AProceed;

  if ADeck.Count <= 10 then
  begin
    ResolveGiri(-1);   // 컷할 여지가 너무 적으면 그대로(퉁) 진행
    Exit;
  end;

  FGiriPhase := True;
  Repaint;
  if Assigned(FOnStateChanged) then
  begin
    FOnStateChanged(Self);
  end;

  if FSpectator or (MalbeonPos <> spBottom) then
  begin
    // AI(또는 관전) 말번 → 카드를 몇 번 훑어보는 연출 후 자동으로 결정(과정이 보이도록)
    FGiriAiHoverStep := 0;
    FGiriAiTimer.Interval := 380;
    FGiriAiTimer.Enabled := True;
  end;
  // 사람이 말번이면 여기서 더 할 일 없음 — MouseDownGiri가 클릭을 기다린다
end;

// AI(또는 관전) 말번의 기리 과정을 보여준다: 카드 몇 장을 훑어보듯 호버를 옮겨가며(소리 포함)
// 고민하는 연출을 몇 차례 반복한 뒤, 마지막에 절반 확률로 임의 위치 컷(아니면 퉁)을 확정한다
procedure TGostopBoard.GiriAiTimerTick(Sender: TObject);
const
  HOVER_PREVIEW_STEPS = 3;
begin
  if FPaused then
  begin
    Exit;
  end;

  if (not FGiriPhase) or (FGiriDeck = nil) then
  begin
    FGiriAiTimer.Enabled := False;
    Exit;
  end;

  Inc(FGiriAiHoverStep);
  if FGiriAiHoverStep <= HOVER_PREVIEW_STEPS then
  begin
    if FGiriRects.Count > 0 then
    begin
      var LNew := Random(FGiriRects.Count);
      if (LNew = FHoverGiri) and (FGiriRects.Count > 1) then
      begin
        LNew := (LNew + 1) mod FGiriRects.Count;
      end;

      FHoverGiri := LNew;
      TGostopAudio.Instance.Play('ui_hover');
      Repaint;
    end;

    Exit;   // 타이머 계속 반복 — 다음 훑어보기로
  end;

  FGiriAiTimer.Enabled := False;
  FHoverGiri := -1;

  // 컷 60% / 퉁 40%
  var LCut := -1;
  if Random(100) < 60 then
  begin
    LCut := 4 + Random(FGiriDeck.Count - 8);
  end;

  BeginGiriClose(LCut);
end;

// 컷(또는 퉁) 결정 직후: 실제로 적용하기 전에, 카드들이 그 지점으로 모여드는 짧은 연출을 먼저 보여준다
procedure TGostopBoard.BeginGiriClose(const APendingCut: Integer);
begin
  FGiriPendingCut := APendingCut;
  FGiriClosing := True;
  FGiriCloseT := 0;
  FHoverGiri := -1;

  if (APendingCut >= 0) and (APendingCut < FGiriRects.Count) then
  begin
    var LR := FGiriRects[APendingCut];
    FGiriClosePt := PointF((LR.Left + LR.Right) / 2, (LR.Top + LR.Bottom) / 2);
  end
  else
  begin
    FGiriClosePt := PointF((FBtnTung.Left + FBtnTung.Right) / 2, (FBtnTung.Top + FBtnTung.Bottom) / 2);
  end;

  TGostopAudio.Instance.Play('card_flip');
  FGiriCloseTimer.Enabled := True;
  Repaint;
end;

// 위 연출 진행 타이머. 퉁은 "모으기"까지만, 컷은 "모으기" 후 "가르기"까지 이어간 뒤
// 그때 비로소 실제 컷/퉁을 적용하고 딜로 진행한다
procedure TGostopBoard.GiriCloseTimerTick(Sender: TObject);
begin
  if FPaused then
  begin
    Exit;
  end;

  if FGiriClosing then
  begin
    FGiriCloseT := FGiriCloseT + 0.045 * FGameSpeed;   // 모으기 총 ~350ms
    if FGiriCloseT >= 1 then
    begin
      FGiriCloseT := 1;
      FGiriClosing := False;
      if FGiriPendingCut >= 0 then
      begin
        // 컷이면 모은 뒤 갈라 자리를 바꾸는 연출로 이어감
        FGiriSplitting := True;
        FGiriSplitT := 0;
        TGostopAudio.Instance.Play('card_flip');
      end
      else
      begin
        // 퉁이면 모으는 것으로 연출 종료 → 바로 적용
        FGiriCloseTimer.Enabled := False;
        ResolveGiri(FGiriPendingCut);
        Exit;
      end;
    end;
  end
  else
  if FGiriSplitting then
  begin
    FGiriSplitT := FGiriSplitT + 0.04 * FGameSpeed;   // 가르기 총 ~400ms
    if FGiriSplitT >= 1 then
    begin
      FGiriCloseTimer.Enabled := False;
      FGiriSplitting := False;
      ResolveGiri(FGiriPendingCut);
      Exit;
    end;
  end
  else
  begin
    FGiriCloseTimer.Enabled := False;
    Exit;
  end;

  Repaint;
end;

// 기리 결정 적용: ACutIndex>=0이면 그 위치에서 컷, 아니면 퉁(그대로). 이어서 딜 진행
procedure TGostopBoard.ResolveGiri(const ACutIndex: Integer);
begin
  FGiriPhase := False;
  FHoverGiri := -1;
  if (ACutIndex >= 0) and Assigned(FGiriDeck) then
  begin
    FGiriDeck.Cut(ACutIndex);
  end;

  var LProceed := FGiriProceed;
  FGiriProceed := nil;
  if Assigned(LProceed) then
  begin
    LProceed();
  end;
end;

// 기리/보너스 뽑기 다이얼로그 공통 지오메트리. 기리(딜 전 전체 덱 커팅)가 항상 최대 장수 케이스이므로
// 그 기준으로 카드 크기·부채각·패널 폭을 고정해 두고, 장수가 적은 보너스 뽑기도 그대로 재사용한다.
// 그러면 장수가 적을 때 카드가 커지거나 배치가 흔들리지 않고, 남는 공간만 좌우로 비워진 채 가운데 정렬된다.
procedure TGostopBoard.FanDialogGeometry(out APanelW, ACardW, ACardH, AStep, AHalfSpread, AArcDrop, AAvColW,
  ATopPad: Single);
begin
  var CS := CardSize;
  ACardW := CS.Width * 1.0;
  ACardH := CS.Height * 1.0;
  AAvColW := Max(130.0, 150.0);
  ATopPad := 54.0;

  var LOpt := CfgDeckOptions;
  var LRefCount := 48;
  if LOpt.IncludeBonus then
  begin
    LRefCount := LRefCount + LOpt.BonusCount;
  end;

  var LMaxPanelW := Width * 0.62;
  // 부채꼴 실폭 = Step*(N-1) + 카드폭(양끝 반폭)이므로, 간격 상한 계산 시 카드폭만큼 미리 빼 둬야
  // 실제 패널 폭이 LMaxPanelW를 넘지 않는다.
  var LFanAvailW := LMaxPanelW - AAvColW - 24 - 20 - 24 - 24 - ACardW;

  AStep := ACardW * 0.55;
  if LRefCount > 1 then
  begin
    var LMaxStep := LFanAvailW / (LRefCount - 1);
    if LMaxStep < AStep then
    begin
      AStep := LMaxStep;
    end;
  end;

  if AStep < 6 then
  begin
    AStep := 6;
  end;

  AHalfSpread := Min(14.0, 1.6 * (LRefCount - 1));
  AArcDrop := ACardH * 0.18;

  var LRefTotalW := AStep * (LRefCount - 1) + ACardW;
  APanelW := AAvColW + 24 + 20 + LRefTotalW + 48;
end;

// 기리 화면: 표준 다이얼로그 안에 사람(항상 말번) 아바타+닉네임을 좌측에, 셔플된 뒷패를 부채꼴로
// 편 카드열을 우측에 배치. 카드 한 장 클릭=그 위치 컷, 퉁=그대로
procedure TGostopBoard.DrawGiri;
begin
  if FGiriDeck = nil then
  begin
    Exit;
  end;

  var LPanelW, LCardW, LCardH, LStep, LHalfSpread, LArcDrop, LAvColW, LTopPad: Single;
  FanDialogGeometry(LPanelW, LCardW, LCardH, LStep, LHalfSpread, LArcDrop, LAvColW, LTopPad);

  var LHoverRaise := LCardH * 0.22;   // 호버 시 위로 솟는 양(보너스 뽑기 호버와 동일한 비율)
  var LBtnH := 46.0;
  var LPanelH := LTopPad + LHoverRaise + LCardH + LArcDrop + 20 + LBtnH + 20;
  var LPanel := DrawStdDialog('기리', LPanelW, LPanelH);
  var LBodyTop := LPanel.Top + LTopPad;

  // 좌측: 말번(커팅 권리자 — 사람일 수도 AI일 수도 있음) 아바타 + 아래에 닉네임
  var LMalbeon := MalbeonPos;
  var LAvSz := 130.0;
  var LAvCx := LPanel.Left + 24 + LAvColW / 2;
  var LAvBmp := NormalAvatarBitmap(FSeatAvatar[LMalbeon]);
  var LAvR := RectF(LAvCx - LAvSz / 2, LBodyTop, LAvCx + LAvSz / 2, LBodyTop + LAvSz);
  if Assigned(LAvBmp) then
  begin
    Canvas.DrawBitmap(LAvBmp, RectF(0, 0, LAvBmp.Width, LAvBmp.Height), LAvR, 1, False);
  end;

  DrawLabel(RectF(LAvCx - LAvColW / 2, LAvR.Bottom + 8, LAvCx + LAvColW / 2, LAvR.Bottom + 34),
    SeatDisplayName(LMalbeon), TAlphaColors.Gold, 18);

  // 우측: 셔플된 뒷패를 부채꼴로 펼침. 남는 카드 영역 안에서 가운데 정렬(장수가 적어도 카드 크기는 고정)
  FGiriRects.Clear;
  var LCardAreaL := LPanel.Left + 24 + LAvColW + 20;
  var LCardAreaR := LPanel.Right - 24;
  var LN := FGiriDeck.Count;
  var LTotalW := LStep * (LN - 1) + LCardW;
  var LMidX := (LCardAreaL + LCardAreaR) / 2;
  var LStartX := LMidX - LTotalW / 2 + LCardW / 2;
  var LRowY := LBodyTop + LHoverRaise + LCardH / 2;

  // 컷일 때 카드들이 좌/우로 모여드는 지점(선택한 카드 기준 그 앞쪽은 왼쪽, 뒤쪽은 오른쪽)
  // 컷 위치가 카드열 좌/우 끝 쪽으로 치우치면 고정 오프셋만으로는 카드 영역을 벗어날 수 있어
  // 패널의 카드 영역(LCardAreaL..LCardAreaR) 안으로 clamp 한다.
  var LSideOffset := Max(LCardW * 1.8, 110.0);
  var LGatherMinX := LCardAreaL + LCardW / 2;
  var LGatherMaxX := LCardAreaR - LCardW / 2;
  var LLeftPt := PointF(EnsureRange(FGiriClosePt.X - LSideOffset, LGatherMinX, LGatherMaxX), FGiriClosePt.Y);
  var LRightPt := PointF(EnsureRange(FGiriClosePt.X + LSideOffset, LGatherMinX, LGatherMaxX), FGiriClosePt.Y);
  var LIsCut := FGiriPendingCut >= 0;

  var LGatherEase: Single := 0;
  if FGiriClosing then
  begin
    LGatherEase := 1 - (1 - FGiriCloseT) * (1 - FGiriCloseT) * (1 - FGiriCloseT);
  end;

  var LMergeEase: Single := 0;
  if FGiriSplitting then
  begin
    LMergeEase := 1 - (1 - FGiriSplitT) * (1 - FGiriSplitT) * (1 - FGiriSplitT);
  end;

  for var I := 0 to LN - 1 do
  begin
    var LCX := LStartX + I * LStep;
    var LT: Single := 0;
    if LN > 1 then
    begin
      LT := (I / (LN - 1)) * 2 - 1;   // -1..1
    end;

    var LAngle := LT * LHalfSpread;
    var LCY := LRowY + Sqr(LT) * LArcDrop;

    // 클릭·호버 판정 rect는 원래(솟아오르기 전) 위치로 고정 — 판정이 흔들리지 않도록
    if (not FGiriClosing) and (not FGiriSplitting) then
    begin
      FGiriRects.Add(RectF(LCX - LCardW / 2, LCY - LCardH / 2, LCX + LCardW / 2, LCY + LCardH / 2));
    end;

    var LDrawY := LCY;
    if I = FHoverGiri then
    begin
      LDrawY := LDrawY - LHoverRaise;
    end;

    var LDrawX := LCX;
    var LDrawW := LCardW;
    var LDrawH := LCardH;
    var LDrawAngle := LAngle;

    if FGiriSplitting then
    begin
      // 2단계(컷 전용): 좌/우로 모였던 자리에서 가운데(선택 지점)로 다시 모여 합쳐짐
      var LFrom: TPointF;
      if I < FGiriPendingCut then
      begin
        LFrom := LLeftPt;
      end
      else
      begin
        LFrom := LRightPt;
      end;

      LDrawX := LFrom.X + (FGiriClosePt.X - LFrom.X) * LMergeEase;
      LDrawY := LFrom.Y + (FGiriClosePt.Y - LFrom.Y) * LMergeEase;
      LDrawW := LCardW * 0.7;
      LDrawH := LCardH * 0.7;
      LDrawAngle := 0;
    end
    else
    if FGiriClosing then
    begin
      // 1단계: 컷이면 선택한 카드를 기준으로 앞쪽 패는 왼쪽, 뒤쪽 패는 오른쪽으로 모임.
      // 퉁이면(선택 지점=퉁 버튼) 그대로 한 점으로 모임
      var LTo := FGiriClosePt;
      if LIsCut then
      begin
        if I < FGiriPendingCut then
        begin
          LTo := LLeftPt;
        end
        else
        begin
          LTo := LRightPt;
        end;
      end;

      LDrawX := LCX + (LTo.X - LCX) * LGatherEase;
      LDrawY := LDrawY + (LTo.Y - LDrawY) * LGatherEase;
      LDrawW := LCardW * (1 - 0.3 * LGatherEase);
      LDrawH := LCardH * (1 - 0.3 * LGatherEase);
      LDrawAngle := LAngle * (1 - LGatherEase);
    end;

    DrawCardRotated(LDrawX, LDrawY, LDrawW, LDrawH, LDrawAngle, '', True);
  end;

  // 퉁 버튼(연출 진행 중엔 더 이상 누를 수 없으므로 숨김)
  if (not FGiriClosing) and (not FGiriSplitting) then
  begin
    var LBtnY := LBodyTop + LHoverRaise + LCardH + LArcDrop + 20;
    FBtnTung := RectF(LMidX - 80, LBtnY, LMidX + 80, LBtnY + LBtnH);
    Canvas.FillRound(FBtnTung, 10, $FF8D6E30);
    Canvas.StrokeRound(FBtnTung, 10, $80FFFFFF, 1);
    DrawLabel(FBtnTung, '퉁~ (그대로)', TAlphaColors.White, 18);
  end;

  EndStdDialog;
end;

// 선(FNextStartPos)이 정해진 뒤 실제 딜·플레이로 진입한다.
procedure TGostopBoard.ProceedAfterSeon;
begin
  if FPlayerCount = 4 then
  begin
    StartNegotiation;
  end
  else
  begin
    // 2/3인: 셔플 후 기리(말번 커팅) → 딜 → 플레이 (보너스패 3장 포함, 정통 51장)
    var LDeck := TDeck.Create(CfgDeckOptions);
    LDeck.ShuffleSecure;
    RequestGiri(LDeck,
      procedure
      var
        LCounts: TArray<Integer>;   // 클로저(딜 완료 콜백)가 캡처하므로 var 블록 선언(인라인 캡처 금지)
      begin
        var LConfig := TDealConfig.ForPlayers(2);
        if FPlayerCount = 3 then
        begin
          LConfig := TDealConfig.Custom(3, 7, 6);
        end;

        var LTable := TDealer.Deal(FGiriDeck, LConfig);
        try
          FSeatMap := nil;   // 2/3인은 좌석맵 미사용
          var LNames: TArray<string>;
          SetLength(LNames, FPlayerCount);
          FGame := TGameState.Create(LNames);
          TGameSetup.Load(FGame, LTable);
        finally
          LTable.Free;
        end;

        FreeAndNil(FGiriDeck);

        for var I := 0 to FPlayerCount - 1 do
        begin
          FGame.Player(I).Name := SeatDisplayName(PhysicalPos(I));
        end;

        SetLength(LCounts, 4);
        for var I := 0 to FPlayerCount - 1 do
        begin
          LCounts[Ord(PhysicalPos(I))] := FGame.Player(I).Hand.Count;
        end;

        // 딜 전에 바닥이 잠시 뒤섞이는 연출을 먼저 보여준 뒤 실제 딜 애니메이션 시작
        BeginShuffleEffect(
          procedure
          begin
            BeginDealAnimation(FGame.Floor.ToArray, LCounts,
              procedure
              begin
                StartPlay;
              end);
          end);
      end);
  end;
end;

// 선 뽑기에 참여하는 물리 위치 목록(사람은 항상 아래=spBottom)
function TGostopBoard.SeonActivePositions: TArray<TSeatPos>;
begin
  case FPlayerCount of
    2:
      begin
        Result := [spTop, spBottom];
      end;
    3:
      begin
        Result := [spTop, spLeft, spBottom];
      end;
  else
    begin
      Result := [spTop, spLeft, spBottom, spRight];
    end;
  end;
end;

function TGostopBoard.SeonPosLabel(const APos: TSeatPos): string;
begin
  Result := SeatDisplayName(APos);
end;

procedure TGostopBoard.BeginSeonPick;
begin
  FreeAndNil(FSeonDeck);
  FSeonDeck := TDeck.Create;   // 표준 48장(보너스 제외 — 월 비교가 명확)
  FSeonDeck.ShuffleSecure;

  // 낮/밤 판정: 시스템 시계(06:00~17:59 = 낮 → 큰 월이 선, 그 외 = 밤 → 작은 월이 선)
  FSeonIsDay := (HourOf(Now) >= 6) and (HourOf(Now) < 18);
  FSeonWinner := -1;

  for var LP := spTop to spRight do
  begin
    FSeonHasCard[LP] := False;
    FSeonRevealed[LP] := False;
  end;

  for var LPos in SeonActivePositions do
  begin
    FSeonHasCard[LPos] := True;
  end;

  FSeonPicking := True;
  SeonDealRound;

  Repaint;
  if Assigned(FOnStateChanged) then
  begin
    FOnStateChanged(Self);
  end;
end;

procedure TGostopBoard.SeonDealRound;
begin
  // 경합자 수만큼 카드가 필요 — 부족하면 덱 재구성(동점 재경합이 많을 때 안전장치)
  var LNeed := 0;
  for var LP := spTop to spRight do
  begin
    if FSeonHasCard[LP] then
    begin
      Inc(LNeed);
    end;
  end;

  if FSeonDeck.Count < LNeed then
  begin
    FSeonDeck.Build(TDeckOptions.Standard);
    FSeonDeck.ShuffleSecure;
  end;

  for var LP := spTop to spRight do
  begin
    if FSeonHasCard[LP] then
    begin
      FSeonCard[LP] := FSeonDeck.Draw;
      FSeonRevealed[LP] := False;
    end;
  end;

  if FSeonIsDay then
  begin
    FStatus := '밤일낮장(낮) — 큰 월이 선. 내 카드를 클릭해 뒤집으세요';
  end
  else
  begin
    FStatus := '밤일낮장(밤) — 작은 월이 선. 내 카드를 클릭해 뒤집으세요';
  end;

  FSeonStep := seReveal;
  FSeonTicks := 0;
  FSeonHumanTimeoutTicks := 0;
  FSeonTimer.Enabled := True;
end;

procedure TGostopBoard.SeonRevealPos(const APos: TSeatPos);
begin
  if (not FSeonHasCard[APos]) or FSeonRevealed[APos] then
  begin
    Exit;
  end;

  FSeonRevealed[APos] := True;
  TGostopAudio.Instance.Play('card_flip');
  Repaint;
  SeonCheckRoundComplete;
end;

procedure TGostopBoard.SeonCheckRoundComplete;
begin
  if FSeonStep <> seReveal then
  begin
    Exit;
  end;

  for var LP := spTop to spRight do
  begin
    if FSeonHasCard[LP] and (not FSeonRevealed[LP]) then
    begin
      Exit;   // 아직 안 뒤집은 자리 있음
    end;
  end;

  SeonEvaluate;
end;

procedure TGostopBoard.SeonEvaluate;
begin
  // 경합자 중 낮=최대 월 / 밤=최소 월을 찾는다
  var LBest := -1;
  for var LP := spTop to spRight do
  begin
    if FSeonHasCard[LP] then
    begin
      var LM := FSeonCard[LP].Month;
      if LBest < 0 then
      begin
        LBest := LM;
      end
      else
      if FSeonIsDay and (LM > LBest) then
      begin
        LBest := LM;
      end
      else
      if (not FSeonIsDay) and (LM < LBest) then
      begin
        LBest := LM;
      end;
    end;
  end;

  var LWinners := TList<TSeatPos>.Create;
  try
    for var LP := spTop to spRight do
    begin
      if FSeonHasCard[LP] and (FSeonCard[LP].Month = LBest) then
      begin
        LWinners.Add(LP);
      end;
    end;

    if LWinners.Count = 1 then
    begin
      FSeonWinner := Ord(LWinners[0]);
      FStatus := Format('%s 선(先)!', [SeonPosLabel(LWinners[0])]);
      TGostopAudio.Instance.Play('sfx_go');
      FSeonStep := seDecide;
      FSeonTicks := 0;
    end
    else
    begin
      // 동점 → 동점자만 재경합(나머지는 이번 매치 선 후보에서 제외)
      for var LP := spTop to spRight do
      begin
        FSeonHasCard[LP] := False;
      end;

      for var LW in LWinners do
      begin
        FSeonHasCard[LW] := True;
      end;

      FStatus := '동점! 재경합합니다';
      FSeonStep := seTie;
      FSeonTicks := 0;
    end;
  finally
    LWinners.Free;
  end;

  Repaint;
  if Assigned(FOnStateChanged) then
  begin
    FOnStateChanged(Self);
  end;
end;

procedure TGostopBoard.SeonFinish;
begin
  FSeonTimer.Enabled := False;
  FSeonPicking := False;
  FreeAndNil(FSeonDeck);
  FNextStartPos := TSeatPos(FSeonWinner);
  ProceedAfterSeon;
end;

procedure TGostopBoard.SeonTimerTick(Sender: TObject);
begin
  if FPaused then
  begin
    Exit;
  end;

  if (not FSeonPicking) or (FSeonDeck = nil) then
  begin
    FSeonTimer.Enabled := False;
    Exit;
  end;

  Inc(FSeonTicks);
  case FSeonStep of
    seReveal:
      begin
        // AI 자리를 한 자리씩 자동 공개(사람=spBottom은 클릭 대기, 관전 모드면 전부 자동)
        for var LP := spTop to spRight do
        begin
          if FSeonHasCard[LP] and (not FSeonRevealed[LP]) and ((LP <> spBottom) or FSpectator) then
          begin
            SeonRevealPos(LP);
            Exit;
          end;
        end;

        // 남은 것은 사람 클릭뿐 → 5초(절대 시간, 배속 무관) 방치되면 자동 공개
        if FSeonHasCard[spBottom] and (not FSeonRevealed[spBottom]) then
        begin
          Inc(FSeonHumanTimeoutTicks);
          if FSeonHumanTimeoutTicks * Integer(FSeonTimer.Interval) >= 5000 then
          begin
            SeonRevealPos(spBottom);
          end;
        end;
      end;
    seDecide:
      begin
        if FSeonTicks >= 3 then   // ~1.8초 표시 후 진행
        begin
          SeonFinish;
        end;
      end;
    seTie:
      begin
        if FSeonTicks >= 2 then   // ~1.2초 후 재경합
        begin
          SeonDealRound;
        end;
      end;
  end;
end;

procedure TGostopBoard.DrawSeonPick;
begin
  // 자리 영역(포커테이블식) — 선 확정 자리는 강조
  for var LP := spTop to spRight do
  begin
    DrawRegion(SeatRegion(LP), FSeonWinner = Ord(LP));
  end;

  // 게임 시작 최초 화면부터 아바타·정보 패널 표시
  DrawPanels;

  // 타이틀·안내는 다른 팝업들과 같은 다이얼로그 스타일(나무 결 패널+팝인)로 — 딤은 지금까지
  // 그린 것(자리 영역·패널)에만 적용되고, 이후 그리는 자리 카드는 딤 위에 밝게 얹힌다.
  var LPanel := DrawStdDialog('', Max(Width * 0.34, 420.0), 130.0);
  DrawLabel(RectF(LPanel.Left, LPanel.Top + 14, LPanel.Right, LPanel.Top + 46), '선(先) 뽑기 · 밤일낮장', TAlphaColors.White, 24);
  var LSub := '';
  if FSeonIsDay then
  begin
    LSub := '낮 — 가장 큰 월이 선';
  end
  else
  begin
    LSub := '밤 — 가장 작은 월이 선';
  end;

  DrawLabel(RectF(LPanel.Left, LPanel.Top + 48, LPanel.Right, LPanel.Top + 74), LSub, $FFFFE08A, 15);

  // 확정 시 패널 안에 선 발표
  if FSeonWinner >= 0 then
  begin
    DrawLabel(RectF(LPanel.Left, LPanel.Top + 82, LPanel.Right, LPanel.Top + 116),
      Format('▶ %s 선(先) ◀', [SeonPosLabel(TSeatPos(FSeonWinner))]), $FFFFD54A, 20);
  end;

  EndStdDialog;

  var CS := CardSize;
  for var LPos in SeonActivePositions do
  begin
    var LR := SeatRegion(LPos);
    var LCX := (LR.Left + LR.Right) / 2;
    var LCY := (LR.Top + LR.Bottom) / 2;
    var LRect := RectF(LCX - CS.Width / 2, LCY - CS.Height / 2, LCX + CS.Width / 2, LCY + CS.Height / 2);
    FSeonRect[LPos] := LRect;

    // 선 확정 강조 테두리
    if FSeonWinner = Ord(LPos) then
    begin
      Canvas.StrokeRound(RectF(LRect.Left - 5, LRect.Top - 5, LRect.Right + 5, LRect.Bottom + 5), 7, $FFFFD54A, 4);
    end;

    if FSeonRevealed[LPos] then
    begin
      DrawCardRotated(LCX, LCY, CS.Width, CS.Height, 0, FSeonCard[LPos].AssetId, False);
    end
    else
    begin
      DrawCardRotated(LCX, LCY, CS.Width, CS.Height, 0, '', True);
    end;

    // 자리명(+ 공개 시 월)
    var LText := SeonPosLabel(LPos);
    if FSeonRevealed[LPos] then
    begin
      LText := LText + Format('  %d월', [FSeonCard[LPos].Month]);
    end;

    DrawLabel(RectF(LCX - 90, LCY + CS.Height / 2 + 4, LCX + 90, LCY + CS.Height / 2 + 28), LText, TAlphaColors.White, 15);

    // 선 라벨
    if FSeonWinner = Ord(LPos) then
    begin
      DrawLabel(RectF(LCX - 60, LCY - CS.Height / 2 - 28, LCX + 60, LCY - CS.Height / 2 - 4), '선(先)', $FFFFD54A, 19);
    end;

    // 사람 클릭 유도(관전 모드엔 없음)
    if (LPos = spBottom) and (not FSpectator) and FSeonHasCard[LPos] and (not FSeonRevealed[LPos]) and (FSeonWinner < 0) then
    begin
      DrawLabel(RectF(LCX - 90, LCY - CS.Height / 2 - 26, LCX + 90, LCY - CS.Height / 2 - 2), '클릭!', $FFFFF176, 17);
    end;
  end;
end;

// 딜 애니메이션 시작 전, 바닥에 뒷면 카드가 랜덤 배치로 깜빡이며 반복돼 "섞는" 연출을 준다.
// 실제 진행·렌더는 TShuffleAnimation(매니저)이 맡고, 여기서는 단계 플래그·상태문구·시작음만 세운다.
procedure TGostopBoard.BeginShuffleEffect(const AOnDone: TProc);
var
  LOnDone: TProc;   // 클로저가 캡처하므로 var 블록에 둔다
begin
  LOnDone := AOnDone;
  FShuffling := True;
  FStatus := '패를 섞는 중...';
  TGostopAudio.Instance.Play('card_deal');

  var LAnim := TShuffleAnimation.Create(Self);
  LAnim.OnDone :=
    procedure
    begin
      FShuffling := False;
      if Assigned(LOnDone) then
      begin
        LOnDone();   // 실제 딜 애니메이션 시작
      end;
    end;

  FAnimMgr.Add(LAnim);
  Repaint;
end;

// 뒷패 위치 — 중앙 영역 우측(라이브 보드의 뒷패 위치와 이어지는 느낌)
function TGostopBoard.DealDeckPoint: TPointF;
begin
  Result := TBoardLayout.DealDeckPoint(Width, Height);
end;

procedure TGostopBoard.BeginDealAnimation(const AFloor: TArray<THwatuCard>; const ACounts: TArray<Integer>; const AOnDone: TProc);
var
  LFlies: TList<TDealFly>;
  LTotal: array [TSeatPos] of Integer;
  LFliesArr: TArray<TDealFly>;
  LOnDone: TProc;   // 클로저가 캡처하므로 var 블록에 둔다

  // 자리 APos의 AIndex번째 손패(총 ATotal장) 착지 정보 — 아바타 카드로 빨려들어가듯 날아감
  function HandFly(const APos: TSeatPos; const AIndex, ATotal: Integer): TDealFly;
  begin
    Result := Default(TDealFly);
    Result.IsFloor := False;
    Result.Pos := APos;
    var LAvatar := SeatAvatarRect(APos);
    // 아바타 얼굴을 가리지 않도록 아바타 아래(닉네임 줄 근처)에 쌓는다.
    // 매 장마다 살짝 랜덤하게 흐트러뜨려 어지럽게 쌓이는 느낌은 유지
    var LJitterX := (Random - 0.5) * LAvatar.Width * 0.6;
    var LJitterY := (Random - 0.5) * 12.0;
    Result.Target := PointF((LAvatar.Left + LAvatar.Right) / 2 + LJitterX, LAvatar.Bottom + 16 + LJitterY);
    case APos of
      spTop:
        begin
          Result.Scale := 0.45;
          Result.Angle := 0;
        end;
      spBottom:
        begin
          Result.Scale := 0.7;
          Result.Angle := 0;
        end;
      spLeft:
        begin
          Result.Scale := 0.45;
          Result.Angle := 90;
        end;
    else
      begin
        Result.Scale := 0.45;
        Result.Angle := 270;
      end;
    end;

    Result.Angle := Result.Angle + (Random - 0.5) * 50;   // -25~+25도, 흐트러진 각도
  end;

  // 바닥 AIndex번째(총 ATotal장) 착지 정보 — 중앙에 2행 그리드
  function FloorFly(const ACard: THwatuCard; const AIndex, ATotal: Integer): TDealFly;
  begin
    Result := Default(TDealFly);
    Result.IsFloor := True;
    // 4인 맞고 정통 룰: 바닥패는 1장만 공개하고 나머지는 뒷면으로 둔다(광팔기 보장 목적).
    // 2/3인은 기존대로 전부 공개.
    Result.Reveal := (FPlayerCount <> 4) or (AIndex = 0);
    Result.Card := ACard;
    Result.Scale := 0.7;
    Result.Angle := 0;
    var CS := CardSize;
    var LCen := CenterRegion;
    var LCols := (ATotal + 1) div 2;
    var LRow := AIndex div LCols;
    var LCol := AIndex mod LCols;
    var LMidX := (LCen.Left + LCen.Right) / 2 - CS.Width * 0.8;   // 뒷패(우측)와 안 겹치게 약간 왼쪽
    var LMidY := (LCen.Top + LCen.Bottom) / 2;
    Result.Target := PointF(LMidX + (LCol - (LCols - 1) / 2) * CS.Width * 0.7 * 1.12,
      LMidY + (LRow - 0.5) * CS.Height * 0.7 * 1.12);
  end;

begin
  LOnDone := AOnDone;
  LFlies := TList<TDealFly>.Create;
  try
    for var LP := spTop to spRight do
    begin
      LTotal[LP] := 0;
      if Ord(LP) <= High(ACounts) then
      begin
        LTotal[LP] := ACounts[Ord(LP)];
      end;
    end;

    // 전통 리듬: 손패 절반(자리별 묶음) → 바닥 절반 → 손패 나머지 → 바닥 나머지
    var LFloorHalf := (Length(AFloor) + 1) div 2;
    for var LPass := 0 to 1 do
    begin
      for var LP := spTop to spRight do
      begin
        var LHalf := (LTotal[LP] + 1) div 2;
        var LFrom := 0;
        var LTo := LHalf - 1;
        if LPass = 1 then
        begin
          LFrom := LHalf;
          LTo := LTotal[LP] - 1;
        end;

        for var K := LFrom to LTo do
        begin
          LFlies.Add(HandFly(LP, K, LTotal[LP]));
        end;
      end;

      var LF0 := 0;
      var LF1 := LFloorHalf - 1;
      if LPass = 1 then
      begin
        LF0 := LFloorHalf;
        LF1 := High(AFloor);
      end;

      for var K := LF0 to LF1 do
      begin
        LFlies.Add(FloorFly(AFloor[K], K, Length(AFloor)));
      end;
    end;

    LFliesArr := LFlies.ToArray;
  finally
    LFlies.Free;
  end;

  FDealing := True;
  FStatus := '패를 나누는 중...';
  TGostopAudio.Instance.Play('card_deal');

  var LAnim := TDealAnimation.Create(Self, LFliesArr);
  LAnim.OnDone :=
    procedure
    begin
      FDealing := False;
      if Assigned(LOnDone) then
      begin
        LOnDone();   // 플레이 시작/협상 진행
      end;
    end;

  FAnimMgr.Add(LAnim);
  Repaint;
end;

// 보너스 뽑기: 펼쳐진 뒷패에서 AStockIndex 카드를 집어 현재 차례 자리로 날리는 애니 시작
procedure TGostopBoard.StartBonusPick(const AStockIndex: Integer);
begin
  if (FGame = nil) or (FGame.Phase <> gpAwaitingBonusDraw) or FPickActive then
  begin
    Exit;
  end;

  if (AStockIndex < 0) or (AStockIndex >= FGame.Stock.Count) then
  begin
    Exit;
  end;

  FHoverBonus := -1;
  FPickIndex := AStockIndex;

  // 출발점: 펼쳐진 카드 rect(직전 Paint에서 기록) — 없으면 중앙 뒷패 위치
  if AStockIndex < FBonusRects.Count then
  begin
    var LR := FBonusRects[AStockIndex];
    FPickFrom := PointF((LR.Left + LR.Right) / 2, (LR.Top + LR.Bottom) / 2);
  end
  else
  begin
    FPickFrom := DealDeckPoint;
  end;

  // 도착점: 현재 차례 자리의 카드 공간(사람이면 손패 줄)
  var LPos := PhysicalPos(FGame.Current);
  var LArea := SeatCardArea(LPos);
  if LPos = spBottom then
  begin
    FPickTo := PointF((LArea.Left + LArea.Right) / 2, LArea.Bottom - CardSize.Height / 2 - 8);
  end
  else
  begin
    FPickTo := PointF((LArea.Left + LArea.Right) / 2, (LArea.Top + LArea.Bottom) / 2);
  end;

  FPickT := 0;
  FPickActive := True;
  TGostopAudio.Instance.Play('card_flip');
  FPickTimer.Enabled := True;
  Repaint;
end;

procedure TGostopBoard.PickTick(Sender: TObject);
begin
  if FPaused then
  begin
    Exit;
  end;

  if (not FPickActive) or (FEngine = nil) then
  begin
    FPickTimer.Enabled := False;
    FPickActive := False;
    Exit;
  end;

  // 다른 카드 애니(놓기 240ms·먹기 260ms)와 비슷한 체감 속도로(기존 0.1은 160ms로 유독 빨랐음)
  FPickT := FPickT + 0.06 * FGameSpeed;
  if FPickT >= 1 then
  begin
    FPickTimer.Enabled := False;
    FPickActive := False;
    FEngine.ResolveBonusDraw(FPickIndex);
    TGostopAudio.Instance.Play('card_capture');
    AfterAction;   // 보너스를 집었으면 대기 유지 → 사람은 재선택, AI는 타이머로 재선택
    Exit;
  end;

  Repaint;
end;

// 보너스 뽑기 오버레이: 남은 뒷패를 펼쳐 보여주고(클릭 선택), 집은 카드는 자리로 비행
// 보너스 뽑기 오버레이: 표준 다이얼로그 안에 현재 차례 플레이어 아바타+닉네임을 좌측에,
// 남은 뒷패를 부채꼴로 편 카드열을 우측에 배치(기리와 동일 레이아웃·카드 크기). 집은 카드는 자리로 비행
procedure TGostopBoard.DrawBonusDraw;
begin
  FBonusRects.Clear;
  var LCount := FGame.Stock.Count;
  if LCount = 0 then
  begin
    Exit;
  end;

  var LPanelW, LCardW, LCardH, LStep, LHalfSpread, LArcDrop, LAvColW, LTopPad: Single;
  FanDialogGeometry(LPanelW, LCardW, LCardH, LStep, LHalfSpread, LArcDrop, LAvColW, LTopPad);

  var LHoverRaise := LCardH * 0.22;   // 호버 시 위로 솟는 양(손패 호버와 동일한 비율)
  var LPanelH := LTopPad + LHoverRaise + LCardH + LArcDrop + 24;
  var LPanel := DrawStdDialog('패선택', LPanelW, LPanelH);
  var LBodyTop := LPanel.Top + LTopPad;

  // 좌측: 현재 차례 플레이어 아바타 + 아래에 닉네임
  var LAvSz := 130.0;
  var LAvCx := LPanel.Left + 24 + LAvColW / 2;
  var LCurPos := PhysicalPos(FGame.Current);
  var LAvBmp := NormalAvatarBitmap(FSeatAvatar[LCurPos]);
  var LAvR := RectF(LAvCx - LAvSz / 2, LBodyTop, LAvCx + LAvSz / 2, LBodyTop + LAvSz);
  if Assigned(LAvBmp) then
  begin
    Canvas.DrawBitmap(LAvBmp, RectF(0, 0, LAvBmp.Width, LAvBmp.Height), LAvR, 1, False);
  end;

  DrawLabel(RectF(LAvCx - LAvColW / 2, LAvR.Bottom + 8, LAvCx + LAvColW / 2, LAvR.Bottom + 34),
    SeatDisplayName(LCurPos), TAlphaColors.Gold, 18);

  // 우측: 남은 뒷패를 부채꼴로 펼침. 남는 카드 영역 안에서 가운데 정렬(장수가 적어도 카드 크기는 고정).
  // 비행 중인 카드 자리는 비워 둔다
  var LCardAreaL := LPanel.Left + 24 + LAvColW + 20;
  var LCardAreaR := LPanel.Right - 24;
  var LTotalW := LStep * (LCount - 1) + LCardW;
  var LMidX := (LCardAreaL + LCardAreaR) / 2;
  var LStartX := LMidX - LTotalW / 2 + LCardW / 2;
  var LRowY := LBodyTop + LHoverRaise + LCardH / 2;

  for var I := 0 to LCount - 1 do
  begin
    var LCX := LStartX + I * LStep;
    var LT: Single := 0;
    if LCount > 1 then
    begin
      LT := (I / (LCount - 1)) * 2 - 1;   // -1..1
    end;

    var LAngle := LT * LHalfSpread;
    var LCY := LRowY + Sqr(LT) * LArcDrop;

    // 클릭·호버 판정 rect는 원래(솟아오르기 전) 위치로 고정 — 손패 호버와 동일하게, 판정이 흔들리지 않도록
    FBonusRects.Add(RectF(LCX - LCardW / 2, LCY - LCardH / 2, LCX + LCardW / 2, LCY + LCardH / 2));
    if FPickActive and (I = FPickIndex) then
    begin
      Continue;
    end;

    var LDrawY := LCY;
    if I = FHoverBonus then
    begin
      LDrawY := LDrawY - LHoverRaise;
    end;

    DrawCardRotated(LCX, LDrawY, LCardW, LCardH, LAngle, '', True);
  end;

  // 집은 카드 비행(ease-out)
  if FPickActive then
  begin
    var LE := 1 - Sqr(1 - FPickT);
    var LX := FPickFrom.X + (FPickTo.X - FPickFrom.X) * LE;
    var LY := FPickFrom.Y + (FPickTo.Y - FPickFrom.Y) * LE;
    DrawBack(RectF(LX - LCardW / 2, LY - LCardH / 2, LX + LCardW / 2, LY + LCardH / 2));
  end;

  EndStdDialog;
end;

procedure TGostopBoard.StartNegotiation;
begin
  // 4인: 셔플 후 기리(말번 커팅) → 딜 → 협상
  var LDeck := TDeck.Create(CfgDeckOptions);
  LDeck.ShuffleSecure;
  RequestGiri(LDeck,
    procedure
    begin
      FTable4 := TDealer.Deal(FGiriDeck, TDealConfig.Custom(4, 7, 6));
      FreeAndNil(FGiriDeck);
      StartNegotiationDeal;
    end);
end;

// 딜 완료 후 협상 애니·진행(기리 콜백에서 호출)
procedure TGostopBoard.StartNegotiationDeal;
begin
  // 딜 애니메이션(4자리 각 7장 + 바닥) 후 협상 진행
  // 딜 전에 바닥이 잠시 뒤섞이는 연출을 먼저 보여준 뒤 실제 딜 애니메이션 시작
  BeginShuffleEffect(
    procedure
    begin
      BeginDealAnimation(FTable4.Floor.ToArray, [7, 7, 7, 7],
        procedure
        begin
          TGostopAudio.Instance.Play('sfx_negotiate');

          // 선 기준 사람의 논리 좌석(아래 자리 = 물리 spBottom)
          FHumanLogical := (Ord(spBottom) - Ord(FNextStartPos) + 4) mod 4;

          // 엔진(TFourPlayer.Resolve)은 P2 우선 규칙이다 — P2가 포기하면 P3·P4는 자동 참가한다.
          // 따라서 P2 → P3 순서로 하나씩 결정한다.

          // ── P2 결정 ──
          var LP2Give := False;
          if IsHumanSeat(1) then
          begin
            if not FGaveUpLast[spBottom] then
            begin
              BeginNegotiationPrompt;   // 사람이 직접 참가·포기 선택
              Exit;
            end;

            // 연사: 직전 판에 포기했으면 이번엔 포기 불가 → 강제 참가
            QueueEffect('연사! — 연속 포기 불가, 참가합니다');
          end
          else
          begin
            LP2Give := AiGiveUp(1);
          end;

          if LP2Give then
          begin
            // P2 포기 → P3·P4 자동 참가(사람이 P3면 선택 없이 참가가 확정된다)
            if IsHumanSeat(2) then
            begin
              QueueEffect('앞자리가 포기! — 자동으로 참가합니다');
            end;

            ResolveNegotiation(True, False, False);
            Exit;
          end;

          // ── P3 결정(P2가 참가한 경우에만) ──
          var LP3Give := False;
          if IsHumanSeat(2) then
          begin
            if not FGaveUpLast[spBottom] then
            begin
              BeginNegotiationPrompt;
              Exit;
            end;

            QueueEffect('연사! — 연속 포기 불가, 참가합니다');
          end
          else
          begin
            LP3Give := AiGiveUp(2);
          end;

          if LP3Give then
          begin
            ResolveNegotiation(False, True, False);
            Exit;
          end;

          // ── 둘 다 참가 → 말번(P4)이 빠진다 ──
          // 말번은 광팔기를 안 할 이유가 없으므로 광값이 있으면 자동 판매(다이얼로그 없음)
          var LP4Sell := TFourPlayer.GwangCount(FTable4.Hand(3), CfgScore) > 0;
          ResolveNegotiation(False, False, LP4Sell);
        end);
    end);
end;

// 사람이 참가·포기를 고르는 다이얼로그로 진입한다(4인 협상, 사람이 P2 또는 P3일 때만).
procedure TGostopBoard.BeginNegotiationPrompt;
begin
  FNegIsSell := False;
  FNegotiating := True;

  Repaint;
  if Assigned(FOnStateChanged) then
  begin
    FOnStateChanged(Self);
  end;
end;

// 논리 좌석(0=선, 1=P2, 2=P3, 3=P4) → 물리 좌석. 선 기준 반시계로 배정된다.
function TGostopBoard.SeatPosOfLogical(const ALogical: Integer): TSeatPos;
begin
  Result := TSeatPos((Ord(FNextStartPos) + ALogical) mod 4);
end;

// 해당 논리 좌석이 사람 자리인지(관전 모드면 전원 AI이므로 항상 False).
function TGostopBoard.IsHumanSeat(const ALogical: Integer): Boolean;
begin
  Result := (not FSpectator) and (FHumanLogical = ALogical);
end;

const
  // 이 손패 점수(TDealer.HandQuality) 미만이면 AI가 포기한다.
  // 공개된 바닥 1장 기준 4인 딜 20만 회 실측 — 자리당 8.4% · 판당 16.2%가 포기(docs/balance.md 참조).
  AI_GIVE_UP_QUALITY = 7.0;
  // 게임 레벨이 낮을수록 판단이 흐려지는 폭(Lv0에서 ±이 값, Lv100에서 오차 없음).
  // 점수 분포의 사분위 범위가 2.9(p25 8.40 ~ p75 11.30)라, 이보다 큰 노이즈를 주면
  // 낮은 레벨의 판단이 사실상 무작위가 된다. 흔들리되 지배당하지 않는 선으로 잡는다.
  AI_GIVE_UP_NOISE = 3.0;

// 4인 협상에서 AI(P2/P3)가 포기할지 결정한다. 손패 점수가 기준 미만이면 포기하되,
// 게임 레벨이 낮으면 판단에 오차가 섞여 가끔 오판한다.
function TGostopBoard.AiGiveUp(const ALogicalSeat: Integer): Boolean;
begin
  if FTable4 = nil then
  begin
    Exit(False);
  end;

  // 연사: 직전 판에 포기한 자리는 이번 판엔 포기할 수 없다(강제 참가)
  var LPos := SeatPosOfLogical(ALogicalSeat);
  if FGaveUpLast[LPos] then
  begin
    Exit(False);
  end;

  // 협상 시점에 공개된 바닥은 맨 앞 1장뿐이다 — 나머지 5장은 엎어 둔다(DrawNegotiation과 동일).
  // 바닥 매칭이 HandQuality에서 가중치가 가장 큰 항목이라, 애초에 그 계산을 막으려고 5장을 감추는
  // 것이다. 전체 바닥을 넘기면 사람이 못 보는 패로 판단하는 치팅이 된다.
  var LOpenFloor := TList<THwatuCard>.Create;
  try
    if FTable4.Floor.Count > 0 then
    begin
      LOpenFloor.Add(FTable4.Floor[0]);
    end;

    var LQuality := TDealer.HandQuality(FTable4.Hand(ALogicalSeat), LOpenFloor);
    var LNoise := (100 - EnsureRange(FSeatSkill[LPos], 0, 100)) / 100 * AI_GIVE_UP_NOISE;
    LQuality := LQuality + (Random * 2 - 1) * LNoise;

    Result := LQuality < AI_GIVE_UP_QUALITY;
  finally
    LOpenFloor.Free;
  end;
end;

procedure TGostopBoard.ResolveNegotiation(const AP2Give, AP3Give, AP4Sell: Boolean);
begin
  FNegotiating := False;
  FNegAnimTimer.Enabled := False;   // 광 패 흔들림 정지

  // 연사: 이번 판에 포기한 자리를 기록한다(다음 판 강제참가 판정). 사람·AI 구분 없이 전 좌석.
  // 선(0)과 말번(3)은 포기 개념이 없으므로 항상 False로 덮여 연사 상태가 풀린다.
  for var L := 0 to 3 do
  begin
    FGaveUpLast[SeatPosOfLogical(L)] := ((L = 1) and AP2Give) or ((L = 2) and AP3Give);
  end;

  var LRound := TFourPlayer.Resolve(FTable4, AP2Give, AP3Give, AP4Sell, GWANG_UNIT_PRICE, CfgScore);
  FSeatMap := LRound.PlaySeats;
  FSitOutSeat := LRound.SitOutSeat;
  FGwang := LRound.Gwang;

  // 광값 선불(선 제외, P2·P3 → P4). 즉시 FMoney에 반영해 판매 직후 바로 보이게 한다
  // (판돈 배수는 미적용 — 광값은 게임 정산과 별개). 논리 좌석 → 물리 위치 매핑.
  if FGwang.Sold then
  begin
    TGostopAudio.Instance.Play('sfx_gwang_sell');
    var LSellerPos := TSeatPos((Ord(FNextStartPos) + FGwang.SellerSeat) mod 4);
    for var LP := 0 to High(FGwang.PayerSeats) do
    begin
      var LPayerPos := TSeatPos((Ord(FNextStartPos) + FGwang.PayerSeats[LP]) mod 4);
      var LAmount := FGwang.ValuePerPayer * FConfig.MoneyPerPoint;
      FMoney[LPayerPos] := FMoney[LPayerPos] - LAmount;
      FMoney[LSellerPos] := FMoney[LSellerPos] + LAmount;
    end;
  end;

  // 치는 3인 이름(물리 좌석 기준)
  var LNames: TArray<string>;
  SetLength(LNames, Length(LRound.PlaySeats));
  for var I := 0 to High(LRound.PlaySeats) do
  begin
    LNames[I] := SeatLabel(LRound.PlaySeats[I]);
  end;

  FGame := TFourPlayer.BuildGame(FTable4, LRound, LNames);

  // 광을 판 경우: 판매자 손패에서 광 패를 캡처해 발표 오버레이로 보여준다
  FGwangCards := nil;
  if FGwang.Sold and (FTable4 <> nil) then
  begin
    // 광+조커 + 실제 보유한 족보(고도리·초단 등) 카드까지 발표에 표시
    FGwangCards := TFourPlayer.SaleCards(FTable4.Hand(FGwang.SellerSeat), CfgScore);
  end;

  // 빠지는 자리의 손패 장수(뒷패 합류 연출용) — FTable4를 놓기 전에 세어 둔다
  var LFoldCount := 0;
  if FTable4 <> nil then
  begin
    LFoldCount := FTable4.Hand(LRound.SitOutSeat).Count;
  end;

  FreeAndNil(FTable4);

  FFoldPendingCount := LFoldCount;
  FFoldPendingPos := SeatPosOfLogical(LRound.SitOutSeat);

  if FGwang.Sold then
  begin
    FGwangShow := True;
    FGwangTimer.Enabled := True;   // 발표 후 자동으로 손패 합류 연출 → StartPlay
    FNegAnimPhase := 0;
    FNegAnimTimer.Enabled := True;   // 발표 광 패 좌우 흔들림
    Repaint;
  end
  else
  begin
    FoldSitOutThenPlay;
  end;
end;

// 빠지는 자리의 손패를 뒷패로 합치는 연출을 보여준 뒤 플레이를 시작한다.
procedure TGostopBoard.FoldSitOutThenPlay;
begin
  BeginSitOutFold(FFoldPendingPos, FFoldPendingCount, FGwang.Sold,
    procedure
    begin
      StartPlay;
    end);
end;

procedure TGostopBoard.GwangTimerTick(Sender: TObject);
begin
  if FPaused then
  begin
    Exit;
  end;

  FinishGwangSale;
end;

// 광팔기 다이얼로그·판매 발표의 패 좌우 흔들림(주기적 Repaint로 위상 진행)
procedure TGostopBoard.NegAnimTick(Sender: TObject);
begin
  if FPaused then
  begin
    Exit;
  end;

  if not ((FNegotiating and FNegIsSell) or FGwangShow) then
  begin
    FNegAnimTimer.Enabled := False;
    Exit;
  end;

  FNegAnimPhase := FNegAnimPhase + 0.35;
  Repaint;
end;

procedure TGostopBoard.FinishGwangSale;
begin
  FGwangTimer.Enabled := False;
  FNegAnimTimer.Enabled := False;   // 발표 흔들림 정지
  if not FGwangShow then
  begin
    Exit;
  end;

  FGwangShow := False;
  FoldSitOutThenPlay;   // 판 광 패 발표가 끝났으니 그 자리 손패를 뒷패로 합치는 연출
end;

const
  FOLD_DURATION_MS = 750.0;   // 손패가 뒷패로 합쳐지는 데 걸리는 시간
  FOLD_STAGGER = 0.65;        // 카드 간 출발 시차(0=동시, 1=완전 순차)

// 4인에서 빠지는 자리(광을 팔았거나 죽은 자리)의 손패가 뒷패로 합쳐지는 연출을 시작한다.
// 카드 실물은 이미 BuildGame이 뒷패로 옮긴 뒤이므로, 이건 그 사실을 눈으로 보여주는 연출이다.
procedure TGostopBoard.BeginSitOutFold(const APos: TSeatPos; const ACount: Integer;
  const ASold: Boolean; const AOnDone: TProc);
begin
  if ACount <= 0 then
  begin
    if Assigned(AOnDone) then
    begin
      AOnDone();
    end;

    Exit;
  end;

  FFoldPos := APos;
  FFoldSold := ASold;
  FFoldOnDone := AOnDone;
  SetLength(FFoldFrom, ACount);
  SetLength(FFoldAngle, ACount);

  // 출발점은 딜 애니메이션이 손패를 쌓아둔 곳(아바타 아래)과 같은 자리 — 화면에서 이어져 보이게 한다
  var LAvatar := SeatAvatarRect(APos);
  var LBaseAngle: Single := 0;
  case APos of
    spLeft:
      begin
        LBaseAngle := 90;
      end;
    spRight:
      begin
        LBaseAngle := 270;
      end;
  end;

  for var I := 0 to ACount - 1 do
  begin
    FFoldFrom[I] := PointF((LAvatar.Left + LAvatar.Right) / 2 + (Random - 0.5) * LAvatar.Width * 0.6,
      LAvatar.Bottom + 16 + (Random - 0.5) * 12.0);
    FFoldAngle[I] := LBaseAngle + (Random - 0.5) * 50;
  end;

  FFoldT := 0;
  FFoldTimer.Enabled := False;
  FFoldTimer.Enabled := True;
  Repaint;
end;

procedure TGostopBoard.FoldTimerTick(Sender: TObject);
begin
  if FPaused then
  begin
    Exit;
  end;

  FFoldT := FFoldT + (FFoldTimer.Interval / FOLD_DURATION_MS) * FGameSpeed;
  if FFoldT >= 1 then
  begin
    FFoldT := 1;
    FFoldTimer.Enabled := False;

    var LDone := FFoldOnDone;
    FFoldOnDone := nil;
    if Assigned(LDone) then
    begin
      LDone();
    end;

    Exit;   // 콜백이 다음 단계로 넘어갔으므로 여기서 Repaint하지 않는다
  end;

  Repaint;
end;

procedure TGostopBoard.DrawSitOutFold;
begin
  // 자리 프레임 + 중앙(바닥·뒷패) + 패널까지 그려 판이 유지된 채로 손패만 빨려들어가게 한다.
  // 이 시점엔 아직 엔진이 없지만(StartPlay 전) DrawPlayerPanel이 FEngine nil을 방어한다.
  for var LP := spTop to spRight do
  begin
    DrawRegion(SeatRegion(LP), False);
  end;

  DrawCenter(CenterRegion);
  DrawPanels;

  var CS := CardSize;
  var LC := CenterRegion;
  var LTo := PointF(LC.Right - 40, (LC.Top + LC.Bottom) / 2);   // 뒷패 위치(StartTurnAnimation과 동일 기준)

  for var I := 0 to High(FFoldFrom) do
  begin
    // 카드마다 시차를 두고 출발해 한 장씩 빨려들어가는 느낌
    var LSpan := 1 + FOLD_STAGGER;
    var LStart := (I / Max(Length(FFoldFrom), 1)) * FOLD_STAGGER;
    var LP := EnsureRange((FFoldT * LSpan - LStart), 0, 1);
    if LP <= 0 then
    begin
      LP := 0;
    end;

    // 감속(ease-out) — 뒷패에 닿을 때 부드럽게 멎는다
    var LE := 1 - Sqr(1 - LP);

    var LX := FFoldFrom[I].X + (LTo.X - FFoldFrom[I].X) * LE;
    var LY := FFoldFrom[I].Y + (LTo.Y - FFoldFrom[I].Y) * LE;
    var LScale := 0.45 + (1.0 - 0.45) * LE;     // 쌓여 있던 작은 크기 → 뒷패 크기
    var LAngle := FFoldAngle[I] * (1 - LE);     // 흐트러진 각도 → 반듯하게

    DrawCardRotated(LX, LY, CS.Width * LScale, CS.Height * LScale, LAngle, '', True);
  end;

  // 무슨 일이 일어나는지 한 줄로 알려준다
  var LLabel := SeatLabel(Ord(FFoldPos));
  var LText := Format('%s 포기 — 손패가 뒷패로', [LLabel]);
  if FFoldSold then
  begin
    LText := Format('%s 광 팔고 빠짐 — 손패가 뒷패로', [LLabel]);
  end;

  DrawLabel(RectF(0, LC.Top - 46, Width, LC.Top - 10), LText, $FFFFE082, 18);
end;

// 광 판매 발표 오버레이: 판 광 패 + "지불자들 → 판매자: 광값" 이동 표시(닉네임 사용)
procedure TGostopBoard.DrawGwangSale;
begin
  var LSeller := SeatLabel(FGwang.SellerSeat);

  // 표준 다이얼로그(딤 + 중앙 패널 + 제목) — 닉네임은 아바타 아래에 표시하므로 제목엔 되풀이하지 않음
  var LPanel := DrawStdDialog('광 팔기!', Max(Width * 0.5, 460.0), 260.0);
  var LBodyCy := (LPanel.Top + LPanel.Bottom) / 2 + 10;   // 제목 영역만큼 살짝 아래로

  // 좌측: 판매자 아바타(크게) + 아래에 닉네임
  var LAvSz := 130.0;
  var LAvColW := Max(LAvSz, 150.0);
  var LAvCx := LPanel.Left + 24 + LAvColW / 2;
  var LSellerPos := TSeatPos((Ord(FNextStartPos) + FGwang.SellerSeat) mod 4);
  var LAvBmp := ResultAvatarBitmap(FSeatAvatar[LSellerPos], True, False);
  var LAvR := RectF(LAvCx - LAvSz / 2, LBodyCy - LAvSz / 2 - 12, LAvCx + LAvSz / 2, LBodyCy + LAvSz / 2 - 12);
  if Assigned(LAvBmp) then
  begin
    Canvas.DrawBitmap(LAvBmp, RectF(0, 0, LAvBmp.Width, LAvBmp.Height), LAvR, 1, False);
  end;

  DrawLabel(RectF(LAvCx - LAvColW / 2, LAvR.Bottom + 8, LAvCx + LAvColW / 2, LAvR.Bottom + 34), LSeller, TAlphaColors.Gold, 18);

  // 우측: 판 광 패(가로 나열, 아바타 열을 뺀 나머지 공간에 가운데 정렬)
  var CS := CardSize;
  var LCW := CS.Width * 0.8;
  var LCH := CS.Height * 0.8;
  var LN := Length(FGwangCards);
  if LN > 0 then
  begin
    var LCardAreaL := LPanel.Left + 24 + LAvColW + 20;
    var LCardAreaR := LPanel.Right - 24;
    var LTotW := LCW + (LN - 1) * LCW * 1.12;
    var LStartX := (LCardAreaL + LCardAreaR) / 2 - LTotW / 2;
    for var I := 0 to LN - 1 do
    begin
      var LCX := LStartX + I * LCW * 1.12;
      // 좌우로 흔드는 효과(카드마다 위상 어긋남)
      var LPh := FNegAnimPhase + I * 0.9;
      var LDX := Sin(LPh) * LCW * 0.16;
      var LAng := Sin(LPh) * 3.0;
      DrawCardRotated(LCX + LCW / 2 + LDX, LBodyCy, LCW, LCH, LAng, FGwangCards[I].AssetId, False);
    end;
  end;

  EndStdDialog;
end;

procedure TGostopBoard.StartPlay;
begin
  SetupAgentsAndEngine(True);
end;

// 에이전트(사람/AI)·엔진 구성 — 새 딜(AFreshDeal=True)과 저장 게임 재개(False) 공용.
// 재개 시에는 FGame이 이미 완전히 채워진 상태로 들어오므로 선 지정·바닥 보너스 처리·딜 효과음은 건너뛴다.
procedure TGostopBoard.SetupAgentsAndEngine(const AFreshDeal: Boolean);
begin
  // 사람의 게임 인덱스(아래 자리) 찾기 — 관전 모드는 사람 없음(-1, 전원 AI)
  FHumanIndex := -1;
  if not FSpectator then
  begin
    for var I := 0 to FGame.PlayerCount - 1 do
    begin
      if PhysicalPos(I) = spBottom then
      begin
        FHumanIndex := I;
        Break;
      end;
    end;
  end;

  // 에이전트 구성(사람 자리는 nil, 나머지는 AI)
  SetLength(FAgents, FGame.PlayerCount);
  for var I := 0 to FGame.PlayerCount - 1 do
  begin
    if I = FHumanIndex then
    begin
      FAgents[I] := nil;
    end
    else
    begin
      var LAi := TAiPlayer.Create(FSeatSkill[PhysicalPos(I)], UInt64(987654321 + I * 1013904223));
      // 캐릭터 성향 주입: 배짱·욕심(스탯 5~40 → 20~90)
      LAi.GoBias := TGostopCharacters.NerveBias(FSeatAvatar[PhysicalPos(I)]);
      LAi.Greed := TGostopCharacters.GreedBias(FSeatAvatar[PhysicalPos(I)]);
      FAiObjects.Add(LAi);
      FAgents[I] := LAi;
    end;
  end;

  if AFreshDeal then
  begin
    // 선(먼저 두는 자리): 지정 위치에 해당하는 게임 인덱스부터 시작
    for var I := 0 to FGame.PlayerCount - 1 do
    begin
      if PhysicalPos(I) = FNextStartPos then
      begin
        FGame.Current := I;
        Break;
      end;
    end;

    FAutoPlay := False;   // 자동 진행은 이번 판 한정 — 새 판마다 꺼진 채로 시작(사람 자리는 위에서 이미 nil)
  end;

  // 피박 기준(피값): 2인 맞고 7 이하, 3인 이상 5 이하
  var LRules := CfgRules;
  if FGame.PlayerCount >= 3 then
  begin
    LRules.Score.PibakMaxJunk := 5;
  end
  else
  begin
    LRules.Score.PibakMaxJunk := 7;
  end;

  FEngine := TTurnEngine.Create(FGame, LRules);
  FEngine.BonusDrawEnabled := True;   // 보너스패를 내면 뒷패를 펼쳐 가져올 패를 고른다(사람·AI 모두 연출)

  // 이번 판 운 주입(게임 인덱스 순): 뒤집기 때 운이 높으면 유리한 카드가 나올 확률↑
  var LLuck: TArray<Integer>;
  SetLength(LLuck, FGame.PlayerCount);
  for var I := 0 to FGame.PlayerCount - 1 do
  begin
    LLuck[I] := FSeatLuckRoll[PhysicalPos(I)];
  end;

  FEngine.PlayerLuck := LLuck;
  FEngine.OnEvent := procedure(AEvt: TPlayEvent)
    begin
      FTurnEvents.Add(AEvt);
    end;

  if AFreshDeal then
  begin
    FEngine.ApplyFloorBonus;   // 바닥에 깔린 보너스패는 선이 획득하고 뒷패에서 보충
    if not FEngine.ApplyFloorChongtong then   // 바닥에 처음부터 같은 월 4장이면 선 즉시 승리
    begin
      FEngine.ApplyHandChongtong;
      FEngine.ApplyFloorBbeok;   // 바닥에 처음부터 같은 월 3장이면 뻑 더미로 등록
    end;
    FAwaitingGoStop := False;
    TGostopAudio.Instance.Play('card_deal');
  end
  else
  begin
    FAwaitingGoStop := FGame.Phase = gpAwaitingGoStop;
  end;

  AfterAction;
end;

// 지금 상태를 안전하게 저장해도 되는지: 엔진 내부에 직렬화되지 않는 임시 상태(뒤집기 선택 대기 등)가
// 없고, 딜·기리·협상·쇼당 대기 등 화면 연출이 끼어 있지 않은 "안정 상태"인지 확인한다.
function TGostopBoard.CanSaveGame: Boolean;
begin
  Result := Assigned(FGame) and Assigned(FEngine)
    and (FGame.Phase in [gpPlaying, gpAwaitingGoStop, gpAwaitingBonusDraw])
    and (not FGiriPhase) and (not FSeonPicking) and (not FDealing) and (not FShuffling)
    and (not FNegotiating) and (not FGwangShow) and (not FAvatarPicking)
    and (not FShodangPending) and (not FChoosing) and (not FFlipChoosing);
end;

// 현재 매치+게임 상태를 파일로 저장한다(AfterAction에서 안전할 때마다 자동 호출).
procedure TGostopBoard.SaveCurrentGame;
begin
  var LData: TSaveData;
  LData.PlayerCount := FPlayerCount;
  LData.Spectator := FSpectator;
  LData.NextStartPos := Ord(FNextStartPos);
  LData.Stakes := FStakes;
  LData.SitOutSeat := FSitOutSeat;
  LData.SeatMap := Copy(FSeatMap);

  SetLength(LData.RowPos, 4);
  for var S := 0 to 3 do
  begin
    LData.RowPos[S] := Ord(FRowPos[S]);
  end;

  for var S := 0 to 3 do
  begin
    var LPos := TSeatPos(S);
    LData.Seats[S].Avatar := FSeatAvatar[LPos];
    LData.Seats[S].Skill := FSeatSkill[LPos];
    LData.Seats[S].Money := FMoney[LPos];
    LData.Seats[S].Wins := FWins[LPos];
    LData.Seats[S].Losses := FLosses[LPos];
    LData.Seats[S].GaveUpLast := FGaveUpLast[LPos];
  end;

  LData.Current := FGame.Current;
  LData.Phase := Ord(FGame.Phase);
  LData.Winner := FGame.Winner;
  LData.PlayCount := FGame.PlayCount;
  LData.ThreeBbeok := FGame.ThreeBbeok;

  LData.BbeokCreator := nil;
  for var LPair in FGame.BbeokCreator do
  begin
    var LEntry: TSaveBbeok;
    LEntry.Month := LPair.Key;
    LEntry.Creator := LPair.Value;
    LData.BbeokCreator := LData.BbeokCreator + [LEntry];
  end;

  SetLength(LData.Players, FGame.PlayerCount);
  for var I := 0 to FGame.PlayerCount - 1 do
  begin
    var LP := FGame.Player(I);
    LData.Players[I].NameStr := LP.Name;
    LData.Players[I].GoCount := LP.GoCount;
    LData.Players[I].LastGoScore := LP.LastGoScore;
    LData.Players[I].ShakeCount := LP.ShakeCount;
    LData.Players[I].CardDebt := LP.CardDebt;
    LData.Players[I].PendingShakeMonth := LP.PendingShakeMonth;
    LData.Players[I].BbeokCount := LP.BbeokCount;
    LData.Players[I].ReverseGo := LP.ReverseGo;

    SetLength(LData.Players[I].Hand, LP.Hand.Count);
    for var J := 0 to LP.Hand.Count - 1 do
    begin
      LData.Players[I].Hand[J] := CardToSave(LP.Hand[J]);
    end;

    SetLength(LData.Players[I].Captured, LP.Captured.Count);
    for var J := 0 to LP.Captured.Count - 1 do
    begin
      LData.Players[I].Captured[J] := CardToSave(LP.Captured[J]);
    end;
  end;

  SetLength(LData.Floor, FGame.Floor.Count);
  for var J := 0 to FGame.Floor.Count - 1 do
  begin
    LData.Floor[J] := CardToSave(FGame.Floor[J]);
  end;

  SetLength(LData.Stock, FGame.Stock.Count);
  for var J := 0 to FGame.Stock.Count - 1 do
  begin
    LData.Stock[J] := CardToSave(FGame.Stock[J]);
  end;

  LData.ShodangActive := FShodangActive;
  LData.ShodangCaller := FShodangCaller;
  LData.ShodangAccepter := FShodangAccepter;
  LData.ShodangDecliner := FShodangDecliner;

  TGostopSaveGame.Save(LData);
end;

// 판이 끝난 뒤 '매치 정보만' 저장한다(진행 중인 게임 없음).
// 이게 있어야 앱을 껐다 켜도 머니·전적을 유지한 채 '이어하기'로 다음 판을 시작할 수 있다.
// 사람이 오링됐거나 관전 모드면 이어갈 매치가 아니므로 저장하지 않는다.
procedure TGostopBoard.SaveMatchSnapshot;
begin
  if FSpectator or (FMoney[spBottom] <= 0) then
  begin
    TGostopSaveGame.Delete;
    Exit;
  end;

  var LData: TSaveData;
  LData := Default(TSaveData);
  LData.MatchOnly := True;
  LData.PlayerCount := FPlayerCount;
  LData.Spectator := FSpectator;
  LData.NextStartPos := Ord(FNextStartPos);
  LData.Stakes := FStakes;
  LData.SitOutSeat := -1;   // 다음 판 협상에서 새로 정해진다
  LData.SeatMap := nil;

  SetLength(LData.RowPos, 4);
  for var S := 0 to 3 do
  begin
    LData.RowPos[S] := Ord(FRowPos[S]);
  end;

  for var S := 0 to 3 do
  begin
    var LPos := TSeatPos(S);
    LData.Seats[S].Avatar := FSeatAvatar[LPos];
    LData.Seats[S].Skill := FSeatSkill[LPos];
    LData.Seats[S].Money := FMoney[LPos];
    LData.Seats[S].Wins := FWins[LPos];
    LData.Seats[S].Losses := FLosses[LPos];
    LData.Seats[S].GaveUpLast := FGaveUpLast[LPos];
  end;

  TGostopSaveGame.Save(LData);
end;

// 저장 파일을 읽어 매치·게임 상태를 통째로 복원하고 플레이를 재개한다. 실패 시 False(상태 변경 없음).
function TGostopBoard.LoadSavedGame: Boolean;
begin
  var LData: TSaveData;
  Result := TGostopSaveGame.TryLoad(LData);
  if not Result then
  begin
    Exit;
  end;

  ClearGame;

  FPlayerCount := LData.PlayerCount;
  FSpectator := LData.Spectator;
  FNextStartPos := TSeatPos(EnsureRange(LData.NextStartPos, 0, 3));
  FStakes := Max(1, LData.Stakes);
  FSitOutSeat := LData.SitOutSeat;
  FSeatMap := Copy(LData.SeatMap);

  for var S := 0 to Min(3, High(LData.RowPos)) do
  begin
    FRowPos[S] := TSeatPos(EnsureRange(LData.RowPos[S], 0, 3));
  end;

  // 새게임/설정 화면을 거치지 않고 타이틀에서 곧바로 이어하기로 들어오면 FAvatarPool이
  // 아직 비어 있어(nil) 캐릭터 이미지 대신 절차 생성 폴백 얼굴이 그려진다 — 미리 로드해 둔다.
  LoadAvatarPool;

  for var S := 0 to 3 do
  begin
    var LPos := TSeatPos(S);
    FSeatAvatar[LPos] := LData.Seats[S].Avatar;
    FSeatSkill[LPos] := LData.Seats[S].Skill;
    FMoney[LPos] := LData.Seats[S].Money;
    FWins[LPos] := LData.Seats[S].Wins;
    FLosses[LPos] := LData.Seats[S].Losses;
    FGaveUpLast[LPos] := LData.Seats[S].GaveUpLast;
  end;

  // 매치 정보만 있는 스냅샷(직전 판이 끝난 상태) — 복원할 게임이 없으므로 곧바로 다음 판을 시작한다.
  // 선은 저장된 FNextStartPos(직전 승자)를 그대로 쓴다.
  if LData.MatchOnly then
  begin
    // AI 난이도는 사람이 아닌 자리에서 읽는다(사람 자리는 AI 레벨과 무관)
    FAiSkill := FSeatSkill[spTop];
    if FAiSkill <= 0 then
    begin
      FAiSkill := FConfig.AiSkill;
    end;

    BeginSeatReplacement(FNextStartPos);   // 오링된 AI 자리는 새 캐릭터로 교체 후 다음 판
    Exit(True);
  end;

  var LNames: TArray<string>;
  SetLength(LNames, Length(LData.Players));
  for var I := 0 to High(LData.Players) do
  begin
    LNames[I] := LData.Players[I].NameStr;
  end;

  FGame := TGameState.Create(LNames);
  FGame.Current := LData.Current;
  FGame.Phase := TGamePhase(EnsureRange(LData.Phase, 0, Ord(gpFinished)));
  FGame.Winner := LData.Winner;
  FGame.PlayCount := LData.PlayCount;
  FGame.ThreeBbeok := LData.ThreeBbeok;

  for var LB in LData.BbeokCreator do
  begin
    FGame.BbeokCreator.AddOrSetValue(LB.Month, LB.Creator);
  end;

  for var I := 0 to High(LData.Players) do
  begin
    var LP := FGame.Player(I);
    LP.GoCount := LData.Players[I].GoCount;
    LP.LastGoScore := LData.Players[I].LastGoScore;
    LP.ShakeCount := LData.Players[I].ShakeCount;
    LP.CardDebt := LData.Players[I].CardDebt;
    LP.PendingShakeMonth := LData.Players[I].PendingShakeMonth;
    LP.BbeokCount := LData.Players[I].BbeokCount;
    LP.ReverseGo := LData.Players[I].ReverseGo;

    for var LC in LData.Players[I].Hand do
    begin
      LP.Hand.Add(CardFromSave(LC));
    end;

    for var LC in LData.Players[I].Captured do
    begin
      LP.Captured.Add(CardFromSave(LC));
    end;
  end;

  for var LC in LData.Floor do
  begin
    FGame.Floor.Add(CardFromSave(LC));
  end;

  for var LC in LData.Stock do
  begin
    FGame.Stock.Add(CardFromSave(LC));
  end;

  FShodangActive := LData.ShodangActive;
  FShodangCaller := LData.ShodangCaller;
  FShodangAccepter := LData.ShodangAccepter;
  FShodangDecliner := LData.ShodangDecliner;

  SetupAgentsAndEngine(False);
  Result := True;
end;

// 저장 파일(중단된 대국)이 없어도 '이어하기'를 쓸 수 있는가: 직전에 끝낸 매치 설정이 아직
// 메모리에 남아 있고(FSeatAvatar[spBottom]로 판정 — 한 번도 대전 설정을 거치지 않았으면 -1),
// 지금 게임이 진행 중이 아니며, 사람이 오링되지 않은 경우. 이 경우 새 대전 설정 없이
// 직전과 같은 게임모드(인원수·AI 난이도 등)로, 머니·전적을 유지한 채 바로 다음 판을 시작한다.
function TGostopBoard.CanResumeMatch: Boolean;
begin
  Result := (FGame = nil) and (not FSpectator) and (FSeatAvatar[spBottom] >= 0) and (FMoney[spBottom] > 0);
end;

// 정산 계산은 Gostop.Board.Settlement.TGostopSettlement.Build(순수 함수)에 위임하고,
// 여기서는 매치 상태를 입력으로 모아 전달한 뒤 결과를 그대로 필드에 반영만 한다.
procedure TGostopBoard.BuildFinalSummary;
begin
  var LInput: TSettlementInput;
  LInput.PlayerCount := FPlayerCount;
  LInput.MoneyPerPoint := FConfig.MoneyPerPoint;
  LInput.Stakes := FStakes;
  LInput.NextStartPos := Ord(FNextStartPos);
  LInput.SeatMap := FSeatMap;
  LInput.SitOutSeat := FSitOutSeat;
  LInput.Spectator := FSpectator;
  LInput.ShodangActive := FShodangActive;
  LInput.ShodangCaller := FShodangCaller;
  LInput.ShodangAccepter := FShodangAccepter;
  LInput.ShodangDecliner := FShodangDecliner;

  SetLength(LInput.SeatAvatar, 4);
  SetLength(LInput.MoneyBefore, 4);
  for var S := 0 to 3 do
  begin
    LInput.SeatAvatar[S] := FSeatAvatar[TSeatPos(S)];
    LInput.MoneyBefore[S] := FMoney[TSeatPos(S)];
  end;

  LInput.ActiveOpponentSeats := nil;
  for var LPos in ActivePhysicalSeats do
  begin
    if LPos <> spBottom then
    begin
      LInput.ActiveOpponentSeats := LInput.ActiveOpponentSeats + [Ord(LPos)];
    end;
  end;

  SetLength(LInput.GameToPhysical, FGame.PlayerCount);
  for var I := 0 to FGame.PlayerCount - 1 do
  begin
    LInput.GameToPhysical[I] := Ord(PhysicalPos(I));
  end;

  var LOut := TGostopSettlement.Build(FGame, FEngine, LInput);

  for var S := 0 to 3 do
  begin
    FMoney[TSeatPos(S)] := LOut.MoneyAfter[S];
  end;

  if LOut.NewlyBrokeCount > 0 then
  begin
    FConfig.KillCount := FConfig.KillCount + LOut.NewlyBrokeCount;
    SaveSettings;
  end;

  if LOut.WinnerSeat >= 0 then
  begin
    Inc(FWins[TSeatPos(LOut.WinnerSeat)]);
    for var LSeat in LOut.ParticipantSeats do
    begin
      if LSeat <> LOut.WinnerSeat then
      begin
        Inc(FLosses[TSeatPos(LSeat)]);
      end;
    end;
  end;

  FResultRows := LOut.ResultRows;
  FResultTitle := LOut.ResultTitle;
  FStatus := LOut.StatusText;
  FStakes := LOut.NewStakes;
end;

// 화면에 아직 진행 중인 연출이 있는가(정산창은 이게 다 끝난 뒤에 띄운다).
// 말풍선은 아바타 옆에 뜨고 정산창을 가리지 않으므로 여기서 세지 않는다.
function TGostopBoard.PresentationBusy: Boolean;
begin
  Result := (FEffectText <> '') or FEffectGap or (Length(FEffectQueue) > 0) or
    (Assigned(FEffectTimer) and FEffectTimer.Enabled) or (FShakeAnim <> nil) or FGukjinMoveActive or (FNagariAnim <> nil);
end;

// 판이 끝났을 때의 정산창 진입. 연출이 남아 있으면 미루고, 그 연출이 끝나는 시점
// (EffectTimerTick·GukjinMoveTick·흔들기/나가리 애니의 OnDone)에 다시 불려 그때 진입한다.
procedure TGostopBoard.MaybeBeginGameOver;
begin
  if (not FGameOverPending) or (FGame = nil) then
  begin
    Exit;
  end;

  if PresentationBusy then
  begin
    Exit;
  end;

  // 다른 연출이 모두 끝난 뒤에 국진 → 쌍피 이동을 보여준다. 여기서 시작해야 '국진 → 쌍피' 배너가
  // 카드 이동과 같이 나온다(AfterAction 에서 시작하면 직전 턴 배너가 남아 있는 동안 카드만 먼저 움직인다).
  // 이동이 시작되면 PresentationBusy 가 다시 참이 되므로, 끝날 때 GukjinMoveTick 이 여길 다시 부른다.
  if not FGukjinMoveDone then
  begin
    FGukjinMoveDone := True;
    BeginGukjinMove;
    if FGukjinMoveActive then
    begin
      Exit;
    end;
  end;

  // 나가리(무승부)면 정산창 직전에 먹은 패 던지기 + '나가리' 도장 연출을 먼저 보여준다. 연출이
  // 시작되면 PresentationBusy 가 참이 되어 정산창이 미뤄지고, 끝날 때 OnDone 이 여길 다시 부른다.
  if (FGame.Winner < 0) and (not FNagariAnimDone) then
  begin
    FNagariAnimDone := True;
    BeginNagariAnim;
    Exit;
  end;

  FGameOverPending := False;
  BuildFinalSummary;   // 여기서 이번 판 정산이 FMoney에 반영된다

  // 정산이 끝난 매치 상태를 남겨 둔다. 앱을 껐다 켜도 오링만 아니면 '이어하기'로 다음 판을 이어간다.
  SaveMatchSnapshot;

  // 정산창 머니 카운트 애니메이션 준비: 1초 대기 후 시작(승자 차오름/패자 깎임이 동시에 시작·종료).
  // 방치 시 자동진행 카운트다운·버튼 활성화는 이 애니메이션이 끝나야 MoneyCountTick에서 시작한다.
  FMoneyCountDelay := 1.0;
  FMoneyCountT := 0;
  FMoneyTickAcc := MONEY_TICK_INTERVAL;   // 첫 동전 소리는 카운트 시작과 동시에
  FGameOverReady := False;
  FMoneyCountTimer.Enabled := True;

  if FGame.Winner < 0 then
  begin
    // 나가리는 도장 쾅 순간(BeginNagariAnim → NagariTimerTick)에 이미 'draw' 소리를 냈으므로 생략
  end
  else
  if FGame.Winner = FHumanIndex then
  begin
    TGostopAudio.Instance.Play('win');
  end
  else
  begin
    TGostopAudio.Instance.Play('lose');
  end;

  Repaint;
end;

procedure TGostopBoard.AfterAction;
begin
  if FGame = nil then
  begin
    FStatus := '새 게임을 시작하세요';
  end
  else
  if FGame.Phase = gpFinished then
  begin
    FAiTimer.Enabled := False;
    // 자동 진행은 이번 판 한정 — 이 판이 사람 턴 중 자동으로 마무리됐더라도 여기서 반드시 꺼야
    // 게임종료 팝업의 버튼 클릭이 위쪽 자동진행 클릭 무시 가드에 막히지 않는다
    FAutoPlay := False;
    // 게임이 끝난 채로 앱이 닫혀도 다음 실행이 끝난 판을 이어서 하기로 열지 않도록 즉시 정리
    TGostopSaveGame.Delete;

    // 정산창은 마지막 턴의 연출(특수 상황 배너·판 흔들림)이 다 끝난 뒤에 띄운다.
    // 바로 띄우면 아직 큐에 남은 배너가 정산창 위에 겹쳐 보인다.
    FGameOverPending := True;

    // 국진 → 쌍피 이동은 MaybeBeginGameOver 안에서(다른 연출이 다 끝난 뒤) 시작한다
    MaybeBeginGameOver;
  end
  else
  if (FGame.Current = FHumanIndex) and FAutoPlay then
  begin
    // 자동 진행: 내 턴이어도 AI 에이전트가 대신 결정하도록 AI 타이머를 그대로 돌린다
    FStatus := '자동 진행 중...';
    FAiTimer.Enabled := True;
  end
  else
  if FGame.Current = FHumanIndex then
  begin
    FAiTimer.Enabled := False;
    if FAwaitingGoStop then
    begin
      FStatus := Format('%d점! 고냐, 스톱이냐!', [FEngine.ScoreOf(FHumanIndex).Total]);
    end
    else
    if FGame.Phase = gpAwaitingBonusDraw then
    begin
      FStatus := '보너스! 뒷패에서 가져올 패를 클릭하세요';
    end
    else
    if (FGame.Player(FHumanIndex).Hand.Count = 0) and FEngine.CanFlipOnly then
    begin
      // 폭탄으로 진 카드빚 때문에 손패가 남보다 먼저 떨어진 경우: 낼 손패가 없으니
      // 뒷패만 뒤집어 자동으로 턴을 진행한다(AI의 뒤집기만 처리와 동일한 규칙)
      FStatus := '카드빚 — 뒷패를 뒤집습니다...';
      FTurnEvents.Clear;
      var LBefore := FGame.Clone;
      FAwaitingGoStop := FEngine.FlipOnly;
      StartTurnAnimation(LBefore,
        procedure
        begin
          AutoStopIfLastCard;
          AfterAction;
        end);
      Exit;
    end
    else
    begin
      FStatus := '내 차례 — 낼 패를 클릭하세요';
    end;
  end
  else
  begin
    FStatus := Format('%s 차례...', [FGame.CurrentPlayer.Name]);
    FAiTimer.Enabled := True;
  end;

  MaybeShowSpeech;

  if CanSaveGame then
  begin
    SaveCurrentGame;
  end;

  Repaint;
  if Assigned(FOnStateChanged) then
  begin
    FOnStateChanged(Self);
  end;

  if (FGame <> nil) and (FGame.Phase = gpFinished) and Assigned(FOnGameOver) then
  begin
    FOnGameOver(Self);
  end;
end;

procedure TGostopBoard.AiTimerTick(Sender: TObject);
begin
  if FPaused then
  begin
    Exit;
  end;

  if (FGame = nil) or (FGame.Phase = gpFinished)
    or ((FGame.Current = FHumanIndex) and not FAutoPlay) then
  begin
    FAiTimer.Enabled := False;
    Exit;
  end;

  // AI가 보너스패를 내고 뒷패 뽑기 대기 중이면, 펼쳐진 뒷패에서 한 장을 집는 연출로 진행
  if FGame.Phase = gpAwaitingBonusDraw then
  begin
    FAiTimer.Enabled := False;
    StartBonusPick(Random(FGame.Stock.Count));
    Exit;
  end;

  // AI 쇼당: 이 AI가 쇼당 상황이면 걸기 시도(3인). 대기/해결 후 흐름은 ResolveShodang이 잇는다
  if (not FShodangActive) and (not FShodangPending) and (FPlayerCount = 3)
    and (FGame.Phase = gpPlaying) and TShodang.Detect(FGame, FGame.Current).Callable then
  begin
    FAiTimer.Enabled := False;
    AiCallShodang(FGame.Current);
    Exit;
  end;

  AiExecuteTurn;
end;

// AI가 실제 턴을 수행(카드 내기 또는 고/스톱 결정 + 애니). 쇼당 계속 흐름에서도 재사용
procedure TGostopBoard.AiExecuteTurn;
begin
  if (FGame = nil) or (not (FGame.Phase in [gpPlaying, gpAwaitingGoStop])) then
  begin
    Exit;
  end;

  FTurnEvents.Clear;
  FEngine.FlipChoiceEnabled := False;   // AI는 자동(값 높은 패)
  var LBefore := FGame.Clone;
  if Assigned(FAgents[FGame.Current]) then
  begin
    FAgents[FGame.Current].Act(FEngine);
  end;

  StartTurnAnimation(LBefore,
    procedure
    begin
      AfterAction;
    end);
end;

procedure TGostopBoard.HumanGo;
begin
  if Assigned(FDisplay) or FDealing or FShuffling then
  begin
    Exit;
  end;

  if FAwaitingGoStop and (FGame <> nil) then
  begin
    TGostopAudio.Instance.Play('sfx_go');
    FEngine.DeclareGo;
    FAwaitingGoStop := False;
    AfterAction;
  end;
end;

procedure TGostopBoard.HumanStop;
begin
  if Assigned(FDisplay) or FDealing or FShuffling then
  begin
    Exit;
  end;

  if FAwaitingGoStop and (FGame <> nil) then
  begin
    TGostopAudio.Instance.Play('sfx_stop');
    FEngine.DeclareStop;
    FAwaitingGoStop := False;
    AfterAction;
  end;
end;

function TGostopBoard.CardSize: TSizeF;
begin
  Result := TBoardLayout.CardSize(Height);
end;

function TGostopBoard.CanCaptureCard(const ACard: THwatuCard): Boolean;
begin
  if FGame = nil then
  begin
    Exit(False);
  end;

  if ACard.Kind = hkBonus then
  begin
    Exit(FGame.Floor.Count > 0);
  end;

  for var LFloorCard in FGame.Floor do
  begin
    if LFloorCard.Month = ACard.Month then
    begin
      Exit(True);
    end;
  end;

  Result := False;
end;

procedure TGostopBoard.DrawLabel(const R: TRectF; const AText: string; const AColor: TAlphaColor;
  const ASize: Single; const ABold: Boolean);
begin
  Canvas.DrawLabel(R, AText, AColor, ASize, ABold);   // Gostop.Canvas.Helper 로 공용화(위임)
end;

procedure TGostopBoard.DrawFront(const R: TRectF; const AAssetId: string);
begin
  try
    var LBmp := FImages.ScaledFront(AAssetId, Round(R.Width * Canvas.Scale), Round(R.Height * Canvas.Scale));
    Canvas.DrawBitmap(LBmp, RectF(0, 0, LBmp.Width, LBmp.Height), R, 1, False);
  except
    Canvas.FillRound(R, 3, TAlphaColors.White);
    DrawLabel(R, AAssetId, TAlphaColors.Black, 8);
  end;
end;

procedure TGostopBoard.DrawBack(const R: TRectF);
begin
  try
    var LBmp := FImages.ScaledBack(FBackColor, Round(R.Width * Canvas.Scale), Round(R.Height * Canvas.Scale));
    Canvas.DrawBitmap(LBmp, RectF(0, 0, LBmp.Width, LBmp.Height), R, 1, False);
  except
    Canvas.FillRound(R, 3, TAlphaColors.Darkred);
  end;
end;

// 획득 패를 광→열끗→띠→피 순으로 정렬한 인덱스 시퀀스(연속 부채용)
function TGostopBoard.CapturedSequence(const APile: TList<THwatuCard>; const AGukjinAsPi: Boolean): TArray<Integer>;
begin
  Result := nil;
  for var G := 0 to 3 do
  begin
    var LGi := TList<Integer>.Create;
    try
      for var I := 0 to APile.Count - 1 do
      begin
        if CapturedGroup(APile[I], AGukjinAsPi) = G then
        begin
          LGi.Add(I);
        end;
      end;

      SortIndexList(APile, LGi);
      for var K := 0 to LGi.Count - 1 do
      begin
        Result := Result + [LGi[K]];
      end;
    finally
      LGi.Free;
    end;
  end;
end;

// 배지에 더할 수. 피는 장수가 아니라 피 값(쌍피=2, 3피=3)을 더해야 실제 점수 기준(피 10 = 1점)과 맞는다.
// 광·열끗·띠는 한 장이 곧 한 개다.
function CapturedBadgeValue(const ACard: THwatuCard; const AGukjinAsPi: Boolean): Integer;
begin
  if CapturedGroup(ACard, AGukjinAsPi) = 3 then
  begin
    // 쌍피로 해석된 국진은 JunkValue 가 0이므로 쌍피 값 2로 센다
    if ACard.IsGukjin then
    begin
      Exit(2);
    end;

    Result := Max(ACard.JunkValue, 1);
  end
  else
  begin
    Result := 1;
  end;
end;

// 획득 더미 그룹별 장수 배지 크기. 동그라미라 가로·세로가 같다.
// 카드와 함께 커지고 작아져야 한다 — 고정 px 로 두면 작은 창에서 배지가 상대적으로 커져
// 먹은패를 자리 밖으로 밀어낸다.
function TGostopBoard.CapturedBadgeSize: TSizeF;
begin
  var LD := EnsureRange(CardSize.Height * 0.18, 15.0, 30.0);
  Result := TSizeF.Create(LD, LD);
end;

// 획득 더미의 그룹(광/열끗/띠/피) 옆에 붙는 장수 배지.
// 회색 반투명으로 흐릿하게 깔아 카드를 가리지 않게 하고, 숫자만 또렷하게 얹는다.
procedure TGostopBoard.DrawCapturedCount(const ACenterX, ACenterY: Single; const ACount: Integer);
begin
  TOverlayRender.CapturedCount(Canvas, ACenterX, ACenterY, ACount, CapturedBadgeSize);
end;

// 획득 패를 하나의 촘촘한 가로 부채로 그린다(광→열끗→띠→피 정렬, 마지막 장이 온전히 보임).
// [AX..ARight] 폭 안에 들어가도록 겹침 간격 자동 축소(최대 획득 수치에서도 넘치지 않음)
// 그룹마다 위쪽에 장수 배지를 얹는다
// 자리별 획득 부채의 배치 파라미터. 그리기(DrawHumanHand·DrawOpponent)와 좌표 질의(GukjinSlotRect)가
// 반드시 같은 값을 쓰도록 여기 한 곳에서만 계산한다 — 양쪽에서 따로 계산하면 언젠가 어긋난다.
// 가로형: A=왼쪽 X, B=오른쪽 X, C=위쪽 Y / 세로형: A=열 중심 X, B=위 Y, C=아래 Y
function TGostopBoard.CapturedFanSpec(const APos: TSeatPos; const AIsHuman: Boolean): TCapturedFanSpec;
begin
  Result := Default(TCapturedFanSpec);

  var CS := CardSize;
  var LRegion := SeatRegion(APos);
  var LPanel := PlayerPanelRect(APos);

  if AIsHuman then
  begin
    // 사람(하단): 패널 오른쪽부터, 손패 위에 얹는다. 상대보다 조금 크게 그린다.
    Result.Scale := 0.72;
    Result.A := LPanel.Right + 14;
    Result.B := LRegion.Right - 6;

    var LHandTop := LRegion.Bottom - CS.Height - 8;
    Result.C := LHandTop - 12 - CS.Height * Result.Scale;
    if Result.C < LRegion.Top + 6 then
    begin
      Result.C := LRegion.Top + 6;
    end;

    Exit;
  end;

  Result.Scale := 0.66;
  case APos of
    spTop, spBottom:
      begin
        var LBackH := CS.Height * 0.5;
        if APos = spTop then
        begin
          Result.A := LRegion.Left + 6;
          Result.B := LPanel.Left - 14;
          Result.AnchorEnd := True;

          // 손패 아래. 먹은패 위에 장수 배지가 얹히므로 그만큼 간격을 더 벌린다
          var LHandY := LRegion.Top + 8;
          Result.C := LHandY + LBackH + 12 + CapturedBadgeSize.Height;
        end
        else
        begin
          Result.A := LPanel.Right + 14;
          Result.B := LRegion.Right - 6;

          var LHandY := LRegion.Bottom - LBackH - 8;
          Result.C := LHandY - 10 - CS.Height * Result.Scale;
        end;
      end;
  else
    begin
      Result.Vertical := True;

      var LColW := LRegion.Right - LRegion.Left;
      if APos = spLeft then
      begin
        Result.Angle := 90;
        Result.A := LRegion.Left + LColW * 0.70;
        Result.B := LPanel.Bottom + 14;
        Result.C := LRegion.Bottom - 6;
        Result.BadgeDir := 1;
      end
      else
      begin
        // P4(오른): 패널이 아래 → 아래 앵커 + 그룹 순서 반전(광이 맨 아래), 배지는 왼쪽
        Result.Angle := 270;
        Result.A := LRegion.Left + LColW * 0.30;
        Result.B := LRegion.Top + 6;
        Result.C := LPanel.Top - 14;
        Result.AnchorEnd := True;
        Result.Reverse := True;
        Result.BadgeDir := -1;
      end;
    end;
  end;
end;

// 가로 부채의 배치만 계산한다(그리기 없음). 국진 이동 연출이 이동 전/후 좌표를 알아야 해서
// 계산과 그리기를 분리했다. Result[K] = ASeq[K] 카드의 왼쪽 X.
function TGostopBoard.CapturedFanLayout(const APile: TList<THwatuCard>; const AX, ARight, AScale: Single;
  const AAnchorRight, AGukjinAsPi: Boolean; out ASeq: TArray<Integer>): TArray<Single>;
begin
  ASeq := CapturedSequence(APile, AGukjinAsPi);
  Result := nil;

  var LN := Length(ASeq);
  if LN = 0 then
  begin
    Exit;
  end;

  var LW := CardSize.Width * AScale;

  // 그룹(광/열끗/띠/피) 경계 수 — 그룹 사이에 간격을 줘 묶여 보이게
  var LBounds := 0;
  for var K := 1 to LN - 1 do
  begin
    if CapturedGroup(APile[ASeq[K]], AGukjinAsPi) <> CapturedGroup(APile[ASeq[K - 1]], AGukjinAsPi) then
    begin
      Inc(LBounds);
    end;
  end;

  // 그룹 사이 간격은 카드폭보다 커야 실제 빈 공간이 생긴다(스텝+간격 > 카드폭)
  var LGap := LW * 1.15;     // 그룹 사이 간격
  var LStep := LW * 0.3;     // 그룹 내 겹침
  var LAvail := ARight - AX;
  if LN > 1 then
  begin
    // 폭 초과 시 간격→겹침 순으로 축소(간격은 최소 0.8×카드폭 유지해 구분 보존)
    if LW + (LN - 1) * LStep + LBounds * LGap > LAvail then
    begin
      var LForSteps := LAvail - LW - LBounds * LGap;
      if LForSteps < (LN - 1) * 2 then
      begin
        LGap := LW * 0.8;
        LForSteps := LAvail - LW - LBounds * LGap;
      end;

      LStep := LForSteps / (LN - 1);
      if LStep < 2 then
      begin
        LStep := 2;
      end;
    end;
  end;

  // 오른쪽 앵커면 패널 쪽(오른쪽)에 붙도록 실제 폭만큼 시작점 이동
  var LX := AX;
  if AAnchorRight then
  begin
    LX := ARight - (LW + (LN - 1) * LStep + LBounds * LGap);
    if LX < AX then
    begin
      LX := AX;
    end;
  end;

  SetLength(Result, LN);
  for var K := 0 to LN - 1 do
  begin
    if (K > 0) and (CapturedGroup(APile[ASeq[K]], AGukjinAsPi) <> CapturedGroup(APile[ASeq[K - 1]], AGukjinAsPi)) then
    begin
      LX := LX + LGap;
    end;

    Result[K] := LX;
    LX := LX + LStep;
  end;
end;

procedure TGostopBoard.DrawCapturedFan(const APile: TList<THwatuCard>; const AX, ARight, AY, AScale: Single;
  const AAnchorRight: Boolean; const AGukjinAsPi: Boolean; const ASkipPileIndex: Integer);
begin
  if APile.Count = 0 then
  begin
    Exit;
  end;

  var LSeq: TArray<Integer>;
  var LXs := CapturedFanLayout(APile, AX, ARight, AScale, AAnchorRight, AGukjinAsPi, LSeq);
  var LN := Length(LSeq);
  var LW := CardSize.Width * AScale;
  var LH := CardSize.Height * AScale;

  // 그룹별 좌우 끝과 장수를 모아 두었다가, 카드를 다 그린 뒤 배지를 얹는다
  var LGCount: TArray<Integer>;
  var LGLeft: TArray<Single>;
  var LGRight: TArray<Single>;
  SetLength(LGCount, 4);
  SetLength(LGLeft, 4);
  SetLength(LGRight, 4);

  for var K := 0 to LN - 1 do
  begin
    var LX := LXs[K];
    var LG := CapturedGroup(APile[LSeq[K]], AGukjinAsPi);
    if LGCount[LG] = 0 then
    begin
      LGLeft[LG] := LX;
    end;

    Inc(LGCount[LG], CapturedBadgeValue(APile[LSeq[K]], AGukjinAsPi));
    LGRight[LG] := LX + LW;

    // 이동 연출 중인 카드는 더미에서 빼고 날아가는 쪽에서 그린다(자리는 이미 비워져 있다)
    if LSeq[K] <> ASkipPileIndex then
    begin
      DrawFront(RectF(LX, AY, LX + LW, AY + LH), APile[LSeq[K]].AssetId);
    end;
  end;

  for var G := 0 to 3 do
  begin
    if LGCount[G] > 0 then
    begin
      DrawCapturedCount((LGLeft[G] + LGRight[G]) / 2, AY - CapturedBadgeSize.Height / 2 - 2, LGCount[G]);
    end;
  end;
end;

// 세로 방향 촘촘 부채(좌/우 자리용, 90/270 회전). [ATopY..ABottomY] 안에 들어가게 자동 축소
// AReverse=True면 그룹 순서를 뒤집어(피→띠→열끗→광) 그려, AAnchorBottom과 함께 쓰면 광이 맨 아래에 온다
// ABadgeDir: 장수 배지를 카드 열의 어느 쪽에 붙일지(+1=오른쪽, -1=왼쪽). 손패 열 반대쪽으로 준다
// 세로 부채의 배치만 계산한다(그리기 없음). Result[K] = ASeq[K] 카드의 중심 Y.
function TGostopBoard.CapturedFanLayoutV(const APile: TList<THwatuCard>; const ATopY, ABottomY, AScale: Single;
  const AAnchorBottom, AReverse, AGukjinAsPi: Boolean; out ASeq: TArray<Integer>): TArray<Single>;
begin
  ASeq := CapturedSequence(APile, AGukjinAsPi);
  Result := nil;

  if AReverse then
  begin
    for var Lo := 0 to (Length(ASeq) div 2) - 1 do
    begin
      var LHi := High(ASeq) - Lo;
      var LTmp := ASeq[Lo];
      ASeq[Lo] := ASeq[LHi];
      ASeq[LHi] := LTmp;
    end;
  end;

  var LN := Length(ASeq);
  if LN = 0 then
  begin
    Exit;
  end;

  // 회전 시 세로로 쌓이는 시각 높이는 카드 폭(LW)
  var LW := CardSize.Width * AScale;

  // 그룹(광/열끗/띠/피) 경계 수 — 그룹 사이 간격으로 묶여 보이게
  var LBounds := 0;
  for var K := 1 to LN - 1 do
  begin
    if CapturedGroup(APile[ASeq[K]], AGukjinAsPi) <> CapturedGroup(APile[ASeq[K - 1]], AGukjinAsPi) then
    begin
      Inc(LBounds);
    end;
  end;

  var LGap := LW * 1.15;   // 그룹 사이 간격
  var LStep := LW * 0.3;
  var LAvail := ABottomY - ATopY;
  if LN > 1 then
  begin
    if LW + (LN - 1) * LStep + LBounds * LGap > LAvail then
    begin
      var LForSteps := LAvail - LW - LBounds * LGap;
      if LForSteps < (LN - 1) * 2 then
      begin
        LGap := LW * 0.8;
        LForSteps := LAvail - LW - LBounds * LGap;
      end;

      LStep := LForSteps / (LN - 1);
      if LStep < 2 then
      begin
        LStep := 2;
      end;
    end;
  end;

  // 아래 앵커면 패널 쪽(아래)에 붙도록 실제 높이만큼 시작점 이동
  var LY := ATopY + LW / 2;
  if AAnchorBottom then
  begin
    LY := ABottomY - (LW + (LN - 1) * LStep + LBounds * LGap) + LW / 2;
    if LY < ATopY + LW / 2 then
    begin
      LY := ATopY + LW / 2;
    end;
  end;

  SetLength(Result, LN);
  for var K := 0 to LN - 1 do
  begin
    if (K > 0) and (CapturedGroup(APile[ASeq[K]], AGukjinAsPi) <> CapturedGroup(APile[ASeq[K - 1]], AGukjinAsPi)) then
    begin
      LY := LY + LGap;
    end;

    Result[K] := LY;
    LY := LY + LStep;
  end;
end;

procedure TGostopBoard.DrawCapturedFanV(const APile: TList<THwatuCard>; const ACX, ATopY, ABottomY, AScale, AAngle: Single;
  const AAnchorBottom: Boolean; const AReverse: Boolean; const ABadgeDir: Integer;
  const AGukjinAsPi: Boolean; const ASkipPileIndex: Integer);
begin
  if APile.Count = 0 then
  begin
    Exit;
  end;

  var LSeq: TArray<Integer>;
  var LYs := CapturedFanLayoutV(APile, ATopY, ABottomY, AScale, AAnchorBottom, AReverse, AGukjinAsPi, LSeq);
  var LN := Length(LSeq);
  var LW := CardSize.Width * AScale;
  var LH := CardSize.Height * AScale;

  // 그리기는 아래에서 위로(역순). 순서대로 그리면 나중에 그린 아래쪽 패가 위쪽 패를 덮어,
  // 위쪽 패가 아래로 들어간 것처럼 보인다.
  for var K := LN - 1 downto 0 do
  begin
    // 이동 연출 중인 카드는 더미에서 빼고 날아가는 쪽에서 그린다
    if LSeq[K] <> ASkipPileIndex then
    begin
      DrawCardRotated(ACX, LYs[K], LW, LH, AAngle, APile[LSeq[K]].AssetId, False);
    end;
  end;

  // 그룹별 장수 배지 — 카드 열 옆(손패 반대쪽)에 그룹 중앙 높이로 붙인다.
  // 배지는 회전시키지 않는다(어느 자리든 똑바로 읽혀야 하므로).
  var LGCount: TArray<Integer>;
  var LGTop: TArray<Single>;
  var LGBottom: TArray<Single>;
  SetLength(LGCount, 4);
  SetLength(LGTop, 4);
  SetLength(LGBottom, 4);

  for var K := 0 to LN - 1 do
  begin
    var LG := CapturedGroup(APile[LSeq[K]], AGukjinAsPi);
    if LGCount[LG] = 0 then
    begin
      LGTop[LG] := LYs[K];
    end;

    Inc(LGCount[LG], CapturedBadgeValue(APile[LSeq[K]], AGukjinAsPi));
    LGBottom[LG] := LYs[K];
  end;

  var LBadgeX := ACX + ABadgeDir * (LH / 2 + CapturedBadgeSize.Width / 2 + 2);
  for var G := 0 to 3 do
  begin
    if LGCount[G] > 0 then
    begin
      DrawCapturedCount(LBadgeX, (LGTop[G] + LGBottom[G]) / 2, LGCount[G]);
    end;
  end;
end;

{$REGION '국진 → 쌍피 이동 연출'}
const
  // 이동에 걸리는 시간(ms). 카드 한 장이 무리를 옮겨가는 게 눈에 들어올 만큼은 길어야 한다.
  GUKJIN_MOVE_MS = 620.0;

// 국진 카드가 놓일 화면 위치. AGukjinAsPi 에 따라 열끗 자리 / 피 자리가 나온다.
function TGostopBoard.GukjinSlotRect(const AGameIndex, APileIndex: Integer; const AGukjinAsPi: Boolean): TRectF;
begin
  Result := TRectF.Empty;

  var LPos := PhysicalPos(AGameIndex);
  var LSpec := CapturedFanSpec(LPos, (LPos = spBottom) and (AGameIndex = FHumanIndex));
  var LPile := RState.Player(AGameIndex).Captured;
  var LSeq: TArray<Integer>;
  var LW := CardSize.Width * LSpec.Scale;
  var LH := CardSize.Height * LSpec.Scale;

  if LSpec.Vertical then
  begin
    var LYs := CapturedFanLayoutV(LPile, LSpec.B, LSpec.C, LSpec.Scale, LSpec.AnchorEnd, LSpec.Reverse,
      AGukjinAsPi, LSeq);
    for var K := 0 to High(LSeq) do
    begin
      if LSeq[K] = APileIndex then
      begin
        // 회전 부채: 중심 기준. 가로 두께가 LH, 세로 두께가 LW 다.
        Exit(RectF(LSpec.A - LH / 2, LYs[K] - LW / 2, LSpec.A + LH / 2, LYs[K] + LW / 2));
      end;
    end;

    Exit;
  end;

  var LXs := CapturedFanLayout(LPile, LSpec.A, LSpec.B, LSpec.Scale, LSpec.AnchorEnd, AGukjinAsPi, LSeq);
  for var K := 0 to High(LSeq) do
  begin
    if LSeq[K] = APileIndex then
    begin
      Exit(RectF(LXs[K], LSpec.C, LXs[K] + LW, LSpec.C + LH));
    end;
  end;
end;

// 정산이 국진을 쌍피로 해석했으면, 획득 더미 안에서 열끗 무리 → 피 무리로 옮겨가는 연출을 시작한다.
// 국진은 덱에 한 장뿐이라 대상은 최대 한 명·한 장이다. 대상이 없으면 아무 일도 하지 않는다.
procedure TGostopBoard.BeginGukjinMove;
begin
  FGukjinMoveActive := False;
  for var LP := Low(TSeatPos) to High(TSeatPos) do
  begin
    FGukjinAsPi[LP] := False;
  end;

  if (not Assigned(FGame)) or (not Assigned(FEngine)) then
  begin
    Exit;
  end;

  var LResults := FEngine.FinalSettlement;
  for var I := 0 to FGame.PlayerCount - 1 do
  begin
    if (I > High(LResults)) or (not LResults[I].GukjinAsPi) then
    begin
      Continue;
    end;

    // 이 플레이어의 더미에서 전환권이 남은 국진을 찾는다.
    // GukjinSlotRect 도 같은 더미(RState)를 보므로 인덱스가 어긋나지 않는다.
    var LPile := RState.Player(I).Captured;
    for var K := 0 to LPile.Count - 1 do
    begin
      if LPile[K].IsGukjin and (not LPile[K].GukjinLocked) then
      begin
        var LFrom := GukjinSlotRect(I, K, False);
        var LTo := GukjinSlotRect(I, K, True);
        if LFrom.IsEmpty or LTo.IsEmpty then
        begin
          Break;
        end;

        FGukjinMoveSeat := PhysicalPos(I);
        FGukjinMovePileIndex := K;
        FGukjinMoveFrom := LFrom;
        FGukjinMoveTo := LTo;
        FGukjinMoveT := 0;
        FGukjinMoveActive := True;

        // 이동 중에도 나머지 패는 이미 '국진이 빠진' 배치로 그린다 — 그래야 착지할 빈자리가 보인다
        FGukjinAsPi[FGukjinMoveSeat] := True;
        FGukjinMoveTimer.Enabled := True;
        QueueEffect('국진 → 쌍피');
        Break;
      end;
    end;

    if FGukjinMoveActive then
    begin
      Break;
    end;
  end;
end;

procedure TGostopBoard.GukjinMoveTick(Sender: TObject);
begin
  if not FGukjinMoveActive then
  begin
    FGukjinMoveTimer.Enabled := False;
    Exit;
  end;

  FGukjinMoveT := FGukjinMoveT + FGukjinMoveTimer.Interval / GUKJIN_MOVE_MS * FGameSpeed;
  if FGukjinMoveT >= 1 then
  begin
    FGukjinMoveT := 1;
    FGukjinMoveActive := False;
    FGukjinMoveTimer.Enabled := False;

    // 연출이 끝나야 정산 다이얼로그가 뜬다(PresentationBusy 가 이 플래그를 본다)
    MaybeBeginGameOver;
  end;

  Repaint;
end;

// 이동 중인 국진 한 장. 더미 쪽에서는 빠져 있고(ASkipPileIndex) 여기서만 그린다.
procedure TGostopBoard.DrawGukjinMove;
begin
  if not FGukjinMoveActive then
  begin
    Exit;
  end;

  // ease-in-out — 출발·도착을 부드럽게
  var LT := EnsureRange(FGukjinMoveT, 0, 1);
  var LE := LT * LT * (3 - 2 * LT);

  var LR := RectF(
    FGukjinMoveFrom.Left + (FGukjinMoveTo.Left - FGukjinMoveFrom.Left) * LE,
    FGukjinMoveFrom.Top + (FGukjinMoveTo.Top - FGukjinMoveFrom.Top) * LE,
    FGukjinMoveFrom.Right + (FGukjinMoveTo.Right - FGukjinMoveFrom.Right) * LE,
    FGukjinMoveFrom.Bottom + (FGukjinMoveTo.Bottom - FGukjinMoveFrom.Bottom) * LE);

  // 가운데서 살짝 떠오르게 — 더미 위를 넘어가는 느낌
  var LLift := Sin(LT * Pi) * LR.Height * 0.35;
  LR.Offset(0, -LLift);

  // 떠 있는 동안 조금 커지고 그림자를 깐다
  var LPop := 1 + Sin(LT * Pi) * 0.12;
  LR.Inflate(LR.Width * (LPop - 1) / 2, LR.Height * (LPop - 1) / 2);

  var LShadow := LR;
  LShadow.Offset(3, 4);
  Canvas.FillRound(LShadow, 4, $55000000);

  var LSeat := FGukjinMoveSeat;
  var LAngle := 0.0;
  if LSeat = spLeft then
  begin
    LAngle := 90;
  end
  else
  if LSeat = spRight then
  begin
    LAngle := 270;
  end;

  var LCard := RState.Player(PlayerAtPos(LSeat)).Captured[FGukjinMovePileIndex];
  if IsZero(LAngle) then
  begin
    DrawFront(LR, LCard.AssetId);
  end
  else
  begin
    // 좌/우 자리는 회전 부채라 회전시켜 그린다(rect 의 가로/세로가 뒤바뀐 상태)
    DrawCardRotated(LR.CenterPoint.X, LR.CenterPoint.Y, LR.Height, LR.Width, LAngle, LCard.AssetId, False);
  end;

  Canvas.StrokeRound(LR, 4, $FFFFE082, 2);
end;
{$ENDREGION}

function TGostopBoard.SeatRegion(const APos: TSeatPos): TRectF;
begin
  Result := TBoardLayout.SeatRegion(Width, Height, APos);
end;

function TGostopBoard.CenterRegion: TRectF;
begin
  Result := TBoardLayout.CenterRegion(Width, Height);

  // 흔들기 연출 중이면 중앙 영역을 통째로 좌우로 민다. 바닥 레이아웃·뒷패·날아가는 패의
  // 목적지·마우스 hit-test가 모두 이 영역을 기준으로 계산되므로 서로 어긋날 일이 없다.
  // (좌석·패널은 SeatRegion 기준이라 영향받지 않는다)
  var LDx := ShakeOffsetX;
  if not IsZero(LDx) then
  begin
    Result.Offset(LDx, 0);
  end;
end;

procedure TGostopBoard.DrawRegion(const ARegion: TRectF; const AHighlight: Boolean);
begin
  // 자리 전체를 감싸는 큰 프레임은 세로 기둥에서 빈 여백처럼 보여 균형을 깬다.
  // 프레임은 더 이상 그리지 않고, 현재 차례 강조는 패널(DrawPlayerPanel)에서 처리한다.
end;

procedure TGostopBoard.DrawCardRotated(const ACenterX, ACenterY, ACardW, ACardH, AAngle: Single; const AAssetId: string; const ABack: Boolean);
begin
  var LR := RectF(ACenterX - ACardW / 2, ACenterY - ACardH / 2, ACenterX + ACardW / 2, ACenterY + ACardH / 2);
  if IsZero(AAngle) then
  begin
    if ABack then
    begin
      DrawBack(LR);
    end
    else
    begin
      DrawFront(LR, AAssetId);
    end;

    Exit;
  end;

  var LSaved := Canvas.Matrix;
  var LRot := TMatrix.CreateTranslation(-ACenterX, -ACenterY) * TMatrix.CreateRotation(DegToRad(AAngle)) * TMatrix.CreateTranslation(ACenterX, ACenterY);
  Canvas.SetMatrix(LRot * LSaved);
  try
    if ABack then
    begin
      DrawBack(LR);
    end
    else
    begin
      DrawFront(LR, AAssetId);
    end;
  finally
    Canvas.SetMatrix(LSaved);
  end;
end;

procedure TGostopBoard.DrawHandList(const AHand: TList<THwatuCard>; const ARegion: TRectF; const AInteractive: Boolean;
  const ARaiseIds: TArray<string>);
begin
  if AInteractive then
  begin
    FHandRects.Clear;
    FHandIndexMap.Clear;
  end;

  var LCount := AHand.Count;
  if LCount = 0 then
  begin
    Exit;
  end;

  var CS := CardSize;
  var LOrder := SortedIndices(AHand);
  // 겹쳐서(부채꼴) 표시해 공간 절약 — 오른쪽 카드가 위로 겹침
  var LStep := Min(CS.Width * 0.62, (ARegion.Width - 20) / LCount);
  var LStartX := (ARegion.Left + ARegion.Right) / 2 - (LStep * (LCount - 1) + CS.Width) / 2;
  var LY := ARegion.Bottom - CS.Height - 8;

  for var D := 0 to LCount - 1 do
  begin
    var LRealIdx := LOrder[D];
    var LR := RectF(LStartX + D * LStep, LY, LStartX + D * LStep + CS.Width, LY + CS.Height);
    if AInteractive then
    begin
      FHandRects.Add(LR);
      FHandIndexMap.Add(LRealIdx);
    end;

    var LDrawR := LR;
    if AInteractive and (D = FHoverHand) then
    begin
      LDrawR.Offset(0, -CS.Height * 0.16);
    end;

    // 지정된 패(예: 팔 수 있는 광·족보패)는 살짝 위로 들어 보여준다
    for var LRaiseId in ARaiseIds do
    begin
      if LRaiseId = AHand[LRealIdx].AssetId then
      begin
        LDrawR.Offset(0, -CS.Height * 0.15);
        Break;
      end;
    end;

    DrawFront(LDrawR, AHand[LRealIdx].AssetId);

    // 먹을 수 있는 카드는 초록 테두리(플레이 중일 때만)
    if AInteractive and CanCaptureCard(AHand[LRealIdx]) then
    begin
      Canvas.StrokeRound(LDrawR, 4, $FF6CE04C, 3);
    end;
  end;
end;

procedure TGostopBoard.DrawHumanHand(const ARegion: TRectF);
begin
  FHandRects.Clear;
  FHandIndexMap.Clear;
  if FHumanIndex < 0 then
  begin
    Exit;
  end;

  // 가로형: 패널 왼쪽 / 오른쪽 위=먹은패 부채, 오른쪽 아래=손패(앞면) 부채
  var CS := CardSize;
  var LPanel := PlayerPanelRect(spBottom);
  var LCardsL := LPanel.Right + 14;
  var LCardsR := ARegion.Right - 6;

  // 손패(앞면) — 오른쪽 영역 하단에 부채
  var LHandRegion := RectF(LCardsL, ARegion.Top, LCardsR + 6, ARegion.Bottom);
  DrawHandList(RState.Player(FHumanIndex).Hand, LHandRegion, not Assigned(FDisplay));

  // 먹은패 — 손패 위 촘촘 가로 부채. 배치값은 CapturedFanSpec 한 곳에서만 계산한다
  var LSpec := CapturedFanSpec(spBottom, True);

  // 국진이 쌍피로 해석돼 이동 중이면, 이동하는 그 카드는 더미에서 빼고 DrawGukjinMove 가 그린다
  var LSkip := -1;
  if FGukjinMoveActive and (FGukjinMoveSeat = spBottom) then
  begin
    LSkip := FGukjinMovePileIndex;
  end;

  DrawCapturedFan(RState.Player(FHumanIndex).Captured, LSpec.A, LSpec.B, LSpec.C, LSpec.Scale,
    LSpec.AnchorEnd, FGukjinAsPi[spBottom], LSkip);
end;

function TGostopBoard.PlayerAtPos(const APos: TSeatPos): Integer;
begin
  for var I := 0 to FGame.PlayerCount - 1 do
  begin
    if PhysicalPos(I) = APos then
    begin
      Exit(I);
    end;
  end;

  Result := -1;
end;

// 자리의 정보 패널 rect — 크기는 전 자리 동일(PANEL_W×PANEL_H), 앵커만 자리별로 다름
// P1(위)=우상, 나(아래)=좌상, P2(좌)=좌상, P4(우)=좌하
function TGostopBoard.PlayerPanelRect(const APos: TSeatPos): TRectF;
begin
  Result := TBoardLayout.PlayerPanelRect(Width, Height, APos);
end;

// 자리에서 카드가 놓일 공간(정보 패널 제외 영역)
function TGostopBoard.SeatCardArea(const APos: TSeatPos): TRectF;
begin
  Result := TBoardLayout.SeatCardArea(Width, Height, APos);
end;

// 자리별 아바타 4종을 절차 생성(원형 배경 + 얼굴 + 자리별 개성: 머리/안경/미소/수염)
procedure TGostopBoard.GenerateAvatars;
const
  BG: array [TSeatPos] of TAlphaColor = ($FF1565C0, $FFEF6C00, $FF2E7D32, $FF6A1B9A);
  ALL4 = [TCorner.TopLeft, TCorner.TopRight, TCorner.BottomLeft, TCorner.BottomRight];
begin
  for var LP := spTop to spRight do
  begin
    if Assigned(FAvatars[LP]) then
    begin
      Continue;
    end;

    var LBmp := TBitmap.Create(96, 96);
    if LBmp.Canvas.BeginScene then
    begin
      try
        LBmp.Canvas.Clear(0);
        LBmp.Canvas.Fill.Kind := TBrushKind.Solid;
        LBmp.Canvas.Stroke.Kind := TBrushKind.Solid;

        // 배경 원
        LBmp.Canvas.Fill.Color := BG[LP];
        LBmp.Canvas.FillEllipse(RectF(2, 2, 94, 94), 1);

        // 얼굴
        LBmp.Canvas.Fill.Color := $FFFFDBAC;
        LBmp.Canvas.FillEllipse(RectF(24, 28, 72, 80), 1);

        // 머리카락(위 반원)
        LBmp.Canvas.Fill.Color := $FF3E2723;
        LBmp.Canvas.FillArc(PointF(48, 46), PointF(24, 18), 180, 180, 1);

        // 눈
        LBmp.Canvas.Fill.Color := $FF212121;
        LBmp.Canvas.FillEllipse(RectF(36, 50, 43, 58), 1);
        LBmp.Canvas.FillEllipse(RectF(53, 50, 60, 58), 1);

        // 자리별 개성
        case LP of
          spTop:
            begin
              // P1: 납작머리 + 무표정 입
              LBmp.Canvas.Fill.Color := $FF3E2723;
              LBmp.Canvas.FillRect(RectF(28, 22, 68, 34), 6, 6, ALL4, 1);
              LBmp.Canvas.Stroke.Color := $FF6D4C41;
              LBmp.Canvas.Stroke.Thickness := 3;
              LBmp.Canvas.DrawLine(PointF(41, 68), PointF(55, 68), 1);
            end;
          spLeft:
            begin
              // P2: 동그란 안경 + 작은 입
              LBmp.Canvas.Stroke.Color := $FF263238;
              LBmp.Canvas.Stroke.Thickness := 2.5;
              LBmp.Canvas.DrawEllipse(RectF(32, 46, 47, 61), 1);
              LBmp.Canvas.DrawEllipse(RectF(49, 46, 64, 61), 1);
              LBmp.Canvas.DrawLine(PointF(47, 53), PointF(49, 53), 1);
              LBmp.Canvas.Stroke.Color := $FF6D4C41;
              LBmp.Canvas.Stroke.Thickness := 3;
              LBmp.Canvas.DrawLine(PointF(43, 70), PointF(53, 70), 1);
            end;
          spBottom:
            begin
              // 나: 함박 미소 + 볼터치
              LBmp.Canvas.Stroke.Color := $FF6D4C41;
              LBmp.Canvas.Stroke.Thickness := 3;
              LBmp.Canvas.DrawArc(PointF(48, 62), PointF(11, 9), 25, 130, 1);
              LBmp.Canvas.Fill.Color := $60FF8A80;
              LBmp.Canvas.FillEllipse(RectF(28, 60, 38, 68), 1);
              LBmp.Canvas.FillEllipse(RectF(58, 60, 68, 68), 1);
            end;
        else
          begin
            // P4: 콧수염 + 입
            LBmp.Canvas.Fill.Color := $FF4E342E;
            LBmp.Canvas.FillRect(RectF(38, 62, 58, 67), 3, 3, ALL4, 1);
            LBmp.Canvas.Stroke.Color := $FF6D4C41;
            LBmp.Canvas.Stroke.Thickness := 3;
            LBmp.Canvas.DrawLine(PointF(42, 73), PointF(54, 73), 1);
          end;
        end;
      finally
        LBmp.Canvas.EndScene;
      end;
    end;

    FAvatars[LP] := LBmp;
  end;
end;

// 지정한 파일을 로드한다. 실패/미존재면 nil.
// 소스 파일이 이미 사각형·투명배경이므로 별도 가공 없이 그대로 사용(평상시 아바타와 동일 스타일).
function TGostopBoard.LoadStateAvatar(const AFile: string): TBitmap;
begin
  Result := nil;
  if not TFile.Exists(AFile) then
  begin
    Exit;
  end;

  try
    Result := TBitmap.CreateFromFile(AFile);
  except
    FreeAndNil(Result);
  end;
end;

// assets\avatars 의 avatar_*.png 를 풀로 로드(지연, 1회). 환호·슬픔·화남 상태 풀도 같은 인덱스로 나란히 로드
// (assets\characters.json에 등록된 파일이 있으면 로드, 없으면 nil — 그리면 텍스트만 폴백).
procedure TGostopBoard.LoadAvatarPool;
begin
  if Assigned(FAvatarPool) then
  begin
    Exit;
  end;

  FAvatarPool := TObjectList<TBitmap>.Create(True);
  FAvatarCheerPool := TObjectList<TBitmap>.Create(True);
  FAvatarSadPool := TObjectList<TBitmap>.Create(True);
  FAvatarAngryPool := TObjectList<TBitmap>.Create(True);
  var LDir := THwatuAssets.AvatarDir;
  if (LDir = '') or (not TDirectory.Exists(LDir)) then
  begin
    Exit;
  end;

  var LFiles := TDirectory.GetFiles(TPath.Combine(LDir, 'normal'), 'avatar_*.png');
  TArray.Sort<string>(LFiles);
  for var LFile in LFiles do
  begin
    try
      FAvatarPool.Add(TBitmap.CreateFromFile(LFile));
    except
      // 손상/열기 실패 파일은 건너뜀(풀에서 제외)
      Continue;
    end;

    // 파일 순서 = characters.json 인덱스 순서(프로젝트 불변식) → 같은 인덱스로 상태 이미지 매칭
    var LIdx := FAvatarPool.Count - 1;
    FAvatarCheerPool.Add(LoadStateAvatar(TPath.Combine(LDir, TGostopCharacters.CheerImageOf(LIdx))));
    FAvatarSadPool.Add(LoadStateAvatar(TPath.Combine(LDir, TGostopCharacters.SadImageOf(LIdx))));
    FAvatarAngryPool.Add(LoadStateAvatar(TPath.Combine(LDir, TGostopCharacters.AngryImageOf(LIdx))));
  end;
end;

// assets\difficulty 의 diff_*.png 를 AI 난이도 카드 전용 풀로 로드(지연, 1회, 파일명 정렬 =
// 병아리/선수/타짜/신의손 순 — AI_SKILL_LABELS와 인덱스 맞춤). 20인 아바타 로스터와 완전히
// 별개의 캐릭터라 avatars 하위가 아닌 assets 바로 아래에 있음(THwatuAssets.DifficultyDir).
procedure TGostopBoard.LoadSkillAvatarPool;
begin
  if Assigned(FSkillAvatarPool) then
  begin
    Exit;
  end;

  FSkillAvatarPool := TObjectList<TBitmap>.Create(True);
  var LDir := THwatuAssets.DifficultyDir;
  if (LDir = '') or (not TDirectory.Exists(LDir)) then
  begin
    Exit;
  end;

  var LFiles := TDirectory.GetFiles(LDir, 'diff_*.png');
  TArray.Sort<string>(LFiles);
  for var LFile in LFiles do
  begin
    try
      FSkillAvatarPool.Add(TBitmap.CreateFromFile(LFile));
    except
      // 손상/열기 실패 파일은 건너뜀(풀에서 제외)
      Continue;
    end;
  end;
end;

// 매치 시작 시 자리별 아바타 배정 — 사람은 선택값(없으면 랜덤), AI는 랜덤. 한 게임 내 중복 금지
procedure TGostopBoard.AssignAvatars;
begin
  LoadAvatarPool;
  for var LP := spTop to spRight do
  begin
    FSeatAvatar[LP] := -1;
  end;

  if FAvatarPool.Count = 0 then
  begin
    Exit;   // 파일 없음 → 절차 생성 아바타 폴백
  end;

  var LHuman := FHumanAvatarIdx;
  if (LHuman < 0) or (LHuman >= FAvatarPool.Count) then
  begin
    LHuman := Random(FAvatarPool.Count);
  end;

  FSeatAvatar[spBottom] := LHuman;

  for var LP := spTop to spRight do
  begin
    if LP = spBottom then
    begin
      Continue;
    end;

    var LPick := Random(FAvatarPool.Count);
    var LGuard := 0;
    while ((LPick = FSeatAvatar[spTop]) or (LPick = FSeatAvatar[spLeft]) or
      (LPick = FSeatAvatar[spBottom]) or (LPick = FSeatAvatar[spRight])) and (LGuard < FAvatarPool.Count) do
    begin
      LPick := (LPick + 1) mod FAvatarPool.Count;
      Inc(LGuard);
    end;

    FSeatAvatar[LP] := LPick;
  end;
end;

// 사람 아바타 선택 적용. 다른 자리와 겹치면 그 자리는 새 아바타로 교체(한 게임 내 중복 금지)
procedure TGostopBoard.SetHumanAvatar(const AIndex: Integer);
begin
  LoadAvatarPool;
  if (AIndex < 0) or (AIndex >= FAvatarPool.Count) then
  begin
    Exit;
  end;

  FHumanAvatarIdx := AIndex;
  FSeatAvatar[spBottom] := AIndex;

  for var LP := spTop to spRight do
  begin
    if (LP <> spBottom) and (FSeatAvatar[LP] = AIndex) then
    begin
      var LPick := Random(FAvatarPool.Count);
      var LGuard := 0;
      while ((LPick = FSeatAvatar[spTop]) or (LPick = FSeatAvatar[spLeft]) or
        (LPick = FSeatAvatar[spBottom]) or (LPick = FSeatAvatar[spRight])) and (LGuard < FAvatarPool.Count) do
      begin
        LPick := (LPick + 1) mod FAvatarPool.Count;
        Inc(LGuard);
      end;

      FSeatAvatar[LP] := LPick;
    end;
  end;

  SaveSettings;   // 아바타 선택 유지
end;

// 아바타 선택 오버레이(최상단): 풀 전체를 격자로 보여주고 클릭으로 선택
procedure TGostopBoard.DrawAvatarPicker;
begin
  FAvatarRects.Clear;
  if (not Assigned(FAvatarPool)) or (FAvatarPool.Count = 0) then
  begin
    FAvatarPicking := False;
    Exit;
  end;

  var LCols := 5;
  var LSize := 64.0;
  var LGap := 12.0;
  var LRows := (FAvatarPool.Count + LCols - 1) div LCols;
  var LPanelW := LCols * LSize + (LCols - 1) * LGap + 40;
  var LPanelH := LRows * (LSize + LGap) + 60;
  var LPanel := RectF(Width / 2 - LPanelW / 2, Height / 2 - LPanelH / 2,
    Width / 2 + LPanelW / 2, Height / 2 + LPanelH / 2);

  Canvas.FillRound(LPanel, 12, $F0101010);
  Canvas.StrokeRound(LPanel, 12, $60FFFFFF, 1);
  DrawLabel(RectF(LPanel.Left, LPanel.Top + 6, LPanel.Right, LPanel.Top + 34), '내 아바타 선택', TAlphaColors.White, 17);

  for var I := 0 to FAvatarPool.Count - 1 do
  begin
    var LRow := I div LCols;
    var LCol := I mod LCols;
    var LX := LPanel.Left + 20 + LCol * (LSize + LGap);
    var LY := LPanel.Top + 44 + LRow * (LSize + LGap);
    var LR := RectF(LX, LY, LX + LSize, LY + LSize);
    FAvatarRects.Add(LR);
    var LBmp := FAvatarPool[I];
    Canvas.DrawBitmap(LBmp, RectF(0, 0, LBmp.Width, LBmp.Height), LR, 1, False);

    if (I = FSeatAvatar[spBottom]) or (I = FHumanAvatarIdx) then
    begin
      // 현재 내 아바타: 금색 테두리
      Canvas.StrokeRound(LR, 8, $FFFFD54A, 3);
    end
    else
    begin
      // 다른 자리가 사용 중이면 회색 테두리(선택하면 그 자리는 자동 교체)
      for var LP := spTop to spRight do
      begin
        if (LP <> spBottom) and (FSeatAvatar[LP] = I) then
        begin
          Canvas.StrokeRound(LR, 8, $80B0B0B0, 2);
          Break;
        end;
      end;
    end;
  end;
end;

// 하단 바: 게임레벨(표시 전용)·일시정지·자동·소리·게임속도를 항상 고정 표시 + 크레딧
// (하단 진행 메시지 박스는 제거 — 진행 메시지는 일단 숨김)
procedure TGostopBoard.DrawControlBar;
begin
  // 우하단 제작자 크레딧(오른쪽·아래 8px 여백. 클릭 = GitHub 저장소)
  FCreditRect := RectF(Width - 168, Height - 25, Width - 8, Height - 8);
  Canvas.Fill.Kind := TBrushKind.Solid;
  Canvas.Fill.Color := $A0FFE082;
  TGostopFonts.Apply(Canvas, 12);
  Canvas.FillText(FCreditRect, '@시골프로그래머', False, 1, [], TTextAlign.Trailing, TTextAlign.Center);

  var LAudio := TGostopAudio.Instance;
  var LBarH := 32.0;
  var LMidX := Width / 2;
  var LTop := Height - LBarH - 6;
  var LBarW := 710.0;   // 게임레벨 섹션 추가분(약 146px) 반영해 기존 560에서 확장
  if FSpectator then
  begin
    LBarW := LBarW + 60;   // 관전 뱃지 추가분
  end;

  var LBar := RectF(LMidX - LBarW / 2, LTop, LMidX + LBarW / 2, LTop + LBarH);
  var LCY := (LBar.Top + LBar.Bottom) / 2;

  Canvas.FillRound(LBar, 15, $C0424242);

  // 게임레벨(표시 전용 — 클릭 불가. 변경은 새 게임 설정에서만 가능)
  var LLevelText := '';
  for var LI := 0 to High(AI_SKILL_VALUES) do
  begin
    if AI_SKILL_VALUES[LI] = FConfig.AiSkill then
    begin
      LLevelText := AI_SKILL_LABELS[LI];
      Break;
    end;
  end;

  if LLevelText = '' then
  begin
    LLevelText := Format('Lv.%d', [FConfig.AiSkill]);
  end;

  DrawLabel(RectF(LBar.Left + 12, LBar.Top, LBar.Left + 68, LBar.Bottom), '게임레벨', $FFD8E0D0, 12);
  DrawLabel(RectF(LBar.Left + 70, LBar.Top, LBar.Left + 138, LBar.Bottom), LLevelText, $FFFFE082, 13);

  var LLevelEndX := LBar.Left + 138;
  if FSpectator then
  begin
    var LSpecR := RectF(LLevelEndX + 6, LBar.Top + 4, LLevelEndX + 60, LBar.Bottom - 4);
    Canvas.FillRound(LSpecR, LSpecR.Height / 2, $FF37474F);
    DrawLabel(LSpecR, '관전', $FFFFE082, 12);
    LLevelEndX := LSpecR.Right;
  end;

  Canvas.Stroke.Kind := TBrushKind.Solid;
  Canvas.Stroke.Color := $30FFFFFF;
  Canvas.Stroke.Thickness := 1;
  Canvas.DrawLine(PointF(LLevelEndX + 8, LBar.Top + 6), PointF(LLevelEndX + 8, LBar.Bottom - 6), 1);

  // 일시정지/재개 버튼(스페이스바와 동일 동작) — 아이콘 + 설명 텍스트(잘리지 않게 넉넉한 폭)
  FBtnPauseBar := RectF(LLevelEndX + 16, LBar.Top + 3, LLevelEndX + 114, LBar.Bottom - 3);
  Canvas.FillRound(FBtnPauseBar, 6, IfThen(IsHot(FBtnPauseBar), $50FFFFFF, $30FFFFFF));
  if FPaused then
  begin
    // 재생 삼각형(재개)
    var LTri: TPolygon;
    SetLength(LTri, 3);
    LTri[0] := PointF(FBtnPauseBar.Left + 12, LCY - 7);
    LTri[1] := PointF(FBtnPauseBar.Left + 12, LCY + 7);
    LTri[2] := PointF(FBtnPauseBar.Left + 22, LCY);
    Canvas.Fill.Color := $FF80CBC4;
    Canvas.FillPolygon(LTri, 1);
    DrawLabel(RectF(FBtnPauseBar.Left + 26, LBar.Top, FBtnPauseBar.Right - 2, LBar.Bottom), '재개', TAlphaColors.White, 12.5);
  end
  else
  begin
    // 일시정지 막대 두 개
    Canvas.Fill.Color := $FFFFD54A;
    Canvas.FillRect(RectF(FBtnPauseBar.Left + 12, LCY - 7, FBtnPauseBar.Left + 16, LCY + 7), 1, 1, [], 1);
    Canvas.FillRect(RectF(FBtnPauseBar.Left + 19, LCY - 7, FBtnPauseBar.Left + 23, LCY + 7), 1, 1, [], 1);
    DrawLabel(RectF(FBtnPauseBar.Left + 26, LBar.Top, FBtnPauseBar.Right - 2, LBar.Bottom), '일시정지', TAlphaColors.White, 12.5);
  end;

  // 자동 진행 버튼(이번 판 한정 — 내 턴도 AI가 대신 결정) — 사람이 있는 판에서만 표시.
  // 문구는 항상 "자동"으로 고정(켜짐 여부는 색으로만 구분)해 텍스트 폭 걱정 없이 확실히 표시되게 한다
  var LAfterAuto := FBtnPauseBar;
  if FHumanIndex >= 0 then
  begin
    FBtnAutoBar := RectF(FBtnPauseBar.Right + 8, LBar.Top + 3, FBtnPauseBar.Right + 66, LBar.Bottom - 3);
    if FAutoPlay then
    begin
      Canvas.FillRound(FBtnAutoBar, 6, $FF2E7D32);
    end
    else
    begin
      Canvas.FillRound(FBtnAutoBar, 6, IfThen(IsHot(FBtnAutoBar), $50FFFFFF, $30FFFFFF));
    end;

    DrawLabel(FBtnAutoBar, '자동', TAlphaColors.White, 12.5);
    LAfterAuto := FBtnAutoBar;
  end
  else
  begin
    FBtnAutoBar := TRectF.Empty;
  end;

  // "소리" 설명 라벨(속도 라벨과 동일 패턴)
  DrawLabel(RectF(LAfterAuto.Right + 8, LBar.Top, LAfterAuto.Right + 40, LBar.Bottom), '소리', $FFD8E0D0, 12);

  // 스피커 아이콘(클릭=음소거 토글)
  FMuteRect := RectF(LAfterAuto.Right + 42, LBar.Top + 3, LAfterAuto.Right + 70, LBar.Bottom - 3);
  Canvas.Fill.Color := TAlphaColors.White;
  Canvas.FillRect(RectF(FMuteRect.Left + 2, LCY - 4, FMuteRect.Left + 8, LCY + 4), 1, 1,
    [TCorner.TopLeft, TCorner.TopRight, TCorner.BottomLeft, TCorner.BottomRight], 1);
  var LCone: TPolygon;
  SetLength(LCone, 4);
  LCone[0] := PointF(FMuteRect.Left + 8, LCY - 4);
  LCone[1] := PointF(FMuteRect.Left + 15, LCY - 9);
  LCone[2] := PointF(FMuteRect.Left + 15, LCY + 9);
  LCone[3] := PointF(FMuteRect.Left + 8, LCY + 4);
  Canvas.FillPolygon(LCone, 1);
  if LAudio.Muted then
  begin
    Canvas.Stroke.Kind := TBrushKind.Solid;
    Canvas.Stroke.Color := $FFE53935;
    Canvas.Stroke.Thickness := 2.5;
    Canvas.DrawLine(PointF(FMuteRect.Left + 1, LCY + 10), PointF(FMuteRect.Left + 24, LCY - 10), 1);
  end
  else
  begin
    Canvas.Stroke.Kind := TBrushKind.Solid;
    Canvas.Stroke.Color := TAlphaColors.White;
    Canvas.Stroke.Thickness := 2;
    Canvas.DrawArc(PointF(FMuteRect.Left + 16, LCY), PointF(4, 5), -60, 120, 1);
    Canvas.DrawArc(PointF(FMuteRect.Left + 16, LCY), PointF(8, 9), -60, 120, 1);
  end;

  // 볼륨 슬라이더
  var LTrack := RectF(FMuteRect.Right + 10, LCY - 3, FMuteRect.Right + 10 + 110, LCY + 3);
  FVolTrackRect := RectF(LTrack.Left - 8, LBar.Top, LTrack.Right + 8, LBar.Bottom);
  Canvas.FillRound(LTrack, 3, $50FFFFFF);
  var LKX := LTrack.Left + LTrack.Width * LAudio.Volume;
  Canvas.Fill.Color := $FFFFD54A;
  Canvas.FillRect(RectF(LTrack.Left, LTrack.Top, LKX, LTrack.Bottom), 3, 3,
    [TCorner.TopLeft, TCorner.TopRight, TCorner.BottomLeft, TCorner.BottomRight], 1);
  Canvas.Fill.Color := TAlphaColors.White;
  Canvas.FillEllipse(RectF(LKX - 7, LCY - 7, LKX + 7, LCY + 7), 1);

  // 속도 슬라이더(0.5~2.0)
  DrawLabel(RectF(LTrack.Right + 14, LBar.Top, LTrack.Right + 48, LBar.Bottom), '속도', $FFD8E0D0, 12);
  var LSpd := RectF(LTrack.Right + 52, LCY - 3, LTrack.Right + 52 + 90, LCY + 3);
  FSpeedRect := RectF(LSpd.Left - 8, LBar.Top, LSpd.Right + 8, LBar.Bottom);
  Canvas.FillRound(LSpd, 3, $50FFFFFF);
  var LST := (FGameSpeed - 0.5) / 1.5;   // 0.5~2.0 → 0~1
  var LSX := LSpd.Left + LSpd.Width * LST;
  Canvas.Fill.Color := $FF80CBC4;
  Canvas.FillRect(RectF(LSpd.Left, LSpd.Top, LSX, LSpd.Bottom), 3, 3,
    [TCorner.TopLeft, TCorner.TopRight, TCorner.BottomLeft, TCorner.BottomRight], 1);
  Canvas.Fill.Color := TAlphaColors.White;
  Canvas.FillEllipse(RectF(LSX - 7, LCY - 7, LSX + 7, LCY + 7), 1);
  DrawLabel(RectF(LSpd.Right + 10, LBar.Top, LBar.Right - 4, LBar.Bottom), Format('×%.1f', [FGameSpeed]), $FFFFE082, 12);
end;

// 속도 슬라이더 트랙 X좌표 → 배속(0.5~2.0, 0.1 단위) 적용
procedure TGostopBoard.SetSpeedFromX(const AX: Single);
begin
  var LLeft := FSpeedRect.Left + 8;
  var LRight := FSpeedRect.Right - 8;
  if LRight <= LLeft then
  begin
    Exit;
  end;

  var LT := EnsureRange((AX - LLeft) / (LRight - LLeft), 0, 1);
  FGameSpeed := Round((0.5 + LT * 1.5) * 10) / 10;
  FAiTimer.Interval := Round(650 / FGameSpeed);
  Repaint;
end;

// 볼륨 슬라이더 트랙 X좌표 → 볼륨(0~1) 적용
procedure TGostopBoard.SetVolumeFromX(const AX: Single);
begin
  var LLeft := FVolTrackRect.Left + 8;
  var LRight := FVolTrackRect.Right - 8;
  if LRight <= LLeft then
  begin
    Exit;
  end;

  TGostopAudio.Instance.Volume := EnsureRange((AX - LLeft) / (LRight - LLeft), 0, 1);
  Repaint;
end;

// 설정 파일 경로(실행 파일 옆 gostop.ini — 포터블)
function TGostopBoard.SettingsPath: string;
begin
  Result := TPath.Combine(TPath.GetDirectoryName(ParamStr(0)), 'gostop.ini');
end;

// INI에서 설정 로드(없으면 기본값 유지)
procedure TGostopBoard.LoadSettings;
begin
  var LIni := TIniFile.Create(SettingsPath);
  try
    FConfig.LoadFrom(LIni);
    FHumanAvatarIdx := LIni.ReadInteger('UI', 'Avatar', FHumanAvatarIdx);
    FGameSpeed := LIni.ReadFloat('UI', 'GameSpeed', FGameSpeed);
    TGostopAudio.Instance.Volume := LIni.ReadFloat('UI', 'Volume', TGostopAudio.Instance.Volume);
    TGostopAudio.Instance.Muted := LIni.ReadBool('UI', 'Muted', TGostopAudio.Instance.Muted);
  finally
    LIni.Free;
  end;

  FConfig.Validate;   // 수동 편집 대비 값 보정
  FGameSpeed := EnsureRange(FGameSpeed, 0.5, 2.0);
  FAiTimer.Interval := Round(650 / FGameSpeed);
end;

// 설정을 INI에 저장(변경 시마다 호출)
procedure TGostopBoard.SaveSettings;
begin
  try
    var LIni := TIniFile.Create(SettingsPath);
    try
      FConfig.SaveTo(LIni);
      LIni.WriteInteger('UI', 'Avatar', FHumanAvatarIdx);
      LIni.WriteFloat('UI', 'GameSpeed', FGameSpeed);
      LIni.WriteFloat('UI', 'Volume', TGostopAudio.Instance.Volume);
      LIni.WriteBool('UI', 'Muted', TGostopAudio.Instance.Muted);
    finally
      LIni.Free;
    end;
  except
    // 설정 저장 실패(쓰기 금지 폴더 등)는 게임 진행에 영향이 없으므로 무시한다
  end;
end;

// 닉네임 인라인 편집 시작(설정창 행 위에 TEdit 표시 — 한글 IME 지원)
procedure TGostopBoard.BeginNickEdit(const ARow: TRectF);
begin
  if FNickEdit = nil then
  begin
    FNickEdit := TEdit.Create(Self);
    FNickEdit.Parent := Self;   // Parent 먼저 지정
    FNickEdit.MaxLength := 10;
    FNickEdit.OnKeyDown := NickEditKeyDown;
  end;

  FNickEdit.SetBounds(ARow.Left, ARow.Top, ARow.Width, ARow.Height);
  FNickEdit.Text := FConfig.Nickname;
  FNickEdit.Visible := True;
  FNickEdit.SetFocus;
  FNickEdit.SelectAll;
end;

// 닉네임 편집 확정(Enter/확인 버튼)
procedure TGostopBoard.ApplyNickEdit;
begin
  if (FNickEdit = nil) or (not FNickEdit.Visible) then
  begin
    Exit;
  end;

  var LName := Trim(FNickEdit.Text);
  if LName = '' then
  begin
    LName := '나';
  end;

  FConfig.Nickname := LName;
  FNickEdit.Visible := False;
  SaveSettings;
  Repaint;
end;

procedure TGostopBoard.NickEditKeyDown(Sender: TObject; var Key: Word; var KeyChar: WideChar; Shift: TShiftState);
begin
  if Key = vkReturn then
  begin
    Key := 0;
    ApplyNickEdit;
  end;
end;

// 설정을 반영한 점수 옵션
function TGostopBoard.CfgScore: TScoreOptions;
begin
  Result := FConfig.ToScore;
end;

function TGostopBoard.CfgRules: TRuleSet;
begin
  Result := FConfig.ToRules;
end;

function TGostopBoard.CfgDeckOptions: TDeckOptions;
begin
  Result := FConfig.ToDeckOptions;
end;

// 설정 행 값 순환(설정창에서 값 버튼 클릭)
procedure TGostopBoard.CycleCfg(const AIndex: Integer);
begin
  case AIndex of
    0:
      begin
        FConfig.Pibak := not FConfig.Pibak;
      end;
    1:
      begin
        FConfig.Gwangbak := not FConfig.Gwangbak;
      end;
    2:
      begin
        FConfig.Meongbak := not FConfig.Meongbak;
      end;
    3:
      begin
        FConfig.Gobak := not FConfig.Gobak;
      end;
    4:
      begin
        FConfig.ReverseGo := not FConfig.ReverseGo;
      end;
    5:
      begin
        FConfig.Bonus := not FConfig.Bonus;
      end;
    6:
      begin
        FConfig.Speech := not FConfig.Speech;
      end;
  end;

  SaveSettings;
end;

// 설정창의 값 버튼(닉네임·아바타처럼 토글이 아닌 항목). 호버·눌림 상태를 반영한다.
// 렌더 본문은 Gostop.Board.Widgets 로 분리됨. 호버/눌림만 계산해 위임.
procedure TGostopBoard.DrawCfgValueButton(const ARect: TRectF; const AText: string);
begin
  TWidgetRender.CfgValueButton(Canvas, ARect, AText, IsHot(ARect), IsPressed(ARect));
end;

// 게임 룰·플레이어 설정창(게임 시작 전 타이틀에서만)
// 켬/끔 설정을 나타내는 슬라이드 토글 스위치(값 영역 오른쪽 정렬로 그림)
procedure TGostopBoard.DrawCfgToggle(const ARect: TRectF; const AOn: Boolean);
begin
  TWidgetRender.CfgToggle(Canvas, ARect, AOn, IsHot(ARect), IsPressed(ARect));
end;

procedure TGostopBoard.DrawSettings;
const
  // 0~6=켬/끔 토글, 7=닉네임, 8=아바타(점당금액·시드머니는 시스템 자동 결정이라 UI 없음)
  GRID_ROWS = 4;         // 규칙 토글 7개를 한 행에 2개씩 놓은 행 수
  CARD_ROW_H = 106.0;
  CARD_GAP = 12.0;
  CARD_AREA_MAX_W = 440.0;   // 인원수·난이도 카드 영역 최대 폭(패널을 넓혀도 카드가 늘어나지 않게)
begin
  var LRowH := 42.0;
  var LPanelW := 480.0;
  // 토글 그리드 4행 + 닉네임·아바타 2행
  var LPanelH := 56 + 2 * CARD_ROW_H + CARD_GAP * 3 + (GRID_ROWS + 2) * LRowH + 66;
  var LPanel := RectF(Width / 2 - LPanelW / 2, Height / 2 - LPanelH / 2,
    Width / 2 + LPanelW / 2, Height / 2 + LPanelH / 2);

  Canvas.FillRound(LPanel, 14, $F02E3A2E);
  Canvas.StrokeRound(LPanel, 14, $FFFFD54A, 2);
  DrawLabel(RectF(LPanel.Left, LPanel.Top + 12, LPanel.Right, LPanel.Top + 46), '새게임', TAlphaColors.Gold, 22);

  // 상단 카드 영역: 라벨 없이 화투 카드 삽화로 인원수(3장)·AI 난이도(4장)를 한 번에 보여줌.
  // 열 개수는 다르지만(3장/4장) 두 줄 모두 같은 전체 폭에 맞춰 카드 폭만 달라진다.
  // 카드 영역은 패널 폭과 무관하게 상한을 두고 가운데 정렬한다.
  // 패널이 넓어졌다고 카드까지 늘리면 정사각형 아바타가 가로로 눌린다.
  var LCardAreaW := Min(LPanel.Width - 40, CARD_AREA_MAX_W);
  var LCardAreaL := (LPanel.Left + LPanel.Right) / 2 - LCardAreaW / 2;
  var LCardAreaR := LCardAreaL + LCardAreaW;
  var LCardY := LPanel.Top + 56;

  var LSeg3Gap := CARD_GAP;
  var LSeg3W := (LCardAreaW - LSeg3Gap * 2) / 3;
  LoadAvatarPool;
  for var LSeg := 0 to 2 do
  begin
    var LSegCount := LSeg + 2;
    var LSegRect := RectF(LCardAreaL + LSeg * (LSeg3W + LSeg3Gap), LCardY,
      LCardAreaL + LSeg * (LSeg3W + LSeg3Gap) + LSeg3W, LCardY + CARD_ROW_H);
    FCfgCountRects[LSeg] := LSegRect;

    // 인원수만큼 아바타를 풀에서 뽑아 렌더러에 넘긴다(렌더러는 게임 상태를 모른다)
    var LStackAv: TArray<TBitmap>;
    SetLength(LStackAv, LSegCount);
    if Assigned(FAvatarPool) and (FAvatarPool.Count > 0) then
    begin
      for var K := 0 to LSegCount - 1 do
      begin
        LStackAv[K] := FAvatarPool[K mod FAvatarPool.Count];
      end;
    end;

    TSelectCardRender.AvatarStack(Canvas, LSegRect, LStackAv, GAME_MODE_LABELS[LSegCount],
      LSegCount = FSetupCount, IsHot(LSegRect), IsPressed(LSegRect));
  end;

  LCardY := LCardY + CARD_ROW_H + CARD_GAP;
  var LSeg4Gap := CARD_GAP * 0.75;
  var LSeg4W := (LCardAreaW - LSeg4Gap * 3) / 4;
  LoadSkillAvatarPool;
  for var LSeg := 0 to 3 do
  begin
    var LSegRect := RectF(LCardAreaL + LSeg * (LSeg4W + LSeg4Gap), LCardY,
      LCardAreaL + LSeg * (LSeg4W + LSeg4Gap) + LSeg4W, LCardY + CARD_ROW_H);
    FCfgSkillRects[LSeg] := LSegRect;
    var LSkillBmp: TBitmap := nil;
    if Assigned(FSkillAvatarPool) and (LSeg < FSkillAvatarPool.Count) then
    begin
      LSkillBmp := FSkillAvatarPool[LSeg];
    end;

    TSelectCardRender.Avatar(Canvas, LSegRect, LSkillBmp, AI_SKILL_LABELS[LSeg],
      AI_SKILL_VALUES[LSeg] = FConfig.AiSkill, IsHot(LSegRect), IsPressed(LSegRect));
  end;

  var LRowsTop := LCardY + CARD_ROW_H + CARD_GAP;

  // 항목: 라벨(왼쪽) + 값(오른쪽). 0~6=켬/끔 토글, 7=닉네임, 8=아바타
  var LLabels: array [0 .. 8] of string;
  LLabels[0] := '피박';
  LLabels[1] := '광박';
  LLabels[2] := '멍박';
  LLabels[3] := '고박 (×2)';
  LLabels[4] := '역고 (×4)';
  LLabels[5] := '보너스패';
  LLabels[6] := '말풍선';
  LLabels[7] := '닉네임';
  LLabels[8] := '아바타';

  var LToggleOn: array [0 .. 6] of Boolean;
  LToggleOn[0] := FConfig.Pibak;
  LToggleOn[1] := FConfig.Gwangbak;
  LToggleOn[2] := FConfig.Meongbak;
  LToggleOn[3] := FConfig.Gobak;
  LToggleOn[4] := FConfig.ReverseGo;
  LToggleOn[5] := FConfig.Bonus;
  LToggleOn[6] := FConfig.Speech;

  // 규칙 토글만 한 행에 2개씩. 닉네임·아바타는 값이 길고 성격이 달라 기존대로 한 행에 하나씩.
  var LGrid: array [0 .. GRID_ROWS - 1, 0 .. 1] of Integer;
  LGrid[0, 0] := 0;  LGrid[0, 1] := 1;   // 피박   | 광박
  LGrid[1, 0] := 2;  LGrid[1, 1] := 3;   // 멍박   | 고박
  LGrid[2, 0] := 4;  LGrid[2, 1] := 5;   // 역고   | 보너스패
  LGrid[3, 0] := 6;  LGrid[3, 1] := -1;  // 말풍선 | (빈 칸)

  // 항목 영역은 위쪽 난이도 카드와 같은 폭·같은 좌우 끝으로 맞춘다(세로선이 어긋나지 않게)
  var LRowsL := LCardAreaL;
  var LRowsR := LCardAreaR;
  var LColGap := 24.0;
  var LColW := (LRowsR - LRowsL - LColGap) / 2;

  for var LRow := 0 to GRID_ROWS - 1 do
  begin
    var LY := LRowsTop + LRow * LRowH;
    for var LCol := 0 to 1 do
    begin
      var LIdx := LGrid[LRow, LCol];
      if LIdx < 0 then
      begin
        Continue;
      end;

      var LCellL := LRowsL + LCol * (LColW + LColGap);
      var LCellR := LCellL + LColW;

      Canvas.Fill.Color := $FFE8EEE4;
      TGostopFonts.Apply(Canvas, 16);
      Canvas.FillText(RectF(LCellL, LY, LCellR - 108, LY + LRowH - 8), LLabels[LIdx],
        False, 1, [], TTextAlign.Leading, TTextAlign.Center);

      var LValueArea := RectF(LCellR - 104, LY + 3, LCellR, LY + LRowH - 8);
      FCfgRects[LIdx] := LValueArea;
      DrawCfgToggle(LValueArea, LToggleOn[LIdx]);
    end;
  end;

  // 닉네임·아바타: 한 행에 하나씩(전체 폭), 값 영역은 오른쪽 정렬
  for var LI := 7 to 8 do
  begin
    var LY := LRowsTop + (GRID_ROWS + (LI - 7)) * LRowH;
    Canvas.Fill.Color := $FFE8EEE4;
    TGostopFonts.Apply(Canvas, 16);
    Canvas.FillText(RectF(LRowsL, LY, LRowsL + 200, LY + LRowH - 8), LLabels[LI],
      False, 1, [], TTextAlign.Leading, TTextAlign.Center);

    FCfgRects[LI] := RectF(LRowsR - 260, LY + 3, LRowsR, LY + LRowH - 8);
    if LI = 7 then
    begin
      DrawCfgValueButton(FCfgRects[LI], FConfig.Nickname);
    end
    else
    begin
      DrawCfgValueButton(FCfgRects[LI], '변경');
    end;
  end;

  // 아바타 값 버튼 안에 현재 아바타 썸네일을 얹는다
  LoadAvatarPool;
  if Assigned(FAvatarPool) and (FHumanAvatarIdx >= 0) and (FHumanAvatarIdx < FAvatarPool.Count) then
  begin
    var LBmp := FAvatarPool[FHumanAvatarIdx];
    var LSide := FCfgRects[8].Height - 4;
    var LTh := RectF(FCfgRects[8].Left + 6, FCfgRects[8].Top + 2, FCfgRects[8].Left + 6 + LSide, FCfgRects[8].Top + 2 + LSide);
    Canvas.DrawBitmap(LBmp, RectF(0, 0, LBmp.Width, LBmp.Height), LTh, 1, False);
  end;

  // 취소 · 다음(대전 설정으로 진행)
  FBtnCfgCancel := DrawStdButton(RectF(Width / 2 - 150, LPanel.Bottom - 56, Width / 2 - 10, LPanel.Bottom - 16), '취소', dbkNeutral);
  FBtnCfgNext := DrawStdButton(RectF(Width / 2 + 10, LPanel.Bottom - 56, Width / 2 + 150, LPanel.Bottom - 16), '다음', dbkPrimary);
end;

// 아바타 인덱스 → 실명풍 이름(범위 밖이면 빈 문자열)
function TGostopBoard.AvatarName(const AIndex: Integer): string;
begin
  Result := TGostopCharacters.NameOf(AIndex);
end;

// 캐릭터 능력치 조회(0=수읽기, 1=침착, 2=배짱, 3=욕심, 4=운). 범위 밖 아바타는 평균 20
function TGostopBoard.AvatarStat(const AIndex: Integer; const AStat: Integer): Integer;
begin
  Result := TGostopCharacters.StatOf(AIndex, AStat);
end;

// 판별 운 굴림: 캐릭터 운 스탯 ×2 ± 15 (5~99). 새 판마다 호출
procedure TGostopBoard.RollSeatLuck;
begin
  for var LP := spTop to spRight do
  begin
    var LStat := AvatarStat(FSeatAvatar[LP], 4);
    FSeatLuckRoll[LP] := EnsureRange(LStat * 2 + Random(31) - 15, 5, 99);
  end;
end;

// 자리의 표시 이름: 아래=나(닉네임, 관전이 아닐 때), 그 외/관전=아바타 이름(폴백: 자리 라벨)
function TGostopBoard.SeatDisplayName(const APos: TSeatPos): string;
begin
  if (APos = spBottom) and (not FSpectator) then
  begin
    Result := FConfig.Nickname;
    Exit;
  end;

  Result := AvatarName(FSeatAvatar[APos]);
  if Result <> '' then
  begin
    Exit;
  end;

  case APos of
    spTop:
      begin
        Result := 'P1';
      end;
    spLeft:
      begin
        Result := 'P2';
      end;
    spBottom:
      begin
        Result := 'P3';
      end;
  else
    begin
      Result := 'P4';
    end;
  end;
end;

// 설정 행들이 아직 안 쓰는 아바타 하나를 무작위로 고른다(사람 아바타 포함 중복 회피)
function TGostopBoard.PickUnusedAvatar: Integer;
begin
  LoadAvatarPool;
  if FAvatarPool.Count = 0 then
  begin
    Exit(-1);
  end;

  Result := Random(FAvatarPool.Count);
  var LGuard := 0;
  while LGuard < FAvatarPool.Count do
  begin
    var LUsed := Result = FHumanAvatarIdx;
    for var R := 0 to FSetupCount - 1 do
    begin
      if FSetupAvatar[R] = Result then
      begin
        LUsed := True;
      end;
    end;

    if not LUsed then
    begin
      Exit;
    end;

    Result := (Result + 1) mod FAvatarPool.Count;
    Inc(LGuard);
  end;
end;

// 현재 인원수 기준 실제로 쓰이는 물리 좌석 목록(항상 위·아래, 3인+좌, 4인+우)
function TGostopBoard.ActivePhysicalSeats: TArray<TSeatPos>;
begin
  Result := [spTop, spBottom];
  if FPlayerCount >= 3 then
  begin
    Result := Result + [spLeft];
  end;

  if FPlayerCount >= 4 then
  begin
    Result := Result + [spRight];
  end;
end;

// 오링 교체용 신규 아바타 하나를 고른다(사람·현재 착석 중인 모든 아바타 + 이번에 같이 교체되는 다른 좌석 회피)
function TGostopBoard.PickReplacementAvatar(const AExtraExclude: Integer): Integer;
begin
  LoadAvatarPool;
  if FAvatarPool.Count = 0 then
  begin
    Exit(-1);
  end;

  Result := Random(FAvatarPool.Count);
  var LGuard := 0;
  while LGuard < FAvatarPool.Count do
  begin
    var LUsed := (Result = FHumanAvatarIdx) or (Result = AExtraExclude);
    for var LP := spTop to spRight do
    begin
      if FSeatAvatar[LP] = Result then
      begin
        LUsed := True;
      end;
    end;

    if not LUsed then
    begin
      Exit;
    end;

    Result := (Result + 1) mod FAvatarPool.Count;
    Inc(LGuard);
  end;
end;

// 좌석 패널 안에서 아바타가 그려지는 정확한 사각형(패널 렌더·등장 애니 공용 — 도착 지점 일치 보장)
function TGostopBoard.SeatAvatarRect(const APos: TSeatPos): TRectF;
const
  AV_INSET = 2.0;   // 카드의 둥근 모서리를 침범하지 않을 만큼만 띄운다
begin
  // 아바타는 카드 상단을 가로로 꽉 채운다. 원본이 정사각형(128x128)이므로 높이 = 폭.
  // 예전에는 카드 안에 60x60 네모 상자를 따로 두고 그 안에 그려 아바타가 작아 보였다.
  var LBox := PlayerPanelRect(APos);
  var LSize := LBox.Width - AV_INSET * 2;
  Result := RectF(LBox.Left + AV_INSET, LBox.Top + AV_INSET,
    LBox.Right - AV_INSET, LBox.Top + AV_INSET + LSize);
end;

// 오링(파산)된 상대 자리를 새 캐릭터로 교체(최대 동시 2명). 없으면 즉시 다음 판 진행.
procedure TGostopBoard.BeginSeatReplacement(const AStartPos: TSeatPos);
begin
  var LBroke: TArray<TSeatPos> := nil;
  for var LPos in ActivePhysicalSeats do
  begin
    if (LPos <> spBottom) and (FMoney[LPos] <= 0) then
    begin
      LBroke := LBroke + [LPos];
      if Length(LBroke) >= 2 then
      begin
        Break;   // 동시 교체는 최대 2명(나머지는 다음 기회에)
      end;
    end;
  end;

  FReplacePendingStartPos := AStartPos;
  if Length(LBroke) = 0 then
  begin
    NewGame(FPlayerCount, FAiSkill, AStartPos, False);
    Exit;
  end;

  FReplacingSeats := LBroke;
  SetLength(FReplaceNewAvatar, Length(LBroke));
  var LExtra := -1;
  for var I := 0 to High(LBroke) do
  begin
    FReplaceNewAvatar[I] := PickReplacementAvatar(LExtra);
    LExtra := FReplaceNewAvatar[I];
    FSeatAvatar[LBroke[I]] := -1;   // 등장 전까지 자리 비움(패널에 이전 아바타 안 보이게)
  end;

  FReplaceProgress := 0;
  TGostopAudio.Instance.Play('sfx_negotiate');
  FReplaceTimer.Enabled := True;
  Repaint;
end;

// 등장 애니 진행 → 완료되면 신규 캐릭터 확정(아바타·시드머니·난이도·전적 리셋) 후 다음 판 진행
procedure TGostopBoard.ReplaceTimerTick(Sender: TObject);
begin
  if FPaused then
  begin
    Exit;
  end;

  if Length(FReplacingSeats) = 0 then
  begin
    FReplaceTimer.Enabled := False;
    Exit;
  end;

  FReplaceProgress := FReplaceProgress + 0.025 * FGameSpeed;
  if FReplaceProgress < 1 then
  begin
    Repaint;
    Exit;
  end;

  FReplaceTimer.Enabled := False;
  for var I := 0 to High(FReplacingSeats) do
  begin
    var LPos := FReplacingSeats[I];
    FSeatAvatar[LPos] := FReplaceNewAvatar[I];
    FSeatSkill[LPos] := FConfig.AiSkill;   // 휴먼 제외 전원 동일 게임 레벨 유지
    FMoney[LPos] := FConfig.SeedMoney;
    FWins[LPos] := 0;
    FLosses[LPos] := 0;
    FGaveUpLast[LPos] := False;
  end;

  FReplacingSeats := nil;
  FReplaceNewAvatar := nil;
  NewGame(FPlayerCount, FAiSkill, FReplacePendingStartPos, False);
end;

// 새 도전자 등장 연출: 화면 밖(1명=오른쪽, 2명=좌우)에서 자기 자리로 아바타가 이동해 온다
procedure TGostopBoard.DrawSeatReplacement;
begin
  if Length(FReplacingSeats) = 0 then
  begin
    Exit;
  end;

  Canvas.FillRound(LocalRect, 0, $60000000);
  DrawLabel(RectF(0, Height * 0.10, Width, Height * 0.10 + 40), '새로운 도전자 등장!', TAlphaColors.Gold, 26);

  var LT := EnsureRange(FReplaceProgress, 0, 1);
  LT := 1 - Power(1 - LT, 3);   // ease-out

  for var I := 0 to High(FReplacingSeats) do
  begin
    var LPos := FReplacingSeats[I];
    var LTarget := SeatAvatarRect(LPos);

    var LFromRight := True;
    if (Length(FReplacingSeats) = 2) and (I = 0) then
    begin
      LFromRight := False;   // 2명 중 첫 번째는 왼쪽에서 등장
    end;

    var LStartCx := Width + LTarget.Width;
    if not LFromRight then
    begin
      LStartCx := -LTarget.Width;
    end;

    var LCx := LStartCx + (((LTarget.Left + LTarget.Right) / 2) - LStartCx) * LT;
    var LCy := (LTarget.Top + LTarget.Bottom) / 2;
    var LR := RectF(LCx - LTarget.Width / 2, LCy - LTarget.Height / 2, LCx + LTarget.Width / 2, LCy + LTarget.Height / 2);

    if Assigned(FAvatarPool) and (FReplaceNewAvatar[I] >= 0) and (FReplaceNewAvatar[I] < FAvatarPool.Count) then
    begin
      Canvas.DrawBitmap(FAvatarPool[FReplaceNewAvatar[I]], RectF(0, 0, FAvatarPool[FReplaceNewAvatar[I]].Width,
        FAvatarPool[FReplaceNewAvatar[I]].Height), LR, 1, False);
      Canvas.StrokeRound(LR, 8, $FFFFD54A, 2);
    end;
  end;
end;

// 대전 설정 열기: 기본 시트(마지막 행=나), AI 행 슬롯머신 스핀 시작
procedure TGostopBoard.OpenMatchSetup(const ACount: Integer);
begin
  FSetupCount := EnsureRange(ACount, 2, 4);
  LoadAvatarPool;
  FSetupHumanRow := FSetupCount - 1;   // 기본: 마지막 시트가 나(클릭으로 변경/관전 가능)
  for var R := 0 to 3 do
  begin
    FSetupAvatar[R] := -1;
    FSlotDisp[R] := -1;
    FSlotRemain[R] := 0;
  end;

  FMatchSetupOpen := True;
  StartSlotSpin;
  Repaint;
end;

// 슬롯머신 스핀 시작: AI 행에 새 타깃 아바타를 뽑고 릴을 돌린다(AOnlyRow>=0면 그 행만)
procedure TGostopBoard.StartSlotSpin(const AOnlyRow: Integer);
begin
  LoadAvatarPool;
  if FAvatarPool.Count = 0 then
  begin
    Exit;
  end;

  for var R := 0 to FSetupCount - 1 do
  begin
    if R = FSetupHumanRow then
    begin
      FSetupAvatar[R] := -1;
      FSlotRemain[R] := 0;
      Continue;
    end;

    if (AOnlyRow >= 0) and (R <> AOnlyRow) then
    begin
      Continue;
    end;

    FSetupAvatar[R] := -1;   // 먼저 비워 중복 회피 계산에서 제외
    FSetupAvatar[R] := PickUnusedAvatar;
    FSlotDisp[R] := Random(FAvatarPool.Count);
    FSlotRemain[R] := 14 + R * 5 + Random(4);   // 행마다 시차를 두고 멈춤(예전보다 짧게)
  end;

  FSlotTick := 0;
  FSlotTimer.Enabled := True;
  TGostopAudio.Instance.Play('card_deal');
end;

procedure TGostopBoard.SlotTick(Sender: TObject);
begin
  if FPaused then
  begin
    Exit;
  end;

  if not FMatchSetupOpen then
  begin
    FSlotTimer.Enabled := False;
    Exit;
  end;

  Inc(FSlotTick);
  var LSpinning := False;
  for var R := 0 to FSetupCount - 1 do
  begin
    if FSlotRemain[R] <= 0 then
    begin
      Continue;
    end;

    // 마지막 6스텝은 절반 속도로 감속(슬롯머신 느낌)
    if (FSlotRemain[R] > 6) or ((FSlotTick and 1) = 0) then
    begin
      Dec(FSlotRemain[R]);
      if FSlotRemain[R] = 0 then
      begin
        FSlotDisp[R] := FSetupAvatar[R];   // 타깃에 착지
        TGostopAudio.Instance.Play('card_place');
      end
      else
      begin
        FSlotDisp[R] := (FSlotDisp[R] + 1) mod FAvatarPool.Count;
      end;
    end;

    if FSlotRemain[R] > 0 then
    begin
      LSpinning := True;
    end;
  end;

  if not LSpinning then
  begin
    FSlotTimer.Enabled := False;
  end;

  Repaint;
end;

// 시트 행 → 물리 위치 매핑 계산(내 시트=아래, 나머지는 위→좌→우 순. 관전은 기본 배치)
procedure TGostopBoard.ComputeRowPos;
begin
  if FSetupHumanRow < 0 then
  begin
    // 관전: P1→위, P2→좌, P3→아래, P4→우 (2인은 위/아래)
    case FSetupCount of
      2:
        begin
          FRowPos[0] := spTop;
          FRowPos[1] := spBottom;
        end;
      3:
        begin
          FRowPos[0] := spTop;
          FRowPos[1] := spLeft;
          FRowPos[2] := spBottom;
        end;
    else
      begin
        FRowPos[0] := spTop;
        FRowPos[1] := spLeft;
        FRowPos[2] := spBottom;
        FRowPos[3] := spRight;
      end;
    end;

    Exit;
  end;

  var LOthers: TArray<TSeatPos>;
  case FSetupCount of
    2:
      begin
        LOthers := [spTop];
      end;
    3:
      begin
        LOthers := [spTop, spLeft];
      end;
  else
    begin
      LOthers := [spTop, spLeft, spRight];
    end;
  end;

  FRowPos[FSetupHumanRow] := spBottom;
  var LK := 0;
  for var R := 0 to FSetupCount - 1 do
  begin
    if R <> FSetupHumanRow then
    begin
      FRowPos[R] := LOthers[LK];
      Inc(LK);
    end;
  end;
end;

// 설정 확정 → 자리별 아바타·난이도 반영 후 매치 시작
procedure TGostopBoard.StartMatchFromSetup;
begin
  // 릴 정지 확정
  FSlotTimer.Enabled := False;
  for var R := 0 to FSetupCount - 1 do
  begin
    if (R <> FSetupHumanRow) and (FSlotRemain[R] > 0) then
    begin
      FSlotRemain[R] := 0;
      FSlotDisp[R] := FSetupAvatar[R];
    end;
  end;

  FSpectator := FSetupHumanRow < 0;
  ComputeRowPos;

  // 사람 아바타 확정(미선택이면 랜덤)
  if (FHumanAvatarIdx < 0) and Assigned(FAvatarPool) and (FAvatarPool.Count > 0) then
  begin
    FHumanAvatarIdx := Random(FAvatarPool.Count);
  end;

  for var R := 0 to FSetupCount - 1 do
  begin
    var LPos := FRowPos[R];
    if R = FSetupHumanRow then
    begin
      FSeatAvatar[LPos] := FHumanAvatarIdx;
      FSeatSkill[LPos] := FConfig.AiSkill;
    end
    else
    begin
      FSeatAvatar[LPos] := FSetupAvatar[R];
      // AI 난이도는 '새게임' 단계에서 정한 게임 레벨(FConfig.AiSkill)을 모든 AI 좌석이 동일하게 사용
      FSeatSkill[LPos] := FConfig.AiSkill;
    end;
  end;

  FMatchSetupOpen := False;
  NewGame(FSetupCount, FConfig.AiSkill);
end;

// 대전 설정 다이얼로그(슬롯머신): 행 클릭=내 시트, 난이도 클릭=순환, 관전 토글
procedure TGostopBoard.DrawMatchSetup;
begin
  // 일관된 여백·행 높이로 정돈
  const LPad = 22.0;        // 패널 좌우 안여백
  const LRowH = 60.0;       // 행 높이(간격 포함)
  const LRowGap = 10.0;     // 행 사이 간격
  const LBtnH = 40.0;       // 버튼 높이
  const LBtnGap = 16.0;     // 버튼 사이 간격
  const LRowGap2 = 12.0;    // 버튼 행 사이 간격

  // 제목(48) + 행들 + 버튼2행 + 하단여백. 휴먼 좌석은 항상 마지막 행 고정(선택 불가)
  var LPanelH := 48 + FSetupCount * LRowH + 12 + LBtnH + LRowGap2 + LBtnH + 22;
  var LPanel := DrawStdDialog(Format('대전 설정 — %s (%d인)', [GAME_MODE_LABELS[FSetupCount], FSetupCount]), 500.0, LPanelH);
  var LCx := (LPanel.Left + LPanel.Right) / 2;

  for var R := 0 to FSetupCount - 1 do
  begin
    var LY := LPanel.Top + 50 + R * LRowH;
    var LRow := RectF(LPanel.Left + LPad, LY, LPanel.Right - LPad, LY + LRowH - LRowGap);

    // 행 배경 — 내 시트 행(항상 마지막 행)만 금테 강조. 좌석 선택 기능은 없음(휴먼 고정)
    Canvas.Fill.Color := $FF20301F;
    if R = FSetupHumanRow then
    begin
      Canvas.Fill.Color := $FF2F4A2E;
    end;

    Canvas.FillRect(LRow, 10, 10, [TCorner.TopLeft, TCorner.TopRight, TCorner.BottomLeft, TCorner.BottomRight], 1);
    if R = FSetupHumanRow then
    begin
      Canvas.Stroke.Color := $FFFFD54A;
      Canvas.Stroke.Thickness := 2;
      Canvas.DrawRect(LRow, 10, 10, [TCorner.TopLeft, TCorner.TopRight, TCorner.BottomLeft, TCorner.BottomRight], 1);
    end;

    // 시트 라벨(세로 중앙)
    DrawLabel(RectF(LRow.Left + 12, LRow.Top, LRow.Left + 48, LRow.Bottom), Format('P%d', [R + 1]), $FFB8C4B8, 15);

    // 아바타(릴) — 세로 중앙 정렬
    var LAvIdx := FSlotDisp[R];
    var LName := '';
    if R = FSetupHumanRow then
    begin
      LAvIdx := FHumanAvatarIdx;
      LName := FConfig.Nickname + ' (나)';
    end
    else
    begin
      LName := AvatarName(LAvIdx);
      if FSlotRemain[R] > 0 then
      begin
        LName := LName + ' …';
      end;
    end;

    var LAvSize := LRow.Height - 12;
    var LAvY := LRow.Top + (LRow.Height - LAvSize) / 2;
    var LAv := RectF(LRow.Left + 54, LAvY, LRow.Left + 54 + LAvSize, LAvY + LAvSize);
    if Assigned(FAvatarPool) and (LAvIdx >= 0) and (LAvIdx < FAvatarPool.Count) then
    begin
      var LBmp := FAvatarPool[LAvIdx];
      Canvas.DrawBitmap(LBmp, RectF(0, 0, LBmp.Width, LBmp.Height), LAv, 1, False);
    end;

    Canvas.StrokeRound(LAv, 6, $80FFFFFF, 1);

    // 이름(아바타 오른쪽 ~ 행 끝까지, 세로 중앙). AI는 모두 '새게임'에서 정한 동일 레벨이라
    // 좌석별 난이도 선택은 없음(휴먼만 다름)
    Canvas.Fill.Color := TAlphaColors.White;
    TGostopFonts.Apply(Canvas, 16);
    Canvas.FillText(RectF(LAv.Right + 14, LRow.Top, LRow.Right - 12, LRow.Bottom), LName,
      False, 1, [], TTextAlign.Leading, TTextAlign.Center);
  end;

  var LBY := LPanel.Top + 50 + FSetupCount * LRowH + 12;

  // 보조 버튼 행: [다시 돌리기] [관전 모드] — 중앙 정렬 한 쌍
  var LBtnW := 160.0;
  FBtnSetupSpin := DrawStdButton(RectF(LCx - LBtnW - LBtnGap / 2, LBY, LCx - LBtnGap / 2, LBY + LBtnH), '다시 돌리기', dbkNeutral);

  var LWatchRect := RectF(LCx + LBtnGap / 2, LBY, LCx + LBtnGap / 2 + LBtnW, LBY + LBtnH);
  if FSetupHumanRow < 0 then
  begin
    FBtnSetupWatch := DrawStdButton(LWatchRect, '관전 모드: 켬', dbkAccent);
  end
  else
  begin
    FBtnSetupWatch := DrawStdButton(LWatchRect, '관전 모드: 끔', dbkNeutral);
  end;

  LBY := LBY + LBtnH + LRowGap2;

  // 주 버튼 행: [시작] [취소] — 중앙 정렬 한 쌍(보조 버튼과 같은 폭)
  FBtnSetupStart := DrawStdButton(RectF(LCx - LBtnW - LBtnGap / 2, LBY, LCx - LBtnGap / 2, LBY + LBtnH), '시작', dbkPrimary);
  FBtnSetupCancel := DrawStdButton(RectF(LCx + LBtnGap / 2, LBY, LCx + LBtnGap / 2 + LBtnW, LBY + LBtnH), '취소', dbkDanger);

  EndStdDialog;
end;

// 타이틀 메뉴(게임 없음 상태): 로고 + 이어하기/새게임/끝내기 3버튼
procedure TGostopBoard.DrawTitleMenu;
begin
  var LMidX := Width / 2;

  // 장식: 고도리 3장(매조·흑싸리·공산 열끗) 부채꼴
  var CS := CardSize;
  var LCW := CS.Width * 1.2;
  var LCH := CS.Height * 1.2;
  var LCY := Height * 0.27;
  DrawCardRotated(LMidX - LCW * 1.0, LCY + 10, LCW, LCH, -16, 'february_tane', False);
  DrawCardRotated(LMidX + LCW * 1.0, LCY + 10, LCW, LCH, 16, 'august_tane', False);
  DrawCardRotated(LMidX, LCY, LCW, LCH, 0, 'april_tane', False);

  // 타이틀(그림자 + 금색)
  TGostopFonts.Apply(Canvas, 56);
  Canvas.Fill.Kind := TBrushKind.Solid;
  Canvas.Fill.Color := $C0000000;
  Canvas.FillText(RectF(3, Height * 0.40 + 3, Width + 3, Height * 0.40 + 75), '루미 고스톱',
    False, 1, [], TTextAlign.Center, TTextAlign.Center);
  Canvas.Fill.Color := TAlphaColors.Gold;
  Canvas.FillText(RectF(0, Height * 0.40, Width, Height * 0.40 + 72), '루미 고스톱',
    False, 1, [], TTextAlign.Center, TTextAlign.Center);
  DrawLabel(RectF(0, Height * 0.40 + 74, Width, Height * 0.40 + 100), '- 둘 부터 넷 까지. 정통 고스톱 -', $FFD8E0D0, 15);

  var LStatParts: TArray<string> := nil;
  if FConfig.KillCount > 0 then
  begin
    LStatParts := LStatParts + [Format('상대 오링 %d회', [FConfig.KillCount])];
  end;

  if FConfig.RefillCount > 0 then
  begin
    LStatParts := LStatParts + [Format('내 리필 %d회', [FConfig.RefillCount])];
  end;

  if Length(LStatParts) > 0 then
  begin
    DrawLabel(RectF(0, Height * 0.40 + 98, Width, Height * 0.40 + 120),
      string.Join('   ·   ', LStatParts), $FFFFD54A, 13);
  end;

  // 메뉴 버튼 2행 3열(전부 같은 크기): 1행=이어하기·새게임·끝내기, 2행=사용설명서·고스톱룰·프로그램정보
  var LBW := 170.0;
  var LBH := 56.0;
  var LGap := 24.0;
  var LRowGap := 16.0;
  var LBY := Height * 0.62;
  var LBY2 := LBY + LBH + LRowGap;
  var LHasSave := TGostopSaveGame.Exists;

  FBtnMenuContinue := DrawStdButton(RectF(LMidX - LBW * 1.5 - LGap, LBY, LMidX - LBW * 0.5 - LGap, LBY + LBH),
    '이어하기', dbkAccent, LHasSave or CanResumeMatch, 19);
  FBtnMenuNew := DrawStdButton(RectF(LMidX - LBW * 0.5, LBY, LMidX + LBW * 0.5, LBY + LBH), '새게임', dbkPrimary, True, 19);
  FBtnMenuExit := DrawStdButton(RectF(LMidX + LBW * 0.5 + LGap, LBY, LMidX + LBW * 1.5 + LGap, LBY + LBH), '끝내기', dbkDanger, True, 19);

  FBtnMenuManual := DrawStdButton(RectF(LMidX - LBW * 1.5 - LGap, LBY2, LMidX - LBW * 0.5 - LGap, LBY2 + LBH),
    '사용설명서', dbkNeutral, True, 16);
  FBtnMenuRules := DrawStdButton(RectF(LMidX - LBW * 0.5, LBY2, LMidX + LBW * 0.5, LBY2 + LBH), '고스톱룰', dbkNeutral, True, 16);
  FBtnMenuInfo := DrawStdButton(RectF(LMidX + LBW * 0.5 + LGap, LBY2, LMidX + LBW * 1.5 + LGap, LBY2 + LBH), '프로그램정보', dbkNeutral, True, 16);
end;

// 타이틀 화면 '프로그램정보' 버튼의 오버레이 다이얼로그: 버전 + 오픈소스 출처 + 저작권
procedure TGostopBoard.DrawProgramInfo;
begin
  var LPanel := DrawStdDialog('프로그램 정보', 480, 360);
  var LY := LPanel.Top + 66;

  DrawLabel(RectF(LPanel.Left, LY, LPanel.Right, LY + 28), '루미고스톱 v1.0.3', TAlphaColors.Gold, 18);
  LY := LY + 40;

  Canvas.Fill.Kind := TBrushKind.Solid;
  Canvas.Fill.Color := $FFE2C674;
  TGostopFonts.Apply(Canvas, 14);
  Canvas.FillText(RectF(LPanel.Left + 28, LY, LPanel.Right - 28, LY + 20), '오픈소스',
    False, 1, [], TTextAlign.Leading, TTextAlign.Center);
  LY := LY + 28;

  // 이름(위 줄) · 출처(아래 줄, 들여쓰기+옅은 색) 두 줄로 표시
  var LOsNames: TArray<string> := ['화투 카드 이미지', '효과음'];
  var LOsSources: TArray<string> := [
    'Wikimedia Commons "Category:Hwatu" (CC BY-SA 4.0)',
    'Kenney.nl Casino / Interface / Impact Audio (CC0)'
  ];

  for var I := 0 to High(LOsNames) do
  begin
    Canvas.Fill.Kind := TBrushKind.Solid;
    Canvas.Fill.Color := $FFEFEFE0;
    TGostopFonts.Apply(Canvas, 12.5);
    Canvas.FillText(RectF(LPanel.Left + 28, LY, LPanel.Right - 28, LY + 18), '- ' + LOsNames[I],
      False, 1, [], TTextAlign.Leading, TTextAlign.Leading);
    LY := LY + 20;

    Canvas.Fill.Color := $FF8A968A;
    TGostopFonts.Apply(Canvas, 11);
    Canvas.FillText(RectF(LPanel.Left + 42, LY, LPanel.Right - 28, LY + 32), LOsSources[I],
      True, 1, [], TTextAlign.Leading, TTextAlign.Leading);
    LY := LY + 36;
  end;

  LY := LY + 8;
  DrawLabel(RectF(LPanel.Left, LY, LPanel.Right, LY + 20), '(c) 2024-2026 copyright in fullbit computing.', $FF8A968A, 12);

  FBtnInfoClose := DrawStdButton(RectF(LPanel.Left + LPanel.Width / 2 - 70, LPanel.Bottom - 54,
    LPanel.Left + LPanel.Width / 2 + 70, LPanel.Bottom - 16), '닫기', dbkNeutral);

  EndStdDialog;
end;

// 참여 자리의 정보 패널 일괄 그리기(선 뽑기·딜·플레이 공용)
procedure TGostopBoard.DrawPanels;
begin
  DrawPlayerPanel(spTop);
  DrawPlayerPanel(spBottom);
  if FPlayerCount >= 3 then
  begin
    DrawPlayerPanel(spLeft);
  end;

  if FPlayerCount >= 4 then
  begin
    DrawPlayerPanel(spRight);
  end;
end;

procedure TGostopBoard.DrawPlayerPanel(const APos: TSeatPos);
begin
  GenerateAvatars;

  // 참가자 식별(선 뽑기·딜 단계 등 게임 생성 전엔 -1)
  var LIdx := -1;
  if FGame <> nil then
  begin
    LIdx := PlayerAtPos(APos);
  end;

  // 라벨: 참가 중이면 이름, 게임 전이면 자리 기본 라벨, 4인 빠진 자리는 선 기준 논리 라벨
  var LLabel := '';
  if LIdx >= 0 then
  begin
    LLabel := FGame.Player(LIdx).Name;
  end
  else
  if FGame = nil then
  begin
    LLabel := SeonPosLabel(APos);
  end
  else
  begin
    LLabel := SeatLabel((Ord(APos) - Ord(FNextStartPos) + 4) mod 4);
  end;

  // 패널 배경
  var LBox := PlayerPanelRect(APos);
  // 현재 차례면 패널을 강조(자리 프레임 대신)
  var LIsCurrent := (FGame <> nil) and (LIdx >= 0) and (LIdx = FGame.Current) and (FGame.Phase = gpPlaying);
  // 관전(4인 빠진 자리)은 회색으로 흐리게
  var LIsSpectator := (FGame <> nil) and (LIdx < 0);
  if LIsCurrent then
  begin
    Canvas.FillRound(LBox, 10, $F03A4A32);          // 현재 차례(밝은 올리브)
    Canvas.StrokeRound(LBox, 10, $FFFFD54A, 3);
  end
  else
  if LIsSpectator then
  begin
    Canvas.FillRound(LBox, 10, $99525A52);          // 관전(회색·흐리게)
    Canvas.StrokeRound(LBox, 10, $22FFFFFF, 1);
  end
  else
  begin
    Canvas.FillRound(LBox, 10, $F0384038);          // 기본(밝은 다크 그린그레이)
    Canvas.StrokeRound(LBox, 10, $50FFFFFF, 1);
  end;

  // 세로형 통일: 아바타 위(가로 중앙) → 정보 아래
  var LAv := SeatAvatarRect(APos);
  var LInfo := RectF(LBox.Left + 8, LAv.Bottom + 6, LBox.Right - 8, LBox.Bottom - 4);

  // 아바타 그리기 — 피 뺏긴 직후 3초는 화남 표정(아바타 액터가 관리, 없으면 평상시로 폴백)
  var LAvDrawn := False;
  var LAvIdx := FSeatAvatar[APos];
  if Assigned(FAvatarPool) and (LAvIdx >= 0) and (LAvIdx < FAvatarPool.Count) then
  begin
    var LBmp: TBitmap := nil;
    if (FAvatarActors[APos].Expression = aeAngry) and Assigned(FAvatarAngryPool) and (LAvIdx < FAvatarAngryPool.Count) then
    begin
      LBmp := FAvatarAngryPool[LAvIdx];
    end;

    if not Assigned(LBmp) then
    begin
      LBmp := FAvatarPool[LAvIdx];
    end;

    Canvas.DrawBitmap(LBmp, RectF(0, 0, LBmp.Width, LBmp.Height), LAv, 1, False);
    LAvDrawn := True;
  end;

  if (not LAvDrawn) and Assigned(FAvatars[APos]) then
  begin
    Canvas.DrawBitmap(FAvatars[APos], RectF(0, 0, FAvatars[APos].Width, FAvatars[APos].Height), LAv, 1, False);
  end;

  // 아바타가 카드 상단을 그대로 채우므로 예전처럼 네모 테두리를 두르지 않는다
  // (테두리가 있으면 '카드 안의 작은 상자'처럼 보인다)

  if APos = spBottom then
  begin
    FMyAvatarRect := LAv;
  end;

  // 정보 스택(LInfo 기준): 이름 → 머니 → 전적 → 배지
  var LIL := LInfo.Left;
  var LIR := LInfo.Right;
  var LIT := LInfo.Top;

  // 선 배지 — 카드 좌상단 코너(정보와 겹치지 않게). 선은 딜(패 돌리기)보다 먼저 정해지므로
  // FGame이 아직 없어도(4인은 협상 완료 전까지 FGame=nil) 셔플·딜·협상 중엔 이미 표시해야 한다.
  if ((FGame <> nil) or FDealing or FShuffling or FNegotiating) and (LogicalSeatOf(APos) = 0) then
  begin
    // 정사각 영역에 원을 그려야 찌그러지지 않는다(예전엔 24x20 둥근 사각형이라 타원처럼 보였다)
    const SEON_D = 24.0;
    var LSB := RectF(LBox.Left + 3, LBox.Top + 3, LBox.Left + 3 + SEON_D, LBox.Top + 3 + SEON_D);
    Canvas.FillCircle(LSB, $FFD32F2F);
    Canvas.StrokeCircle(LSB, TAlphaColors.White, 1);
    DrawLabel(LSB, '선', TAlphaColors.White, 12);
  end;

  // 1) 이름 — 전체 폭 사용(잘림 방지)
  Canvas.Fill.Color := TAlphaColors.White;
  TGostopFonts.Apply(Canvas, 13);
  Canvas.FillText(RectF(LIL, LIT + 0, LIR - 2, LIT + 20), LLabel,
    False, 1, [], TTextAlign.Leading, TTextAlign.Center);

  // 2) 보유머니 — 우측 정렬
  Canvas.Fill.Color := TAlphaColors.White;
  TGostopFonts.Apply(Canvas, 13);
  Canvas.FillText(RectF(LIL, LIT + 21, LIR - 2, LIT + 39),
    Format('%s원', [FormatFloat('#,##0', FMoney[APos])]), False, 1, [], TTextAlign.Trailing, TTextAlign.Center);

  // 3) 전적 — 승률(%) 표시, 우측 정렬 (운 별점은 숨김 — 내부 로직으로만 작동)
  var LTotalGames := FWins[APos] + FLosses[APos];
  var LRecordText: string;
  if LTotalGames > 0 then
  begin
    var LWinRate := Round(FWins[APos] / LTotalGames * 100);
    LRecordText := Format('%d승 %d패 (%d%%)', [FWins[APos], FLosses[APos], LWinRate]);
  end
  else
  begin
    LRecordText := Format('%d승 %d패', [FWins[APos], FLosses[APos]]);
  end;

  Canvas.Fill.Color := $FFB8C4B8;
  TGostopFonts.Apply(Canvas, 11);
  Canvas.FillText(RectF(LIL, LIT + 40, LIR - 2, LIT + 55),
    LRecordText, False, 1, [], TTextAlign.Trailing, TTextAlign.Center);

  // 4) 이번 게임 정보: 점수·고·흔들 배지 / 관전 / 게임 전엔 생략
  if (FGame <> nil) and (LIdx < 0) then
  begin
    Canvas.Fill.Color := $FF8A968A;
    TGostopFonts.Apply(Canvas, 12);
    Canvas.FillText(RectF(LIL, LIT + 57, LIR, LIT + 77), '관전',
      False, 1, [], TTextAlign.Leading, TTextAlign.Center);
    Exit;
  end;

  if (LIdx < 0) or (not Assigned(FEngine)) then
  begin
    Exit;
  end;

  var LScore := FEngine.ScoreOf(LIdx).Total;
  var LGo := FGame.Player(LIdx).GoCount;
  var LShake := FGame.Player(LIdx).ShakeCount;
  var LBX := LIL;
  var LBY := LIT + 57;

  // 점수 배지(항상 표시)
  Canvas.Fill.Color := $FF37474F;
  Canvas.FillRect(RectF(LBX, LBY, LBX + 26, LBY + 20), 5, 5,
    [TCorner.TopLeft, TCorner.TopRight, TCorner.BottomLeft, TCorner.BottomRight], 1);
  DrawLabel(RectF(LBX, LBY, LBX + 26, LBY + 20), Format('%d점', [LScore]), $FFFFE082, 11);
  LBX := LBX + 28;

  // 고 배지
  if LGo > 0 then
  begin
    Canvas.Fill.Color := $FFB35900;
    Canvas.FillRect(RectF(LBX, LBY, LBX + 20, LBY + 20), 5, 5,
      [TCorner.TopLeft, TCorner.TopRight, TCorner.BottomLeft, TCorner.BottomRight], 1);
    DrawLabel(RectF(LBX, LBY, LBX + 20, LBY + 20), Format('%d고', [LGo]), TAlphaColors.White, 11);
    LBX := LBX + 22;
  end;

  // 흔들기 배지
  if LShake > 0 then
  begin
    Canvas.Fill.Color := $FF8E2430;
    Canvas.FillRect(RectF(LBX, LBY, LBX + 24, LBY + 20), 5, 5,
      [TCorner.TopLeft, TCorner.TopRight, TCorner.BottomLeft, TCorner.BottomRight], 1);
    DrawLabel(RectF(LBX, LBY, LBX + 24, LBY + 20), Format('흔%d', [LShake]), TAlphaColors.White, 11);
  end;
end;

procedure TGostopBoard.DrawOpponent(const AGameIndex: Integer; const APos: TSeatPos; const ARegion: TRectF);
begin
  var CS := CardSize;
  var LBackW := CS.Width * 0.5;
  var LBackH := CS.Height * 0.5;
  var LHand := RState.Player(AGameIndex).Hand;
  var LCaptured := RState.Player(AGameIndex).Captured;
  var LHandCount := LHand.Count;
  var LHandStep := LBackW * 0.5;
  var LPanel := PlayerPanelRect(APos);

  case APos of
    spTop, spBottom:
      begin
        // 가로형. P1(위)=패널 오른쪽→카드 왼쪽 / P3자리(아래 관전)=패널 왼쪽→카드 오른쪽
        var LCardsL: Single;
        var LCardsR: Single;
        if APos = spTop then
        begin
          LCardsL := ARegion.Left + 6;
          LCardsR := LPanel.Left - 14;
        end
        else
        begin
          LCardsL := LPanel.Right + 14;
          LCardsR := ARegion.Right - 6;
        end;

        // 손패(뒷면) Y — P1(위)은 자리 맨 위, P3(아래)는 자리 맨 아래
        var LHandY := ARegion.Bottom - LBackH - 8;
        if APos = spTop then
        begin
          LHandY := ARegion.Top + 8;
        end;

        // 먹은패 배치값은 CapturedFanSpec 한 곳에서만 계산한다(좌표 질의와 어긋나지 않도록)
        var LSpecH := CapturedFanSpec(APos, False);

        var LSkipH := -1;
        if FGukjinMoveActive and (FGukjinMoveSeat = APos) then
        begin
          LSkipH := FGukjinMovePileIndex;
        end;

        DrawCapturedFan(LCaptured, LSpecH.A, LSpecH.B, LSpecH.C, LSpecH.Scale, LSpecH.AnchorEnd,
          FGukjinAsPi[APos], LSkipH);

        // 손패(뒷면) 그리기 — 가로 부채. P1은 우측(패널쪽) 앵커
        var LStep := LHandStep;
        if LHandCount > 1 then
        begin
          var LMax := (LCardsR - LCardsL - LBackW) / (LHandCount - 1);
          if LMax < LStep then
          begin
            LStep := LMax;
          end;
        end;

        var LHandX0 := LCardsL;
        if APos = spTop then
        begin
          LHandX0 := LCardsR - (LBackW + (LHandCount - 1) * LStep);
          if LHandX0 < LCardsL then
          begin
            LHandX0 := LCardsL;
          end;
        end;

        for var I := 0 to LHandCount - 1 do
        begin
          DrawCardRotated(LHandX0 + LBackW / 2 + I * LStep, LHandY + LBackH / 2, LBackW, LBackH, 0, '', True);
        end;
      end;

    spLeft, spRight:
      begin
        // 세로형. P2(왼)=패널 위→카드 아래(90°) / P4(오른)=패널 아래→카드 위(270°)
        var LAng := 90.0;
        var LTop: Single;
        var LBot: Single;
        if APos = spLeft then
        begin
          LTop := LPanel.Bottom + 14;
          LBot := ARegion.Bottom - 6;
        end
        else
        begin
          LAng := 270.0;
          LTop := ARegion.Top + 6;
          LBot := LPanel.Top - 14;
        end;

        // 손패(뒷면) 열. P2(왼)는 손패가 바깥쪽(왼쪽), P4(오른)는 바깥쪽(오른쪽).
        // 먹은패 열 X 는 CapturedFanSpec 이 준다.
        var LColW := ARegion.Right - ARegion.Left;
        var LXHand := ARegion.Left + LColW * 0.30;
        if APos = spRight then
        begin
          LXHand := ARegion.Left + LColW * 0.70;
        end;

        // 손패(뒷면) 세로 부채
        var LStep := LHandStep;
        if LHandCount > 1 then
        begin
          var LMax := (LBot - LTop - LBackW) / (LHandCount - 1);
          if LMax < LStep then
          begin
            LStep := LMax;
          end;
        end;

        // P4(오른)은 패널(아래)에 붙여 아래 앵커
        var LHandY0 := LTop;
        if APos = spRight then
        begin
          LHandY0 := LBot - (LBackW + (LHandCount - 1) * LStep);
          if LHandY0 < LTop then
          begin
            LHandY0 := LTop;
          end;
        end;

        for var I := 0 to LHandCount - 1 do
        begin
          DrawCardRotated(LXHand, LHandY0 + LBackW / 2 + I * LStep, LBackW, LBackH, LAng, '', True);
        end;

        // 먹은패 세로 촘촘 부채. P4는 아래(패널쪽) 앵커 + 그룹 순서 반전(광이 맨 아래)
        // 배치값은 CapturedFanSpec 한 곳에서만 계산한다
        var LSpecV := CapturedFanSpec(APos, False);

        var LSkipV := -1;
        if FGukjinMoveActive and (FGukjinMoveSeat = APos) then
        begin
          LSkipV := FGukjinMovePileIndex;
        end;

        DrawCapturedFanV(LCaptured, LSpecV.A, LSpecV.B, LSpecV.C, LSpecV.Scale, LSpecV.Angle,
          LSpecV.AnchorEnd, LSpecV.Reverse, LSpecV.BadgeDir, FGukjinAsPi[APos], LSkipV);
      end;
  end;
end;

function TGostopBoard.FloorLayout(const AFloor: TList<THwatuCard>): TArray<TRectF>;
begin
  var LCount := AFloor.Count;
  SetLength(Result, LCount);
  if LCount = 0 then
  begin
    Exit;
  end;

  var CS := CardSize;
  var LRegion := CenterRegion;
  var LOrder := SortedIndices(AFloor);

  // 월별 개수 — 같은 월이 3장 이상일 때만 포갠다(2장은 그냥 벌려 그림)
  var LMonthCount := TDictionary<Integer, Integer>.Create;
  try
    for var LCard in AFloor do
    begin
      var LC := 0;
      LMonthCount.TryGetValue(LCard.Month, LC);
      LMonthCount.AddOrSetValue(LCard.Month, LC + 1);
    end;

    var LStackStep := CS.Width * 0.26;   // 3장+ 겹침 간격
    var LColStep := CS.Width + 6;        // 벌림 간격
    var LXs: TArray<Single>;
    var LYo: TArray<Single>;
    SetLength(LXs, LCount);
    SetLength(LYo, LCount);

    var LCurX := 0.0;
    var LGroupPos := 0;
    for var D := 0 to LCount - 1 do
    begin
      if D = 0 then
      begin
        LCurX := 0;
        LGroupPos := 0;
      end
      else
      begin
        var LMonth := AFloor[LOrder[D]].Month;
        // 뒤집기 선택 대기 중엔 후보를 명확히 고르도록 겹치지 않고 펼친다
        var LStack := (LMonth = AFloor[LOrder[D - 1]].Month) and (LMonthCount[LMonth] >= 3) and (not FFlipChoosing);
        if LStack then
        begin
          LCurX := LCurX + LStackStep;
          Inc(LGroupPos);
        end
        else
        begin
          LCurX := LCurX + LColStep;
          LGroupPos := 0;
        end;
      end;

      LXs[D] := LCurX;
      LYo[D] := LGroupPos * 4;
    end;

    var LFloorW := LXs[LCount - 1] + CS.Width;
    if LFloorW > LRegion.Width * 0.72 then
    begin
      var LScale := (LRegion.Width * 0.72) / LFloorW;
      for var D := 0 to LCount - 1 do
      begin
        LXs[D] := LXs[D] * LScale;
      end;

      LFloorW := LXs[LCount - 1] + CS.Width;
    end;

    // 뒷패 폭까지 고려해 가운데 정렬
    var LGroupW := LFloorW;
    if RState.Stock.Count > 0 then
    begin
      LGroupW := LGroupW + CS.Width * 0.5 + CS.Width;
    end;

    var LStartX := (LRegion.Left + LRegion.Right) / 2 - LGroupW / 2;
    var LY := (LRegion.Top + LRegion.Bottom) / 2 - CS.Height / 2;
    for var D := 0 to LCount - 1 do
    begin
      Result[LOrder[D]] := RectF(LStartX + LXs[D], LY + LYo[D], LStartX + LXs[D] + CS.Width, LY + LYo[D] + CS.Height);
    end;
  finally
    LMonthCount.Free;
  end;
end;

function TGostopBoard.CardCenterInFloor(const AFloor: TList<THwatuCard>; const AAssetId: string): TPointF;
begin
  var LLayout := FloorLayout(AFloor);
  for var I := 0 to AFloor.Count - 1 do
  begin
    if AFloor[I].AssetId = AAssetId then
    begin
      Exit(PointF((LLayout[I].Left + LLayout[I].Right) / 2, (LLayout[I].Top + LLayout[I].Bottom) / 2));
    end;
  end;

  var LC := CenterRegion;
  Result := PointF((LC.Left + LC.Right) / 2, (LC.Top + LC.Bottom) / 2);
end;

function TGostopBoard.IsCapturedAsset(const AAssetId: string): Boolean;
begin
  for var LCard in FAnimCaptured do
  begin
    if LCard.AssetId = AAssetId then
    begin
      Exit(True);
    end;
  end;

  Result := False;
end;

function TGostopBoard.FloorMonthCenter(const AMonth: Integer): TPointF;
begin
  // 표시 클론 바닥에서 같은 월 카드(짝)의 위치 — 그 위에 얹기 위함
  for var LCard in FDisplay.Floor do
  begin
    if LCard.Month = AMonth then
    begin
      Exit(CardCenterInFloor(FDisplay.Floor, LCard.AssetId));
    end;
  end;

  var LC := CenterRegion;
  Result := PointF((LC.Left + LC.Right) / 2, (LC.Top + LC.Bottom) / 2);
end;

procedure TGostopBoard.DrawCenter(const ARegion: TRectF);
begin
  var CS := CardSize;
  var LFloor := RState.Floor;
  FFloorRects.Clear;
  FFloorIndexMap.Clear;

  var LLayout := FloorLayout(LFloor);
  var LMaxRight := ARegion.Left;
  var LY := (ARegion.Top + ARegion.Bottom) / 2 - CS.Height / 2;

  // 바닥 카드(정렬 순으로 그려 겹침 z-order 유지)
  if LFloor.Count > 0 then
  begin
    var LOrder := SortedIndices(LFloor);
    for var D := 0 to LFloor.Count - 1 do
    begin
      var LRealIdx := LOrder[D];
      var LR := LLayout[LRealIdx];
      FFloorRects.Add(LR);
      FFloorIndexMap.Add(LRealIdx);
      DrawFront(LR, LFloor[LRealIdx].AssetId);
      if LR.Right > LMaxRight then
      begin
        LMaxRight := LR.Right;
      end;

      var LHighlight := FChoosing and (LFloor[LRealIdx].Month = FChooseMonth);
      if FFlipChoosing and ((LFloor[LRealIdx].AssetId = FFlipOptAssets[0]) or (LFloor[LRealIdx].AssetId = FFlipOptAssets[1])) then
      begin
        LHighlight := True;
      end;

      if LHighlight then
      begin
        Canvas.StrokeRound(LR, 4, TAlphaColors.Yellow, 4);
      end;
    end;
  end;

  // 뒷패 — 바닥 오른쪽에 인접, 여러 장 겹쳐 두께 표현
  if RState.Stock.Count > 0 then
  begin
    var LStockX: Single;
    if LFloor.Count > 0 then
    begin
      LStockX := LMaxRight + CS.Width * 0.5;
    end
    else
    begin
      LStockX := (ARegion.Left + ARegion.Right) / 2 - CS.Width / 2;
    end;

    var LLayers := Min(RState.Stock.Count, 6);
    for var I := LLayers - 1 downto 0 do
    begin
      var LOff := I * 2.0;
      DrawBack(RectF(LStockX + LOff, LY + LOff, LStockX + LOff + CS.Width, LY + LOff + CS.Height));
    end;
  end;
end;

procedure TGostopBoard.DrawNegotiation;
begin
  // 항상 4자리 구조 영역
  for var LP := spTop to spRight do
  begin
    DrawRegion(SeatRegion(LP), False);
  end;

  if FNegIsSell then
  begin
    // 광팔기 결정(P4)은 기존 레이아웃 유지: 내 손패 + 광 패 흔들기 + 하단(중앙) 버튼
    if (FTable4 <> nil) and (FTable4.PlayerCount = 4) then
    begin
      var LHandRegion := RectF(Width * 0.05, Height * 0.68, Width * 0.95, Height * 0.93);
      DrawLabel(RectF(0, Height * 0.63, Width, Height * 0.67), '내 손패', $FFD8E0D0, 15);
      DrawHandList(FTable4.Hand(FHumanLogical), LHandRegion, False);
    end;

    if FTable4 <> nil then
    begin
      var LHand := FTable4.Hand(FHumanLogical);
      // 광+조커 + 실제 보유한 족보(고도리·초단 등) 카드까지 표시
      var LGwang := TFourPlayer.SaleCards(LHand, CfgScore);

      DrawLabel(RectF(0, Height * 0.06, Width, Height * 0.10), '광 팔기', TAlphaColors.Gold, 20);

      var CS := CardSize;
      var LGCount := TFourPlayer.GwangCount(LHand, CfgScore);
      if Length(LGwang) > 0 then
      begin
        var LTotW := CS.Width + (Length(LGwang) - 1) * CS.Width * 1.12;
        var LStartX := Width / 2 - LTotW / 2;
        var LGY := Height * 0.12 + CS.Height / 2;
        for var I := 0 to High(LGwang) do
        begin
          // 카드마다 위상을 어긋나게 줘 좌우로 흔드는(shake) 느낌 — 수평 이동 강조
          var LPh := FNegAnimPhase + I * 0.9;
          var LDX := Sin(LPh) * CS.Width * 0.18;   // 좌우 흔들림(수평)
          var LAng := Sin(LPh) * 3.0;              // 미세 회전
          DrawCardRotated(LStartX + I * CS.Width * 1.12 + CS.Width / 2 + LDX, LGY, CS.Width, CS.Height, LAng, LGwang[I].AssetId, False);
        end;
      end;

      DrawLabel(RectF(0, Height * 0.12 + CS.Height + 6, Width, Height * 0.12 + CS.Height + 34),
        Format('%s·%s에게서 각 %s원', [SeatLabel(1), SeatLabel(2),
          FormatFloat('#,##0', LGCount * GWANG_UNIT_PRICE * FConfig.MoneyPerPoint)]),
        TAlphaColors.White, 16);
    end;

    var LSellBtnW := 140.0;
    var LSellBtnH := 48.0;
    var LSellGap := 30.0;
    var LSellCX := Width / 2;
    var LSellBtnY := Height * 0.60;
    FBtnJoin := DrawStdButton(RectF(LSellCX - LSellBtnW - LSellGap / 2, LSellBtnY, LSellCX - LSellGap / 2, LSellBtnY + LSellBtnH), '광팔기', dbkPrimary);
    FBtnGiveUp := DrawStdButton(RectF(LSellCX + LSellGap / 2, LSellBtnY, LSellCX + LSellGap / 2 + LSellBtnW, LSellBtnY + LSellBtnH), '안팔기', dbkDanger);
    Exit;
  end;

  // 참가/포기: 표준 다이얼로그 — 바닥패는 1장만 공개, 나머지는 뒷면(4인 맞고 정통 룰) + 하단 버튼
  if (FTable4 <> nil) and (FTable4.Floor.Count > 0) then
  begin
    var CS := CardSize;
    var LC := CenterRegion;
    var LCX := (LC.Left + LC.Right) / 2;
    var LCY := (LC.Top + LC.Bottom) / 2;

    // 공개 안 된 나머지는 살짝 겹쳐 쌓인 뒷패로(뒷패와 같은 표현)
    var LHiddenCount := FTable4.Floor.Count - 1;
    for var I := LHiddenCount downto 1 do
    begin
      var LOff := I * 3.0;
      DrawBack(RectF(LCX - CS.Width / 2 + LOff, LCY - CS.Height / 2 + LOff,
        LCX + CS.Width / 2 + LOff, LCY + CS.Height / 2 + LOff));
    end;

    DrawFront(RectF(LCX - CS.Width / 2, LCY - CS.Height / 2, LCX + CS.Width / 2, LCY + CS.Height / 2), FTable4.Floor[0].AssetId);
  end;

  var LPanelW := Min(Width * 0.86, 760.0);
  var LPanelH := 300.0;
  var LPanel := DrawStdDialog('이번 판, 붙으시겠습니까?', LPanelW, LPanelH);

  if (FTable4 <> nil) and (FTable4.PlayerCount = 4) then
  begin
    var LHand := FTable4.Hand(FHumanLogical);
    var LSaleCards := TFourPlayer.SaleCards(LHand, CfgScore);
    var LRaiseIds: TArray<string>;
    for var LSaleCard in LSaleCards do
    begin
      LRaiseIds := LRaiseIds + [LSaleCard.AssetId];
    end;

    var LHandRegion := RectF(LPanel.Left + 24, LPanel.Top + 60, LPanel.Right - 24, LPanel.Bottom - 88);
    DrawHandList(LHand, LHandRegion, False, LRaiseIds);
  end;

  var LBtnW := 140.0;
  var LBtnH := 48.0;
  var LGap := 30.0;
  var LCX := (LPanel.Left + LPanel.Right) / 2;
  var LBtnY := LPanel.Bottom - LBtnH - 18;
  FBtnJoin := DrawStdButton(RectF(LCX - LBtnW - LGap / 2, LBtnY, LCX - LGap / 2, LBtnY + LBtnH), '참가', dbkPrimary);
  FBtnGiveUp := DrawStdButton(RectF(LCX + LGap / 2, LBtnY, LCX + LGap / 2 + LBtnW, LBtnY + LBtnH), '포기', dbkDanger);

  EndStdDialog;
end;

// 정산 줄에 표시할 아바타 비트맵. 승자=환호, 패자=슬픔(없으면 평상시로 폴백). 인덱스 없으면 nil
// 정산 줄 아바타: 승자=환호, 박(피박/광박/고박/멍박/쇼당독박) 당한 패자=화남, 그 외 패자=슬픔.
// 상태 이미지가 없으면 화남→슬픔→평상시 순으로 폴백.
function TGostopBoard.ResultAvatarBitmap(const AAvatarIdx: Integer; const AIsWinner, AIsPenalized: Boolean): TBitmap;
begin
  Result := nil;
  if AAvatarIdx < 0 then
  begin
    Exit;
  end;

  LoadAvatarPool;
  if AIsWinner then
  begin
    if Assigned(FAvatarCheerPool) and (AAvatarIdx < FAvatarCheerPool.Count) then
    begin
      Result := FAvatarCheerPool[AAvatarIdx];
    end;
  end
  else
  begin
    if AIsPenalized and Assigned(FAvatarAngryPool) and (AAvatarIdx < FAvatarAngryPool.Count) then
    begin
      Result := FAvatarAngryPool[AAvatarIdx];
    end;

    if (not Assigned(Result)) and Assigned(FAvatarSadPool) and (AAvatarIdx < FAvatarSadPool.Count) then
    begin
      Result := FAvatarSadPool[AAvatarIdx];
    end;
  end;

  if (not Assigned(Result)) and Assigned(FAvatarPool) and (AAvatarIdx < FAvatarPool.Count) then
  begin
    Result := FAvatarPool[AAvatarIdx];   // 상태 이미지가 없으면 평상시 아바타로 폴백
  end;
end;

// 승패와 무관한 다이얼로그(기리·패선택 등)에서 쓰는 평상시(웃는) 아바타. 정산 결과와 무관하므로
// ResultAvatarBitmap(승자=환호/패자=슬픔)을 쓰면 안 되고, 항상 기본 아바타를 보여준다
function TGostopBoard.NormalAvatarBitmap(const AAvatarIdx: Integer): TBitmap;
begin
  Result := nil;
  if AAvatarIdx < 0 then
  begin
    Exit;
  end;

  LoadAvatarPool;
  if Assigned(FAvatarPool) and (AAvatarIdx < FAvatarPool.Count) then
  begin
    Result := FAvatarPool[AAvatarIdx];
  end;
end;

// 게임종료 팝업 '새게임' 처리(버튼 클릭·자동진행 공용). 매치 이어가기(머니·전적 유지).
// 오링된 상대가 있으면 새 도전자 등장 연출 후 진행
procedure TGostopBoard.GameOverContinue;
begin
  FGameOverTimer.Enabled := False;
  var LStartPos := spTop;
  if FGame.Winner >= 0 then
  begin
    LStartPos := PhysicalPos(FGame.Winner);
  end;

  BeginSeatReplacement(LStartPos);
end;

// 게임종료 팝업 '중지'/'타이틀로' 처리(버튼 클릭·자동진행 공용)
procedure TGostopBoard.GameOverQuit;
begin
  FGameOverTimer.Enabled := False;

  // 휴먼이 오링된 채로 나가는 경우: 대기실(타이틀)로 나가며 시드머니를 리필하고
  // 그 사실을 개인 이력에 기록(오링된 상대 캐릭터 교체는 AI 쪽 별도 로직이라 여기선 상관없음)
  if (not FSpectator) and (FMoney[spBottom] <= 0) then
  begin
    FMoney[spBottom] := FConfig.SeedMoney;
    FConfig.RefillCount := FConfig.RefillCount + 1;
    SaveSettings;
  end;

  ClearGame;
  FStatus := '새 게임을 시작하세요';
  Repaint;
  if Assigned(FOnStateChanged) then
  begin
    FOnStateChanged(Self);
  end;
end;

// 게임종료 팝업 방치 카운트다운. 다 되면 자동진행(오링된 휴먼이면 타이틀로, 아니면 새게임)
procedure TGostopBoard.GameOverTimerTick(Sender: TObject);
begin
  if FPaused then
  begin
    // 멈춰 있는 동안은 시간이 흐르지 않게 기준점만 현재로 당겨 둔다
    FGameOverLastSec := FGameOverSw.Elapsed.TotalSeconds;
    Exit;
  end;

  if (FGame = nil) or (FGame.Phase <> gpFinished) then
  begin
    FGameOverTimer.Enabled := False;
    Exit;
  end;

  // 게임속도(FGameSpeed)와 무관하게 절대 초로 흘러야 함(속도를 올려도 다음 판까지 기다리는
  // 시간이 짧아지지 않게) — 다른 애니메이션과 달리 FGameSpeed를 곱하지 않는다.
  //
  // 타이머 간격을 그대로 빼면 안 된다. FMX 타이머는 UI가 바쁠 때(AI 연산·리페인트) 틱을
  // 흘려버려서, 16ms씩 누적하면 5초 카운트다운이 실제로는 그보다 오래 걸린다.
  // 스톱워치로 실제 경과 시간을 재서 빼야 표시되는 초가 진짜 초가 된다.
  var LNow := FGameOverSw.Elapsed.TotalSeconds;
  FGameOverRemain := FGameOverRemain - (LNow - FGameOverLastSec);
  FGameOverLastSec := LNow;
  if FGameOverRemain > 0 then
  begin
    Repaint;
    Exit;
  end;

  var LHumanBroke := (not FSpectator) and (FHumanIndex >= 0) and (FMoney[spBottom] <= 0);
  if LHumanBroke then
  begin
    GameOverQuit;
  end
  else
  begin
    GameOverContinue;
  end;
end;

procedure TGostopBoard.DrawGameOver;
begin
  var LN := Length(FResultRows);
  if LN = 0 then
  begin
    Exit;
  end;

  // 중앙 오버레이 패널 — 줄마다 큰 아바타(승자=환호/패자=슬픔) + 박 뱃지 + 우측정렬 금액 + 다음게임 버튼
  // 패널 폭은 창 크기에 비례시키지 않고 콘텐츠에 맞춘 고정폭(다른 표준 다이얼로그들과 동일한 방식)
  var LRowH := 108.0;
  var LAvSize := 84.0;
  var LWinAvSize := 100.0;
  var LAmountColW := 130.0;   // 금액은 패널 오른쪽 끝이 아니라 이 고정폭 안에서만 우측 정렬(간격 과다 방지)
  var LBtnH := 44.0;
  var LTopPad := 20.0;
  if FResultTitle <> '' then
  begin
    LTopPad := 52.0;   // 판돈 배수 제목이 있으면 그만큼 위쪽 여백 확보
  end;

  // 자동 진행 카운트다운 표시 영역 — 실제로 뜨기 전(머니 카운트 애니메이션 중)에도 항상 자리를
  // 확보해 둔다. 그렇지 않으면 카운트다운이 나타나는 순간 패널 높이(=DrawStdDialog의 팝인 키)가
  // 바뀌어 정산창이 닫혔다 다시 열리는 것처럼 튕겨 보인다.
  var LCountdownH := 56.0;

  // 승자 줄은 점수 내역 뱃지(광(3)·열끗(3)·청단(3) 등)가 있으면 한 줄 더 필요해 그만큼 늘림
  const SCORE_ROW_EXTRA_H = 32.0;
  var LRowHeights: TArray<Single>;
  SetLength(LRowHeights, LN);
  var LRowsTotalH := 0.0;
  for var I := 0 to LN - 1 do
  begin
    LRowHeights[I] := LRowH;
    if FResultRows[I].IsWinner and (Length(FResultRows[I].ScoreParts) > 0) then
    begin
      LRowHeights[I] := LRowH + SCORE_ROW_EXTRA_H;
    end;

    LRowsTotalH := LRowsTotalH + LRowHeights[I];
  end;

  var LPanelH := LTopPad + LRowsTotalH + 18 + LCountdownH + LBtnH + 18;
  var LPanel := DrawStdDialog(FResultTitle, 480.0, LPanelH);
  var LCX := (LPanel.Left + LPanel.Right) / 2;
  var LAmountR0 := LPanel.Right - 18 - LAmountColW;

  var LY := LPanel.Top + LTopPad;
  for var I := 0 to LN - 1 do
  begin
    var LRow := FResultRows[I];
    var LAvSz := LAvSize;
    if LRow.IsWinner then
    begin
      LAvSz := LWinAvSize;
    end;

    var LBmp := ResultAvatarBitmap(LRow.AvatarIdx, LRow.IsWinner, Length(LRow.Flags) > 0);
    var LTextLeft := LPanel.Left + 18;
    if Assigned(LBmp) then
    begin
      var LAvR := RectF(LPanel.Left + 16, LY + (LRowH - LAvSz) / 2,
        LPanel.Left + 16 + LAvSz, LY + (LRowH - LAvSz) / 2 + LAvSz);
      Canvas.DrawBitmap(LBmp, RectF(0, 0, LBmp.Width, LBmp.Height), LAvR, 1, False);
      LTextLeft := LAvR.Right + 14;
    end;

    if LRow.HasAmount then
    begin
      // 박 뱃지(아바타 오른쪽, 둥근 라벨로 나열)
      var LBadgeH := 24.0;
      var LBadgeY := LY + (LRowH - LBadgeH) / 2;
      var LBadgeX := LTextLeft;
      TGostopFonts.Apply(Canvas, 13);
      for var LFlag in LRow.Flags do
      begin
        var LBadgeW := Canvas.TextWidth(LFlag) + 20;
        var LBadgeR := RectF(LBadgeX, LBadgeY, LBadgeX + LBadgeW, LBadgeY + LBadgeH);
        Canvas.FillRound(LBadgeR, LBadgeH / 2, $FF8E2430);
        DrawLabel(LBadgeR, LFlag, TAlphaColors.White, 13);
        LBadgeX := LBadgeR.Right + 6;
      end;

      // 금액 두 줄(천단위 콤마, 고정폭 금액란 안에서 우측 정렬):
      // 위=보유한 돈(크게, 강조), 아래=이번 판 손익(±N원만 — "이번 판" 접두어는 군더더기라 생략)
      var LAmtR := RectF(LAmountR0 - 20, LY, LPanel.Right - 18, LY + LRowH);
      var LBalR := RectF(LAmtR.Left, LAmtR.Top + LRowH * 0.10, LAmtR.Right, LAmtR.Top + LRowH * 0.58);
      var LNetR := RectF(LAmtR.Left, LBalR.Bottom, LAmtR.Right, LAmtR.Bottom - LRowH * 0.06);

      var LBalColor := TAlphaColors.White;
      var LBalSize := 24.0;
      if LRow.IsWinner then
      begin
        LBalColor := TAlphaColors.Gold;
        LBalSize := 27.0;
      end;

      // 머니 카운트 애니메이션: 승자는 백단위로 차오르고 패자는 백단위로 깎여내려감(모든 줄이
      // FMoneyCountT 하나를 공유해 동시에 시작·종료됨). 진행 중엔 100원 단위로 스냅해서 보여준다.
      var LDisplayBalance := LRow.BalanceAfter;
      if FMoneyCountT < 1 then
      begin
        var LEase := 1 - Power(1 - FMoneyCountT, 3);
        var LBefore := LRow.BalanceAfter - LRow.Amount;
        LDisplayBalance := LBefore + Round(LRow.Amount * LEase / 100) * 100;
      end;

      Canvas.Fill.Color := LBalColor;
      TGostopFonts.Apply(Canvas, LBalSize);
      Canvas.FillText(LBalR, Format('%s원', [FormatFloat('#,##0', LDisplayBalance)]),
        False, 1, [], TTextAlign.Trailing, TTextAlign.Center);

      var LNetSign := '';
      if LRow.Amount > 0 then
      begin
        LNetSign := '+';
      end;

      var LNetColor := $FFB8C4B8;   // 무승부·0원 등 중립 톤
      if LRow.Amount > 0 then
      begin
        LNetColor := $FF7ED9A0;     // 이득(연한 초록)
      end
      else
      if LRow.Amount < 0 then
      begin
        LNetColor := $FFE08080;     // 손실(연한 빨강)
      end;

      Canvas.Fill.Color := LNetColor;
      TGostopFonts.Apply(Canvas, 14);
      Canvas.FillText(LNetR, Format('%s%s원', [LNetSign, FormatFloat('#,##0', LRow.Amount)]),
        False, 1, [], TTextAlign.Trailing, TTextAlign.Center);
    end
    else
    begin
      var LTextColor := TAlphaColors.White;
      var LFontSize := 17.0;
      if LRow.IsWinner then
      begin
        LTextColor := TAlphaColors.Gold;
        LFontSize := 21.0;
      end;

      DrawLabel(RectF(LTextLeft, LY, LPanel.Right - 18, LY + LRowH), LRow.Text, LTextColor, LFontSize);
    end;

    // 승자 점수 내역(광(3)·열끗(3)·청단(3) 등) — 박 뱃지와 같은 둥근 뱃지 스타일, 아바타 아래 별도 줄
    if LRow.IsWinner and (Length(LRow.ScoreParts) > 0) then
    begin
      var LScoreBadgeH := 24.0;
      var LScoreBadgeY := LY + LRowH + (SCORE_ROW_EXTRA_H - LScoreBadgeH) / 2;
      var LScoreBadgeX := LPanel.Left + 18;
      TGostopFonts.Apply(Canvas, 13);
      for var LPart in LRow.ScoreParts do
      begin
        var LScoreBadgeW := Canvas.TextWidth(LPart) + 20;
        var LScoreBadgeR := RectF(LScoreBadgeX, LScoreBadgeY, LScoreBadgeX + LScoreBadgeW, LScoreBadgeY + LScoreBadgeH);
        Canvas.FillRound(LScoreBadgeR, LScoreBadgeH / 2, $FF2E5F4E);
        Canvas.StrokeRound(LScoreBadgeR, LScoreBadgeH / 2, $FF5FA98A, 1);
        DrawLabel(LScoreBadgeR, LPart, TAlphaColors.White, 13);
        LScoreBadgeX := LScoreBadgeR.Right + 6;
      end;

      // 합계 점수(고·박 적용 전) — 다른 뱃지들과 구분되도록 금색으로 강조
      var LTotalText := Format('합계(%d)', [LRow.ScoreTotal]);
      var LTotalBadgeW := Canvas.TextWidth(LTotalText) + 20;
      var LTotalBadgeR := RectF(LScoreBadgeX, LScoreBadgeY, LScoreBadgeX + LTotalBadgeW, LScoreBadgeY + LScoreBadgeH);
      Canvas.FillRound(LTotalBadgeR, LScoreBadgeH / 2, $FF6B5610);
      Canvas.StrokeRound(LTotalBadgeR, LScoreBadgeH / 2, TAlphaColors.Gold, 1);
      DrawLabel(LTotalBadgeR, LTotalText, TAlphaColors.Gold, 13);
    end;

    LY := LY + LRowHeights[I];
  end;

  // 자동 진행 카운트다운(가운데, 숫자가 크게 나타났다가 작아지는 애니메이션 — 매초 반복)
  if FGameOverTimer.Enabled then
  begin
    var LCdCY := LY + LCountdownH / 2 - 6;
    var LSecLeft := Trunc(FGameOverRemain) + 1;
    if LSecLeft < 1 then
    begin
      LSecLeft := 1;
    end;

    var LLocalT := Frac(FGameOverRemain);
    if FGameOverRemain <= 0 then
    begin
      LLocalT := 0;
    end;

    var LScale := 1.0 + LLocalT * 0.9;   // 매초 시작(1.9배 큼) → 그 초가 끝날수록(1.0배) 작아짐
    var LBaseR := 20.0;
    var LR := LBaseR * LScale;
    var LCircle := RectF(LCX - LR, LCdCY - LR, LCX + LR, LCdCY + LR);
    Canvas.FillCircle(LCircle, $302E7D32);
    Canvas.StrokeCircle(LCircle, $FFFFD54A, 2);
    DrawLabel(LCircle, IntToStr(LSecLeft), TAlphaColors.White, 16 * LScale);
    DrawLabel(RectF(LCX - 100, LCdCY + LBaseR + 6, LCX + 100, LCdCY + LBaseR + 22), '자동 진행까지', $FF8A968A, 11);
  end;

  LY := LY + LCountdownH;   // 카운트다운이 아직 안 떠도 자리는 항상 확보(패널 크기 고정)

  // 버튼: 내가 파산했으면 타이틀로 복귀만, 아니면 새게임(이어가기)/중지 2개
  // 머니 카운트 애니메이션이 끝나기 전(FGameOverReady=False)엔 비활성 표시하고 클릭도 무시한다
  // (MouseDownGameOver에서 재확인)
  var LBtnW := 140.0;
  var LGap := 16.0;
  var LHumanBroke := (not FSpectator) and (FHumanIndex >= 0) and (FMoney[spBottom] <= 0);
  if LHumanBroke then
  begin
    FBtnNext := TRectF.Empty;
    FBtnQuit := DrawStdButton(RectF(LCX - LBtnW / 2, LY + 12, LCX + LBtnW / 2, LY + 12 + LBtnH), '타이틀로',
      dbkDanger, FGameOverReady);
  end
  else
  begin
    FBtnNext := DrawStdButton(RectF(LCX - LBtnW - LGap / 2, LY + 12, LCX - LGap / 2, LY + 12 + LBtnH), '다음 판',
      dbkPrimary, FGameOverReady);
    FBtnQuit := DrawStdButton(RectF(LCX + LGap / 2, LY + 12, LCX + LGap / 2 + LBtnW, LY + 12 + LBtnH), '그만하기',
      dbkDanger, FGameOverReady);
  end;

  EndStdDialog;
end;

procedure TGostopBoard.DrawGoStopPrompt;
begin
  var LScore := FEngine.ScoreOf(FHumanIndex).Total;
  var LPanel := DrawStdDialog(Format('%d점! 고냐, 스톱이냐!', [LScore]), Max(Width * 0.34, 340.0), 128.0);

  var LBtnW := 120.0;
  var LBtnH := 46.0;
  var LGap := 24.0;
  var LCX := (LPanel.Left + LPanel.Right) / 2;
  var LBtnY := LPanel.Bottom - LBtnH - 16;
  FBtnGo := DrawStdButton(RectF(LCX - LBtnW - LGap / 2, LBtnY, LCX - LGap / 2, LBtnY + LBtnH), '고', dbkPrimary);
  FBtnStop := DrawStdButton(RectF(LCX + LGap / 2, LBtnY, LCX + LGap / 2 + LBtnW, LBtnY + LBtnH), '스톱', dbkDanger);

  EndStdDialog;
end;

// 다이얼로그 등장 팝인 진행 타이머(등장 시작~정착까지 매 프레임 재생)
procedure TGostopBoard.DialogPopTick(Sender: TObject);
begin
  if FPaused then
  begin
    Exit;
  end;

  FDialogPopT := FDialogPopT + FDialogPopTimer.Interval / 170;   // 총 170ms
  if FDialogPopT >= 1 then
  begin
    FDialogPopT := 1;
    FDialogPopTimer.Enabled := False;
  end;

  Repaint;
end;

// 정산창 머니 카운트 애니메이션 진행(모든 줄이 이 하나의 진행도를 공유해 동시 시작·종료됨).
// 대기(FMoneyCountDelay) → 카운트(FMoneyCountT) 순으로 진행하고, 다 끝나면 자동진행
// 카운트다운·버튼 활성화(FGameOverReady)를 그제서야 켠다.
procedure TGostopBoard.MoneyCountTick(Sender: TObject);
begin
  if FPaused then
  begin
    Exit;
  end;

  if FMoneyCountDelay > 0 then
  begin
    FMoneyCountDelay := FMoneyCountDelay - FMoneyCountTimer.Interval / 1000;
  end
  else
  begin
    FMoneyCountT := FMoneyCountT + FMoneyCountTimer.Interval / 900 * FGameSpeed;   // 총 900ms

    // 금액이 차오르는 동안 동전 소리를 일정 간격으로 흘려 숫자가 도는 것을 귀로도 알게 한다
    if FMoneyCountT < 1 then
    begin
      FMoneyTickAcc := FMoneyTickAcc + FMoneyCountTimer.Interval / 1000;
      if FMoneyTickAcc >= MONEY_TICK_INTERVAL then
      begin
        FMoneyTickAcc := 0;
        TGostopAudio.Instance.Play('sfx_coin');
      end;
    end;

    if FMoneyCountT >= 1 then
    begin
      FMoneyCountT := 1;
      FMoneyCountTimer.Enabled := False;
      FGameOverReady := True;

      // 카운트다운은 벽시계 기준(타이머 틱 누적이 아니라 실제 경과 시간)
      FGameOverRemain := GAME_OVER_COUNTDOWN_SECONDS;
      FGameOverSw := TStopwatch.StartNew;
      FGameOverLastSec := 0;
      FGameOverTimer.Enabled := True;
    end;
  end;

  Repaint;
end;

// 표준 다이얼로그 패널 시작. (제목+크기)가 직전 프레임과 다르면 새로 등장한 것으로 보고
// 팝인 애니메이션(살짝 작게 시작해 튀었다 정착)을 시작한다. 이 함수가 남긴 매트릭스는
// 다이얼로그 내용을 전부 그린 뒤 EndStdDialog로 반드시 복원해야 한다(패널·내용이 함께 스케일되도록).
function TGostopBoard.DrawStdDialog(const ATitle: string; const AWidth, AHeight: Single): TRectF;
begin
  Canvas.FillRound(LocalRect, 0, $88000000);   // 배경 딤

  var LKey := Format('%s|%.0f|%.0f', [ATitle, AWidth, AHeight]);
  if LKey <> FDialogPopKey then
  begin
    FDialogPopKey := LKey;
    FDialogPopT := 0;
    FDialogPopTimer.Enabled := True;
  end;

  Result := RectF(Width / 2 - AWidth / 2, Height / 2 - AHeight / 2, Width / 2 + AWidth / 2, Height / 2 + AHeight / 2);

  FDialogPreMatrix := Canvas.Matrix;
  if FDialogPopT < 1 then
  begin
    // ease-out-back: 0에서 살짝 넘치듯(오버슈트) 1로 정착
    const OVERSHOOT = 1.70158;
    var LK := FDialogPopT - 1;
    var LBack := 1 + (OVERSHOOT + 1) * LK * LK * LK + OVERSHOOT * LK * LK;
    var LScale := 0.6 + LBack * 0.4;   // 60% 크기에서 시작해 튀며 100%로 정착

    var LCx := (Result.Left + Result.Right) / 2;
    var LCy := (Result.Top + Result.Bottom) / 2;
    var LMx := TMatrix.CreateTranslation(-LCx, -LCy) * TMatrix.CreateScaling(LScale, LScale) * TMatrix.CreateTranslation(LCx, LCy);
    Canvas.SetMatrix(LMx * FDialogPreMatrix);
  end;

  // 옻칠 목함 느낌: 판(펠트)과 톤이 이어지는 짙은 녹색 세로 그라데이션 + 금테.
  // (이전의 절차 생성 나무 텍스처는 색이 겉돌아 제거)
  // 뒤에 그림자를 깔아 떠 있는 느낌을 준다
  Canvas.FillRound(RectF(Result.Left + 5, Result.Top + 7, Result.Right + 5, Result.Bottom + 7), 18, $58000000);

  Canvas.Fill.Kind := TBrushKind.Gradient;
  Canvas.Fill.Gradient.Style := TGradientStyle.Linear;
  Canvas.Fill.Gradient.StartPosition.Point := PointF(0.5, 0);
  Canvas.Fill.Gradient.StopPosition.Point := PointF(0.5, 1);
  Canvas.Fill.Gradient.Color := $FA2C3D30;    // 상단: 펠트보다 살짝 밝은 짙은 녹색
  Canvas.Fill.Gradient.Color1 := $FA111A13;   // 하단: 옻칠처럼 깊게 가라앉는 톤
  Canvas.FillRect(Result, 18, 18, [TCorner.TopLeft, TCorner.TopRight, TCorner.BottomLeft, TCorner.BottomRight], 1);
  Canvas.Fill.Kind := TBrushKind.Solid;

  Canvas.StrokeRound(Result, 18, $FFE8C868, 2.5);   // 금색 외곽 테두리(액자 느낌)
  Canvas.StrokeRound(RectF(Result.Left + 4, Result.Top + 4, Result.Right - 4, Result.Bottom - 4), 14, $30E8C868, 1);   // 안쪽 은은한 이너라인

  if ATitle <> '' then
  begin
    // 제목: 그림자 얹은 금색 글자 + 아래 금색 구분선(중앙 ◆ 장식)으로 현판 느낌
    DrawLabel(RectF(Result.Left + 1, Result.Top + 18, Result.Right + 1, Result.Top + 52), ATitle, $C0000000, 22);
    DrawLabel(RectF(Result.Left, Result.Top + 16, Result.Right, Result.Top + 50), ATitle, TAlphaColors.Gold, 22);

    var LCx := (Result.Left + Result.Right) / 2;
    var LLineY := Result.Top + 56;
    var LHalf := Min(Result.Width * 0.30, 150.0);
    Canvas.Fill.Kind := TBrushKind.Solid;
    Canvas.Fill.Color := $70E8C868;
    Canvas.FillRect(RectF(LCx - LHalf, LLineY, LCx - 10, LLineY + 1), 0, 0, [], 1);
    Canvas.FillRect(RectF(LCx + 10, LLineY, LCx + LHalf, LLineY + 1), 0, 0, [], 1);
    Canvas.Fill.Color := $FFE8C868;
    Canvas.FillPolygon([PointF(LCx, LLineY - 4), PointF(LCx + 4, LLineY), PointF(LCx, LLineY + 4), PointF(LCx - 4, LLineY)], 1);
  end;
end;

// DrawStdDialog가 남긴 팝인 매트릭스를 복원한다 — 그 다이얼로그의 내용(버튼·라벨·카드 등)을
// 전부 그린 직후 반드시 호출해야, 패널과 내용이 함께 스케일되어 자연스럽게 등장한다.
procedure TGostopBoard.EndStdDialog;
begin
  Canvas.SetMatrix(FDialogPreMatrix);
end;

// AARRGGBB 색상의 RGB 채널을 ADelta만큼 밝게(양수)/어둡게(음수) 조정(호버·눌림 효과 공용).
// Gostop.Canvas.Helper 로 공용화(위임) — 외부 렌더 유닛과 같은 구현을 공유한다.
function TGostopBoard.AdjustColor(const AColor: TAlphaColor; const ADelta: Integer): TAlphaColor;
begin
  Result := Gostop.Canvas.Helper.AdjustColor(AColor, ADelta);
end;

// 현재 마우스 위치가 이 영역 위에 있는가(호버 판정 공용). 애니메이션 중엔 입력을 안 받으므로 호버도 끔
function TGostopBoard.IsHot(const ARect: TRectF): Boolean;
begin
  Result := (not Assigned(FDisplay)) and (not FDealing) and (not FShuffling) and (Length(FReplacingSeats) = 0) and ARect.Contains(FMousePos);
end;

// 이 영역을 누른 채 마우스 버튼이 눌려 있는가(눌림 효과 공용)
function TGostopBoard.IsPressed(const ARect: TRectF): Boolean;
begin
  Result := FMouseDown and IsHot(ARect);
end;

// 표준 다이얼로그 버튼: 종류별 색상 통일 + 호버(밝게)·눌림(어둡게+눌림 느낌)·비활성(회색조) 효과. rect 반환(클릭 판정용)
// 렌더 본문은 Gostop.Board.Widgets(TWidgetRender.StdButton)로 분리됨. 여기서는 호버/눌림만 계산해 위임.
function TGostopBoard.DrawStdButton(const ARect: TRectF; const ACaption: string; const AKind: TDlgBtnKind;
  const AEnabled: Boolean; const AFontSize: Single): TRectF;
begin
  Result := TWidgetRender.StdButton(Canvas, ARect, ACaption, AKind, AEnabled, AFontSize,
    IsHot(ARect), IsPressed(ARect));
end;

// 사람이 지금 쇼당을 걸 수 있는가(3인·내 차례·손패로 두 상대 완성 위협)
function TGostopBoard.HumanCanShodang: Boolean;
begin
  Result := False;
  if FShodangActive or FSpectator or (FPlayerCount <> 3) or (FGame = nil) then
  begin
    Exit;
  end;

  if Assigned(FDisplay) or (FHumanIndex < 0) then
  begin
    Exit;
  end;

  if (FGame.Phase <> gpPlaying) or (FGame.Current <> FHumanIndex) then
  begin
    Exit;
  end;

  Result := TShodang.Detect(FGame, FHumanIndex).Callable;
end;

// 사람 차례에 쇼당 가능하면 '쇼당!' 버튼을 제시
procedure TGostopBoard.DrawShodangButton;
begin
  FBtnShodang := TRectF.Empty;
  if not HumanCanShodang then
  begin
    Exit;
  end;

  var LW := 150.0;
  var LH := 46.0;
  FBtnShodang := RectF(Width / 2 - LW / 2, Height * 0.545, Width / 2 + LW / 2, Height * 0.545 + LH);

  var LColor: TAlphaColor := $FFB8860B;
  var LFillR := FBtnShodang;
  if IsPressed(FBtnShodang) then
  begin
    LColor := AdjustColor(LColor, -30);
    LFillR := RectF(FBtnShodang.Left + 2, FBtnShodang.Top + 2, FBtnShodang.Right - 1, FBtnShodang.Bottom - 1);
  end
  else
  if IsHot(FBtnShodang) then
  begin
    LColor := AdjustColor(LColor, 24);
  end;

  Canvas.FillRound(LFillR, 10, LColor);
  Canvas.StrokeRound(LFillR, 10, TAlphaColors.White, 2);
  DrawLabel(LFillR, '쇼당!', TAlphaColors.White, 22);
end;

// 두 상대의 게임 인덱스(ACaller 제외)
function ShodangOpps(const AGame: TGameState; const ACaller: Integer): TArray<Integer>;
begin
  Result := nil;
  for var I := 0 to AGame.PlayerCount - 1 do
  begin
    if I <> ACaller then
    begin
      Result := Result + [I];
    end;
  end;
end;

// 쇼당 결정 종합: 둘 다 수락=나가리 / 한 명 수락=밀어주기(거절자 독박) / 둘 다 거절=계속.
// 계속 진행 시 호출자가 AI면 그 AI의 실제 턴을 이어서 실행한다.
procedure TGostopBoard.ResolveShodang(const ACaller, AOppA, AOppB: Integer; const AAccA, AAccB: Boolean);
begin
  var LDecision := TShodang.Resolve(ACaller, AOppA, AOppB, AAccA, AAccB);

  case LDecision.Outcome of
    soNagari:
      begin
        QueueEffect('쇼당 — 둘 다 수락! 나가리');
        FEngine.DeclareNagari;
        AfterAction;
        Exit;
      end;
    soContinue:
      begin
        QueueEffect('쇼당 — 둘 다 거절, 계속 진행');
      end;
  else
    begin
      // 한 명 수락 → 그 사람을 밀어줌, 거절자는 독박 대기
      FShodangActive := True;
      FShodangCaller := LDecision.Caller;
      FShodangAccepter := LDecision.Accepter;
      FShodangDecliner := LDecision.Decliner;
      QueueEffect(Format('쇼당! %s 수락 — %s 독박',
        [FGame.Player(LDecision.Accepter).Name, FGame.Player(LDecision.Decliner).Name]));
    end;
  end;

  // 계속 진행: 호출자가 AI면 그 AI가 카드를 내야 함
  if ACaller <> FHumanIndex then
  begin
    AiExecuteTurn;
  end
  else
  begin
    Repaint;
  end;
end;

// 사람이 쇼당을 건다(버튼) → 두 상대(AI) 자동 결정 후 종합
procedure TGostopBoard.HumanCallShodang;
begin
  if not HumanCanShodang then
  begin
    Exit;
  end;

  TGostopAudio.Instance.Play('sfx_negotiate');
  var LOpps := ShodangOpps(FGame, FHumanIndex);
  ResolveShodang(FHumanIndex, LOpps[0], LOpps[1], Random(100) < 60, Random(100) < 60);
end;

// AI가 쇼당을 건다: 사람이 상대면 수락/거절 다이얼로그, 관전(전원 AI)이면 자동 종합
procedure TGostopBoard.AiCallShodang(const ACaller: Integer);
begin
  TGostopAudio.Instance.Play('sfx_negotiate');
  var LOpps := ShodangOpps(FGame, ACaller);

  var LHumanIsOpp := (not FSpectator) and (FHumanIndex >= 0)
    and ((LOpps[0] = FHumanIndex) or (LOpps[1] = FHumanIndex));

  if LHumanIsOpp then
  begin
    // 다른 상대(AI)는 선결정, 사람은 다이얼로그로 결정 대기
    var LAiOpp := LOpps[0];
    if LOpps[0] = FHumanIndex then
    begin
      LAiOpp := LOpps[1];
    end;

    FShodangPending := True;
    FShodangPendCaller := ACaller;
    FShodangPendAiOpp := LAiOpp;
    FShodangPendAiAccept := Random(100) < 60;

    // 공개할 위협 패
    FShodangCards := nil;
    var LDet := TShodang.Detect(FGame, ACaller);
    for var LT in LDet.Threats do
    begin
      FShodangCards := FShodangCards + [LT.CardId];
    end;

    Repaint;
    if Assigned(FOnStateChanged) then
    begin
      FOnStateChanged(Self);
    end;
  end
  else
  begin
    // 전원 AI: 둘 다 자동
    ResolveShodang(ACaller, LOpps[0], LOpps[1], Random(100) < 60, Random(100) < 60);
  end;
end;

// 사람이 AI 쇼당에 수락/거절 응답
procedure TGostopBoard.HumanRespondShodang(const AAccept: Boolean);
begin
  if not FShodangPending then
  begin
    Exit;
  end;

  FShodangPending := False;
  ResolveShodang(FShodangPendCaller, FHumanIndex, FShodangPendAiOpp, AAccept, FShodangPendAiAccept);
end;

// AI 쇼당 → 사람에게 수락/거절 묻는 표준 다이얼로그(공개 패 + [받기][거절])
procedure TGostopBoard.DrawShodangPrompt;
begin
  var LPanel := DrawStdDialog(Format('%s 쇼당! — 받으시겠습니까?', [FGame.Player(FShodangPendCaller).Name]), Max(Width * 0.4, 420.0), 260.0);

  // 공개 패
  var CS := CardSize;
  var LCW := CS.Width * 0.7;
  var LCH := CS.Height * 0.7;
  var LN := Length(FShodangCards);
  if LN > 0 then
  begin
    var LTotW := LCW + (LN - 1) * LCW * 1.2;
    var LSX := (LPanel.Left + LPanel.Right) / 2 - LTotW / 2;
    var LCY := LPanel.Top + 62;
    for var I := 0 to LN - 1 do
    begin
      DrawFront(RectF(LSX + I * LCW * 1.2, LCY, LSX + I * LCW * 1.2 + LCW, LCY + LCH), FShodangCards[I]);
    end;
  end;

  DrawLabel(RectF(LPanel.Left, LPanel.Bottom - 96, LPanel.Right, LPanel.Bottom - 74),
    '받으면 이 판 나가리(둘 다 받을 때), 거절 시 밀리면 독박', $FFB8C4B8, 13);

  var LBtnW := 130.0;
  var LBtnH := 46.0;
  var LGap := 24.0;
  var LCX := (LPanel.Left + LPanel.Right) / 2;
  var LBtnY := LPanel.Bottom - LBtnH - 16;
  FBtnShodangYes := DrawStdButton(RectF(LCX - LBtnW - LGap / 2, LBtnY, LCX - LGap / 2, LBtnY + LBtnH), '받기', dbkPrimary);
  FBtnShodangNo := DrawStdButton(RectF(LCX + LGap / 2, LBtnY, LCX + LGap / 2 + LBtnW, LBtnY + LBtnH), '거절', dbkDanger);

  EndStdDialog;
end;

procedure TGostopBoard.PaintGame;
begin
  // 군용담요(올리브 울) 텍스처 타일링
  if FFeltTile = nil then
  begin
    GenerateFeltTile;
  end;

  if (FFeltTile <> nil) and (FFeltTile.Width > 0) then
  begin
    // 타일 비트맵 브러시로 한 번에 채운다(프레임당 DrawBitmap 수십~수백회 회피)
    Canvas.Fill.Kind := TBrushKind.Bitmap;
    Canvas.Fill.Bitmap.Bitmap := FFeltTile;
    Canvas.Fill.Bitmap.WrapMode := TWrapMode.Tile;
    Canvas.FillRect(LocalRect, 0, 0, [], 1);
    Canvas.Fill.Kind := TBrushKind.Solid;   // 이후 그리기에 영향 없게 복원
  end
  else
  begin
    Canvas.Fill.Kind := TBrushKind.Solid;
    Canvas.Fill.Color := $FF284230;
    Canvas.FillRect(LocalRect, 0, 0, [], 1);
  end;

  // 하단 컨트롤 바(볼륨·음소거·속도) — 모든 화면 공통
  DrawControlBar;

  // 기리(딜 전 말번 커팅) 단계
  if FGiriPhase then
  begin
    DrawGiri;
    Exit;
  end;

  // 선 뽑기(밤일낮장) 단계
  if FSeonPicking then
  begin
    DrawSeonPick;
    Exit;
  end;

  // 셔플 연출 단계(딜 직전) — 실제 렌더는 FAnimMgr.DrawAll(Paint 최상단)의 TShuffleAnimation 이 맡는다.
  // 여기서는 게임 요소를 그리지 않고 빠져나간다.
  if FShuffling then
  begin
    Exit;
  end;

  // 딜(패 돌리기) 애니메이션 단계 — 실제 렌더는 FAnimMgr.DrawAll 의 TDealAnimation 이 맡는다.
  if FDealing then
  begin
    Exit;
  end;

  // 협상 단계
  if FNegotiating then
  begin
    DrawNegotiation;
    Exit;
  end;

  // 광 판매 발표
  if FGwangShow then
  begin
    DrawGwangSale;
    Exit;
  end;

  // 빠지는 자리의 손패가 뒷패로 합쳐지는 연출(광 발표 뒤 · 플레이 시작 전)
  if FFoldT < 1 then
  begin
    DrawSitOutFold;
    Exit;
  end;

  if FGame = nil then
  begin
    // 게임풍 타이틀 메뉴(대전 설정/설정/종료)
    if FSettingsOpen then
    begin
      DrawSettings;
      if FAvatarPicking then
      begin
        DrawAvatarPicker;
      end;
    end
    else
    if FMatchSetupOpen then
    begin
      DrawMatchSetup;
    end
    else
    begin
      DrawTitleMenu;
      if FInfoOpen then
      begin
        DrawProgramInfo;
      end;
    end;

    Exit;
  end;

  // 현재 턴 위치(강조용). 애니 중이면 행위자 자리를 강조
  var LHasCurrent := (FGame.Phase <> gpFinished) or Assigned(FDisplay);
  var LCurPos := spBottom;
  if Assigned(FDisplay) then
  begin
    LCurPos := PhysicalPos(FAnimActor);
  end
  else
  if FGame.Phase <> gpFinished then
  begin
    LCurPos := PhysicalPos(FGame.Current);
  end;

  // 플레이어 영역(포커테이블식) — 항상 4자리 구조로 그리고, 현재 턴 영역은 색으로 강조
  for var LP := spTop to spRight do
  begin
    DrawRegion(SeatRegion(LP), LHasCurrent and (LP = LCurPos));
  end;

  // 중앙: 바닥 + 뒷패
  DrawCenter(CenterRegion);

  // 좌석별 카드(참가 중인 플레이어만). 관전 모드에선 아래 자리도 AI로 그린다
  for var I := 0 to FGame.PlayerCount - 1 do
  begin
    var LPos := PhysicalPos(I);
    if (LPos = spBottom) and (I = FHumanIndex) then
    begin
      DrawHumanHand(SeatRegion(spBottom));
    end
    else
    begin
      DrawOpponent(I, LPos, SeatRegion(LPos));
    end;
  end;

  // 자리별 정보 패널(아바타·머니·전적·게임정보) — 매치의 모든 자리(빠진 자리 포함)
  DrawPanels;

  // 보너스 뽑기: 뒷패 펼쳐 고르기 오버레이(턴 애니 중엔 숨김)
  if (FGame.Phase = gpAwaitingBonusDraw) and (not Assigned(FDisplay)) then
  begin
    DrawBonusDraw;
  end;

  // 애니메이션 중이면 플라이어만, 아니면 종료/고·스톱 팝업
  if Assigned(FDisplay) then
  begin
    DrawFlyers;
  end
  else
  begin
    // 연출이 아직 남아 정산창을 미루는 중(FGameOverPending)이면 그리지 않는다
    if (FGame.Phase = gpFinished) and (not FGameOverPending) and (Length(FReplacingSeats) = 0) then
    begin
      DrawGameOver;
    end;

    if FAwaitingGoStop and (FGame.Phase = gpAwaitingGoStop) and (FGame.Current = FHumanIndex) then
    begin
      DrawGoStopPrompt;
    end;

    // 사람 차례에 쇼당 가능하면 '쇼당!' 버튼 제시
    DrawShodangButton;
  end;

  // AI 쇼당 → 사람 수락/거절 대기 다이얼로그(최상단 모달)
  if FShodangPending then
  begin
    DrawShodangPrompt;
  end;

  // 캐릭터 말풍선(턴 시작마다 일정 확률로)
  DrawSpeechBubble;

  // 아바타 선택 오버레이(최상단)
  if FAvatarPicking then
  begin
    DrawAvatarPicker;
  end;

  // 오링 좌석 신규 캐릭터 등장 연출(모든 것 위에 표시)
  if Length(FReplacingSeats) > 0 then
  begin
    DrawSeatReplacement;
  end;
end;

// 실제 화면 그리기(PaintGame) 후, 일시정지 중이면 그 위에 딤+안내를 얹는다(모든 단계 공통)
procedure TGostopBoard.Paint;
begin
  PaintGame;

  // 국진 → 쌍피 이동은 더미 위를 지나가므로 카드보다 뒤에, 배너보다는 앞에 그린다
  DrawGukjinMove;

  // 특수 상황 배너(쪽/따닥/싹쓸이/폭탄/흔들기/뻑/총통/연사…)는 PaintGame 밖에서 그린다.
  // PaintGame 은 협상·광판매 발표·타이틀 단계에서 일찍 Exit 하므로 그 안에서 그리면
  // 해당 단계에 큐잉된 배너(연사 강제참가 안내 등)가 표시되지 못하고 그대로 만료된다.
  DrawEffectBanner;

  // 매니저에 등록된 애니메이션(현재 나가리 흩기·도장)을 최상단에 그린다
  if Assigned(FAnimMgr) then
  begin
    FAnimMgr.DrawAll;
  end;

  if FPaused then
  begin
    DrawPauseOverlay;
    DrawControlBar;   // 딤 오버레이 위에 다시 그려 재개 버튼이 가려지지 않게 함
  end;
end;

procedure TGostopBoard.DrawPauseOverlay;
begin
  TOverlayRender.PauseOverlay(Canvas, LocalRect);
end;

// 스페이스바 등 외부 단축키에서 호출 — 일시정지 상태를 켜고 끈다
procedure TGostopBoard.TogglePause;
begin
  FPaused := not FPaused;
  TGostopAudio.Instance.Play('ui_click');
  Repaint;
end;

// 이번 판 한정 자동 진행 토글. 켜면 내 자리에도 임시 AI 에이전트를 붙여 AiTimerTick이 대신 진행하게
// 하고, 끄면 그 에이전트를 떼어내 다시 사람이 직접 조작한다. 다음 딜(새 판)에서는 항상 꺼진 채로 시작.
procedure TGostopBoard.ToggleAutoPlay;
begin
  FAutoPlay := not FAutoPlay;
  TGostopAudio.Instance.Play('ui_click');

  if (FHumanIndex >= 0) and (Length(FAgents) > FHumanIndex) then
  begin
    if FAutoPlay then
    begin
      if not Assigned(FAgents[FHumanIndex]) then
      begin
        var LAi := TAiPlayer.Create(FAiSkill, UInt64(424242424242));
        FAiObjects.Add(LAi);
        FAgents[FHumanIndex] := LAi;
      end;

      // 지금 마침 내 턴이면 곧바로 진행되게 트리거
      if (FGame <> nil) and (FGame.Current = FHumanIndex) and (not Assigned(FDisplay)) then
      begin
        FAiTimer.Enabled := True;
      end;
    end
    else
    begin
      FAgents[FHumanIndex] := nil;
    end;
  end;

  Repaint;
end;

function TGostopBoard.IsTextInputActive: Boolean;
begin
  Result := Assigned(FNickEdit) and FNickEdit.Visible and FNickEdit.IsFocused;
end;

function TGostopBoard.FloorMatchOrdinal(const AFloorIndex, AMonth: Integer): Integer;
begin
  Result := 0;
  for var I := 0 to AFloorIndex - 1 do
  begin
    if FGame.Floor[I].Month = AMonth then
    begin
      Inc(Result);
    end;
  end;
end;

procedure TGostopBoard.AutoStopIfLastCard;
begin
  // 마지막 장을 내서 손패가 비었으면 GO가 무의미 → 자동 스톱(즉시 종료)
  if FAwaitingGoStop and (FHumanIndex >= 0) and (FGame.Player(FHumanIndex).Hand.Count = 0) then
  begin
    FEngine.DeclareStop;
    FAwaitingGoStop := False;
  end;
end;

function TGostopBoard.RState: TGameState;
begin
  // 애니 진행 중이면 표시용 클론, 아니면 실제 상태
  if Assigned(FDisplay) then
  begin
    Result := FDisplay;
  end
  else
  begin
    Result := FGame;
  end;
end;

function TGostopBoard.CapturedAnchor(const AActor: Integer): TPointF;
begin
  // 먹은 패·뺏어온 피는 좌석의 아바타 카드로 빨려들어가듯 날아가게 함
  var LAvatar := SeatAvatarRect(PhysicalPos(AActor));
  Result := PointF((LAvatar.Left + LAvatar.Right) / 2, (LAvatar.Top + LAvatar.Bottom) / 2);
end;

procedure TGostopBoard.CollectTurnEffects;
begin
  // 한 턴에 이벤트가 여럿이면(예: 따닥+뻑) 한 줄로 합쳐 동시에 보여주지 않고, QueueEffect로 하나씩
  // 순서대로 넣어 각 이벤트가 사이 공백을 두고 구분되어 보이게 한다
  var LSeen := TDictionary<string, Boolean>.Create;
  try
    for var LEvt in FTurnEvents do
    begin
      var LLabel := EventEffectLabel(LEvt.Kind);
      if (LLabel <> '') and (not LSeen.ContainsKey(LLabel)) then
      begin
        LSeen.Add(LLabel, True);
        QueueEffect(LLabel);
      end;
    end;
  finally
    LSeen.Free;
  end;

  // 흔들기·폭탄: 판이 흔들리는 연출 + 그 자리의 대사(사람·AI 공통).
  // 성립 조건이 서로 배타적(바닥에 그 월이 있으면 폭탄, 없으면 흔들기)이라 한 턴에 둘 다
  // 나오지는 않지만, 그래도 더 센 쪽이 이기도록 골라 둔다.
  var LShakeAmp := 0.0;
  var LShakeSeat := -1;
  var LShakeText := '';
  for var LEvt in FTurnEvents do
  begin
    var LAmp := 0.0;
    var LText := '';
    case LEvt.Kind of
      pekShake:
        begin
          LAmp := 1.0;
          LText := '흔들어써~~!';
        end;
      pekBomb:
        begin
          LAmp := 1.8;   // 폭탄은 판이 더 크게 튄다
          LText := '폭탄이야!!';
        end;
    end;

    if LAmp > LShakeAmp then
    begin
      LShakeAmp := LAmp;
      LShakeSeat := LEvt.PlayerIndex;
      LShakeText := LText;
    end;
  end;

  if LShakeAmp > 0 then
  begin
    BeginShakeEffect(LShakeAmp);
    if LShakeSeat >= 0 then
    begin
      ForceSpeech(PhysicalPos(LShakeSeat), LShakeText);
    end;
  end;

  // 피 뺏김: 뺏긴 좌석을 3초간 화난 표정으로(자뻑·뻑 회수·3장 쓸어먹기 등 모든 pekPiSteal 공통).
  // 명령만 하면 아바타 액터가 좌석별로 3초 뒤 알아서 평상시로 되돌린다(전역 타이머 없이 자기완결).
  for var LEvt in FTurnEvents do
  begin
    if (LEvt.Kind = pekPiSteal) and (LEvt.VictimIndex >= 0) then
    begin
      FAvatarActors[PhysicalPos(LEvt.VictimIndex)].HoldExpression(aeAngry, 3.0);
    end;
  end;
end;

const
  EFFECT_SHOW_MS = 1500;
  EFFECT_GAP_MS = 300;

procedure TGostopBoard.QueueEffect(const AText: string);
begin
  if AText = '' then
  begin
    Exit;
  end;

  // 지금 아무것도 표시/대기 중이 아니면(빈 큐 + 타이머 꺼짐) 바로 시작, 아니면 큐에 쌓아 순서를 지킴
  var LWasIdle := (FEffectText = '') and (not FEffectGap) and (not FEffectTimer.Enabled);
  SetLength(FEffectQueue, Length(FEffectQueue) + 1);
  FEffectQueue[High(FEffectQueue)] := AText;
  if LWasIdle then
  begin
    ShowNextQueuedEffect;
  end;
end;

procedure TGostopBoard.ShowNextQueuedEffect;
begin
  if FEffectQueueIdx > High(FEffectQueue) then
  begin
    FEffectText := '';
    FEffectQueue := nil;
    FEffectQueueIdx := 0;
    Exit;
  end;

  FEffectText := FEffectQueue[FEffectQueueIdx];
  Inc(FEffectQueueIdx);
  FEffectGap := False;
  FEffectTimer.Interval := EFFECT_SHOW_MS;
  FEffectTimer.Enabled := False;
  FEffectTimer.Enabled := True;
end;

procedure TGostopBoard.EffectTimerTick(Sender: TObject);
begin
  if FPaused then
  begin
    Exit;
  end;

  FEffectTimer.Enabled := False;

  if FEffectGap then
  begin
    // 공백 구간이 끝났으면 다음 이벤트 배너를 이어서 표시
    ShowNextQueuedEffect;
  end
  else
  begin
    FEffectText := '';
    if FEffectQueueIdx <= High(FEffectQueue) then
    begin
      // 보여줄 배너가 더 있으면 곧바로 잇지 않고 짧은 공백을 둬 서로 다른 이벤트임을 알 수 있게 한다
      FEffectGap := True;
      FEffectTimer.Interval := EFFECT_GAP_MS;
      FEffectTimer.Enabled := True;
    end
    else
    begin
      FEffectQueue := nil;
      FEffectQueueIdx := 0;
      MaybeBeginGameOver;   // 배너가 다 끝났으니 미뤄둔 정산창이 있으면 지금 띄운다
    end;
  end;

  Repaint;
end;


// 렌더 본문은 Gostop.Board.OverlayRender 로 분리됨. 텍스트·중앙영역·흔들림오프셋만 뽑아 위임.
procedure TGostopBoard.DrawEffectBanner;
begin
  if FEffectText = '' then
  begin
    Exit;
  end;

  TOverlayRender.EffectBanner(Canvas, FEffectText, CenterRegion, ShakeOffsetX);
end;

// 나가리(무승부) 연출을 시작한다. 모든 좌석의 먹은 패를 스냅샷으로 떠, 각 좌석 아바타에서
// 중앙 바닥으로 던지는 좌표(출발·도착·시차)를 애니(TNagariAnimation)에 넘긴다. 이후 렌더는
// 애니가 스스로 하고, 바닥패·먹은패 원본은 기존 렌더가 그대로 그린다(오버레이 방식).
procedure TGostopBoard.BeginNagariAnim;
begin
  var LCen := CenterRegion;
  var LMidX := (LCen.Left + LCen.Right) / 2;
  var LMidY := (LCen.Top + LCen.Bottom) / 2;
  var LSpreadX := LCen.Width * 0.34;
  var LSpreadY := LCen.Height * 0.30;
  var LCS := CardSize;

  // 모든 좌석의 먹은 패를 모아, 각자 아바타에서 중앙 바닥의 무작위 지점으로 시차를 두고 던진다
  var LList := TList<TNagariCard>.Create;
  try
    for var I := 0 to FGame.PlayerCount - 1 do
    begin
      var LFrom := CapturedAnchor(I);
      var LCaptured := FGame.Player(I).Captured;
      for var J := 0 to LCaptured.Count - 1 do
      begin
        var LItem: TNagariCard;
        LItem.AssetId := LCaptured[J].AssetId;
        LItem.FromX := LFrom.X + (Random - 0.5) * LCS.Width * 0.6;
        LItem.FromY := LFrom.Y + (Random - 0.5) * LCS.Height * 0.4;
        LItem.ToX := LMidX + (Random - 0.5) * 2 * LSpreadX;
        LItem.ToY := LMidY + (Random - 0.5) * 2 * LSpreadY;
        LItem.Delay := Random * 0.34;         // 애니의 NAGARI_THROW_WINDOW 와 맞춤(우르르 시차)
        LItem.Rot := (Random - 0.5) * 120;    // -60~60도
        LList.Add(LItem);
      end;
    end;

    FNagariAnim := TNagariAnimation.Create(Self, LList.ToArray);
  finally
    LList.Free;
  end;

  FNagariAnim.OnDone :=
    procedure
    begin
      FNagariAnim := nil;   // 매니저가 이미 애니 객체를 해제한 상태 — 참조만 끊는다
      MaybeBeginGameOver;   // 미뤄둔 정산창으로 이어간다
    end;

  FAnimMgr.Add(FNagariAnim);
  Repaint;
end;

// --- IAnimationHost 구현(Gostop.Board.Animation) ---
function TGostopBoard.GetCanvas: TCanvas;
begin
  Result := Canvas;
end;

function TGostopBoard.GetGameSpeed: Single;
begin
  Result := FGameSpeed;
end;

procedure TGostopBoard.PlaySound(const AName: string);
begin
  TGostopAudio.Instance.Play(AName);
end;

procedure TGostopBoard.RequestRepaint;
begin
  Repaint;
end;

// 흔들기 연출의 현재 좌우 오프셋(px). 진행 중 흔들기 애니가 있으면 그 값을, 없으면 0을 준다.
function TGostopBoard.ShakeOffsetX: Single;
begin
  if FShakeAnim <> nil then
  begin
    Result := FShakeAnim.OffsetX;
  end
  else
  begin
    Result := 0;
  end;
end;

// 판을 흔드는 연출 시작(바닥패·뒷패가 함께 좌우로 진동). 이미 진행 중이면 처음부터 다시.
// AAmplitude: 진폭 배율 — 흔들기는 1.0, 폭탄처럼 더 센 연출은 그 이상.
procedure TGostopBoard.BeginShakeEffect(const AAmplitude: Single);
begin
  if FShakeAnim <> nil then
  begin
    FShakeAnim.Restart(AAmplitude);   // 진행 중이면 처음부터 다시 흔든다
  end
  else
  begin
    FShakeAnim := TShakeAnimation.Create(Self, AAmplitude);
    FShakeAnim.OnDone :=
      procedure
      begin
        FShakeAnim := nil;
        MaybeBeginGameOver;   // 흔들림이 끝났으니 미뤄둔 정산창이 있으면 지금 띄운다
      end;

    FAnimMgr.Add(FShakeAnim);
  end;

  Repaint;
end;

// 특정 자리에 대사를 강제로 띄운다(흔들기 등 확정 연출용). 확률 판정 없이 항상 표시.
procedure TGostopBoard.ForceSpeech(const ASeat: TSeatPos; const AText: string);
begin
  if not FConfig.Speech then
  begin
    Exit;   // 말풍선 옵션 꺼짐
  end;

  FSpeechSeat := ASeat;
  FSpeechText := AText;
  FSpeechTimer.Enabled := False;
  FSpeechTimer.Enabled := True;
end;

// 턴이 새로 시작될 때(같은 턴 안에서 AfterAction이 여러 번 불려도 한 번만) 일정 확률로 그
// 자리 캐릭터의 대사 하나를 말풍선으로 잠깐 띄운다 — 하단 상태문구는 안내용이라 손대지 않고
// 별도 연출로만 추가(캐릭터 개성 표현, 게임다운 느낌).
procedure TGostopBoard.MaybeShowSpeech;
begin
  if not FConfig.Speech then
  begin
    Exit;   // 말풍선 옵션 꺼짐(새 게임 설정에서 변경, 기본 켬)
  end;

  if (FGame = nil) or (FGame.Phase = gpFinished) then
  begin
    Exit;
  end;

  if FGame.Current = FLastSpeechGameIndex then
  begin
    Exit;
  end;

  FLastSpeechGameIndex := FGame.Current;
  if Random(100) >= 40 then
  begin
    Exit;
  end;

  var LSeat := PhysicalPos(FGame.Current);
  var LAvIdx := FSeatAvatar[LSeat];
  var LQCount := TGostopCharacters.QuoteCount(LAvIdx);
  if LQCount = 0 then
  begin
    Exit;
  end;

  FSpeechSeat := LSeat;
  FSpeechText := TGostopCharacters.QuoteOf(LAvIdx, Random(LQCount));
  FSpeechTimer.Enabled := False;
  FSpeechTimer.Enabled := True;
end;

procedure TGostopBoard.SpeechTimerTick(Sender: TObject);
begin
  if FPaused then
  begin
    Exit;
  end;

  FSpeechTimer.Enabled := False;
  FSpeechText := '';
  Repaint;
end;

// 좌석 아바타 옆, 카드 영역과 겹치지 않는 "빈" 쪽에 대사 말풍선 + 꼬리를 그린다.
// PlayerPanelRect 배치상 손패는 항상 아바타의 특정 한쪽에 붙어 있으므로(P1=왼쪽·P3=오른쪽·
// P2=아래·P4=위), 그 반대쪽이 상대적으로 비어 있는 방향이다.
// 렌더 본문은 Gostop.Board.OverlayRender 로 분리됨. 텍스트·아바타rect·방향만 뽑아 위임.
procedure TGostopBoard.DrawSpeechBubble;
begin
  if FSpeechText = '' then
  begin
    Exit;
  end;

  // P1(spTop)·P2(spLeft)는 오른쪽(+1), P3(spBottom)·P4(spRight)는 왼쪽(-1)으로 고정
  var LDirX: Single := -1;
  if FSpeechSeat in [spTop, spLeft] then
  begin
    LDirX := 1;
  end;

  TOverlayRender.SpeechBubble(Canvas, FSpeechText, SeatAvatarRect(FSpeechSeat), LDirX);
end;

procedure TGostopBoard.PlayTurnSound;
begin
  // 이번 턴의 대표 특수 이벤트를 정해 둔다(먹기 단계에서 재생). 단일 채널이므로 하나만.
  FTurnSpecialKind := pekTurnPass;
  FTurnSpecialPri := 0;
  for var LEvt in FTurnEvents do
  begin
    var LPri := EventSoundPriority(LEvt.Kind);
    if LPri > FTurnSpecialPri then
    begin
      FTurnSpecialPri := LPri;
      FTurnSpecialKind := LEvt.Kind;
    end;
  end;

  // 먹기(캡처)가 없으면 먹기 단계가 안 도니 특수/고·스톱 소리는 지금 재생
  if (FTurnSpecialPri > 0) and (Length(FAnimCaptured) = 0) then
  begin
    TGostopAudio.Instance.PlayEvent(FTurnSpecialKind);
  end;
end;

procedure TGostopBoard.StartTurnAnimation(const ABefore: TGameState; const AOnDone: TProc);
begin
  FAnimActor := ABefore.Current;
  FAnimPlayed := CardsRemoved(ABefore.Player(FAnimActor).Hand, FGame.Player(FAnimActor).Hand);
  FAnimDrawn := CardsRemoved(ABefore.Stock, FGame.Stock);
  // 스톡은 맨 뒤(Count-1)부터 먼저 뽑히는데(DrawNonBonus 참조) CardsRemoved는 원래 리스트의
  // 오름차순 인덱스 순서로 돌려줘 실제 뽑은 순서와 반대다 — 보너스패 연쇄 애니메이션이 뽑힌 순서
  // 그대로(보너스패부터 → 마지막에 결과 카드) 재생되도록 순서를 뒤집는다
  for var LLo := 0 to (Length(FAnimDrawn) div 2) - 1 do
  begin
    var LHi := High(FAnimDrawn) - LLo;
    var LTmp := FAnimDrawn[LLo];
    FAnimDrawn[LLo] := FAnimDrawn[LHi];
    FAnimDrawn[LHi] := LTmp;
  end;

  FAnimCaptured := CardsAdded(ABefore.Player(FAnimActor).Captured, FGame.Player(FAnimActor).Captured);
  PlayTurnSound;
  FAnimDone := AOnDone;
  SetLength(FRestCards, 0);
  SetLength(FRestPts, 0);

  // 뻑·따닥 등 효과 배너는 그 결과가 실제로 화면에 드러나는 단계에서 띄운다(먹기>뒤집기>놓기 순으로
  // 마지막에 벌어지는 단계) — 그래야 카드가 실제로 움직이기 전에 배너부터 먼저 뜨는 일이 없다
  if Length(FAnimCaptured) > 0 then
  begin
    FEffectStage := 4;
  end
  else
  if Length(FAnimDrawn) > 0 then
  begin
    FEffectStage := 2;
  end
  else
  if Length(FAnimPlayed) > 0 then
  begin
    FEffectStage := 1;
  end
  else
  begin
    FEffectStage := 0;
  end;

  // 애니메이션할 게 없으면(고/스톱 등) 즉시 완료
  if (Length(FAnimPlayed) = 0) and (Length(FAnimDrawn) = 0) and (Length(FAnimCaptured) = 0) then
  begin
    CollectTurnEffects;
    ABefore.Free;
    FAnimDone := nil;
    if Assigned(AOnDone) then
    begin
      AOnDone();
    end;

    Exit;
  end;

  // 출발점: 사람 놓기=클릭한 손패 rect, 그 외=행위자 자리 중심
  var LActorRegion := SeatRegion(PhysicalPos(FAnimActor));
  if (FAnimActor = FHumanIndex) and (FClickRect.Width > 0) then
  begin
    FAnimPlayedFrom := PointF((FClickRect.Left + FClickRect.Right) / 2, (FClickRect.Top + FClickRect.Bottom) / 2);
  end
  else
  begin
    FAnimPlayedFrom := PointF((LActorRegion.Left + LActorRegion.Right) / 2, (LActorRegion.Top + LActorRegion.Bottom) / 2);
  end;

  // 뒷패 위치: 중앙 오른쪽
  var LC := CenterRegion;
  FAnimDrawnFrom := PointF(LC.Right - 40, (LC.Top + LC.Bottom) / 2);

  // 표시용 클론을 before로 시작해 단계별로 진행
  FDisplay := ABefore;
  FAiTimer.Enabled := False;
  FAnimStage := 0;
  AnimAdvanceStage;
  FAnimTimer.Enabled := True;
end;

procedure TGostopBoard.AnimApplyStageStart(const AStage: Integer);
begin
  // 뻑·따닥 등 효과 배너는 그 결과가 실제로 보이는 단계가 시작될 때 띄운다(StartTurnAnimation에서 계산한 FEffectStage).
  // 단, 보너스패로 여러 장을 이어 뒤집는 중이면(뒤집기 단계 시작 시점엔 아직 결과가 나온 게 아니라
  // "한장 더~"만 뜨는 상태) — 실제 결과 카드(마지막 장)의 구간이 시작될 때 AnimTick에서 대신 띄운다.
  var LDeferToLastDraw := (AStage = 2) and (Length(FAnimDrawn) > 1);
  if (AStage = FEffectStage) and (not LDeferToLastDraw) then
  begin
    CollectTurnEffects;
  end;

  var CS := CardSize;
  // 먹는 패를 짝 위에 얹을 때 오른쪽-아래로 살짝 밀어 짝이 드러나게
  var LRestOff := PointF(CS.Width * 0.16, CS.Height * 0.26);

  case AStage of
    1:
      begin
        // 놓기 소리
        TGostopAudio.Instance.Play('card_place');
        // 손패에서 들어올림. 먹는 패는 짝 위(오버레이), 그냥 놓는 패는 제 슬롯
        for var LCard in FAnimPlayed do
        begin
          RemoveCardByAsset(FDisplay.Player(FAnimActor).Hand, LCard.AssetId);
        end;

        var LTemp := TList<THwatuCard>.Create;
        try
          LTemp.AddRange(FDisplay.Floor);
          for var LCard in FAnimPlayed do
          begin
            if not IsCapturedAsset(LCard.AssetId) then
            begin
              LTemp.Add(LCard);
            end;
          end;

          SetLength(FFlySources, Length(FAnimPlayed));
          SetLength(FFlyTargets, Length(FAnimPlayed));
          for var I := 0 to High(FAnimPlayed) do
          begin
            FFlySources[I] := FAnimPlayedFrom;
            if IsCapturedAsset(FAnimPlayed[I].AssetId) then
            begin
              var LM := FloorMonthCenter(FAnimPlayed[I].Month);
              // 폭탄처럼 같은 월 손패 여러 장이 한꺼번에 잡히면 목표점이 완전히 겹쳐 한 장처럼
              // 보이지 않도록, 같은 월 카드일수록 조금씩 더 벌려 쌓는다
              var LDup := 0;
              for var K := 0 to I - 1 do
              begin
                if IsCapturedAsset(FAnimPlayed[K].AssetId) and (FAnimPlayed[K].Month = FAnimPlayed[I].Month) then
                begin
                  Inc(LDup);
                end;
              end;

              FFlyTargets[I] := PointF(LM.X + LRestOff.X + LDup * CS.Width * 0.12,
                LM.Y + LRestOff.Y + LDup * CS.Height * 0.10);
            end
            else
            begin
              FFlyTargets[I] := CardCenterInFloor(LTemp, FAnimPlayed[I].AssetId);
            end;
          end;
        finally
          LTemp.Free;
        end;
      end;
    2:
      begin
        // 뒤집기 소리(폴리포니라 놓기 소리와 겹쳐도 안 끊김) — 첫 장은 여기서, 나머지(보너스라
        // 다시 뒤집은 카드)는 AnimTick이 각자의 구간이 시작될 때마다 재생한다
        TGostopAudio.Instance.Play('card_flip');
        FAnimDrawSoundIdx := 0;

        // 첫 장부터 보너스패면 곧바로 "한장 더~" 안내(같은 월 뒤집기가 이어짐을 알림).
        // 단, 그 보너스패가 뒷패의 마지막 장이면 더 뒤집을 패가 없으므로 안내하지 않는다.
        if (Length(FAnimDrawn) > 1) and (FAnimDrawn[0].Kind = hkBonus) then
        begin
          QueueEffect('한장 더~');
        end;

        // 뒷패에서 들어올림(놓기와 동일 처리)
        for var LCard in FAnimDrawn do
        begin
          RemoveCardByAsset(FDisplay.Stock, LCard.AssetId);
        end;

        var LTemp := TList<THwatuCard>.Create;
        try
          LTemp.AddRange(FDisplay.Floor);
          for var LCard in FAnimDrawn do
          begin
            if not IsCapturedAsset(LCard.AssetId) then
            begin
              LTemp.Add(LCard);
            end;
          end;

          SetLength(FFlySources, Length(FAnimDrawn));
          SetLength(FFlyTargets, Length(FAnimDrawn));
          for var I := 0 to High(FAnimDrawn) do
          begin
            FFlySources[I] := FAnimDrawnFrom;
            if IsCapturedAsset(FAnimDrawn[I].AssetId) then
            begin
              var LM := FloorMonthCenter(FAnimDrawn[I].Month);
              FFlyTargets[I] := PointF(LM.X + LRestOff.X, LM.Y + LRestOff.Y);
            end
            else
            begin
              FFlyTargets[I] := CardCenterInFloor(LTemp, FAnimDrawn[I].AssetId);
            end;
          end;
        finally
          LTemp.Free;
        end;
      end;
    4:
      begin
        // 먹기(가져가기) 소리: 특수가 있으면 특수, 없으면 슬라이드 '씁~~'
        if FTurnSpecialPri > 0 then
        begin
          TGostopAudio.Instance.PlayEvent(FTurnSpecialKind);
        end
        else
        begin
          TGostopAudio.Instance.Play('card_capture');
        end;

        // 소스: 얹혀있던 위치(FRest) > 바닥 위치 > 상대 획득더미(뺏어온 피). 타깃은 내 획득더미
        SetLength(FFlySources, Length(FAnimCaptured));
        SetLength(FFlyTargets, Length(FAnimCaptured));
        SetLength(FFlyIsPi, Length(FAnimCaptured));
        var LAnchor := CapturedAnchor(FAnimActor);
        FCaptureConvergePt := LAnchor;   // 손패·바닥패(비-피)를 하나도 못 찾은 극단적 경우의 기본값
        var LConvergeSet := False;
        var LStolen := 0;
        for var I := 0 to High(FAnimCaptured) do
        begin
          FFlyTargets[I] := LAnchor;
          FFlyIsPi[I] := False;
          var LAsset := FAnimCaptured[I].AssetId;
          var LFound := False;

          // 짝 위에 얹혀 대기 중이던 패
          for var J := 0 to High(FRestCards) do
          begin
            if FRestCards[J].AssetId = LAsset then
            begin
              FFlySources[I] := FRestPts[J];
              LFound := True;
              Break;
            end;
          end;

          // 바닥에 있으면 바닥 제자리
          if not LFound then
          begin
            for var K := 0 to FDisplay.Floor.Count - 1 do
            begin
              if FDisplay.Floor[K].AssetId = LAsset then
              begin
                FFlySources[I] := CardCenterInFloor(FDisplay.Floor, LAsset);
                LFound := True;
                Break;
              end;
            end;
          end;

          // 손패·바닥패(비-피) 중 처음 찾은 위치를 "싼 무더기가 있던 자리"로 삼는다(피가 1단계로 모일 지점)
          if LFound and (not LConvergeSet) then
          begin
            FCaptureConvergePt := FFlySources[I];
            LConvergeSet := True;
          end;

          // 그 외 = 상대에게서 뺏어온 피 → 그 상대 획득더미에서 날아옴(1단계: 싼 무더기 자리로 먼저 모임)
          if not LFound then
          begin
            var P := 0;
            while (not LFound) and (P < FDisplay.PlayerCount) do
            begin
              if P <> FAnimActor then
              begin
                for var Q := 0 to FDisplay.Player(P).Captured.Count - 1 do
                begin
                  if FDisplay.Player(P).Captured[Q].AssetId = LAsset then
                  begin
                    FFlySources[I] := CapturedAnchor(P);
                    FFlyIsPi[I] := True;
                    LFound := True;
                    Inc(LStolen);
                    Break;
                  end;
                end;
              end;

              Inc(P);
            end;
          end;

          if not LFound then
          begin
            FFlySources[I] := LAnchor;
          end;
        end;

        // 뺏어온 피가 있으면 뺏기 소리(폴리포니라 다른 소리와 겹쳐도 됨) + 눈에 띄도록 이 단계를 늦춤
        FAnimStealCount := LStolen;
        if LStolen > 0 then
        begin
          TGostopAudio.Instance.Play('sfx_pi_steal');
        end;

        // 표시 클론의 바닥/획득더미에서 제거(FRest 카드는 표시에 없어 제거 대상 아님)
        for var LCard in FAnimCaptured do
        begin
          if not RemoveCardByAsset(FDisplay.Floor, LCard.AssetId) then
          begin
            for var P := 0 to FDisplay.PlayerCount - 1 do
            begin
              if RemoveCardByAsset(FDisplay.Player(P).Captured, LCard.AssetId) then
              begin
                Break;
              end;
            end;
          end;
        end;
      end;
  end;
end;

procedure TGostopBoard.AnimApplyStageEnd(const AStage: Integer);
begin
  case AStage of
    1:
      begin
        // 먹는 패는 짝 위에 얹어 대기(FRest), 그냥 놓는 패는 바닥에 안착
        for var I := 0 to High(FAnimPlayed) do
        begin
          if IsCapturedAsset(FAnimPlayed[I].AssetId) then
          begin
            var LN := Length(FRestCards);
            SetLength(FRestCards, LN + 1);
            SetLength(FRestPts, LN + 1);
            FRestCards[LN] := FAnimPlayed[I];
            FRestPts[LN] := FFlyTargets[I];
          end
          else
          begin
            FDisplay.Floor.Add(FAnimPlayed[I]);
          end;
        end;
      end;
    2:
      begin
        for var I := 0 to High(FAnimDrawn) do
        begin
          if IsCapturedAsset(FAnimDrawn[I].AssetId) then
          begin
            var LN := Length(FRestCards);
            SetLength(FRestCards, LN + 1);
            SetLength(FRestPts, LN + 1);
            FRestCards[LN] := FAnimDrawn[I];
            FRestPts[LN] := FFlyTargets[I];
          end
          else
          begin
            FDisplay.Floor.Add(FAnimDrawn[I]);
          end;
        end;
      end;
    4:
      begin
        for var LCard in FAnimCaptured do
        begin
          FDisplay.Player(FAnimActor).Captured.Add(LCard);
        end;
      end;
  end;
end;

procedure TGostopBoard.AnimAdvanceStage;
begin
  // 다음 '내용 있는' 단계로 진행하며 시작 훅 적용. 없으면 종료.
  repeat
    Inc(FAnimStage);
    FAnimT := 0;

    var LHasContent: Boolean;
    case FAnimStage of
      1:
        begin
          LHasContent := Length(FAnimPlayed) > 0;
        end;
      2:
        begin
          LHasContent := Length(FAnimDrawn) > 0;
        end;
      3:
        begin
          // 뒤집기 후 멈춤(뒷패를 뒤집었을 때만)
          LHasContent := Length(FAnimDrawn) > 0;
        end;
      4:
        begin
          LHasContent := Length(FAnimCaptured) > 0;
        end;
    else
      begin
        FinishAnimation;
        Exit;
      end;
    end;

    if LHasContent then
    begin
      AnimApplyStageStart(FAnimStage);
      Exit;
    end;
  until False;
end;

// 보너스패로 여러 장을 순서대로 뒤집을 때 카드별 시간 구간을 계산한다. 보너스패는 착지 후
// BONUS_HOLD_MS만큼 그대로 멈춰 있어("한장 더~" 등 안내를 읽을 시간을 줌) 다음 장이 바로
// 이어 날아가지 않게 한다 — 후속이 있는 연출이 너무 빨리 지나가 버리는 문제 방지.
// AWinStart/AWinEnd = 전체(0~1) 중 그 카드의 구간, AFlyEnd = 그중 실제 날아가는(착지까지) 부분의 끝.
procedure TGostopBoard.ComputeDrawWindows(out AWinStart, AFlyEnd, AWinEnd: TArray<Single>; out ATotalMs: Single);
const
  FLY_MS = 320.0;
  BONUS_HOLD_MS = 650.0;
begin
  var LN := Length(FAnimDrawn);
  SetLength(AWinStart, LN);
  SetLength(AFlyEnd, LN);
  SetLength(AWinEnd, LN);
  if LN = 0 then
  begin
    ATotalMs := 1;
    Exit;
  end;

  var LDurs: TArray<Single>;
  SetLength(LDurs, LN);
  ATotalMs := 0;
  for var I := 0 to LN - 1 do
  begin
    LDurs[I] := FLY_MS;
    if FAnimDrawn[I].Kind = hkBonus then
    begin
      LDurs[I] := LDurs[I] + BONUS_HOLD_MS;
    end;

    ATotalMs := ATotalMs + LDurs[I];
  end;

  var LCum := 0.0;
  for var I := 0 to LN - 1 do
  begin
    AWinStart[I] := LCum / ATotalMs;
    AFlyEnd[I] := (LCum + FLY_MS) / ATotalMs;
    LCum := LCum + LDurs[I];
    AWinEnd[I] := LCum / ATotalMs;
  end;
end;

procedure TGostopBoard.AnimTick(Sender: TObject);
begin
  if FPaused then
  begin
    Exit;
  end;

  if (FDisplay = nil) or (FAnimStage = 0) then
  begin
    FAnimTimer.Enabled := False;
    Exit;
  end;

  // 단계별 지속시간(ms)
  var LDur: Single := 240.0;
  var LDrawWinStart, LDrawFlyEnd, LDrawWinEnd: TArray<Single>;
  case FAnimStage of
    2:
      begin
        if Length(FAnimDrawn) > 1 then
        begin
          // 보너스패가 나와 다시 뒤집은 경우: 카드별 구간(뒤집기+보너스 정지시간)을 계산해 총 시간으로 씀
          ComputeDrawWindows(LDrawWinStart, LDrawFlyEnd, LDrawWinEnd, LDur);
        end
        else
        begin
          LDur := 320;
        end;
      end;
    3:
      begin
        LDur := 220;   // 멈춤
      end;
    4:
      begin
        LDur := 260;
        if FAnimStealCount > 0 then
        begin
          LDur := 620;   // 상대에게서 피를 뺏어올 땐 눈에 띄도록 느리게
        end;
      end;
  end;

  FAnimT := FAnimT + FAnimTimer.Interval / LDur * FGameSpeed;

  // 보너스패로 여러 장을 순서대로 뒤집는 중이면, 새 카드의 구간에 들어설 때마다 뒤집기 소리 재생
  // + 그 카드도 보너스패면 "한장 더~" 안내를 다시 띄운다(또 이어서 뒤집힘을 알림)
  if (FAnimStage = 2) and (Length(FAnimDrawn) > 1) then
  begin
    var LWinIdx := 0;
    for var I := 0 to High(LDrawWinStart) do
    begin
      if FAnimT >= LDrawWinStart[I] then
      begin
        LWinIdx := I;
      end;
    end;

    if LWinIdx > FAnimDrawSoundIdx then
    begin
      FAnimDrawSoundIdx := LWinIdx;
      TGostopAudio.Instance.Play('card_flip');
      // 이 보너스패가 뒷패의 마지막 장이면(체인에서 더 이어질 카드가 없으면) 안내하지 않는다.
      if (FAnimDrawn[LWinIdx].Kind = hkBonus) and (LWinIdx < High(FAnimDrawn)) then
      begin
        QueueEffect('한장 더~');
      end;

      // 마지막 장(실제 결과가 나오는 카드)의 구간이 시작되면, 그제서야 이번 턴의 결과 배너(뻑! 등)를
      // 큐에 올린다 — "한장 더~"가 먼저 다 보인 뒤 이어서 결과 배너가 뜸(AnimApplyStageStart에서 미룸)
      if (LWinIdx = High(FAnimDrawn)) and (FAnimStage = FEffectStage) then
      begin
        CollectTurnEffects;
      end;
    end;
  end;

  if FAnimT >= 1 then
  begin
    AnimApplyStageEnd(FAnimStage);
    AnimAdvanceStage;
  end;

  Repaint;
end;

procedure TGostopBoard.FinishAnimation;
begin
  FAnimTimer.Enabled := False;
  FAnimStage := 0;
  FreeAndNil(FDisplay);

  var LDone := FAnimDone;
  FAnimDone := nil;
  if Assigned(LDone) then
  begin
    LDone();
  end;
end;

procedure TGostopBoard.DrawFlyerCard(const ACenter: TPointF; const AAssetId: string; const AFlip: Boolean;
  const AProgress: Single; const ASquashY: Single);
begin
  var CS := CardSize;
  var LScaleX := 1.0;
  var LShowBack := False;
  if AFlip then
  begin
    LScaleX := Abs(1 - 2 * AProgress);   // 1→0→1: 중간에 얇아졌다가 다시 펴짐
    LShowBack := AProgress < 0.5;         // 전반부는 뒷면, 후반부는 앞면
  end;

  var LW := CS.Width * LScaleX;
  var LH := CS.Height * ASquashY;   // 착지 임팩트: 도착 막바지에 살짝 눌렸다 펴짐
  var LR := RectF(ACenter.X - LW / 2, ACenter.Y - LH / 2, ACenter.X + LW / 2, ACenter.Y + LH / 2);
  if LShowBack then
  begin
    DrawBack(LR);
  end
  else
  begin
    DrawFront(LR, AAssetId);
  end;
end;

procedure TGostopBoard.DrawFlyers;
begin
  // 먹기 직전 짝 위에 얹혀 대기 중인 카드(뒤집기·멈춤 단계에서 표시) — 살짝 기울여 얹음
  if (FAnimStage = 2) or (FAnimStage = 3) then
  begin
    var CS := CardSize;
    for var I := 0 to High(FRestCards) do
    begin
      DrawCardRotated(FRestPts[I].X, FRestPts[I].Y, CS.Width, CS.Height, 10, FRestCards[I].AssetId, False);
    end;
  end;

  // 손으로 쥔 패를 내려치는 느낌: 초반에 빠르게 튀어나가 감속(ease-out cubic) + 이동 중 살짝
  // 떠오르는 아치(사인 곡선, 이동거리에 비례해 최대 높이 제한) + 도착 막바지 착지 스쿼시
  var LT := FAnimT;
  var LEase := 1 - (1 - LT) * (1 - LT) * (1 - LT);   // ease-out cubic

  var LSquash := 1.0;
  if LT > 0.82 then
  begin
    var LK := (LT - 0.82) / 0.18;
    LSquash := 1 - 0.16 * Sin(LK * Pi);   // 눌렸다(중간) 다시 펴짐(끝)
  end;

  var LCards: TArray<THwatuCard>;
  var LFlip := False;
  case FAnimStage of
    1:
      begin
        LCards := FAnimPlayed;
      end;
    2:
      begin
        LCards := FAnimDrawn;
        LFlip := True;
      end;
    4:
      begin
        LCards := FAnimCaptured;
      end;
  else
    begin
      Exit;
    end;
  end;

  // 뻑 더미를 뺏기와 함께 먹는 경우(먹기 단계 + 뺏은 피 있음): 뺏은 피는 먼저 싼 무더기 자리로
  // 모이고(전반부), 그 다음 손패·바닥패와 함께 한꺼번에 내 자리로 날아간다(후반부) — 2단 비행
  var LTwoLeg := (FAnimStage = 4) and (FAnimStealCount > 0);

  // 뒤집었는데 보너스패(조커)라 다시 뒤집은 경우: 뒷패 여러 장이 한 번에 뒤집힌다.
  // 동시에 겹쳐 날아가면 몇 장이 어떻게 나왔는지 구분이 안 되므로, 순서대로 하나씩 뒤집혀 보이게
  // 카드별 구간(뒤집기+보너스면 정지시간 포함)을 나눠 쓴다(아직 차례가 안 된 카드는 그리지 않음).
  var LMultiDraw := (FAnimStage = 2) and (Length(FAnimDrawn) > 1);
  var LDrawWinStart, LDrawFlyEnd, LDrawWinEnd: TArray<Single>;
  if LMultiDraw then
  begin
    var LDummyMs: Single;
    ComputeDrawWindows(LDrawWinStart, LDrawFlyEnd, LDrawWinEnd, LDummyMs);
  end;

  // 각 카드가 출발점에서 제자리(타깃)로, 직선이 아니라 아치를 그리며 날아감
  for var I := 0 to High(LCards) do
  begin
    if (I > High(FFlySources)) or (I > High(FFlyTargets)) then
    begin
      Break;
    end;

    var LSrc := FFlySources[I];
    var LDst := FFlyTargets[I];
    var LLocalT := LT;
    var LLocalEase := LEase;

    if LMultiDraw and (I <= High(LDrawWinStart)) then
    begin
      if LT < LDrawWinStart[I] then
      begin
        Continue;   // 아직 이 카드 차례가 아님 — 뒷패에 남아있는 것처럼 그리지 않음
      end;

      // 구간 내에서: 앞부분(WinStart~FlyEnd)은 실제 날아가는 구간, 나머지(~WinEnd)는 착지 후
      // 그대로 멈춰 있는 정지시간(보너스패일 때만 존재 — 안내를 읽을 시간)
      if LT >= LDrawFlyEnd[I] then
      begin
        LLocalT := 1;
      end
      else
      begin
        LLocalT := (LT - LDrawWinStart[I]) / (LDrawFlyEnd[I] - LDrawWinStart[I]);
      end;

      LLocalEase := 1 - (1 - LLocalT) * (1 - LLocalT) * (1 - LLocalT);   // ease-out cubic
    end;

    if LTwoLeg and (I <= High(FFlyIsPi)) then
    begin
      if FFlyIsPi[I] then
      begin
        // 뺏은 피: 1구간(상대 자리 → 싼 무더기 자리), 2구간(싼 무더기 자리 → 내 자리)
        if LT < 0.5 then
        begin
          LDst := FCaptureConvergePt;
          LLocalT := LT / 0.5;
        end
        else
        begin
          LSrc := FCaptureConvergePt;
          LLocalT := (LT - 0.5) / 0.5;
        end;
      end
      else
      begin
        // 손패·바닥패 등: 전반부는 싼 무더기 자리에서 대기하다 후반부에 다 같이 이동
        if LT < 0.5 then
        begin
          LDst := LSrc;
          LLocalT := 0;
        end
        else
        begin
          LLocalT := (LT - 0.5) / 0.5;
        end;
      end;

      LLocalEase := 1 - (1 - LLocalT) * (1 - LLocalT) * (1 - LLocalT);   // ease-out cubic
    end;

    var LDX := LDst.X - LSrc.X;
    var LDY := LDst.Y - LSrc.Y;
    var LDist := Sqrt(LDX * LDX + LDY * LDY);
    var LArcH := Min(70.0, LDist * 0.14);
    var LArc := Sin(LLocalT * Pi) * LArcH;

    var LP := PointF(LSrc.X + LDX * LLocalEase, LSrc.Y + LDY * LLocalEase - LArc);
    DrawFlyerCard(LP, LCards[I].AssetId, LFlip, LLocalEase, LSquash);
  end;
end;

procedure TGostopBoard.EnterFlipChoice;
begin
  var LOpts := FEngine.FlipChoiceOptions;
  FFlipOptAssets[0] := LOpts[0].AssetId;
  FFlipOptAssets[1] := LOpts[1].AssetId;
  FFlipChoosing := True;
  FStatus := '뒤집은 패로 가져갈 바닥패를 선택하세요';
  Repaint;
  if Assigned(FOnStateChanged) then
  begin
    FOnStateChanged(Self);
  end;
end;

procedure TGostopBoard.PlayChosen(const AHandIndex: Integer; const AFloorChoice: Integer);
begin
  FChoosing := False;
  FHoverHand := -1;
  FTurnEvents.Clear;
  FEngine.FlipChoiceEnabled := True;   // 사람 차례 → 뒤집기 선택 허용
  var LBefore := FGame.Clone;
  FAwaitingGoStop := FEngine.PlayHandCard(AHandIndex, AFloorChoice);
  StartTurnAnimation(LBefore,
    procedure
    begin
      if FGame.Phase = gpAwaitingFlipChoice then
      begin
        EnterFlipChoice;
      end
      else
      begin
        AutoStopIfLastCard;
        AfterAction;
      end;
    end);
end;

procedure TGostopBoard.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Single);
begin
  inherited;
  FMousePos := PointF(X, Y);
  FMouseDown := True;
  var LPoint := PointF(X, Y);

  // 일시정지 중엔 재개 버튼만 반응(다른 조작은 전부 무시) — 이 체크가 아래 FPaused 전체 차단보다 먼저 와야
  // 일시정지 상태에서도 재개 버튼을 누를 수 있다
  if FPaused then
  begin
    if FBtnPauseBar.Contains(LPoint) then
    begin
      TogglePause;
    end;

    Exit;
  end;

  // 기리(말번 커팅): 카드 클릭=그 위치 컷 / 퉁=그대로
  if FGiriPhase then
  begin
    MouseDownGiri(LPoint);
    Exit;
  end;

  // AI 쇼당 → 사람 수락/거절 응답(최상단 모달)
  if FShodangPending then
  begin
    MouseDownShodangPrompt(LPoint);
    Exit;
  end;

  // 광 판매 발표: 아무 곳이나 클릭하면 즉시 진행(스킵)
  if FGwangShow then
  begin
    FinishGwangSale;
    Exit;
  end;

  // 우하단 크레딧 → GitHub 저장소 열기
  if FCreditRect.Contains(LPoint) then
  begin
    TGostopAudio.Instance.Play('ui_click');
    ShellExecute(0, 'open', 'https://github.com/civilian7/gostop', nil, nil, SW_SHOWNORMAL);
    Exit;
  end;

  // 하단 컨트롤 바(일시정지/자동/볼륨/음소거/속도) — 어떤 화면·상태에서도 동작
  if FBtnPauseBar.Contains(LPoint) then
  begin
    TogglePause;
    Exit;
  end;

  if FBtnAutoBar.Contains(LPoint) then
  begin
    ToggleAutoPlay;
    Exit;
  end;

  if FMuteRect.Contains(LPoint) then
  begin
    TGostopAudio.Instance.Muted := not TGostopAudio.Instance.Muted;
    TGostopAudio.Instance.Play('ui_click');
    SaveSettings;
    Repaint;
    Exit;
  end;

  if FSpeedRect.Contains(LPoint) then
  begin
    FSpdDragging := True;
    SetSpeedFromX(X);
    Exit;
  end;

  if FVolTrackRect.Contains(LPoint) then
  begin
    FVolDragging := True;
    SetVolumeFromX(X);
    Exit;
  end;

  // 애니메이션 진행 중엔 그 외 입력 무시(턴 애니·딜 애니·오링 좌석 교체 애니)
  if Assigned(FDisplay) or FDealing or FShuffling or (Length(FReplacingSeats) > 0) then
  begin
    Exit;
  end;

  // 자동 진행 중(내 턴을 AI가 대신하는 동안)엔 판 자체에 대한 클릭은 무시(컨트롤 바는 위에서 이미 처리됨)
  if FAutoPlay and (FGame <> nil) and (FGame.Current = FHumanIndex) then
  begin
    Exit;
  end;

  // 타이틀 메뉴(게임 없음): 대전 시작/설정/종료 (선 뽑기·4인 협상 중엔 제외)
  if (FGame = nil) and (not FSeonPicking) and (not FNegotiating) then
  begin
    MouseDownTitleArea(LPoint);
    Exit;
  end;

  // 아바타 선택 오버레이: 하나 고르거나 밖을 누르면 닫기
  if FAvatarPicking then
  begin
    MouseDownAvatarPicker(LPoint);
    Exit;
  end;

  // 내 아바타 클릭 → 아바타 선택 열기(게임 화면에서, 관전 모드 제외)
  if (FGame <> nil) and (not FSeonPicking) and (not FSpectator) and Assigned(FAvatarPool) and (FAvatarPool.Count > 0)
    and FMyAvatarRect.Contains(LPoint) then
  begin
    TGostopAudio.Instance.Play('ui_click');
    FAvatarPicking := True;
    Repaint;
    Exit;
  end;

  // 선 뽑기: 내 카드를 클릭해 뒤집기
  if FSeonPicking then
  begin
    MouseDownSeonPick(LPoint);
    Exit;
  end;

  // 보너스 뽑기: 펼쳐진 뒷패에서 한 장 클릭(사람 차례일 때만)
  if (FGame <> nil) and (FGame.Phase = gpAwaitingBonusDraw) then
  begin
    MouseDownBonusDraw(LPoint);
    Exit;
  end;

  // 게임 종료: 새게임(이전 승자가 선) / 중지(매치 종료)
  if (FGame <> nil) and (FGame.Phase = gpFinished) then
  begin
    MouseDownGameOver(LPoint);
    Exit;
  end;

  // 고/스톱 대기: 보드 팝업의 고/스톱 버튼
  if FAwaitingGoStop and (FGame <> nil) and (FGame.Phase = gpAwaitingGoStop) then
  begin
    MouseDownGoStopPrompt(LPoint);
    Exit;
  end;

  // 쇼당 걸기 버튼(사람 차례에 가능할 때만 표시됨)
  if (not FBtnShodang.IsEmpty) and FBtnShodang.Contains(LPoint) and HumanCanShodang then
  begin
    TGostopAudio.Instance.Play('ui_click');
    HumanCallShodang;
    Exit;
  end;

  // 뒤집기 선택 대기: 강조된 후보(바닥 2장) 중 하나를 클릭하면 그 패로 확정
  if FFlipChoosing and (FGame <> nil) and (FGame.Phase = gpAwaitingFlipChoice) then
  begin
    MouseDownFlipChoice(LPoint);
    Exit;
  end;

  // 협상: 왼쪽=참가/광팔기, 오른쪽=포기/안팔기 (사람의 논리 좌석에 따라 슬롯 매핑)
  if FNegotiating then
  begin
    MouseDownNegotiation(LPoint);
    Exit;
  end;

  if (FGame = nil) or (FGame.Phase <> gpPlaying) or (FGame.Current <> FHumanIndex) then
  begin
    Exit;
  end;

  // 선택 모드: 강조된 후보(바닥 같은 월) 클릭
  if FChoosing then
  begin
    MouseDownFloorChoice(LPoint);
    Exit;
  end;

  // 일반 모드: 오른쪽(위에 겹친) 손패부터 히트 테스트
  MouseDownPlayHand(LPoint);
end;

procedure TGostopBoard.MouseDownGiri(const LPoint: TPointF);
begin
  // AI(또는 관전) 말번의 기리는 보여주기만 하고 자동으로 결정되므로, 사람 클릭은 무시
  if FSpectator or (MalbeonPos <> spBottom) then
  begin
    Exit;
  end;

  // 이미 결정 연출(모으기·가르기)이 진행 중이면 추가 클릭 무시
  if FGiriClosing or FGiriSplitting then
  begin
    Exit;
  end;

  if FBtnTung.Contains(LPoint) then
  begin
    TGostopAudio.Instance.Play('ui_click');
    BeginGiriClose(-1);
    Exit;
  end;

  // 부채꼴로 겹친 카드이므로 나중에 그린(위에 보이는) 카드부터 판정
  for var K := FGiriRects.Count - 1 downto 0 do
  begin
    if FGiriRects[K].Contains(LPoint) then
    begin
      TGostopAudio.Instance.Play('ui_click');
      BeginGiriClose(K);
      Exit;
    end;
  end;
end;

procedure TGostopBoard.MouseDownShodangPrompt(const LPoint: TPointF);
begin
  if FBtnShodangYes.Contains(LPoint) then
  begin
    TGostopAudio.Instance.Play('ui_click');
    HumanRespondShodang(True);
  end
  else
  if FBtnShodangNo.Contains(LPoint) then
  begin
    TGostopAudio.Instance.Play('ui_click');
    HumanRespondShodang(False);
  end;
end;

// 타이틀 화면(게임 없음) 클릭 디스패치: 프로그램정보 → 설정창 → 대전설정 다이얼로그 → 타이틀 버튼 순
procedure TGostopBoard.MouseDownTitleArea(const LPoint: TPointF);
begin
  if FInfoOpen then
  begin
    MouseDownProgramInfo(LPoint);
    Exit;
  end;

  if FSettingsOpen then
  begin
    MouseDownSettingsDialog(LPoint);
    Exit;
  end;

  if FMatchSetupOpen then
  begin
    MouseDownMatchSetupDialog(LPoint);
    Exit;
  end;

  MouseDownTitleButtons(LPoint);
end;

procedure TGostopBoard.MouseDownSettingsDialog(const LPoint: TPointF);
begin
  // 아바타 선택 오버레이가 떠 있으면 그것부터
  if FAvatarPicking then
  begin
    for var K := 0 to FAvatarRects.Count - 1 do
    begin
      if FAvatarRects[K].Contains(LPoint) then
      begin
        TGostopAudio.Instance.Play('ui_select');
        SetHumanAvatar(K);
        Break;
      end;
    end;

    FAvatarPicking := False;
    Repaint;
    Exit;
  end;

  // 인원수: 2/3/4 중 클릭한 칸으로 즉시 선택(3분할 버튼)
  for var LSeg := 0 to 2 do
  begin
    if FCfgCountRects[LSeg].Contains(LPoint) then
    begin
      TGostopAudio.Instance.Play('ui_click');
      FSetupCount := LSeg + 2;
      Repaint;
      Exit;
    end;
  end;

  // AI 난이도: 하수/중수/고수/최고수 중 클릭한 칸으로 즉시 선택(4분할 버튼)
  for var LSeg := 0 to 3 do
  begin
    if FCfgSkillRects[LSeg].Contains(LPoint) then
    begin
      TGostopAudio.Instance.Play('ui_click');
      FConfig.AiSkill := AI_SKILL_VALUES[LSeg];
      FConfig.SyncMoneyPerPoint;   // 점당 금액은 게임 레벨에 자동 연동
      SaveSettings;
      Repaint;
      Exit;
    end;
  end;

  for var I := 0 to High(FCfgRects) do
  begin
    if FCfgRects[I].Contains(LPoint) then
    begin
      TGostopAudio.Instance.Play('ui_click');
      if I <= 6 then
      begin
        CycleCfg(I);
      end
      else
      if I = 7 then
      begin
        // 닉네임: 행 위에 입력창 표시
        BeginNickEdit(FCfgRects[7]);
      end
      else
      begin
        // 아바타: 선택 오버레이 열기
        ApplyNickEdit;
        LoadAvatarPool;
        if FAvatarPool.Count > 0 then
        begin
          FAvatarPicking := True;
        end;
      end;

      Repaint;
      Exit;
    end;
  end;

  if FBtnCfgCancel.Contains(LPoint) then
  begin
    TGostopAudio.Instance.Play('ui_click');
    ApplyNickEdit;
    FSettingsOpen := False;
    Repaint;
  end
  else
  if FBtnCfgNext.Contains(LPoint) then
  begin
    TGostopAudio.Instance.Play('ui_click');
    ApplyNickEdit;
    FSettingsOpen := False;
    OpenMatchSetup(FSetupCount);
  end;
end;

procedure TGostopBoard.MouseDownMatchSetupDialog(const LPoint: TPointF);
begin
  if FBtnSetupSpin.Contains(LPoint) then
  begin
    TGostopAudio.Instance.Play('ui_click');
    StartSlotSpin;
    Repaint;
  end
  else
  if FBtnSetupWatch.Contains(LPoint) then
  begin
    TGostopAudio.Instance.Play('ui_click');
    if FSetupHumanRow >= 0 then
    begin
      // 관전 켬: 내 시트도 AI로 채움
      var LOld := FSetupHumanRow;
      FSetupHumanRow := -1;
      StartSlotSpin(LOld);
    end
    else
    begin
      // 관전 끔: 마지막 시트에 복귀
      FSetupHumanRow := FSetupCount - 1;
      FSetupAvatar[FSetupHumanRow] := -1;
      FSlotRemain[FSetupHumanRow] := 0;
    end;

    Repaint;
  end
  else
  if FBtnSetupStart.Contains(LPoint) then
  begin
    TGostopAudio.Instance.Play('ui_click');
    StartMatchFromSetup;
  end
  else
  if FBtnSetupCancel.Contains(LPoint) then
  begin
    TGostopAudio.Instance.Play('ui_click');
    FSlotTimer.Enabled := False;
    FMatchSetupOpen := False;
    Repaint;
  end;
end;

procedure TGostopBoard.MouseDownTitleButtons(const LPoint: TPointF);
begin
  if FBtnMenuContinue.Contains(LPoint) and TGostopSaveGame.Exists then
  begin
    TGostopAudio.Instance.Play('ui_click');
    if not LoadSavedGame then
    begin
      FStatus := '저장된 게임을 불러오지 못했습니다';
      Repaint;
    end;
  end
  else
  if FBtnMenuContinue.Contains(LPoint) and CanResumeMatch then
  begin
    // 중단된 대국 저장은 없지만, 직전에 끝낸 매치가 오링 없이 남아 있는 경우 —
    // 새 대전 설정 없이 같은 게임모드로 머니·전적을 유지한 채 바로 다음 판 시작
    TGostopAudio.Instance.Play('ui_click');
    LoadAvatarPool;
    BeginSeatReplacement(spTop);
  end
  else
  if FBtnMenuNew.Contains(LPoint) then
  begin
    TGostopAudio.Instance.Play('ui_click');
    // 인원수 기본값: 직전 매치 인원(있으면) 유지, 없으면 3인
    if not (FSetupCount in [2, 3, 4]) then
    begin
      if FPlayerCount in [2, 3, 4] then
      begin
        FSetupCount := FPlayerCount;
      end
      else
      begin
        FSetupCount := 3;
      end;
    end;

    FSettingsOpen := True;
    Repaint;
  end
  else
  if FBtnMenuExit.Contains(LPoint) and Assigned(FOnExitRequest) then
  begin
    FOnExitRequest(Self);
  end
  else
  if FBtnMenuManual.Contains(LPoint) then
  begin
    TGostopAudio.Instance.Play('ui_click');
    OpenHelpDoc('gostop-manual.html');
  end
  else
  if FBtnMenuRules.Contains(LPoint) then
  begin
    TGostopAudio.Instance.Play('ui_click');
    OpenHelpDoc('gostop-guide.html');
  end
  else
  if FBtnMenuInfo.Contains(LPoint) then
  begin
    TGostopAudio.Instance.Play('ui_click');
    FInfoOpen := True;
    Repaint;
  end;
end;

procedure TGostopBoard.MouseDownProgramInfo(const LPoint: TPointF);
begin
  if FBtnInfoClose.Contains(LPoint) then
  begin
    TGostopAudio.Instance.Play('ui_click');
    FInfoOpen := False;
    Repaint;
  end;
end;

// help\ 폴더의 문서(사용설명서·고스톱룰)를 exe 기준 상대경로로 찾아 기본 브라우저로 연다
procedure TGostopBoard.OpenHelpDoc(const AFileName: string);
begin
  var LPath := TPath.Combine(TPath.Combine(TPath.GetDirectoryName(ParamStr(0)), 'help'), AFileName);
  if not TFile.Exists(LPath) then
  begin
    FStatus := Format('문서를 찾을 수 없습니다: help\%s', [AFileName]);
    Repaint;
    Exit;
  end;

  Winapi.ShellAPI.ShellExecute(0, 'open', PChar(LPath), nil, nil, SW_SHOWNORMAL);
end;

procedure TGostopBoard.MouseDownAvatarPicker(const LPoint: TPointF);
begin
  for var K := 0 to FAvatarRects.Count - 1 do
  begin
    if FAvatarRects[K].Contains(LPoint) then
    begin
      TGostopAudio.Instance.Play('ui_select');
      SetHumanAvatar(K);
      Break;
    end;
  end;

  FAvatarPicking := False;
  Repaint;
end;

procedure TGostopBoard.MouseDownSeonPick(const LPoint: TPointF);
begin
  if (FSeonStep = seReveal) and FSeonHasCard[spBottom] and (not FSeonRevealed[spBottom])
    and FSeonRect[spBottom].Contains(LPoint) then
  begin
    SeonRevealPos(spBottom);
  end;
end;

procedure TGostopBoard.MouseDownBonusDraw(const LPoint: TPointF);
begin
  if (FGame.Current = FHumanIndex) and (not FPickActive) then
  begin
    for var K := FBonusRects.Count - 1 downto 0 do
    begin
      if FBonusRects[K].Contains(LPoint) then
      begin
        TGostopAudio.Instance.Play('ui_click');
        StartBonusPick(K);
        Break;
      end;
    end;
  end;
end;

procedure TGostopBoard.MouseDownGameOver(const LPoint: TPointF);
begin
  // 머니 카운트 애니메이션이 끝나기 전엔 버튼이 비활성 표시이므로 클릭도 무시
  if not FGameOverReady then
  begin
    Exit;
  end;

  if FBtnNext.Contains(LPoint) then
  begin
    TGostopAudio.Instance.Play('ui_click');
    GameOverContinue;
  end
  else
  if FBtnQuit.Contains(LPoint) then
  begin
    TGostopAudio.Instance.Play('ui_click');
    GameOverQuit;
  end;
end;

procedure TGostopBoard.MouseDownGoStopPrompt(const LPoint: TPointF);
begin
  if FBtnGo.Contains(LPoint) then
  begin
    HumanGo;
  end
  else
  if FBtnStop.Contains(LPoint) then
  begin
    HumanStop;
  end;
end;

procedure TGostopBoard.MouseDownFlipChoice(const LPoint: TPointF);
begin
  for var K := 0 to FFloorRects.Count - 1 do
  begin
    var LRealFloor := FFloorIndexMap[K];
    var LAsset := FGame.Floor[LRealFloor].AssetId;
    if ((LAsset = FFlipOptAssets[0]) or (LAsset = FFlipOptAssets[1])) and FFloorRects[K].Contains(LPoint) then
    begin
      var LOrd := 0;
      if LAsset = FFlipOptAssets[1] then
      begin
        LOrd := 1;
      end;

      TGostopAudio.Instance.Play('ui_click');
      FFlipChoosing := False;
      FTurnEvents.Clear;
      var LBefore := FGame.Clone;
      FAwaitingGoStop := FEngine.ResolveFlipChoice(LOrd);
      StartTurnAnimation(LBefore,
        procedure
        begin
          AutoStopIfLastCard;
          AfterAction;
        end);
      Exit;
    end;
  end;
end;

procedure TGostopBoard.MouseDownNegotiation(const LPoint: TPointF);
begin
  var LLeft := FBtnJoin.Contains(LPoint);
  var LRight := FBtnGiveUp.Contains(LPoint);
  if LLeft or LRight then
  begin
    TGostopAudio.Instance.Play('ui_click');
    var LP2 := False;
    var LP3 := False;
    // AI인 P4는 광값이 있을 때만 판매(0원 판매 방지)
    var LP4 := (FTable4 <> nil) and (TFourPlayer.GwangCount(FTable4.Hand(3), CfgScore) > 0);
    if FNegIsSell then
    begin
      LP4 := LLeft;   // 사람이 P4: 광팔기=왼쪽, 안팔기=오른쪽
    end
    else
    if FHumanLogical = 1 then
    begin
      LP2 := LRight;  // P2 포기=오른쪽
      if not LP2 then
      begin
        LP3 := AiGiveUp(2);   // 사람(P2)이 참가했으니 이제 P3(AI)가 결정할 차례
      end;
    end
    else
    begin
      LP3 := LRight;  // P3 포기=오른쪽 (P2는 이 다이얼로그 이전에 이미 참가로 결정됨)
    end;

    // 누군가 포기하면 P4가 그 자리를 메우므로 광팔기 자체가 없다
    if LP2 or LP3 then
    begin
      LP4 := False;
    end;

    ResolveNegotiation(LP2, LP3, LP4);
  end;
end;

procedure TGostopBoard.MouseDownFloorChoice(const LPoint: TPointF);
begin
  for var K := 0 to FFloorRects.Count - 1 do
  begin
    var LRealFloor := FFloorIndexMap[K];
    if (LRealFloor >= 0) and (LRealFloor < FGame.Floor.Count) and
      (FGame.Floor[LRealFloor].Month = FChooseMonth) and FFloorRects[K].Contains(LPoint) then
    begin
      TGostopAudio.Instance.Play('ui_click');
      PlayChosen(FChooseHandIndex, FloorMatchOrdinal(LRealFloor, FChooseMonth));
      Exit;
    end;
  end;
end;

procedure TGostopBoard.MouseDownPlayHand(const LPoint: TPointF);
begin
  for var K := FHandRects.Count - 1 downto 0 do
  begin
    if FHandRects[K].Contains(LPoint) then
    begin
      var LRealIdx := FHandIndexMap[K];
      if (LRealIdx < 0) or (LRealIdx >= FGame.Player(FHumanIndex).Hand.Count) then
      begin
        Exit;   // 애니 직후 스테일 rect — 다음 Repaint까지 무시
      end;

      FClickRect := FHandRects[K];   // 놓기 애니 출발점
      var LCard := FGame.Player(FHumanIndex).Hand[LRealIdx];
      var LMonth := LCard.Month;

      // 폭탄: 같은 월 3장 보유 + 바닥에 그 월이 있으면 폭탄으로 처리
      var LHandMonthCount := 0;
      for var LHandCard in FGame.Player(FHumanIndex).Hand do
      begin
        if LHandCard.Month = LMonth then
        begin
          Inc(LHandMonthCount);
        end;
      end;

      if (LCard.Kind <> hkBonus) and (LHandMonthCount >= 3) and FEngine.CanBomb(LMonth) then
      begin
        FChoosing := False;
        FHoverHand := -1;
        FTurnEvents.Clear;
        var LBefore := FGame.Clone;
        FAwaitingGoStop := FEngine.PlayBomb(LMonth);
        StartTurnAnimation(LBefore,
          procedure
          begin
            AutoStopIfLastCard;
            AfterAction;
          end);
        Exit;
      end;

      // 바닥 같은 월 2장이 '종류가 서로 다를 때만' 선택(같은 종류면 골라도 무의미 → 자동)
      var LMatchCount := 0;
      var LK0 := hkJunk;
      var LK1 := hkJunk;
      for var LFloorCard in FGame.Floor do
      begin
        if LFloorCard.Month = LMonth then
        begin
          if LMatchCount = 0 then
          begin
            LK0 := LFloorCard.Kind;
          end
          else
          if LMatchCount = 1 then
          begin
            LK1 := LFloorCard.Kind;
          end;

          Inc(LMatchCount);
        end;
      end;

      // 뻑 더미(짝 없이 쌓여 대기 중인 패)면 선택 없이 전부 가져가야 하므로 선택 UI를 건너뛴다
      if (LMatchCount = 2) and (LK0 <> LK1) and (LCard.Kind <> hkBonus) and (not FGame.BbeokCreator.ContainsKey(LMonth)) then
      begin
        TGostopAudio.Instance.Play('ui_select');
        FChoosing := True;
        FChooseHandIndex := LRealIdx;
        FChooseMonth := LMonth;
        FStatus := '가져갈 바닥패를 선택하세요(노란 테두리)';
        Repaint;
        if Assigned(FOnStateChanged) then
        begin
          FOnStateChanged(Self);
        end;
      end
      else
      begin
        PlayChosen(LRealIdx, 0);
      end;

      Exit;
    end;
  end;
end;

procedure TGostopBoard.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Single);
begin
  inherited;
  FMousePos := PointF(X, Y);
  FMouseDown := False;
  if FVolDragging or FSpdDragging then
  begin
    SaveSettings;   // 볼륨·배속 변경 확정 저장
  end;

  FVolDragging := False;
  FSpdDragging := False;
  Repaint;   // 눌림 효과 해제 반영
end;

procedure TGostopBoard.MouseMove(Shift: TShiftState; X, Y: Single);
begin
  inherited;
  FMousePos := PointF(X, Y);
  Repaint;   // 버튼 호버 효과 실시간 반영

  // 슬라이더 드래그
  if FVolDragging then
  begin
    SetVolumeFromX(X);
    Exit;
  end;

  if FSpdDragging then
  begin
    SetSpeedFromX(X);
    Exit;
  end;

  var LNew := -1;
  if (FGame <> nil) and (not Assigned(FDisplay)) and (FGame.Phase = gpPlaying) and (FGame.Current = FHumanIndex) and (not FChoosing) then
  begin
    var LPoint := PointF(X, Y);
    for var K := FHandRects.Count - 1 downto 0 do
    begin
      if FHandRects[K].Contains(LPoint) then
      begin
        LNew := K;
        Break;
      end;
    end;
  end;

  if LNew <> FHoverHand then
  begin
    if LNew >= 0 then
    begin
      TGostopAudio.Instance.Play('ui_hover');
    end;

    FHoverHand := LNew;
    Repaint;
  end;

  // 보너스패 뒷패 뽑기: 사람 차례에 펼쳐진 패 위 호버 추적(손패 호버와 동일한 방식)
  var LNewBonus := -1;
  if (FGame <> nil) and (not Assigned(FDisplay)) and (FGame.Phase = gpAwaitingBonusDraw)
    and (FGame.Current = FHumanIndex) and (not FPickActive) then
  begin
    var LPoint := PointF(X, Y);
    for var K := FBonusRects.Count - 1 downto 0 do
    begin
      if FBonusRects[K].Contains(LPoint) then
      begin
        LNewBonus := K;
        Break;
      end;
    end;
  end;

  if LNewBonus <> FHoverBonus then
  begin
    if LNewBonus >= 0 then
    begin
      TGostopAudio.Instance.Play('ui_hover');
    end;

    FHoverBonus := LNewBonus;
    Repaint;
  end;

  // 기리: 사람이 말번일 때만 마우스로 호버 추적(보너스 뽑기와 동일한 방식). AI/관전 차례의 호버는
  // GiriAiTimerTick이 훑어보기 연출로 직접 제어하므로, 사람 마우스 이동으로 건드리지 않는다
  if FGiriPhase and (not FSpectator) and (MalbeonPos = spBottom) and (not FGiriClosing) and (not FGiriSplitting) then
  begin
    var LNewGiri := -1;
    var LPoint := PointF(X, Y);
    for var K := FGiriRects.Count - 1 downto 0 do
    begin
      if FGiriRects[K].Contains(LPoint) then
      begin
        LNewGiri := K;
        Break;
      end;
    end;

    if LNewGiri <> FHoverGiri then
    begin
      if LNewGiri >= 0 then
      begin
        TGostopAudio.Instance.Play('ui_hover');
      end;

      FHoverGiri := LNewGiri;
      Repaint;
    end;
  end;
end;

procedure TGostopBoard.DoMouseLeave;
begin
  inherited;
  FMousePos := PointF(-1, -1);   // 화면 밖 좌표 → 모든 버튼 호버 해제
  FMouseDown := False;
  FVolDragging := False;
  FSpdDragging := False;
  if FHoverHand <> -1 then
  begin
    FHoverHand := -1;
    Repaint;
  end;

  if FHoverBonus <> -1 then
  begin
    FHoverBonus := -1;
    Repaint;
  end;

  if FHoverGiri <> -1 then
  begin
    FHoverGiri := -1;
    Repaint;
  end;

  Repaint;   // 버튼 호버 해제 반영
end;
{$ENDREGION}

end.
