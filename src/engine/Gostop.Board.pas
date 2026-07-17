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
  System.Generics.Collections,
  Winapi.Windows,
  Winapi.ShellAPI,
  FMX.Types,
  FMX.Controls,
  FMX.Graphics,
  FMX.Edit,
  Gostop.Cards,
  Gostop.Deck,
  Gostop.Deal,
  Gostop.Score,
  Gostop.Play,
  Gostop.Setup,
  Gostop.AI,
  Gostop.FourPlayer,
  Gostop.CardImages,
  Gostop.Audio,
  Gostop.Assets;
{$ENDREGION}

type
  /// <summary>보드 위 좌석의 화면 위치.</summary>
  TSeatPos = (
    spTop,
    spLeft,
    spBottom,
    spRight
  );

  /// <summary>선 뽑기(밤일낮장) 진행 단계.</summary>
  TSeonStep = (
    seReveal,    // 각 자리 카드 공개 대기(AI 자동·사람 클릭)
    seDecide,    // 선 확정 후 잠시 표시
    seTie        // 동점 → 재경합 대기
  );

  /// <summary>딜(패 돌리기) 애니메이션에서 날아가는 카드 1장.</summary>
  TDealFly = record
    Target: TPointF;     // 착지 지점(중심)
    Card: THwatuCard;    // 바닥 카드의 앞면 표시용(손패는 미사용)
    IsFloor: Boolean;    // True=바닥(앞면 착지), False=손패(뒷면)
    Pos: TSeatPos;       // 손패 대상 자리
    Angle: Single;       // 착지 각도(좌/우 자리는 90/270)
    Scale: Single;       // 카드 크기 배율
  end;

  /// <summary>
  ///   고스톱 플레이 보드(FMX 커스텀 컨트롤). 2/3/4인 모드·좌석 배치(반시계)·렌더링·클릭 입력·AI 진행·
  ///   4인 광팔기 협상·고/스톱을 모두 담당한다. 사람은 항상 아래 자리, 나머지는 AI.
  /// </summary>
  TGostopBoard = class(TControl)
  private
    FImages: TCardImageCache;
    FFeltTile: TBitmap;
    FAvatars: array [TSeatPos] of TBitmap;      // 자리별 아바타(절차 생성 폴백)
    FAvatarPool: TObjectList<TBitmap>;          // 파일 아바타 풀(assets\avatars, 지연 로드)
    FSeatAvatar: array [TSeatPos] of Integer;   // 자리별 배정(풀 인덱스, -1=미배정)
    FHumanAvatarIdx: Integer;                   // 사람이 고른 아바타(-1=랜덤). 매치 간 유지
    FAvatarPicking: Boolean;                    // 아바타 선택 오버레이 표시 중
    FAvatarRects: TList<TRectF>;                // 선택 오버레이 아바타 rect
    FMyAvatarRect: TRectF;                      // 내 패널 아바타 rect(클릭 → 선택 열기)

    // 하단 컨트롤 바(볼륨·음소거·게임속도) + 타이틀 메뉴 — 유튜브식 호버 표시
    FGameSpeed: Single;        // 애니·AI 대기 속도 배율(0.5~2.0)
    FBarVisible: Boolean;      // 하단 호버 시에만 컨트롤 바 표시
    FVolDragging: Boolean;     // 볼륨 노브 드래그 중
    FSpdDragging: Boolean;     // 속도 노브 드래그 중
    FMuteRect: TRectF;
    FVolTrackRect: TRectF;
    FSpeedRect: TRectF;        // 속도 슬라이더 히트 영역
    FBtnMenu2: TRectF;
    FBtnMenu3: TRectF;
    FBtnMenu4: TRectF;
    FBtnMenuExit: TRectF;
    FBtnMenuCfg: TRectF;       // 타이틀 '설정' 버튼
    FCreditRect: TRectF;       // 우하단 제작자 크레딧(클릭=GitHub)
    FOnExitRequest: TNotifyEvent;

    // 게임 룰·플레이어 설정(게임 시작 전 설정창에서 변경, INI 유지)
    FCfgPibak: Boolean;          // 피박
    FCfgGwangbak: Boolean;       // 광박
    FCfgGobak: Boolean;          // 고박(×2)
    FCfgBonus: Boolean;          // 보너스패 3장 포함(끄면 순수 48장)
    FCfgMoneyPerPoint: Integer;  // 점당 금액
    FCfgSeedMoney: Integer;      // 시드머니
    FCfgAiSkill: Integer;        // AI 난이도(30/50/70/90)
    FCfgNickname: string;        // 내 닉네임
    FNickEdit: TEdit;            // 닉네임 입력용(설정창에서만 표시, IME 지원)
    FSettingsOpen: Boolean;      // 설정창 표시 중
    FCfgRects: array [0 .. 8] of TRectF;   // 설정 행 값 버튼(7=닉네임, 8=아바타)
    FBtnCfgClose: TRectF;

    // 대전 설정 다이얼로그: 슬롯머신 연출로 AI 배정, 내 시트(P1~PN) 선택, 관전 모드
    FMatchSetupOpen: Boolean;
    FSetupCount: Integer;                        // 시작할 인원(2/3/4)
    FSetupHumanRow: Integer;                     // 내 시트 행(0-기반), -1 = 관전(전원 AI)
    FSetupAvatar: array [0 .. 3] of Integer;     // 행별 배정 아바타(릴 타깃)
    FSetupSkill: array [0 .. 3] of Integer;      // 행별 AI 난이도
    FSlotDisp: array [0 .. 3] of Integer;        // 릴에 현재 표시 중인 아바타
    FSlotRemain: array [0 .. 3] of Integer;      // 남은 스핀 스텝(0=정지)
    FSlotTick: Integer;
    FSlotTimer: TTimer;
    FSetupRowRects: array [0 .. 3] of TRectF;    // 행 클릭 → 내 시트로
    FSetupSkRects: array [0 .. 3] of TRectF;     // 난이도 클릭 → 순환
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
    FResultLines: TArray<string>;
    FAwaitingGoStop: Boolean;

    // 4인 광팔기
    FNegotiating: Boolean;
    FTable4: TTableState;
    FSeatMap: TArray<Integer>;       // 게임 인덱스 → 물리 좌석(0..3)
    FSitOutSeat: Integer;
    FGwang: TGwangSale;
    FNet4: array [0 .. 3] of Integer;

    // 시드머니·전적(물리 자리별로 판 간 지속)
    FStakes: Integer;   // 판돈 배수(나가리 시 다음 판 ×2로 이월, 승부 나면 1로 복귀)
    FMoney: array [TSeatPos] of Integer;
    FWins: array [TSeatPos] of Integer;
    FLosses: array [TSeatPos] of Integer;
    FBtnJoin: TRectF;
    FBtnGiveUp: TRectF;
    FBtnNext: TRectF;
    FBtnGo: TRectF;
    FBtnStop: TRectF;
    FNextStartPos: TSeatPos;   // 선(P1)의 물리 위치. 반시계로 P1→P2→P3→P4 배정
    FHumanLogical: Integer;    // 4인에서 사람의 논리 좌석(0=선,1=P2,2=P3,3=P4)
    FNegIsSell: Boolean;       // 협상 버튼이 광팔기(True) / 참가·포기(False)

    // 선 뽑기(밤일낮장) — 새 매치 시작 시 각자 카드 1장을 뒤집어 선 결정
    FSeonPicking: Boolean;                         // 선 뽑기 진행 중
    FSeonStep: TSeonStep;                          // 현재 단계
    FSeonIsDay: Boolean;                           // 낮(큰 월=선) / 밤(작은 월=선)
    FSeonDeck: TDeck;                              // 뽑기용 셔플 덱(48장)
    FSeonWinner: Integer;                          // 확정된 선 물리위치(Ord), -1=미결정
    FSeonTicks: Integer;                           // 현재 단계 경과 틱(지연용)
    FSeonTimer: TTimer;                            // AI 자동 공개·단계 페이싱
    FSeonCard: array [TSeatPos] of THwatuCard;     // 각 물리 위치가 뒤집은 카드
    FSeonHasCard: array [TSeatPos] of Boolean;     // 이번 라운드 경합자(카드 배정됨)
    FSeonRevealed: array [TSeatPos] of Boolean;    // 앞면 공개됨
    FSeonRect: array [TSeatPos] of TRectF;         // 각 카드 rect(사람 클릭 히트)

    // 보너스 뽑기(더미 펼쳐 고르기) UI + 가져오기 비행 애니메이션
    FBonusRects: TList<TRectF>;   // 펼쳐진 더미 카드 rect(인덱스 = 더미 인덱스)
    FPickActive: Boolean;         // 고른 카드 비행 중
    FPickIndex: Integer;
    FPickFrom: TPointF;
    FPickTo: TPointF;
    FPickT: Single;
    FPickTimer: TTimer;
    FBtnQuit: TRectF;             // 게임 종료 팝업 '중지' 버튼

    // 딜(패 돌리기) 애니메이션 — 덱에서 각 자리·바닥으로 카드가 날아가며 분배
    FDealing: Boolean;
    FDealTimer: TTimer;
    FDealFlies: TArray<TDealFly>;   // 분배 순서대로의 카드 목록
    FDealLanded: Integer;           // 착지 완료 장수
    FDealT: Single;                 // 현재 카드 비행 진행(0~1)
    FDealOnDone: TProc;             // 완료 후 진행(플레이 시작/협상)

    // 단계 애니메이션(놓기→뒤집기→먹기)
    FDisplay: TGameState;            // 애니 중 표시용 상태(진행 중일 때만, 아니면 nil)
    FAnimTimer: TTimer;
    FAnimStage: Integer;            // 0=없음,1=놓기,2=뒤집기,3=멈춤,4=먹기
    FAnimT: Single;                 // 현재 단계 진행(0~1)
    FAnimActor: Integer;
    FAnimPlayed: TArray<THwatuCard>;
    FAnimDrawn: TArray<THwatuCard>;
    FAnimCaptured: TArray<THwatuCard>;
    FAnimPlayedFrom: TPointF;
    FAnimDrawnFrom: TPointF;
    FFlySources: TArray<TPointF>;
    FFlyTargets: TArray<TPointF>;
    FRestCards: TArray<THwatuCard>;   // 먹히기 직전 짝 위에 얹혀 대기하는 카드(낸/뒤집은 패)
    FRestPts: TArray<TPointF>;
    FAnimDone: TProc;
    FClickRect: TRectF;             // 사람이 클릭한 손패 rect(놓기 애니 출발점)

    // 특수 상황(쪽·따닥·싹쓸이·폭탄·흔들기·뻑·총통 등) 배너
    FTurnEvents: TList<TPlayEvent>;
    FEffectText: string;
    FEffectTimer: TTimer;
    FTurnSpecialKind: TPlayEventKind;   // 이번 턴 대표 특수 이벤트(먹기 단계에 재생)
    FTurnSpecialPri: Integer;

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

    FOnStateChanged: TNotifyEvent;
    FOnGameOver: TNotifyEvent;

    procedure AiTimerTick(Sender: TObject);
    procedure ClearGame;
    procedure GenerateFeltTile;
    procedure AfterAction;
    procedure StartPlay;
    procedure StartNegotiation;
    procedure ResolveNegotiation(const AP2Give, AP3Give, AP4Sell: Boolean);
    procedure ProceedAfterSeon;
    procedure BeginSeonPick;
    function  SeonActivePositions: TArray<TSeatPos>;
    function  SeonPosLabel(const APos: TSeatPos): string;
    procedure SeonDealRound;
    procedure SeonRevealPos(const APos: TSeatPos);
    procedure SeonCheckRoundComplete;
    procedure SeonEvaluate;
    procedure SeonFinish;
    procedure SeonTimerTick(Sender: TObject);
    procedure DrawSeonPick;
    procedure BeginDealAnimation(const AFloor: TArray<THwatuCard>; const ACounts: TArray<Integer>; const AOnDone: TProc);
    function  DealDeckPoint: TPointF;
    procedure DealTick(Sender: TObject);
    procedure DrawDeal;
    procedure StartBonusPick(const AStockIndex: Integer);
    procedure PickTick(Sender: TObject);
    procedure DrawBonusDraw;
    procedure BuildFinalSummary;
    function FlagStr(const AResult: TPlayerResult): string;
    function StakesSuffix: string;
    procedure PlayChosen(const AHandIndex: Integer; const AFloorChoice: Integer);
    procedure AutoStopIfLastCard;
    procedure EnterFlipChoice;
    function RState: TGameState;
    procedure StartTurnAnimation(const ABefore: TGameState; const AOnDone: TProc);
    procedure AnimTick(Sender: TObject);
    procedure AnimAdvanceStage;
    procedure AnimApplyStageStart(const AStage: Integer);
    procedure AnimApplyStageEnd(const AStage: Integer);
    procedure FinishAnimation;
    procedure DrawFlyers;
    procedure DrawFlyerCard(const ACenter: TPointF; const AAssetId: string; const AFlip: Boolean; const AProgress: Single);
    procedure DrawEffectBanner;
    procedure EffectTimerTick(Sender: TObject);
    procedure CollectTurnEffects;
    procedure PlayTurnSound;
    function CapturedAnchor(const AActor: Integer): TPointF;
    function FloorMatchOrdinal(const AFloorIndex, AMonth: Integer): Integer;
    function CanCaptureCard(const ACard: THwatuCard): Boolean;
    function PhysicalPos(const AGameIndex: Integer): TSeatPos;
    function SeatLabel(const APhysicalSeat: Integer): string;
    function CardSize: TSizeF;
    procedure DrawFront(const R: TRectF; const AAssetId: string);
    procedure DrawBack(const R: TRectF);
    procedure DrawLabel(const R: TRectF; const AText: string; const AColor: TAlphaColor; const ASize: Single);
    procedure DrawCapturedGrouped(const APile: TList<THwatuCard>; const AX, AY: Single; const AScale: Single);
    procedure DrawCapturedLine(const APile: TList<THwatuCard>; const ACX, ACY, ADX, ADY, ACardW, ACardH, AAngle: Single);
    procedure DrawCardRotated(const ACenterX, ACenterY, ACardW, ACardH, AAngle: Single; const AAssetId: string; const ABack: Boolean);
    procedure DrawHumanHand(const ARegion: TRectF);
    procedure DrawHandList(const AHand: TList<THwatuCard>; const ARegion: TRectF; const AInteractive: Boolean);
    procedure DrawPlayerPanel(const APos: TSeatPos);
    procedure DrawPanels;
    procedure GenerateAvatars;
    procedure LoadAvatarPool;
    procedure AssignAvatars;
    procedure SetHumanAvatar(const AIndex: Integer);
    procedure DrawAvatarPicker;
    procedure DrawControlBar;
    procedure DrawTitleMenu;
    procedure DrawSettings;
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
    function  DerivedSkill(const AAvatarIndex: Integer): Integer;
    procedure RollSeatLuck;
    function  SeatDisplayName(const APos: TSeatPos): string;
    function  SkillLabel(const ASkill: Integer): string;
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
    procedure DrawGoStopPrompt;
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
  PANEL_W = 160;             // 플레이어 정보 패널 너비(전 자리 동일)
  PANEL_H = 104;             // 플레이어 정보 패널 높이(전 자리 동일)

  // 아바타(assets\avatars 순서)와 짝을 이루는 재미난 닉네임 풀
  AVATAR_NAMES: array [0 .. 19] of string = (
    '피주워요', '못먹어도고', '광팔이', '흔들신사', '동네타짜',
    '초단콜렉터', '고도리헌터', '쌍피장인', '뻑전문가', '화투도사',
    '쪽쪽이', '싹쓸이요정', '피박금지', '고고고', '국진할멈',
    '스톱은없다', '자뻑여왕', '점백의달인', '판쓸이할매', '옆집고수'
  );

  // 캐릭터 능력치(각 행 합계 100): [수읽기, 침착, 배짱, 욕심, 운]
  // 수읽기+침착 → AI 스킬(×1.25), 배짱 → GoBias, 욕심 → Greed, 운 → 판별 운 굴림 기반
  AVATAR_STATS: array [0 .. 19, 0 .. 4] of Integer = (
    (10, 15, 10, 25, 40),   // 피주워요
    (10, 10, 40, 30, 10),   // 못먹어도고
    (25, 25, 15, 25, 10),   // 광팔이
    (25, 20, 30, 15, 10),   // 흔들신사
    (35, 30, 15, 15, 5),    // 동네타짜
    (20, 25, 10, 35, 10),   // 초단콜렉터
    (25, 15, 25, 30, 5),    // 고도리헌터
    (25, 30, 15, 20, 10),   // 쌍피장인
    (10, 5, 25, 20, 40),    // 뻑전문가
    (40, 25, 15, 10, 10),   // 화투도사
    (10, 15, 20, 25, 30),   // 쪽쪽이
    (15, 10, 30, 30, 15),   // 싹쓸이요정
    (20, 30, 10, 10, 30),   // 피박금지
    (10, 10, 40, 25, 15),   // 고고고
    (30, 25, 10, 15, 20),   // 국진할멈
    (15, 15, 40, 25, 5),    // 스톱은없다
    (20, 15, 30, 25, 10),   // 자뻑여왕
    (40, 30, 10, 15, 5),    // 점백의달인
    (30, 20, 25, 20, 5),    // 판쓸이할매
    (35, 35, 10, 10, 10)    // 옆집고수
  );

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
function CapturedGroup(const ACard: THwatuCard): Integer;
begin
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
    pekChongtong:
      begin
        Result := '총통!';
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
  FPlayerCount := 2;
  FAiSkill := 70;
  FStatus := '새 게임을 시작하세요';
  FHandRects := TList<TRectF>.Create;
  FHandIndexMap := TList<Integer>.Create;
  FFloorRects := TList<TRectF>.Create;
  FFloorIndexMap := TList<Integer>.Create;
  FAiObjects := TObjectList<TAiPlayer>.Create(True);
  FImages := TCardImageCache.Create(THwatuAssets.PngDir);
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
  FSeonTimer := TTimer.Create(Self);
  FSeonTimer.Interval := 600;
  FSeonTimer.Enabled := False;
  FSeonTimer.OnTimer := SeonTimerTick;
  FDealTimer := TTimer.Create(Self);
  FDealTimer.Interval := 16;   // ~60fps
  FDealTimer.Enabled := False;
  FDealTimer.OnTimer := DealTick;
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
  FSetupHumanRow := 0;
  FRowPos[0] := spTop;
  FRowPos[1] := spBottom;
  FRowPos[2] := spLeft;
  FRowPos[3] := spRight;

  FGameSpeed := 1.0;

  // 게임 룰 기본값(설정창에서 변경 가능)
  FCfgPibak := True;
  FCfgGwangbak := True;
  FCfgGobak := True;
  FCfgBonus := True;
  FCfgMoneyPerPoint := 100;
  FCfgSeedMoney := 30000;
  FCfgAiSkill := 70;
  FCfgNickname := '나';

  Randomize;   // 아바타 랜덤 배정·AI 연출용(덱 셔플은 별도 보안 난수 사용)
  LoadSettings;   // INI(gostop.ini)에서 룰·볼륨·배속·아바타 복원
end;

destructor TGostopBoard.Destroy;
begin
  ClearGame;
  for var LP := spTop to spRight do
  begin
    FreeAndNil(FAvatars[LP]);
  end;

  FreeAndNil(FAiObjects);
  FreeAndNil(FTurnEvents);
  FreeAndNil(FBonusRects);
  FreeAndNil(FAvatarRects);
  FreeAndNil(FAvatarPool);
  FreeAndNil(FFeltTile);
  FreeAndNil(FImages);
  FreeAndNil(FFloorIndexMap);
  FreeAndNil(FFloorRects);
  FreeAndNil(FHandIndexMap);
  FreeAndNil(FHandRects);
  inherited Destroy;
end;

procedure TGostopBoard.ClearGame;
begin
  FAiTimer.Enabled := False;
  FAnimTimer.Enabled := False;
  if Assigned(FSeonTimer) then
  begin
    FSeonTimer.Enabled := False;
  end;

  FSeonPicking := False;
  FreeAndNil(FSeonDeck);
  if Assigned(FDealTimer) then
  begin
    FDealTimer.Enabled := False;
  end;

  FDealing := False;
  FDealFlies := nil;
  FDealOnDone := nil;
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
  FHoverHand := -1;
  FAgents := nil;
  if Assigned(FAiObjects) then
  begin
    FAiObjects.Clear;
  end;

  FreeAndNil(FEngine);
  FreeAndNil(FGame);
  FreeAndNil(FTable4);
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
  for var S := 0 to 3 do
  begin
    FNet4[S] := 0;
  end;

  // 새 매치면 시드머니·전적·판돈 배수 리셋
  if ANewMatch then
  begin
    FStakes := 1;
    for var LP := spTop to spRight do
    begin
      FMoney[LP] := FCfgSeedMoney;
      FWins[LP] := 0;
      FLosses[LP] := 0;
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

// 선(FNextStartPos)이 정해진 뒤 실제 딜·플레이로 진입한다.
procedure TGostopBoard.ProceedAfterSeon;
begin
  if FPlayerCount = 4 then
  begin
    StartNegotiation;
  end
  else
  begin
    // 2/3인: 바로 딜 후 플레이 (보너스패 3장 포함 — 정통 51장)
    var LDeck := TDeck.Create(CfgDeckOptions);
    try
      LDeck.ShuffleSecure;
      var LConfig := TDealConfig.ForPlayers(2);
      if FPlayerCount = 3 then
      begin
        LConfig := TDealConfig.Custom(3, 7, 6);
      end;

      var LTable := TDealer.Deal(LDeck, LConfig);
      try
        // 운 반영은 딜이 아니라 뒤집기 흐름(FEngine.PlayerLuck)에서 — 손패 재배정은
        // 검증 결과 승률 예측력이 없어(46%) 채택하지 않음
        FSeatMap := nil;   // 2/3인은 좌석맵 미사용
        var LNames: TArray<string>;
        SetLength(LNames, FPlayerCount);   // 이름은 아래에서 물리 위치 기준으로 부여
        FGame := TGameState.Create(LNames);
        TGameSetup.Load(FGame, LTable);
      finally
        LTable.Free;
      end;
    finally
      LDeck.Free;
    end;

    // 이름 부여(물리 위치 기준 표시 이름: 나=닉네임, AI=아바타 닉네임)
    for var I := 0 to FPlayerCount - 1 do
    begin
      FGame.Player(I).Name := SeatDisplayName(PhysicalPos(I));
    end;

    // 딜 애니메이션(각 자리 손패 + 바닥) 후 플레이 시작
    var LCounts: TArray<Integer>;
    SetLength(LCounts, 4);
    for var I := 0 to FPlayerCount - 1 do
    begin
      LCounts[Ord(PhysicalPos(I))] := FGame.Player(I).Hand.Count;
    end;

    BeginDealAnimation(FGame.Floor.ToArray, LCounts,
      procedure
      begin
        StartPlay;
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
        // 남은 것은 사람 클릭뿐 → 대기
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

  // 타이틀·안내는 빈 중앙 영역에(자리 카드와 겹치지 않게)
  var LCen := CenterRegion;
  var LMidY := (LCen.Top + LCen.Bottom) / 2;
  DrawLabel(RectF(LCen.Left, LMidY - 52, LCen.Right, LMidY - 20), '선(先) 뽑기 · 밤일낮장', TAlphaColors.White, 26);
  var LSub := '';
  if FSeonIsDay then
  begin
    LSub := '낮 — 가장 큰 월이 선';
  end
  else
  begin
    LSub := '밤 — 가장 작은 월이 선';
  end;

  DrawLabel(RectF(LCen.Left, LMidY - 18, LCen.Right, LMidY + 10), LSub, $FFFFE08A, 16);

  // 확정 시 중앙에 선 발표
  if FSeonWinner >= 0 then
  begin
    DrawLabel(RectF(LCen.Left, LMidY + 14, LCen.Right, LMidY + 50),
      Format('▶ %s 선(先) ◀', [SeonPosLabel(TSeatPos(FSeonWinner))]), $FFFFD54A, 22);
  end;

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
      Canvas.Stroke.Kind := TBrushKind.Solid;
      Canvas.Stroke.Color := $FFFFD54A;
      Canvas.Stroke.Thickness := 4;
      Canvas.DrawRect(RectF(LRect.Left - 5, LRect.Top - 5, LRect.Right + 5, LRect.Bottom + 5), 7, 7,
        [TCorner.TopLeft, TCorner.TopRight, TCorner.BottomLeft, TCorner.BottomRight], 1);
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

// 덱(무더기) 위치 — 중앙 영역 우측(라이브 보드의 더미 위치와 이어지는 느낌)
function TGostopBoard.DealDeckPoint: TPointF;
begin
  var LCen := CenterRegion;
  Result := PointF(LCen.Right - CardSize.Width * 0.7, (LCen.Top + LCen.Bottom) / 2);
end;

procedure TGostopBoard.BeginDealAnimation(const AFloor: TArray<THwatuCard>; const ACounts: TArray<Integer>; const AOnDone: TProc);
var
  LFlies: TList<TDealFly>;
  LTotal: array [TSeatPos] of Integer;

  // 자리 APos의 AIndex번째 손패(총 ATotal장) 착지 정보 — 정보 패널 제외 공간 기준
  function HandFly(const APos: TSeatPos; const AIndex, ATotal: Integer): TDealFly;
  begin
    Result := Default(TDealFly);
    Result.IsFloor := False;
    Result.Pos := APos;
    var CS := CardSize;
    var LA := SeatCardArea(APos);
    var LMidX := (LA.Left + LA.Right) / 2;
    case APos of
      spTop:
        begin
          Result.Scale := 0.45;
          Result.Angle := 0;
          Result.Target := PointF(LMidX + (AIndex - (ATotal - 1) / 2) * CS.Width * 0.45 * 0.45,
            LA.Top + 10 + CS.Height * 0.45 / 2);
        end;
      spBottom:
        begin
          Result.Scale := 0.7;
          Result.Angle := 0;
          Result.Target := PointF(LMidX + (AIndex - (ATotal - 1) / 2) * CS.Width * 0.7 * 0.5,
            LA.Top + LA.Height * 0.55);
        end;
      spLeft:
        begin
          Result.Scale := 0.45;
          Result.Angle := 90;
          Result.Target := PointF(LA.Left + 6 + CS.Height * 0.45 / 2,
            LA.Top + CS.Width * 0.45 / 2 + AIndex * CS.Width * 0.45 * 0.45);
        end;
    else
      begin
        Result.Scale := 0.45;
        Result.Angle := 270;
        Result.Target := PointF(LA.Right - 6 - CS.Height * 0.45 / 2,
          LA.Top + CS.Width * 0.45 / 2 + AIndex * CS.Width * 0.45 * 0.45);
      end;
    end;
  end;

  // 바닥 AIndex번째(총 ATotal장) 착지 정보 — 중앙에 2행 그리드
  function FloorFly(const ACard: THwatuCard; const AIndex, ATotal: Integer): TDealFly;
  begin
    Result := Default(TDealFly);
    Result.IsFloor := True;
    Result.Card := ACard;
    Result.Scale := 0.7;
    Result.Angle := 0;
    var CS := CardSize;
    var LCen := CenterRegion;
    var LCols := (ATotal + 1) div 2;
    var LRow := AIndex div LCols;
    var LCol := AIndex mod LCols;
    var LMidX := (LCen.Left + LCen.Right) / 2 - CS.Width * 0.8;   // 덱(우측)과 안 겹치게 약간 왼쪽
    var LMidY := (LCen.Top + LCen.Bottom) / 2;
    Result.Target := PointF(LMidX + (LCol - (LCols - 1) / 2) * CS.Width * 0.7 * 1.12,
      LMidY + (LRow - 0.5) * CS.Height * 0.7 * 1.12);
  end;

begin
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

    FDealFlies := LFlies.ToArray;
  finally
    LFlies.Free;
  end;

  FDealLanded := 0;
  FDealT := 0;
  FDealOnDone := AOnDone;
  FDealing := True;
  FStatus := '패를 나누는 중...';
  TGostopAudio.Instance.Play('card_deal');
  FDealTimer.Enabled := True;
  Repaint;
end;

procedure TGostopBoard.DealTick(Sender: TObject);
begin
  if not FDealing then
  begin
    FDealTimer.Enabled := False;
    Exit;
  end;

  FDealT := FDealT + 0.22 * FGameSpeed;
  if FDealT >= 1 then
  begin
    FDealT := 0;
    Inc(FDealLanded);
    TGostopAudio.Instance.Play('card_place');
    if FDealLanded >= Length(FDealFlies) then
    begin
      FDealing := False;
      FDealTimer.Enabled := False;
      var LDone := FDealOnDone;
      FDealOnDone := nil;
      if Assigned(LDone) then
      begin
        LDone();
      end;

      Exit;
    end;
  end;

  Repaint;
end;

procedure TGostopBoard.DrawDeal;
begin
  // 자리 영역(포커테이블식)
  for var LP := spTop to spRight do
  begin
    DrawRegion(SeatRegion(LP), False);
  end;

  // 딜 중에도 아바타·정보 패널 유지
  DrawPanels;

  var CS := CardSize;
  var LDeckPt := DealDeckPoint;

  // 덱 스택(뒷면 겹침)
  for var I := 2 downto 0 do
  begin
    DrawCardRotated(LDeckPt.X - I * 2, LDeckPt.Y - I * 2, CS.Width * 0.8, CS.Height * 0.8, 0, '', True);
  end;

  // 착지한 카드
  for var I := 0 to FDealLanded - 1 do
  begin
    var LF := FDealFlies[I];
    DrawCardRotated(LF.Target.X, LF.Target.Y, CS.Width * LF.Scale, CS.Height * LF.Scale, LF.Angle,
      LF.Card.AssetId, not LF.IsFloor);
  end;

  // 비행 중 카드(덱 → 착지 지점, ease-out. 바닥 카드는 중간에 앞면으로 플립)
  if FDealLanded <= High(FDealFlies) then
  begin
    var LF := FDealFlies[FDealLanded];
    var LE := 1 - Sqr(1 - FDealT);
    var LX := LDeckPt.X + (LF.Target.X - LDeckPt.X) * LE;
    var LY := LDeckPt.Y + (LF.Target.Y - LDeckPt.Y) * LE;
    var LBack := (not LF.IsFloor) or (FDealT < 0.5);
    DrawCardRotated(LX, LY, CS.Width * LF.Scale, CS.Height * LF.Scale, LF.Angle * LE, LF.Card.AssetId, LBack);
  end;
end;

// 보너스 뽑기: 펼쳐진 더미에서 AStockIndex 카드를 집어 현재 차례 자리로 날리는 애니 시작
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

  FPickIndex := AStockIndex;

  // 출발점: 펼쳐진 카드 rect(직전 Paint에서 기록) — 없으면 중앙 덱 위치
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
  if not FPickActive then
  begin
    FPickTimer.Enabled := False;
    Exit;
  end;

  FPickT := FPickT + 0.1 * FGameSpeed;
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

// 보너스 뽑기 오버레이: 남은 더미를 뒷면으로 펼쳐 보여주고(클릭 선택), 집은 카드는 자리로 비행
procedure TGostopBoard.DrawBonusDraw;
begin
  FBonusRects.Clear;
  var LCount := FGame.Stock.Count;
  if LCount = 0 then
  begin
    Exit;
  end;

  var CS := CardSize;
  var LW := CS.Width * 0.75;
  var LH := CS.Height * 0.75;
  var LCen := CenterRegion;
  var LPerRow := Min(LCount, 12);
  var LRows := (LCount + LPerRow - 1) div LPerRow;
  var LStep := Min(LW * 0.9, (LCen.Width - 60) / LPerRow);
  var LPanelW := LStep * (LPerRow - 1) + LW + 36;
  var LPanelH := LRows * (LH + 10) + 56;
  var LMidX := (LCen.Left + LCen.Right) / 2;
  var LMidY := (LCen.Top + LCen.Bottom) / 2;
  var LPanel := RectF(LMidX - LPanelW / 2, LMidY - LPanelH / 2, LMidX + LPanelW / 2, LMidY + LPanelH / 2);

  Canvas.Fill.Kind := TBrushKind.Solid;
  Canvas.Fill.Color := $E0101010;
  Canvas.FillRect(LPanel, 10, 10, [TCorner.TopLeft, TCorner.TopRight, TCorner.BottomLeft, TCorner.BottomRight], 1);
  Canvas.Stroke.Kind := TBrushKind.Solid;
  Canvas.Stroke.Color := $60FFFFFF;
  Canvas.Stroke.Thickness := 1;
  Canvas.DrawRect(LPanel, 10, 10, [TCorner.TopLeft, TCorner.TopRight, TCorner.BottomLeft, TCorner.BottomRight], 1);

  var LTitle := '';
  if FGame.Current = FHumanIndex then
  begin
    LTitle := '더미에서 가져올 패를 고르세요';
  end
  else
  begin
    LTitle := Format('%s이(가) 더미에서 한 장 가져갑니다', [FGame.CurrentPlayer.Name]);
  end;

  DrawLabel(RectF(LPanel.Left, LPanel.Top + 6, LPanel.Right, LPanel.Top + 34), LTitle, TAlphaColors.White, 16);

  // 뒷면 펼침(행별 가운데 정렬). 비행 중인 카드 자리는 비워 둔다
  for var I := 0 to LCount - 1 do
  begin
    var LRow := I div LPerRow;
    var LCol := I mod LPerRow;
    var LInRow := Min(LPerRow, LCount - LRow * LPerRow);
    var LX0 := LMidX - (LStep * (LInRow - 1) + LW) / 2;
    var LR := RectF(LX0 + LCol * LStep, LPanel.Top + 42 + LRow * (LH + 10),
      LX0 + LCol * LStep + LW, LPanel.Top + 42 + LRow * (LH + 10) + LH);
    FBonusRects.Add(LR);
    if FPickActive and (I = FPickIndex) then
    begin
      Continue;
    end;

    DrawBack(LR);
  end;

  // 집은 카드 비행(ease-out)
  if FPickActive then
  begin
    var LE := 1 - Sqr(1 - FPickT);
    var LX := FPickFrom.X + (FPickTo.X - FPickFrom.X) * LE;
    var LY := FPickFrom.Y + (FPickTo.Y - FPickFrom.Y) * LE;
    DrawBack(RectF(LX - LW / 2, LY - LH / 2, LX + LW / 2, LY + LH / 2));
  end;
end;

procedure TGostopBoard.StartNegotiation;
begin
  // 4인 딜 (보너스패 3장 포함 — 정통 51장)
  var LDeck := TDeck.Create(CfgDeckOptions);
  try
    LDeck.ShuffleSecure;
    FTable4 := TDealer.Deal(LDeck, TDealConfig.Custom(4, 7, 6));
  finally
    LDeck.Free;
  end;

  // 운 반영은 뒤집기 흐름(FEngine.PlayerLuck, StartPlay에서 설정)에서 처리

  // 딜 애니메이션(4자리 각 7장 + 바닥) 후 협상 진행
  BeginDealAnimation(FTable4.Floor.ToArray, [7, 7, 7, 7],
    procedure
    begin
      TGostopAudio.Instance.Play('sfx_negotiate');

      // 선 기준 사람의 논리 좌석(아래 자리 = 물리 spBottom)
      FHumanLogical := (Ord(spBottom) - Ord(FNextStartPos) + 4) mod 4;

      // 관전(전원 AI)이거나 사람이 선(논리0)이면 결정할 것이 없음 → 자동 진행(AI 모두 참가, P4 광팔기)
      if FSpectator or (FHumanLogical = 0) then
      begin
        ResolveNegotiation(False, False, True);
        Exit;
      end;

      // 사람이 P2/P3면 참가·포기, P4면 광팔기 결정
      FNegIsSell := FHumanLogical = 3;
      FNegotiating := True;
      Repaint;
      if Assigned(FOnStateChanged) then
      begin
        FOnStateChanged(Self);
      end;
    end);
end;

procedure TGostopBoard.ResolveNegotiation(const AP2Give, AP3Give, AP4Sell: Boolean);
begin
  FNegotiating := False;

  var LRound := TFourPlayer.Resolve(FTable4, AP2Give, AP3Give, AP4Sell, GWANG_UNIT_PRICE, CfgScore);
  FSeatMap := LRound.PlaySeats;
  FSitOutSeat := LRound.SitOutSeat;
  FGwang := LRound.Gwang;

  // 광값 선불(선 제외, P2·P3 → P4)
  if FGwang.Sold then
  begin
    TGostopAudio.Instance.Play('sfx_gwang_sell');
    for var LP := 0 to High(FGwang.PayerSeats) do
    begin
      var LPayer := FGwang.PayerSeats[LP];
      FNet4[LPayer] := FNet4[LPayer] - FGwang.ValuePerPayer;
      FNet4[FGwang.SellerSeat] := FNet4[FGwang.SellerSeat] + FGwang.ValuePerPayer;
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
  FreeAndNil(FTable4);

  StartPlay;
end;

procedure TGostopBoard.StartPlay;
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
      LAi.GoBias := EnsureRange(AvatarStat(FSeatAvatar[PhysicalPos(I)], 2) * 2 + 10, 0, 100);
      LAi.Greed := EnsureRange(AvatarStat(FSeatAvatar[PhysicalPos(I)], 3) * 2 + 10, 0, 100);
      FAiObjects.Add(LAi);
      FAgents[I] := LAi;
    end;
  end;

  // 선(먼저 두는 자리): 지정 위치에 해당하는 게임 인덱스부터 시작
  for var I := 0 to FGame.PlayerCount - 1 do
  begin
    if PhysicalPos(I) = FNextStartPos then
    begin
      FGame.Current := I;
      Break;
    end;
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
  FEngine.BonusDrawEnabled := True;   // 보너스패를 내면 더미를 펼쳐 가져올 패를 고른다(사람·AI 모두 연출)

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
  FEngine.ApplyFloorBonus;   // 바닥에 깔린 보너스패는 선이 획득하고 더미에서 보충
  FEngine.ApplyHandChongtong;
  FAwaitingGoStop := False;
  TGostopAudio.Instance.Play('card_deal');
  AfterAction;
end;

function TGostopBoard.FlagStr(const AResult: TPlayerResult): string;
begin
  Result := '';
  if AResult.Gobak then
  begin
    Result := Result + ' 고박';
  end;

  if AResult.Pibak then
  begin
    Result := Result + ' 피박';
  end;

  if AResult.Gwangbak then
  begin
    Result := Result + ' 광박';
  end;

  Result := Trim(Result);
end;

// 판돈 배수 표기(나가리 이월분). ×1이면 빈 문자열
function TGostopBoard.StakesSuffix: string;
begin
  if FStakes > 1 then
  begin
    Result := Format(' (판돈 ×%d)', [FStakes]);
  end
  else
  begin
    Result := '';
  end;
end;

procedure TGostopBoard.BuildFinalSummary;
begin
  var LSettle := FEngine.FinalSettlement;

  var LSeatFlag: array [0 .. 3] of string;
  for var S := 0 to 3 do
  begin
    LSeatFlag[S] := '';
  end;

  // 4인: 게임 정산을 FNet4(좌석)에 합산해 최종 손익 확정 + 좌석별 박 플래그
  if FPlayerCount = 4 then
  begin
    for var I := 0 to High(FSeatMap) do
    begin
      FNet4[FSeatMap[I]] := FNet4[FSeatMap[I]] + LSettle[I].Net;
      LSeatFlag[FSeatMap[I]] := FlagStr(LSettle[I]);
    end;
  end;

  // 물리 자리별 머니 반영(최종 손익 × 단가 × 판돈 배수)
  if FPlayerCount = 4 then
  begin
    for var S := 0 to 3 do
    begin
      var LPos := TSeatPos((Ord(FNextStartPos) + S) mod 4);
      FMoney[LPos] := FMoney[LPos] + FNet4[S] * FCfgMoneyPerPoint * FStakes;
    end;
  end
  else
  begin
    for var I := 0 to FGame.PlayerCount - 1 do
    begin
      FMoney[PhysicalPos(I)] := FMoney[PhysicalPos(I)] + LSettle[I].Net * FCfgMoneyPerPoint * FStakes;
    end;
  end;

  // 전적(참가자만): 승자 1승, 나머지 참가자 1패
  if FGame.Winner >= 0 then
  begin
    Inc(FWins[PhysicalPos(FGame.Winner)]);
    for var I := 0 to FGame.PlayerCount - 1 do
    begin
      if I <> FGame.Winner then
      begin
        Inc(FLosses[PhysicalPos(I)]);
      end;
    end;
  end;

  // 총통 무효 판인지(나가리와 구분 — 판돈 이월 없음)
  var LChongtong := False;
  for var LEvt in FGame.Events do
  begin
    if LEvt.Kind = pekChongtong then
    begin
      LChongtong := True;
      Break;
    end;
  end;

  // 결과 라인
  var LLines := TList<string>.Create;
  try
    if FGame.Winner < 0 then
    begin
      if LChongtong then
      begin
        LLines.Add('총통! — 무효 판');
        LLines.Add('다음 게임으로 넘어갑니다');
      end
      else
      begin
        LLines.Add('나가리 (무승부)');
        LLines.Add(Format('다음 판 판돈 ×%d!', [FStakes * 2]));
      end;
    end
    else
    if FPlayerCount = 4 then
    begin
      var LWinnerSeat := FSeatMap[FGame.Winner];
      LLines.Add(Trim(Format('%s 승%s', [SeatLabel(LWinnerSeat), StakesSuffix])));
      for var S := 0 to 3 do
      begin
        if S <> LWinnerSeat then
        begin
          LLines.Add(Trim(Format('%s   %d원  %s', [SeatLabel(S), FNet4[S] * FCfgMoneyPerPoint * FStakes, LSeatFlag[S]])));
        end;
      end;
    end
    else
    begin
      LLines.Add(Trim(Format('%s 승%s', [FGame.Player(FGame.Winner).Name, StakesSuffix])));
      for var I := 0 to FGame.PlayerCount - 1 do
      begin
        if I <> FGame.Winner then
        begin
          LLines.Add(Trim(Format('%s   %d원  %s',
            [FGame.Player(I).Name, LSettle[I].Net * FCfgMoneyPerPoint * FStakes, FlagStr(LSettle[I])])));
        end;
      end;
    end;

    FResultLines := LLines.ToArray;
  finally
    LLines.Free;
  end;

  // 판돈 배수 갱신: 나가리면 다음 판 ×2 이월(총통 무효 판은 그대로 유지), 승부가 나면 1로 복귀
  if FGame.Winner < 0 then
  begin
    if not LChongtong then
    begin
      FStakes := FStakes * 2;
    end;
  end
  else
  begin
    FStakes := 1;
  end;

  FStatus := string.Join('   ', FResultLines);
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
    BuildFinalSummary;
    if FGame.Winner < 0 then
    begin
      TGostopAudio.Instance.Play('draw');
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
  end
  else
  if FGame.Current = FHumanIndex then
  begin
    FAiTimer.Enabled := False;
    if FAwaitingGoStop then
    begin
      FStatus := Format('%d점! 고 또는 스톱을 선택하세요', [FEngine.ScoreOf(FHumanIndex).Total]);
    end
    else
    if FGame.Phase = gpAwaitingBonusDraw then
    begin
      FStatus := '보너스! 더미에서 가져올 패를 클릭하세요';
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
  if (FGame = nil) or (FGame.Phase = gpFinished) or (FGame.Current = FHumanIndex) then
  begin
    FAiTimer.Enabled := False;
    Exit;
  end;

  // AI가 보너스패를 내고 더미 뽑기 대기 중이면, 펼쳐진 더미에서 한 장을 집는 연출로 진행
  if FGame.Phase = gpAwaitingBonusDraw then
  begin
    FAiTimer.Enabled := False;
    StartBonusPick(Random(FGame.Stock.Count));
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
  var LH := Height * 0.15;
  Result := TSizeF.Create(LH * 600 / 978, LH);
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

procedure TGostopBoard.DrawLabel(const R: TRectF; const AText: string; const AColor: TAlphaColor; const ASize: Single);
begin
  Canvas.Fill.Kind := TBrushKind.Solid;
  Canvas.Fill.Color := AColor;
  Canvas.Font.Size := ASize;
  Canvas.FillText(R, AText, False, 1, [], TTextAlign.Center, TTextAlign.Center);
end;

procedure TGostopBoard.DrawFront(const R: TRectF; const AAssetId: string);
begin
  try
    var LBmp := FImages.ScaledFront(AAssetId, Round(R.Width * Canvas.Scale), Round(R.Height * Canvas.Scale));
    Canvas.DrawBitmap(LBmp, RectF(0, 0, LBmp.Width, LBmp.Height), R, 1, False);
  except
    Canvas.Fill.Kind := TBrushKind.Solid;
    Canvas.Fill.Color := TAlphaColors.White;
    Canvas.FillRect(R, 3, 3, [TCorner.TopLeft, TCorner.TopRight, TCorner.BottomLeft, TCorner.BottomRight], 1);
    DrawLabel(R, AAssetId, TAlphaColors.Black, 8);
  end;
end;

procedure TGostopBoard.DrawBack(const R: TRectF);
begin
  try
    var LBmp := FImages.ScaledBack(FBackColor, Round(R.Width * Canvas.Scale), Round(R.Height * Canvas.Scale));
    Canvas.DrawBitmap(LBmp, RectF(0, 0, LBmp.Width, LBmp.Height), R, 1, False);
  except
    Canvas.Fill.Kind := TBrushKind.Solid;
    Canvas.Fill.Color := TAlphaColors.Darkred;
    Canvas.FillRect(R, 3, 3, [TCorner.TopLeft, TCorner.TopRight, TCorner.BottomLeft, TCorner.BottomRight], 1);
  end;
end;

procedure TGostopBoard.DrawCapturedGrouped(const APile: TList<THwatuCard>; const AX, AY: Single; const AScale: Single);
begin
  var CS := CardSize;
  var LW := CS.Width * AScale;
  var LH := CS.Height * AScale;
  var LStep := LW * 0.4;
  var LGroupGap := LW * 0.5;
  var LX := AX;

  for var G := 0 to 3 do
  begin
    var LIdx := TList<Integer>.Create;
    try
      for var I := 0 to APile.Count - 1 do
      begin
        if CapturedGroup(APile[I]) = G then
        begin
          LIdx.Add(I);
        end;
      end;

      if LIdx.Count = 0 then
      begin
        Continue;
      end;

      SortIndexList(APile, LIdx);
      for var K := 0 to LIdx.Count - 1 do
      begin
        var LR := RectF(LX + K * LStep, AY, LX + K * LStep + LW, AY + LH);
        DrawFront(LR, APile[LIdx[K]].AssetId);
      end;

      LX := LX + LStep * (LIdx.Count - 1) + LW + LGroupGap;
    finally
      LIdx.Free;
    end;
  end;
end;

function TGostopBoard.SeatRegion(const APos: TSeatPos): TRectF;
begin
  // 항상 4인 구조로 고정: 좌/우 좌석은 세로 전체, 상/하/중앙은 두 기둥 사이(서로 침범 없음)
  case APos of
    spTop:
      begin
        Result := RectF(Width * 0.19, Height * 0.012, Width * 0.81, Height * 0.25);
      end;
    spBottom:
      begin
        // 아래는 하단 컨트롤 바(볼륨·속도) 자리를 남기고 끝냄
        Result := RectF(Width * 0.19, Height * 0.70, Width * 0.81, Height * 0.95);
      end;
    spLeft:
      begin
        Result := RectF(Width * 0.005, Height * 0.02, Width * 0.18, Height * 0.95);
      end;
  else
    begin
      Result := RectF(Width * 0.82, Height * 0.02, Width * 0.995, Height * 0.95);
    end;
  end;
end;

function TGostopBoard.CenterRegion: TRectF;
begin
  // 위 영역(P1)을 키운 만큼 중앙을 아래로
  Result := RectF(Width * 0.19, Height * 0.265, Width * 0.81, Height * 0.685);
end;

procedure TGostopBoard.DrawRegion(const ARegion: TRectF; const AHighlight: Boolean);
begin
  if AHighlight then
  begin
    Canvas.Fill.Kind := TBrushKind.Solid;
    Canvas.Fill.Color := $33FFD54A;
    Canvas.FillRect(ARegion, 12, 12, [TCorner.TopLeft, TCorner.TopRight, TCorner.BottomLeft, TCorner.BottomRight], 1);
  end;

  Canvas.Stroke.Kind := TBrushKind.Solid;
  if AHighlight then
  begin
    Canvas.Stroke.Color := $FFFFD54A;
    Canvas.Stroke.Thickness := 4;
  end
  else
  begin
    Canvas.Stroke.Color := $55FFFFFF;
    Canvas.Stroke.Thickness := 1.5;
  end;

  Canvas.DrawRect(ARegion, 12, 12, [TCorner.TopLeft, TCorner.TopRight, TCorner.BottomLeft, TCorner.BottomRight], 1);
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

procedure TGostopBoard.DrawCapturedLine(const APile: TList<THwatuCard>; const ACX, ACY, ADX, ADY, ACardW, ACardH, AAngle: Single);
begin
  var LPX := ACX;
  var LPY := ACY;
  var LFirst := True;
  for var G := 0 to 3 do
  begin
    var LIdx := TList<Integer>.Create;
    try
      for var I := 0 to APile.Count - 1 do
      begin
        if CapturedGroup(APile[I]) = G then
        begin
          LIdx.Add(I);
        end;
      end;

      if LIdx.Count = 0 then
      begin
        Continue;
      end;

      SortIndexList(APile, LIdx);
      if not LFirst then
      begin
        LPX := LPX + ADX * 1.4;
        LPY := LPY + ADY * 1.4;
      end;

      LFirst := False;
      for var K := 0 to LIdx.Count - 1 do
      begin
        DrawCardRotated(LPX, LPY, ACardW, ACardH, AAngle, APile[LIdx[K]].AssetId, False);
        LPX := LPX + ADX;
        LPY := LPY + ADY;
      end;
    finally
      LIdx.Free;
    end;
  end;
end;

procedure TGostopBoard.DrawHandList(const AHand: TList<THwatuCard>; const ARegion: TRectF; const AInteractive: Boolean);
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

    DrawFront(LDrawR, AHand[LRealIdx].AssetId);

    // 먹을 수 있는 카드는 초록 테두리(플레이 중일 때만)
    if AInteractive and CanCaptureCard(AHand[LRealIdx]) then
    begin
      Canvas.Stroke.Kind := TBrushKind.Solid;
      Canvas.Stroke.Color := $FF6CE04C;
      Canvas.Stroke.Thickness := 3;
      Canvas.DrawRect(LDrawR, 4, 4, [TCorner.TopLeft, TCorner.TopRight, TCorner.BottomLeft, TCorner.BottomRight], 1);
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

  // 정보 패널을 제외한 카드 공간에 획득 더미(위) + 손패(아래)
  var LArea := SeatCardArea(spBottom);
  DrawCapturedGrouped(RState.Player(FHumanIndex).Captured, LArea.Left + 4, ARegion.Top + 8, 0.5);
  DrawHandList(RState.Player(FHumanIndex).Hand, LArea, not Assigned(FDisplay));
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
  var LR := SeatRegion(APos);
  var LW := Min(PANEL_W, LR.Width - 8);   // 좁은 창 안전 클램프
  case APos of
    spTop:
      begin
        Result := RectF(LR.Right - 4 - LW, LR.Top + 4, LR.Right - 4, LR.Top + 4 + PANEL_H);
      end;
    spBottom:
      begin
        Result := RectF(LR.Left + 4, LR.Top + 4, LR.Left + 4 + LW, LR.Top + 4 + PANEL_H);
      end;
    spLeft:
      begin
        Result := RectF(LR.Left + 4, LR.Top + 4, LR.Left + 4 + LW, LR.Top + 4 + PANEL_H);
      end;
  else
    begin
      Result := RectF(LR.Left + 4, LR.Bottom - 4 - PANEL_H, LR.Left + 4 + LW, LR.Bottom - 4);
    end;
  end;
end;

// 자리에서 카드가 놓일 공간(정보 패널 제외 영역)
function TGostopBoard.SeatCardArea(const APos: TSeatPos): TRectF;
begin
  var LR := SeatRegion(APos);
  case APos of
    spTop:
      begin
        Result := RectF(LR.Left, LR.Top, LR.Right - PANEL_W - 12, LR.Bottom);
      end;
    spBottom:
      begin
        Result := RectF(LR.Left + PANEL_W + 12, LR.Top, LR.Right, LR.Bottom);
      end;
    spLeft:
      begin
        Result := RectF(LR.Left, LR.Top + PANEL_H + 10, LR.Right, LR.Bottom);
      end;
  else
    begin
      Result := RectF(LR.Left, LR.Top, LR.Right, LR.Bottom - PANEL_H - 10);
    end;
  end;
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

// assets\avatars 의 avatar_*.png 를 풀로 로드(지연, 1회)
procedure TGostopBoard.LoadAvatarPool;
begin
  if Assigned(FAvatarPool) then
  begin
    Exit;
  end;

  FAvatarPool := TObjectList<TBitmap>.Create(True);
  var LDir := THwatuAssets.AvatarDir;
  if (LDir = '') or (not TDirectory.Exists(LDir)) then
  begin
    Exit;
  end;

  var LFiles := TDirectory.GetFiles(LDir, 'avatar_*.png');
  TArray.Sort<string>(LFiles);
  for var LFile in LFiles do
  begin
    try
      FAvatarPool.Add(TBitmap.CreateFromFile(LFile));
    except
      // 손상/열기 실패 파일은 건너뜀(풀에서 제외)
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
    while (LPick = FSeatAvatar[spTop]) or (LPick = FSeatAvatar[spLeft]) or
      (LPick = FSeatAvatar[spBottom]) or (LPick = FSeatAvatar[spRight]) do
    begin
      LPick := (LPick + 1) mod FAvatarPool.Count;
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
      while (LPick = FSeatAvatar[spTop]) or (LPick = FSeatAvatar[spLeft]) or
        (LPick = FSeatAvatar[spBottom]) or (LPick = FSeatAvatar[spRight]) do
      begin
        LPick := (LPick + 1) mod FAvatarPool.Count;
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

  Canvas.Fill.Kind := TBrushKind.Solid;
  Canvas.Fill.Color := $F0101010;
  Canvas.FillRect(LPanel, 12, 12, [TCorner.TopLeft, TCorner.TopRight, TCorner.BottomLeft, TCorner.BottomRight], 1);
  Canvas.Stroke.Kind := TBrushKind.Solid;
  Canvas.Stroke.Color := $60FFFFFF;
  Canvas.Stroke.Thickness := 1;
  Canvas.DrawRect(LPanel, 12, 12, [TCorner.TopLeft, TCorner.TopRight, TCorner.BottomLeft, TCorner.BottomRight], 1);
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
      // 현재 내 아바타: 금색 링
      Canvas.Stroke.Color := $FFFFD54A;
      Canvas.Stroke.Thickness := 3;
      Canvas.DrawEllipse(LR, 1);
    end
    else
    begin
      // 다른 자리가 사용 중이면 회색 링(선택하면 그 자리는 자동 교체)
      for var LP := spTop to spRight do
      begin
        if (LP <> spBottom) and (FSeatAvatar[LP] = I) then
        begin
          Canvas.Stroke.Color := $80B0B0B0;
          Canvas.Stroke.Thickness := 2;
          Canvas.DrawEllipse(LR, 1);
          Break;
        end;
      end;
    end;
  end;
end;

// 하단 바: 전용 메시지 자리(항상) + 유튜브식 컨트롤(호버/드래그 중에만) + 크레딧
procedure TGostopBoard.DrawControlBar;
begin
  // 하단 전용 메시지 바 — 게임 진행 메시지를 큰 글꼴로 표시
  var LMsgBar := RectF(0, Height - 34, Width, Height);
  Canvas.Fill.Kind := TBrushKind.Solid;
  Canvas.Fill.Color := $8A000000;
  Canvas.FillRect(LMsgBar, 0, 0, [], 1);
  if FStatus <> '' then
  begin
    DrawLabel(RectF(20, Height - 33, Width - 190, Height - 3), FStatus, $FFFFE9A8, 17);
  end;

  // 우하단 제작자 크레딧(오른쪽·아래 8px 여백. 클릭 = GitHub 저장소)
  FCreditRect := RectF(Width - 168, Height - 25, Width - 8, Height - 8);
  Canvas.Fill.Kind := TBrushKind.Solid;
  Canvas.Fill.Color := $A0FFE082;
  Canvas.Font.Size := 12;
  Canvas.FillText(FCreditRect, '@시골프로그래머', False, 1, [], TTextAlign.Trailing, TTextAlign.Center);

  // 컨트롤은 하단 호버 시에만(드래그 중엔 유지) 메시지 위로 표시
  if not (FBarVisible or FVolDragging or FSpdDragging) then
  begin
    FMuteRect := TRectF.Empty;
    FVolTrackRect := TRectF.Empty;
    FSpeedRect := TRectF.Empty;
    Exit;
  end;

  var LAudio := TGostopAudio.Instance;
  var LBarH := 32.0;
  var LMidX := Width / 2;
  var LTop := Height - LBarH - 6;
  var LBar := RectF(LMidX - 195, LTop, LMidX + 195, LTop + LBarH);
  var LCY := (LBar.Top + LBar.Bottom) / 2;

  Canvas.Fill.Kind := TBrushKind.Solid;
  Canvas.Fill.Color := $C0000000;
  Canvas.FillRect(LBar, 15, 15, [TCorner.TopLeft, TCorner.TopRight, TCorner.BottomLeft, TCorner.BottomRight], 1);

  // 스피커 아이콘(클릭=음소거 토글)
  FMuteRect := RectF(LBar.Left + 10, LBar.Top + 3, LBar.Left + 38, LBar.Bottom - 3);
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
  Canvas.Fill.Color := $50FFFFFF;
  Canvas.FillRect(LTrack, 3, 3, [TCorner.TopLeft, TCorner.TopRight, TCorner.BottomLeft, TCorner.BottomRight], 1);
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
  Canvas.Fill.Color := $50FFFFFF;
  Canvas.FillRect(LSpd, 3, 3, [TCorner.TopLeft, TCorner.TopRight, TCorner.BottomLeft, TCorner.BottomRight], 1);
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
    FCfgPibak := LIni.ReadBool('Rules', 'Pibak', FCfgPibak);
    FCfgGwangbak := LIni.ReadBool('Rules', 'Gwangbak', FCfgGwangbak);
    FCfgGobak := LIni.ReadBool('Rules', 'Gobak', FCfgGobak);
    FCfgBonus := LIni.ReadBool('Rules', 'Bonus', FCfgBonus);
    FCfgMoneyPerPoint := LIni.ReadInteger('Rules', 'MoneyPerPoint', FCfgMoneyPerPoint);
    FCfgSeedMoney := LIni.ReadInteger('Rules', 'SeedMoney', FCfgSeedMoney);
    FCfgAiSkill := LIni.ReadInteger('Rules', 'AiSkill', FCfgAiSkill);
    FCfgNickname := LIni.ReadString('Player', 'Nickname', FCfgNickname);
    FHumanAvatarIdx := LIni.ReadInteger('UI', 'Avatar', FHumanAvatarIdx);
    FGameSpeed := LIni.ReadFloat('UI', 'GameSpeed', FGameSpeed);
    TGostopAudio.Instance.Volume := LIni.ReadFloat('UI', 'Volume', TGostopAudio.Instance.Volume);
    TGostopAudio.Instance.Muted := LIni.ReadBool('UI', 'Muted', TGostopAudio.Instance.Muted);
  finally
    LIni.Free;
  end;

  // 값 검증(수동 편집 대비)
  FCfgAiSkill := EnsureRange(FCfgAiSkill, 0, 100);
  if FCfgMoneyPerPoint <= 0 then
  begin
    FCfgMoneyPerPoint := 100;
  end;

  if FCfgSeedMoney <= 0 then
  begin
    FCfgSeedMoney := 30000;
  end;

  FGameSpeed := EnsureRange(FGameSpeed, 0.5, 2.0);
  FAiTimer.Interval := Round(650 / FGameSpeed);
  FCfgNickname := Trim(FCfgNickname);
  if FCfgNickname = '' then
  begin
    FCfgNickname := '나';
  end;
end;

// 설정을 INI에 저장(변경 시마다 호출)
procedure TGostopBoard.SaveSettings;
begin
  try
    var LIni := TIniFile.Create(SettingsPath);
    try
      LIni.WriteBool('Rules', 'Pibak', FCfgPibak);
      LIni.WriteBool('Rules', 'Gwangbak', FCfgGwangbak);
      LIni.WriteBool('Rules', 'Gobak', FCfgGobak);
      LIni.WriteBool('Rules', 'Bonus', FCfgBonus);
      LIni.WriteInteger('Rules', 'MoneyPerPoint', FCfgMoneyPerPoint);
      LIni.WriteInteger('Rules', 'SeedMoney', FCfgSeedMoney);
      LIni.WriteInteger('Rules', 'AiSkill', FCfgAiSkill);
      LIni.WriteString('Player', 'Nickname', FCfgNickname);
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
  FNickEdit.Text := FCfgNickname;
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

  FCfgNickname := LName;
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
  Result := TScoreOptions.Default;
  Result.PibakEnabled := FCfgPibak;
  Result.GwangbakEnabled := FCfgGwangbak;
  if FCfgGobak then
  begin
    Result.GobakMultiplier := 2;
  end
  else
  begin
    Result.GobakMultiplier := 1;
  end;
end;

// 설정을 반영한 룰셋
function TGostopBoard.CfgRules: TRuleSet;
begin
  Result := TRuleSet.Default;
  Result.Score := CfgScore;
end;

// 설정을 반영한 덱 구성(보너스패 포함/순수 48장)
function TGostopBoard.CfgDeckOptions: TDeckOptions;
begin
  if FCfgBonus then
  begin
    Result := TDeckOptions.WithBonus(3);
  end
  else
  begin
    Result := TDeckOptions.Standard;
  end;
end;

// 설정 행 값 순환(설정창에서 값 버튼 클릭)
procedure TGostopBoard.CycleCfg(const AIndex: Integer);
begin
  case AIndex of
    0:
      begin
        FCfgPibak := not FCfgPibak;
      end;
    1:
      begin
        FCfgGwangbak := not FCfgGwangbak;
      end;
    2:
      begin
        FCfgGobak := not FCfgGobak;
      end;
    3:
      begin
        FCfgBonus := not FCfgBonus;
      end;
    4:
      begin
        case FCfgMoneyPerPoint of
          50:
            begin
              FCfgMoneyPerPoint := 100;
            end;
          100:
            begin
              FCfgMoneyPerPoint := 500;
            end;
          500:
            begin
              FCfgMoneyPerPoint := 1000;
            end;
        else
          begin
            FCfgMoneyPerPoint := 50;
          end;
        end;
      end;
    5:
      begin
        case FCfgSeedMoney of
          10000:
            begin
              FCfgSeedMoney := 30000;
            end;
          30000:
            begin
              FCfgSeedMoney := 50000;
            end;
          50000:
            begin
              FCfgSeedMoney := 100000;
            end;
        else
          begin
            FCfgSeedMoney := 10000;
          end;
        end;
      end;
    6:
      begin
        case FCfgAiSkill of
          30:
            begin
              FCfgAiSkill := 50;
            end;
          50:
            begin
              FCfgAiSkill := 70;
            end;
          70:
            begin
              FCfgAiSkill := 90;
            end;
        else
          begin
            FCfgAiSkill := 30;
          end;
        end;
      end;
  end;

  SaveSettings;
end;

// 게임 룰·플레이어 설정창(게임 시작 전 타이틀에서만)
procedure TGostopBoard.DrawSettings;
const
  ROW_COUNT = 9;
begin
  var LRowH := 42.0;
  var LPanelW := 460.0;
  var LPanelH := 56 + ROW_COUNT * LRowH + 66;
  var LPanel := RectF(Width / 2 - LPanelW / 2, Height / 2 - LPanelH / 2,
    Width / 2 + LPanelW / 2, Height / 2 + LPanelH / 2);

  Canvas.Fill.Kind := TBrushKind.Solid;
  Canvas.Fill.Color := $F0141414;
  Canvas.FillRect(LPanel, 14, 14, [TCorner.TopLeft, TCorner.TopRight, TCorner.BottomLeft, TCorner.BottomRight], 1);
  Canvas.Stroke.Kind := TBrushKind.Solid;
  Canvas.Stroke.Color := $FFFFD54A;
  Canvas.Stroke.Thickness := 2;
  Canvas.DrawRect(LPanel, 14, 14, [TCorner.TopLeft, TCorner.TopRight, TCorner.BottomLeft, TCorner.BottomRight], 1);
  DrawLabel(RectF(LPanel.Left, LPanel.Top + 12, LPanel.Right, LPanel.Top + 46), '게임 룰 설정', TAlphaColors.Gold, 22);

  // 행: 라벨(왼쪽) + 값 버튼(오른쪽)
  var LLabels: array [0 .. ROW_COUNT - 1] of string;
  LLabels[0] := '피박';
  LLabels[1] := '광박';
  LLabels[2] := '고박 (×2)';
  LLabels[3] := '보너스패';
  LLabels[4] := '점당 금액';
  LLabels[5] := '시드머니';
  LLabels[6] := 'AI 난이도';
  LLabels[7] := '닉네임';
  LLabels[8] := '아바타';

  var LValues: array [0 .. ROW_COUNT - 1] of string;
  if FCfgPibak then
  begin
    LValues[0] := '켬';
  end
  else
  begin
    LValues[0] := '끔';
  end;

  if FCfgGwangbak then
  begin
    LValues[1] := '켬';
  end
  else
  begin
    LValues[1] := '끔';
  end;

  if FCfgGobak then
  begin
    LValues[2] := '켬';
  end
  else
  begin
    LValues[2] := '끔';
  end;

  if FCfgBonus then
  begin
    LValues[3] := '3장 포함';
  end
  else
  begin
    LValues[3] := '없음(48장)';
  end;

  LValues[4] := Format('%s원', [FormatFloat('#,##0', FCfgMoneyPerPoint)]);
  LValues[5] := Format('%s원', [FormatFloat('#,##0', FCfgSeedMoney)]);
  LValues[7] := FCfgNickname;
  LValues[8] := '변경';
  case FCfgAiSkill of
    30:
      begin
        LValues[6] := '초급';
      end;
    50:
      begin
        LValues[6] := '중급';
      end;
    70:
      begin
        LValues[6] := '고급';
      end;
  else
    begin
      LValues[6] := '최상';
    end;
  end;

  for var I := 0 to ROW_COUNT - 1 do
  begin
    var LY := LPanel.Top + 56 + I * LRowH;
    Canvas.Fill.Color := $FFE8EEE4;
    Canvas.Font.Size := 16;
    Canvas.FillText(RectF(LPanel.Left + 28, LY, LPanel.Left + 220, LY + LRowH - 8), LLabels[I],
      False, 1, [], TTextAlign.Leading, TTextAlign.Center);

    FCfgRects[I] := RectF(LPanel.Right - 178, LY + 3, LPanel.Right - 28, LY + LRowH - 8);
    Canvas.Fill.Color := $FF2F4436;
    Canvas.FillRect(FCfgRects[I], 8, 8, [TCorner.TopLeft, TCorner.TopRight, TCorner.BottomLeft, TCorner.BottomRight], 1);
    Canvas.Stroke.Color := $60FFFFFF;
    Canvas.Stroke.Thickness := 1;
    Canvas.DrawRect(FCfgRects[I], 8, 8, [TCorner.TopLeft, TCorner.TopRight, TCorner.BottomLeft, TCorner.BottomRight], 1);
    DrawLabel(FCfgRects[I], LValues[I], $FFFFE082, 15);
  end;

  // 아바타 행: 현재 아바타 썸네일을 값 버튼 안에 표시
  LoadAvatarPool;
  if Assigned(FAvatarPool) and (FHumanAvatarIdx >= 0) and (FHumanAvatarIdx < FAvatarPool.Count) then
  begin
    var LBmp := FAvatarPool[FHumanAvatarIdx];
    var LSide := FCfgRects[8].Height - 4;
    var LTh := RectF(FCfgRects[8].Left + 6, FCfgRects[8].Top + 2, FCfgRects[8].Left + 6 + LSide, FCfgRects[8].Top + 2 + LSide);
    Canvas.DrawBitmap(LBmp, RectF(0, 0, LBmp.Width, LBmp.Height), LTh, 1, False);
  end;

  // 닫기
  FBtnCfgClose := RectF(Width / 2 - 70, LPanel.Bottom - 56, Width / 2 + 70, LPanel.Bottom - 16);
  Canvas.Fill.Color := $FF2E7D32;
  Canvas.FillRect(FBtnCfgClose, 10, 10, [TCorner.TopLeft, TCorner.TopRight, TCorner.BottomLeft, TCorner.BottomRight], 1);
  DrawLabel(FBtnCfgClose, '확인', TAlphaColors.White, 17);
end;

// 아바타 인덱스 → 실명풍 이름(범위 밖이면 빈 문자열)
function TGostopBoard.AvatarName(const AIndex: Integer): string;
begin
  if (AIndex >= 0) and (AIndex <= High(AVATAR_NAMES)) then
  begin
    Result := AVATAR_NAMES[AIndex];
  end
  else
  begin
    Result := '';
  end;
end;

// 캐릭터 능력치 조회(0=수읽기, 1=침착, 2=배짱, 3=욕심, 4=운). 범위 밖 아바타는 평균 20
function TGostopBoard.AvatarStat(const AIndex: Integer; const AStat: Integer): Integer;
begin
  if (AIndex >= 0) and (AIndex <= High(AVATAR_STATS)) and (AStat >= 0) and (AStat <= 4) then
  begin
    Result := AVATAR_STATS[AIndex, AStat];
  end
  else
  begin
    Result := 20;
  end;
end;

// 캐릭터 고유 AI 스킬 = (수읽기 + 침착) × 1.25 (0~100)
function TGostopBoard.DerivedSkill(const AAvatarIndex: Integer): Integer;
begin
  Result := EnsureRange(Round((AvatarStat(AAvatarIndex, 0) + AvatarStat(AAvatarIndex, 1)) * 1.25), 0, 100);
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
    Result := FCfgNickname;
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

function TGostopBoard.SkillLabel(const ASkill: Integer): string;
begin
  if ASkill < 0 then
  begin
    Result := '고유';
    Exit;
  end;

  if ASkill <= 30 then
  begin
    Result := '초급';
  end
  else
  if ASkill <= 50 then
  begin
    Result := '중급';
  end
  else
  if ASkill <= 70 then
  begin
    Result := '고급';
  end
  else
  begin
    Result := '최상';
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

// 대전 설정 열기: 기본 시트(마지막 행=나), AI 행 슬롯머신 스핀 시작
procedure TGostopBoard.OpenMatchSetup(const ACount: Integer);
begin
  FSetupCount := EnsureRange(ACount, 2, 4);
  LoadAvatarPool;
  FSetupHumanRow := FSetupCount - 1;   // 기본: 마지막 시트가 나(클릭으로 변경/관전 가능)
  for var R := 0 to 3 do
  begin
    FSetupAvatar[R] := -1;
    FSetupSkill[R] := -1;   // 기본: 캐릭터 고유 능력치
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
    FSlotRemain[R] := 22 + R * 9 + Random(6);   // 행마다 시차를 두고 멈춤
  end;

  FSlotTick := 0;
  FSlotTimer.Enabled := True;
  TGostopAudio.Instance.Play('card_deal');
end;

procedure TGostopBoard.SlotTick(Sender: TObject);
begin
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
      FSeatSkill[LPos] := FCfgAiSkill;
    end
    else
    begin
      FSeatAvatar[LPos] := FSetupAvatar[R];
      // 고유(-1)면 캐릭터 능력치(수읽기+침착)에서 스킬 유도
      if FSetupSkill[R] < 0 then
      begin
        FSeatSkill[LPos] := DerivedSkill(FSetupAvatar[R]);
      end
      else
      begin
        FSeatSkill[LPos] := FSetupSkill[R];
      end;
    end;
  end;

  FMatchSetupOpen := False;
  NewGame(FSetupCount, FCfgAiSkill);
end;

// 대전 설정 다이얼로그(슬롯머신): 행 클릭=내 시트, 난이도 클릭=순환, 관전 토글
procedure TGostopBoard.DrawMatchSetup;
begin
  var LRowH := 58.0;
  var LPanelW := 480.0;
  var LPanelH := 60 + FSetupCount * LRowH + 118;
  var LPanel := RectF(Width / 2 - LPanelW / 2, Height / 2 - LPanelH / 2,
    Width / 2 + LPanelW / 2, Height / 2 + LPanelH / 2);

  Canvas.Fill.Kind := TBrushKind.Solid;
  Canvas.Fill.Color := $F0141414;
  Canvas.FillRect(LPanel, 14, 14, [TCorner.TopLeft, TCorner.TopRight, TCorner.BottomLeft, TCorner.BottomRight], 1);
  Canvas.Stroke.Kind := TBrushKind.Solid;
  Canvas.Stroke.Color := $FFFFD54A;
  Canvas.Stroke.Thickness := 2;
  Canvas.DrawRect(LPanel, 14, 14, [TCorner.TopLeft, TCorner.TopRight, TCorner.BottomLeft, TCorner.BottomRight], 1);
  DrawLabel(RectF(LPanel.Left, LPanel.Top + 10, LPanel.Right, LPanel.Top + 44),
    Format('대전 설정 — %d인전', [FSetupCount]), TAlphaColors.Gold, 21);

  for var R := 0 to FSetupCount - 1 do
  begin
    var LY := LPanel.Top + 56 + R * LRowH;
    var LRow := RectF(LPanel.Left + 18, LY, LPanel.Right - 18, LY + LRowH - 8);
    FSetupRowRects[R] := RectF(LRow.Left, LRow.Top, LRow.Right - 118, LRow.Bottom);

    // 내 시트 행은 금테 강조
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

    // 시트 라벨
    DrawLabel(RectF(LRow.Left + 6, LRow.Top, LRow.Left + 48, LRow.Bottom), Format('P%d', [R + 1]), $FFB8C4B8, 15);

    // 아바타(릴) + 이름
    var LAvIdx := FSlotDisp[R];
    var LName := '';
    if R = FSetupHumanRow then
    begin
      LAvIdx := FHumanAvatarIdx;
      LName := FCfgNickname + ' (나)';
    end
    else
    begin
      LName := AvatarName(LAvIdx);
      if FSlotRemain[R] > 0 then
      begin
        LName := LName + ' …';
      end;
    end;

    var LAv := RectF(LRow.Left + 52, LRow.Top + 5, LRow.Left + 52 + LRowH - 18, LRow.Top + 5 + LRowH - 18);
    if Assigned(FAvatarPool) and (LAvIdx >= 0) and (LAvIdx < FAvatarPool.Count) then
    begin
      var LBmp := FAvatarPool[LAvIdx];
      Canvas.DrawBitmap(LBmp, RectF(0, 0, LBmp.Width, LBmp.Height), LAv, 1, False);
    end;

    Canvas.Stroke.Color := $80FFFFFF;
    Canvas.Stroke.Thickness := 1;
    Canvas.DrawEllipse(LAv, 1);
    Canvas.Fill.Color := TAlphaColors.White;
    Canvas.Font.Size := 16;
    Canvas.FillText(RectF(LAv.Right + 12, LRow.Top, LRow.Right - 124, LRow.Bottom), LName,
      False, 1, [], TTextAlign.Leading, TTextAlign.Center);

    // 난이도(AI 행만)
    if R <> FSetupHumanRow then
    begin
      FSetupSkRects[R] := RectF(LRow.Right - 110, LRow.Top + 9, LRow.Right - 12, LRow.Bottom - 9);
      Canvas.Fill.Color := $FF37474F;
      Canvas.FillRect(FSetupSkRects[R], 8, 8, [TCorner.TopLeft, TCorner.TopRight, TCorner.BottomLeft, TCorner.BottomRight], 1);
      DrawLabel(FSetupSkRects[R], SkillLabel(FSetupSkill[R]), $FFFFE082, 14);
    end
    else
    begin
      FSetupSkRects[R] := TRectF.Empty;
    end;
  end;

  var LBY := LPanel.Top + 56 + FSetupCount * LRowH + 8;
  DrawLabel(RectF(LPanel.Left, LBY, LPanel.Right, LBY + 20), 'AI 행을 클릭하면 그 시트에 내가 앉습니다', $FF8A968A, 12);

  // 다시 돌리기 · 관전 토글
  FBtnSetupSpin := RectF(LPanel.Left + 30, LBY + 26, LPanel.Left + 30 + 130, LBY + 26 + 36);
  Canvas.Fill.Color := $FF5D4037;
  Canvas.FillRect(FBtnSetupSpin, 8, 8, [TCorner.TopLeft, TCorner.TopRight, TCorner.BottomLeft, TCorner.BottomRight], 1);
  DrawLabel(FBtnSetupSpin, '다시 돌리기', TAlphaColors.White, 14);

  FBtnSetupWatch := RectF(LPanel.Right - 30 - 130, LBY + 26, LPanel.Right - 30, LBY + 26 + 36);
  Canvas.Fill.Color := $FF37474F;
  if FSetupHumanRow < 0 then
  begin
    Canvas.Fill.Color := $FF6A1B9A;
  end;

  Canvas.FillRect(FBtnSetupWatch, 8, 8, [TCorner.TopLeft, TCorner.TopRight, TCorner.BottomLeft, TCorner.BottomRight], 1);
  if FSetupHumanRow < 0 then
  begin
    DrawLabel(FBtnSetupWatch, '관전 모드: 켬', TAlphaColors.White, 14);
  end
  else
  begin
    DrawLabel(FBtnSetupWatch, '관전 모드: 끔', TAlphaColors.White, 14);
  end;

  // 시작 · 취소
  FBtnSetupStart := RectF(Width / 2 - 148, LBY + 72, Width / 2 - 8, LBY + 72 + 40);
  Canvas.Fill.Color := $FF2E7D32;
  Canvas.FillRect(FBtnSetupStart, 10, 10, [TCorner.TopLeft, TCorner.TopRight, TCorner.BottomLeft, TCorner.BottomRight], 1);
  DrawLabel(FBtnSetupStart, '시작', TAlphaColors.White, 17);

  FBtnSetupCancel := RectF(Width / 2 + 8, LBY + 72, Width / 2 + 148, LBY + 72 + 40);
  Canvas.Fill.Color := $FF8E2430;
  Canvas.FillRect(FBtnSetupCancel, 10, 10, [TCorner.TopLeft, TCorner.TopRight, TCorner.BottomLeft, TCorner.BottomRight], 1);
  DrawLabel(FBtnSetupCancel, '취소', TAlphaColors.White, 17);
end;

// 타이틀 메뉴(게임 없음 상태): 로고 + 대전 버튼 + 종료
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
  Canvas.Font.Size := 56;
  Canvas.Fill.Kind := TBrushKind.Solid;
  Canvas.Fill.Color := $C0000000;
  Canvas.FillText(RectF(3, Height * 0.40 + 3, Width + 3, Height * 0.40 + 75), '고스톱',
    False, 1, [], TTextAlign.Center, TTextAlign.Center);
  Canvas.Fill.Color := TAlphaColors.Gold;
  Canvas.FillText(RectF(0, Height * 0.40, Width, Height * 0.40 + 72), '고스톱',
    False, 1, [], TTextAlign.Center, TTextAlign.Center);
  DrawLabel(RectF(0, Height * 0.40 + 74, Width, Height * 0.40 + 100), '- 밤일낮장 · 정통 맞고 -', $FFD8E0D0, 15);

  // 대전 버튼 3개
  var LBW := 150.0;
  var LBH := 54.0;
  var LGap := 24.0;
  var LBY := Height * 0.62;
  FBtnMenu2 := RectF(LMidX - LBW * 1.5 - LGap, LBY, LMidX - LBW * 0.5 - LGap, LBY + LBH);
  FBtnMenu3 := RectF(LMidX - LBW * 0.5, LBY, LMidX + LBW * 0.5, LBY + LBH);
  FBtnMenu4 := RectF(LMidX + LBW * 0.5 + LGap, LBY, LMidX + LBW * 1.5 + LGap, LBY + LBH);

  Canvas.Stroke.Kind := TBrushKind.Solid;
  Canvas.Stroke.Color := $FFFFD54A;
  Canvas.Stroke.Thickness := 2;
  Canvas.Fill.Kind := TBrushKind.Solid;
  Canvas.Fill.Color := $FF2E7D32;
  Canvas.FillRect(FBtnMenu2, 10, 10, [TCorner.TopLeft, TCorner.TopRight, TCorner.BottomLeft, TCorner.BottomRight], 1);
  Canvas.DrawRect(FBtnMenu2, 10, 10, [TCorner.TopLeft, TCorner.TopRight, TCorner.BottomLeft, TCorner.BottomRight], 1);
  DrawLabel(FBtnMenu2, '2인 대전', TAlphaColors.White, 19);

  Canvas.Fill.Color := $FF2E7D32;
  Canvas.FillRect(FBtnMenu3, 10, 10, [TCorner.TopLeft, TCorner.TopRight, TCorner.BottomLeft, TCorner.BottomRight], 1);
  Canvas.DrawRect(FBtnMenu3, 10, 10, [TCorner.TopLeft, TCorner.TopRight, TCorner.BottomLeft, TCorner.BottomRight], 1);
  DrawLabel(FBtnMenu3, '3인 대전', TAlphaColors.White, 19);

  Canvas.Fill.Color := $FF2E7D32;
  Canvas.FillRect(FBtnMenu4, 10, 10, [TCorner.TopLeft, TCorner.TopRight, TCorner.BottomLeft, TCorner.BottomRight], 1);
  Canvas.DrawRect(FBtnMenu4, 10, 10, [TCorner.TopLeft, TCorner.TopRight, TCorner.BottomLeft, TCorner.BottomRight], 1);
  DrawLabel(FBtnMenu4, '4인 대전', TAlphaColors.White, 19);

  // 설정 · 종료
  FBtnMenuCfg := RectF(LMidX - 150, LBY + LBH + 26, LMidX - 10, LBY + LBH + 26 + 40);
  Canvas.Fill.Color := $FF37474F;
  Canvas.FillRect(FBtnMenuCfg, 10, 10, [TCorner.TopLeft, TCorner.TopRight, TCorner.BottomLeft, TCorner.BottomRight], 1);
  DrawLabel(FBtnMenuCfg, '설정', TAlphaColors.White, 17);

  FBtnMenuExit := RectF(LMidX + 10, LBY + LBH + 26, LMidX + 150, LBY + LBH + 26 + 40);
  Canvas.Fill.Color := $FF8E2430;
  Canvas.FillRect(FBtnMenuExit, 10, 10, [TCorner.TopLeft, TCorner.TopRight, TCorner.BottomLeft, TCorner.BottomRight], 1);
  DrawLabel(FBtnMenuExit, '종료', TAlphaColors.White, 17);
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
  Canvas.Fill.Kind := TBrushKind.Solid;
  Canvas.Fill.Color := $E6141414;
  Canvas.FillRect(LBox, 8, 8, [TCorner.TopLeft, TCorner.TopRight, TCorner.BottomLeft, TCorner.BottomRight], 1);
  Canvas.Stroke.Kind := TBrushKind.Solid;
  Canvas.Stroke.Color := $40FFFFFF;
  Canvas.Stroke.Thickness := 1;
  Canvas.DrawRect(LBox, 8, 8, [TCorner.TopLeft, TCorner.TopRight, TCorner.BottomLeft, TCorner.BottomRight], 1);

  // 아바타 이미지 + 테두리 (파일 풀 우선, 없으면 절차 생성 폴백)
  var LAv := RectF(LBox.Left + 8, LBox.Top + 8, LBox.Left + 48, LBox.Top + 48);
  var LAvDrawn := False;
  if Assigned(FAvatarPool) and (FSeatAvatar[APos] >= 0) and (FSeatAvatar[APos] < FAvatarPool.Count) then
  begin
    var LBmp := FAvatarPool[FSeatAvatar[APos]];
    Canvas.DrawBitmap(LBmp, RectF(0, 0, LBmp.Width, LBmp.Height), LAv, 1, False);
    LAvDrawn := True;
  end;

  if (not LAvDrawn) and Assigned(FAvatars[APos]) then
  begin
    Canvas.DrawBitmap(FAvatars[APos], RectF(0, 0, FAvatars[APos].Width, FAvatars[APos].Height), LAv, 1, False);
  end;

  Canvas.Stroke.Color := $80FFFFFF;
  Canvas.DrawEllipse(LAv, 1);

  // 내 아바타 rect(클릭하면 아바타 선택 열림)
  if APos = spBottom then
  begin
    FMyAvatarRect := LAv;
  end;

  // 아바타 아래: 이름(패널 전체 폭 사용 — 긴 닉네임 잘림 방지)
  Canvas.Fill.Color := TAlphaColors.White;
  Canvas.Font.Size := 13;
  Canvas.FillText(RectF(LBox.Left + 8, LBox.Top + 48, LBox.Right - 6, LBox.Top + 66), LLabel,
    False, 1, [], TTextAlign.Leading, TTextAlign.Center);

  // 아바타 오른쪽: 보유머니 + 전적
  Canvas.Fill.Color := TAlphaColors.White;
  Canvas.Font.Size := 13;
  Canvas.FillText(RectF(LAv.Right + 8, LBox.Top + 8, LBox.Right - 6, LBox.Top + 29),
    Format('%s원', [FormatFloat('#,##0', FMoney[APos])]), False, 1, [], TTextAlign.Leading, TTextAlign.Center);
  Canvas.Fill.Color := $FFB8C4B8;
  Canvas.Font.Size := 12;
  Canvas.FillText(RectF(LAv.Right + 8, LBox.Top + 29, LBox.Right - 6, LBox.Top + 48),
    Format('%d승 %d패', [FWins[APos], FLosses[APos]]), False, 1, [], TTextAlign.Leading, TTextAlign.Center);

  // 이번 판 운(굴림) 별점(1~5) — 전적 행 우측
  if FSeatLuckRoll[APos] > 0 then
  begin
    Canvas.Fill.Color := $C0FFD54A;
    Canvas.Font.Size := 10;
    Canvas.FillText(RectF(LAv.Right + 8, LBox.Top + 29, LBox.Right - 8, LBox.Top + 48),
      StringOfChar('★', (FSeatLuckRoll[APos] + 19) div 20), False, 1, [], TTextAlign.Trailing, TTextAlign.Center);
  end;

  // 구분선
  Canvas.Stroke.Color := $30FFFFFF;
  Canvas.DrawLine(PointF(LBox.Left + 8, LBox.Top + 68), PointF(LBox.Right - 8, LBox.Top + 68), 1);

  // 이번 게임 정보: 점수·고·흔들 배지(참가 중) / 관전(4인 빠진 자리) / 게임 전엔 생략
  if (FGame <> nil) and (LIdx < 0) then
  begin
    Canvas.Fill.Color := $FF8A968A;
    Canvas.Font.Size := 12;
    Canvas.FillText(RectF(LBox.Left + 10, LBox.Top + 72, LBox.Right - 6, LBox.Top + 94), '관전',
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
  var LBX := LBox.Left + 6;
  var LBY := LBox.Top + 74;

  // 점수 배지(항상 표시)
  Canvas.Fill.Color := $FF37474F;
  Canvas.FillRect(RectF(LBX, LBY, LBX + 46, LBY + 22), 6, 6,
    [TCorner.TopLeft, TCorner.TopRight, TCorner.BottomLeft, TCorner.BottomRight], 1);
  DrawLabel(RectF(LBX, LBY, LBX + 46, LBY + 22), Format('%d점', [LScore]), $FFFFE082, 13);
  LBX := LBX + 50;

  // 고 배지
  if LGo > 0 then
  begin
    Canvas.Fill.Color := $FFB35900;
    Canvas.FillRect(RectF(LBX, LBY, LBX + 38, LBY + 22), 6, 6,
      [TCorner.TopLeft, TCorner.TopRight, TCorner.BottomLeft, TCorner.BottomRight], 1);
    DrawLabel(RectF(LBX, LBY, LBX + 38, LBY + 22), Format('%d고', [LGo]), TAlphaColors.White, 13);
    LBX := LBX + 42;
  end;

  // 흔들기 배지
  if LShake > 0 then
  begin
    Canvas.Fill.Color := $FF8E2430;
    Canvas.FillRect(RectF(LBX, LBY, LBX + 52, LBY + 22), 6, 6,
      [TCorner.TopLeft, TCorner.TopRight, TCorner.BottomLeft, TCorner.BottomRight], 1);
    DrawLabel(RectF(LBX, LBY, LBX + 52, LBY + 22), Format('흔들%d', [LShake]), TAlphaColors.White, 13);
  end;
end;

procedure TGostopBoard.DrawOpponent(const AGameIndex: Integer; const APos: TSeatPos; const ARegion: TRectF);
begin
  var CS := CardSize;
  var LBackW := CS.Width * 0.45;
  var LBackH := CS.Height * 0.45;
  var LCapW := CS.Width * 0.5;    // 획득 패는 크게(잘 보이게)
  var LCapH := CS.Height * 0.5;
  var LHand := RState.Player(AGameIndex).Hand;
  var LCaptured := RState.Player(AGameIndex).Captured;
  var LHandCount := LHand.Count;
  var LHandStep := LBackW * 0.45;
  var LArea := SeatCardArea(APos);   // 정보 패널을 제외한 카드 공간

  case APos of
    spTop, spBottom:
      begin
        // 가로 배치(회전 없음). 관전 모드에선 아래 자리도 이 형태
        var LCX0 := (LArea.Left + LArea.Right) / 2 - LHandStep * (LHandCount - 1) / 2;
        var LCY := LArea.Top + 10 + LBackH / 2;
        if APos = spBottom then
        begin
          LCY := LArea.Top + 16 + LBackH / 2;
        end;

        for var I := 0 to LHandCount - 1 do
        begin
          DrawCardRotated(LCX0 + I * LHandStep, LCY, LBackW, LBackH, 0, '', True);
        end;

        DrawCapturedGrouped(LCaptured, LArea.Left + 4, LCY + LBackH / 2 + 6, 0.5);
      end;

    spLeft:
      begin
        // 세로 배치 + 90도 회전
        var LXC := LArea.Left + 6 + LBackH / 2;
        var LCY0 := LArea.Top + LBackW / 2;
        for var I := 0 to LHandCount - 1 do
        begin
          DrawCardRotated(LXC, LCY0 + I * LHandStep, LBackW, LBackH, 90, '', True);
        end;

        var LCapXC := LArea.Left + 6 + LBackH + 10 + LCapH / 2;
        DrawCapturedLine(LCaptured, LCapXC, LArea.Top + LCapW / 2, 0, LCapW * 0.5, LCapW, LCapH, 90);
      end;

    spRight:
      begin
        // 세로 배치 + 270도 회전
        var LXC := LArea.Right - 6 - LBackH / 2;
        var LCY0 := LArea.Top + LBackW / 2;
        for var I := 0 to LHandCount - 1 do
        begin
          DrawCardRotated(LXC, LCY0 + I * LHandStep, LBackW, LBackH, 270, '', True);
        end;

        var LCapXC := LArea.Right - 6 - LBackH - 10 - LCapH / 2;
        DrawCapturedLine(LCaptured, LCapXC, LArea.Top + LCapW / 2, 0, LCapW * 0.5, LCapW, LCapH, 270);
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

    // 스톡 폭까지 고려해 가운데 정렬
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
        Canvas.Stroke.Kind := TBrushKind.Solid;
        Canvas.Stroke.Color := TAlphaColors.Yellow;
        Canvas.Stroke.Thickness := 4;
        Canvas.DrawRect(LR, 4, 4, [TCorner.TopLeft, TCorner.TopRight, TCorner.BottomLeft, TCorner.BottomRight], 1);
      end;
    end;
  end;

  // 뒤집을 패 무더기(스톡) — 바닥 오른쪽에 인접, 여러 장 겹쳐 두께 표현
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

  // 내 손패(참가/포기·광팔기 판단용) — 아래 자리에 표시
  if (FTable4 <> nil) and (FTable4.PlayerCount = 4) then
  begin
    DrawHandList(FTable4.Hand(FHumanLogical), SeatRegion(spBottom), False);
  end;

  // 중앙: 바닥패 1장만 표시
  if (FTable4 <> nil) and (FTable4.Floor.Count > 0) then
  begin
    var CS := CardSize;
    var LC := CenterRegion;
    var LX := (LC.Left + LC.Right) / 2 - CS.Width / 2;
    var LY := (LC.Top + LC.Bottom) / 2 - CS.Height / 2;
    DrawFront(RectF(LX, LY, LX + CS.Width, LY + CS.Height), FTable4.Floor[0].AssetId);
  end;

  // 참가/포기 버튼 — 중앙 카드 아래
  var LBtnW := 140.0;
  var LBtnH := 48.0;
  var LGap := 30.0;
  var LCX := Width / 2;
  var LBtnY := Height * 0.60;
  FBtnJoin := RectF(LCX - LBtnW - LGap / 2, LBtnY, LCX - LGap / 2, LBtnY + LBtnH);
  FBtnGiveUp := RectF(LCX + LGap / 2, LBtnY, LCX + LGap / 2 + LBtnW, LBtnY + LBtnH);

  Canvas.Fill.Kind := TBrushKind.Solid;
  Canvas.Fill.Color := $FF2E7D32;
  Canvas.FillRect(FBtnJoin, 8, 8, [TCorner.TopLeft, TCorner.TopRight, TCorner.BottomLeft, TCorner.BottomRight], 1);
  Canvas.Fill.Color := $FF8D3030;
  Canvas.FillRect(FBtnGiveUp, 8, 8, [TCorner.TopLeft, TCorner.TopRight, TCorner.BottomLeft, TCorner.BottomRight], 1);

  if FNegIsSell then
  begin
    DrawLabel(FBtnJoin, '광팔기', TAlphaColors.White, 18);
    DrawLabel(FBtnGiveUp, '안팔기', TAlphaColors.White, 18);
  end
  else
  begin
    DrawLabel(FBtnJoin, '참가', TAlphaColors.White, 18);
    DrawLabel(FBtnGiveUp, '포기', TAlphaColors.White, 18);
  end;
end;

procedure TGostopBoard.DrawGameOver;
begin
  var LN := Length(FResultLines);
  if LN = 0 then
  begin
    Exit;
  end;

  // 중앙 오버레이 패널 — 승자 + 좌석별 금액·박 + 다음게임 버튼
  var LHeadH := 46.0;
  var LLineH := 30.0;
  var LBtnH := 44.0;
  var LPanelH := 18 + LHeadH + (LN - 1) * LLineH + 14 + LBtnH + 18;
  var LPanel := RectF(Width * 0.26, (Height - LPanelH) / 2, Width * 0.74, (Height + LPanelH) / 2);

  Canvas.Fill.Kind := TBrushKind.Solid;
  Canvas.Fill.Color := $EA1C1C1C;
  Canvas.FillRect(LPanel, 16, 16, [TCorner.TopLeft, TCorner.TopRight, TCorner.BottomLeft, TCorner.BottomRight], 1);
  Canvas.Stroke.Kind := TBrushKind.Solid;
  Canvas.Stroke.Color := $FFFFD54A;
  Canvas.Stroke.Thickness := 3;
  Canvas.DrawRect(LPanel, 16, 16, [TCorner.TopLeft, TCorner.TopRight, TCorner.BottomLeft, TCorner.BottomRight], 1);

  var LY := LPanel.Top + 18;
  // 헤드라인(승자 또는 나가리)
  DrawLabel(RectF(LPanel.Left, LY, LPanel.Right, LY + LHeadH), FResultLines[0], TAlphaColors.Gold, 26);
  LY := LY + LHeadH;

  // 플레이어별 라인
  for var I := 1 to LN - 1 do
  begin
    DrawLabel(RectF(LPanel.Left, LY, LPanel.Right, LY + LLineH), FResultLines[I], TAlphaColors.White, 18);
    LY := LY + LLineH;
  end;

  // 버튼 2개: 새게임(이전 승자가 선으로 계속) / 중지(매치 종료)
  var LBtnW := 140.0;
  var LGap := 16.0;
  var LCX := (LPanel.Left + LPanel.Right) / 2;
  FBtnNext := RectF(LCX - LBtnW - LGap / 2, LY + 12, LCX - LGap / 2, LY + 12 + LBtnH);
  Canvas.Fill.Kind := TBrushKind.Solid;
  Canvas.Fill.Color := $FF2E7D32;
  Canvas.FillRect(FBtnNext, 8, 8, [TCorner.TopLeft, TCorner.TopRight, TCorner.BottomLeft, TCorner.BottomRight], 1);
  DrawLabel(FBtnNext, '새게임', TAlphaColors.White, 18);

  FBtnQuit := RectF(LCX + LGap / 2, LY + 12, LCX + LGap / 2 + LBtnW, LY + 12 + LBtnH);
  Canvas.Fill.Color := $FF8E2430;
  Canvas.FillRect(FBtnQuit, 8, 8, [TCorner.TopLeft, TCorner.TopRight, TCorner.BottomLeft, TCorner.BottomRight], 1);
  DrawLabel(FBtnQuit, '중지', TAlphaColors.White, 18);
end;

procedure TGostopBoard.DrawGoStopPrompt;
begin
  var LScore := FEngine.ScoreOf(FHumanIndex).Total;

  var LPanelW := Max(Width * 0.34, 320.0);
  var LPanelH := 128.0;
  var LPanel := RectF((Width - LPanelW) / 2, Height * 0.30, (Width + LPanelW) / 2, Height * 0.30 + LPanelH);
  Canvas.Fill.Kind := TBrushKind.Solid;
  Canvas.Fill.Color := $EA1C1C1C;
  Canvas.FillRect(LPanel, 16, 16, [TCorner.TopLeft, TCorner.TopRight, TCorner.BottomLeft, TCorner.BottomRight], 1);
  Canvas.Stroke.Kind := TBrushKind.Solid;
  Canvas.Stroke.Color := $FFFFD54A;
  Canvas.Stroke.Thickness := 3;
  Canvas.DrawRect(LPanel, 16, 16, [TCorner.TopLeft, TCorner.TopRight, TCorner.BottomLeft, TCorner.BottomRight], 1);

  DrawLabel(RectF(LPanel.Left, LPanel.Top + 14, LPanel.Right, LPanel.Top + 46), Format('%d점! 고 또는 스톱', [LScore]), TAlphaColors.Gold, 22);

  var LBtnW := 120.0;
  var LBtnH := 46.0;
  var LGap := 24.0;
  var LCX := (LPanel.Left + LPanel.Right) / 2;
  var LBtnY := LPanel.Bottom - LBtnH - 16;
  FBtnGo := RectF(LCX - LBtnW - LGap / 2, LBtnY, LCX - LGap / 2, LBtnY + LBtnH);
  FBtnStop := RectF(LCX + LGap / 2, LBtnY, LCX + LGap / 2 + LBtnW, LBtnY + LBtnH);

  Canvas.Fill.Color := $FF2E7D32;
  Canvas.FillRect(FBtnGo, 8, 8, [TCorner.TopLeft, TCorner.TopRight, TCorner.BottomLeft, TCorner.BottomRight], 1);
  Canvas.Fill.Color := $FF8D3030;
  Canvas.FillRect(FBtnStop, 8, 8, [TCorner.TopLeft, TCorner.TopRight, TCorner.BottomLeft, TCorner.BottomRight], 1);
  DrawLabel(FBtnGo, '고', TAlphaColors.White, 20);
  DrawLabel(FBtnStop, '스톱', TAlphaColors.White, 20);
end;

procedure TGostopBoard.Paint;
begin
  // 군용담요(올리브 울) 텍스처 타일링
  if FFeltTile = nil then
  begin
    GenerateFeltTile;
  end;

  if (FFeltTile <> nil) and (FFeltTile.Width > 0) then
  begin
    var LSrc := RectF(0, 0, FFeltTile.Width, FFeltTile.Height);
    var LY := 0.0;
    while LY < Height do
    begin
      var LX := 0.0;
      while LX < Width do
      begin
        Canvas.DrawBitmap(FFeltTile, LSrc, RectF(LX, LY, LX + FFeltTile.Width, LY + FFeltTile.Height), 1, True);
        LX := LX + FFeltTile.Width;
      end;

      LY := LY + FFeltTile.Height;
    end;
  end
  else
  begin
    Canvas.Fill.Kind := TBrushKind.Solid;
    Canvas.Fill.Color := $FF284230;
    Canvas.FillRect(LocalRect, 0, 0, [], 1);
  end;

  // 하단 컨트롤 바(볼륨·음소거·속도) — 모든 화면 공통
  DrawControlBar;

  // 선 뽑기(밤일낮장) 단계
  if FSeonPicking then
  begin
    DrawSeonPick;
    Exit;
  end;

  // 딜(패 돌리기) 애니메이션 단계
  if FDealing then
  begin
    DrawDeal;
    Exit;
  end;

  // 협상 단계
  if FNegotiating then
  begin
    DrawNegotiation;
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

  // 중앙: 바닥 + 뒤집을 패 무더기
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

  // 보너스 뽑기: 더미 펼쳐 고르기 오버레이(턴 애니 중엔 숨김)
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
    if FGame.Phase = gpFinished then
    begin
      DrawGameOver;
    end;

    if FAwaitingGoStop and (FGame.Phase = gpAwaitingGoStop) and (FGame.Current = FHumanIndex) then
    begin
      DrawGoStopPrompt;
    end;
  end;

  // 특수 상황 배너(쪽/따닥/싹쓸이/폭탄/흔들기/뻑/총통…)
  DrawEffectBanner;

  // 아바타 선택 오버레이(최상단)
  if FAvatarPicking then
  begin
    DrawAvatarPicker;
  end;
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
  var LRegion := SeatRegion(PhysicalPos(AActor));
  Result := PointF(LRegion.Left + 50, LRegion.Top + 30);
end;

procedure TGostopBoard.CollectTurnEffects;
begin
  var LText := '';
  var LSeen := TDictionary<string, Boolean>.Create;
  try
    for var LEvt in FTurnEvents do
    begin
      var LLabel := EventEffectLabel(LEvt.Kind);
      if (LLabel <> '') and (not LSeen.ContainsKey(LLabel)) then
      begin
        LSeen.Add(LLabel, True);
        if LText <> '' then
        begin
          LText := LText + '    ';
        end;

        LText := LText + LLabel;
      end;
    end;
  finally
    LSeen.Free;
  end;

  FEffectText := LText;
  if FEffectText <> '' then
  begin
    FEffectTimer.Enabled := False;
    FEffectTimer.Enabled := True;   // 표시 시간 리셋
  end;
end;

procedure TGostopBoard.EffectTimerTick(Sender: TObject);
begin
  FEffectTimer.Enabled := False;
  FEffectText := '';
  Repaint;
end;

procedure TGostopBoard.DrawEffectBanner;
begin
  if FEffectText = '' then
  begin
    Exit;
  end;

  var LRect := RectF(Width * 0.18, Height * 0.11, Width * 0.82, Height * 0.11 + 78);
  Canvas.Fill.Kind := TBrushKind.Solid;
  Canvas.Fill.Color := $B0201008;
  Canvas.FillRect(LRect, 16, 16, [TCorner.TopLeft, TCorner.TopRight, TCorner.BottomLeft, TCorner.BottomRight], 1);
  Canvas.Stroke.Kind := TBrushKind.Solid;
  Canvas.Stroke.Color := $FFFFD54A;
  Canvas.Stroke.Thickness := 2;
  Canvas.DrawRect(LRect, 16, 16, [TCorner.TopLeft, TCorner.TopRight, TCorner.BottomLeft, TCorner.BottomRight], 1);
  DrawLabel(LRect, FEffectText, $FFFFE14A, 42);
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
  CollectTurnEffects;
  FAnimActor := ABefore.Current;
  FAnimPlayed := CardsRemoved(ABefore.Player(FAnimActor).Hand, FGame.Player(FAnimActor).Hand);
  FAnimDrawn := CardsRemoved(ABefore.Stock, FGame.Stock);
  FAnimCaptured := CardsAdded(ABefore.Player(FAnimActor).Captured, FGame.Player(FAnimActor).Captured);
  PlayTurnSound;
  FAnimDone := AOnDone;
  SetLength(FRestCards, 0);
  SetLength(FRestPts, 0);

  // 애니메이션할 게 없으면(고/스톱 등) 즉시 완료
  if (Length(FAnimPlayed) = 0) and (Length(FAnimDrawn) = 0) and (Length(FAnimCaptured) = 0) then
  begin
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

  // 더미(스톡) 위치: 중앙 오른쪽
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
              FFlyTargets[I] := PointF(LM.X + LRestOff.X, LM.Y + LRestOff.Y);
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
        // 뒤집기 소리(폴리포니라 놓기 소리와 겹쳐도 안 끊김)
        TGostopAudio.Instance.Play('card_flip');
        // 더미에서 들어올림(놓기와 동일 처리)
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
        var LAnchor := CapturedAnchor(FAnimActor);
        var LStolen := 0;
        for var I := 0 to High(FAnimCaptured) do
        begin
          FFlyTargets[I] := LAnchor;
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

          // 그 외 = 상대에게서 뺏어온 피 → 그 상대 획득더미에서 날아옴
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

        // 뺏어온 피가 있으면 뺏기 소리(폴리포니라 다른 소리와 겹쳐도 됨)
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
          // 뒤집기 후 멈춤(더미를 뒤집었을 때만)
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

procedure TGostopBoard.AnimTick(Sender: TObject);
begin
  if (FDisplay = nil) or (FAnimStage = 0) then
  begin
    FAnimTimer.Enabled := False;
    Exit;
  end;

  // 단계별 지속시간(ms)
  var LDur := 240.0;
  case FAnimStage of
    2:
      begin
        LDur := 320;
      end;
    3:
      begin
        LDur := 220;   // 멈춤
      end;
    4:
      begin
        LDur := 260;
      end;
  end;

  FAnimT := FAnimT + FAnimTimer.Interval / LDur * FGameSpeed;
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

procedure TGostopBoard.DrawFlyerCard(const ACenter: TPointF; const AAssetId: string; const AFlip: Boolean; const AProgress: Single);
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
  var LR := RectF(ACenter.X - LW / 2, ACenter.Y - CS.Height / 2, ACenter.X + LW / 2, ACenter.Y + CS.Height / 2);
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

  var LEase := FAnimT * FAnimT * (3 - 2 * FAnimT);   // smoothstep

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

  // 각 카드가 출발점에서 제자리(타깃)로 직행
  for var I := 0 to High(LCards) do
  begin
    if (I > High(FFlySources)) or (I > High(FFlyTargets)) then
    begin
      Break;
    end;

    var LP := PointF(FFlySources[I].X + (FFlyTargets[I].X - FFlySources[I].X) * LEase,
      FFlySources[I].Y + (FFlyTargets[I].Y - FFlySources[I].Y) * LEase);
    DrawFlyerCard(LP, LCards[I].AssetId, LFlip, LEase);
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
  var LPoint := PointF(X, Y);

  // 우하단 크레딧 → GitHub 저장소 열기
  if FCreditRect.Contains(LPoint) then
  begin
    TGostopAudio.Instance.Play('ui_click');
    ShellExecute(0, 'open', 'https://github.com/civilian7/gostop', nil, nil, SW_SHOWNORMAL);
    Exit;
  end;

  // 하단 컨트롤 바(볼륨/음소거/속도) — 어떤 화면·상태에서도 동작
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

  // 애니메이션 진행 중엔 그 외 입력 무시(턴 애니·딜 애니)
  if Assigned(FDisplay) or FDealing then
  begin
    Exit;
  end;

  // 타이틀 메뉴(게임 없음): 대전 시작/설정/종료 (선 뽑기·4인 협상 중엔 제외)
  if (FGame = nil) and (not FSeonPicking) and (not FNegotiating) then
  begin
    // 설정창이 열려 있으면 설정 조작만
    if FSettingsOpen then
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

      if FBtnCfgClose.Contains(LPoint) then
      begin
        TGostopAudio.Instance.Play('ui_click');
        ApplyNickEdit;
        FSettingsOpen := False;
        Repaint;
      end;

      Exit;
    end;

    // 대전 설정 다이얼로그(슬롯머신) 조작
    if FMatchSetupOpen then
    begin
      // 행 클릭 = 그 시트에 내가 앉음(이전 내 시트는 AI로 스핀)
      for var R := 0 to FSetupCount - 1 do
      begin
        if FSetupRowRects[R].Contains(LPoint) and (R <> FSetupHumanRow) then
        begin
          TGostopAudio.Instance.Play('ui_select');
          var LOld := FSetupHumanRow;
          FSetupHumanRow := R;
          FSetupAvatar[R] := -1;
          FSlotRemain[R] := 0;
          if LOld >= 0 then
          begin
            StartSlotSpin(LOld);
          end;

          Repaint;
          Exit;
        end;
      end;

      // 난이도 순환
      for var R := 0 to FSetupCount - 1 do
      begin
        if (R <> FSetupHumanRow) and FSetupSkRects[R].Contains(LPoint) then
        begin
          TGostopAudio.Instance.Play('ui_click');
          // 고유(-1) → 초급 → 중급 → 고급 → 최상 → 고유 순환
          case FSetupSkill[R] of
            -1:
              begin
                FSetupSkill[R] := 30;
              end;
            30:
              begin
                FSetupSkill[R] := 50;
              end;
            50:
              begin
                FSetupSkill[R] := 70;
              end;
            70:
              begin
                FSetupSkill[R] := 90;
              end;
          else
            begin
              FSetupSkill[R] := -1;
            end;
          end;

          Repaint;
          Exit;
        end;
      end;

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

      Exit;
    end;

    if FBtnMenu2.Contains(LPoint) then
    begin
      TGostopAudio.Instance.Play('ui_click');
      OpenMatchSetup(2);
    end
    else
    if FBtnMenu3.Contains(LPoint) then
    begin
      TGostopAudio.Instance.Play('ui_click');
      OpenMatchSetup(3);
    end
    else
    if FBtnMenu4.Contains(LPoint) then
    begin
      TGostopAudio.Instance.Play('ui_click');
      OpenMatchSetup(4);
    end
    else
    if FBtnMenuCfg.Contains(LPoint) then
    begin
      TGostopAudio.Instance.Play('ui_click');
      FSettingsOpen := True;
      Repaint;
    end
    else
    if FBtnMenuExit.Contains(LPoint) and Assigned(FOnExitRequest) then
    begin
      FOnExitRequest(Self);
    end;

    Exit;
  end;

  // 아바타 선택 오버레이: 하나 고르거나 밖을 누르면 닫기
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
    if (FSeonStep = seReveal) and FSeonHasCard[spBottom] and (not FSeonRevealed[spBottom])
      and FSeonRect[spBottom].Contains(LPoint) then
    begin
      SeonRevealPos(spBottom);
    end;

    Exit;
  end;

  // 보너스 뽑기: 펼쳐진 더미에서 한 장 클릭(사람 차례일 때만)
  if (FGame <> nil) and (FGame.Phase = gpAwaitingBonusDraw) then
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

    Exit;
  end;

  // 게임 종료: 새게임(이전 승자가 선) / 중지(매치 종료)
  if (FGame <> nil) and (FGame.Phase = gpFinished) then
  begin
    if FBtnNext.Contains(LPoint) then
    begin
      TGostopAudio.Instance.Play('ui_click');
      var LStartPos := spTop;
      if FGame.Winner >= 0 then
      begin
        LStartPos := PhysicalPos(FGame.Winner);
      end;

      NewGame(FPlayerCount, FAiSkill, LStartPos, False);   // 매치 이어가기(머니·전적 유지)
    end
    else
    if FBtnQuit.Contains(LPoint) then
    begin
      TGostopAudio.Instance.Play('ui_click');
      ClearGame;
      FStatus := '새 게임을 시작하세요';
      Repaint;
      if Assigned(FOnStateChanged) then
      begin
        FOnStateChanged(Self);
      end;
    end;

    Exit;
  end;

  // 고/스톱 대기: 보드 팝업의 고/스톱 버튼
  if FAwaitingGoStop and (FGame <> nil) and (FGame.Phase = gpAwaitingGoStop) then
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

    Exit;
  end;

  // 뒤집기 선택 대기: 강조된 후보(바닥 2장) 중 하나를 클릭하면 그 패로 확정
  if FFlipChoosing and (FGame <> nil) and (FGame.Phase = gpAwaitingFlipChoice) then
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

    Exit;   // 후보 아닌 곳은 무시
  end;

  // 협상: 왼쪽=참가/광팔기, 오른쪽=포기/안팔기 (사람의 논리 좌석에 따라 슬롯 매핑)
  if FNegotiating then
  begin
    var LLeft := FBtnJoin.Contains(LPoint);
    var LRight := FBtnGiveUp.Contains(LPoint);
    if LLeft or LRight then
    begin
      TGostopAudio.Instance.Play('ui_click');
      var LP2 := False;
      var LP3 := False;
      var LP4 := True;
      if FNegIsSell then
      begin
        LP4 := LLeft;   // 광팔기=왼쪽, 안팔기=오른쪽
      end
      else
      if FHumanLogical = 1 then
      begin
        LP2 := LRight;  // P2 포기=오른쪽
      end
      else
      begin
        LP3 := LRight;  // P3 포기=오른쪽
      end;

      ResolveNegotiation(LP2, LP3, LP4);
    end;

    Exit;
  end;

  if (FGame = nil) or (FGame.Phase <> gpPlaying) or (FGame.Current <> FHumanIndex) then
  begin
    Exit;
  end;

  // 선택 모드: 강조된 후보(바닥 같은 월) 클릭
  if FChoosing then
  begin
    for var K := 0 to FFloorRects.Count - 1 do
    begin
      var LRealFloor := FFloorIndexMap[K];
      if (FGame.Floor[LRealFloor].Month = FChooseMonth) and FFloorRects[K].Contains(LPoint) then
      begin
        PlayChosen(FChooseHandIndex, FloorMatchOrdinal(LRealFloor, FChooseMonth));
        Exit;
      end;
    end;

    Exit;
  end;

  // 일반 모드: 오른쪽(위에 겹친) 손패부터 히트 테스트
  for var K := FHandRects.Count - 1 downto 0 do
  begin
    if FHandRects[K].Contains(LPoint) then
    begin
      FClickRect := FHandRects[K];   // 놓기 애니 출발점
      var LRealIdx := FHandIndexMap[K];
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

      if (LMatchCount = 2) and (LK0 <> LK1) and (LCard.Kind <> hkBonus) then
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
  if FVolDragging or FSpdDragging then
  begin
    SaveSettings;   // 볼륨·배속 변경 확정 저장
  end;

  FVolDragging := False;
  FSpdDragging := False;
end;

procedure TGostopBoard.MouseMove(Shift: TShiftState; X, Y: Single);
begin
  inherited;
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

  // 유튜브식: 하단 근처 호버 시에만 컨트롤 바 표시
  var LShow := Y >= Height - 64;
  if LShow <> FBarVisible then
  begin
    FBarVisible := LShow;
    Repaint;
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
end;

procedure TGostopBoard.DoMouseLeave;
begin
  inherited;
  FVolDragging := False;
  FSpdDragging := False;
  if FBarVisible then
  begin
    FBarVisible := False;
    Repaint;
  end;

  if FHoverHand <> -1 then
  begin
    FHoverHand := -1;
    Repaint;
  end;
end;
{$ENDREGION}

end.
