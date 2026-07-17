unit Gostop.Play;

interface

{$REGION 'uses'}
uses
  System.SysUtils,
  System.Generics.Collections,
  Gostop.Cards,
  Gostop.Score;
{$ENDREGION}

type
  /// <summary>한 턴 진행 중 발생한 사건의 종류.</summary>
  TPlayEventKind = (
    pekPlace,       // 매칭 없이 바닥에 놓음
    pekCapture,     // 카드를 먹음
    pekBbeok,       // 뻑
    pekJabbeok,     // 자뻑(자기가 만든 뻑 더미를 자기가 먹음)
    pekYeonbbeok,   // 연뻑(뻑이 있는 상태에서 또 뻑)
    pekCheotbbeok,  // 첫뻑(게임 첫 수가 뻑)
    pekJjok,        // 쪽(놓은 카드를 뒤집은 같은 월로 먹음)
    pekTtadak,      // 따닥
    pekSseul,       // 쓸(싹쓸이)
    pekBomb,        // 폭탄
    pekShake,       // 흔들기
    pekChongtong,   // 총통(손패 같은 월 4장)
    pekPiSteal,     // 피 이동(뺏김)
    pekGoStop,      // 고/스톱 선택 가능
    pekGo,          // 고 선언
    pekStop,        // 스톱 선언
    pekTurnPass,    // 턴 넘어감
    pekFinished     // 게임 종료
  );

  /// <summary>턴 진행 사건 1건.</summary>
  TPlayEvent = record
    /// <summary>사건 종류.</summary>
    Kind: TPlayEventKind;
    /// <summary>사건 주체 플레이어 인덱스(해당 없으면 -1).</summary>
    PlayerIndex: Integer;
    /// <summary>관련 월(해당 없으면 0).</summary>
    Month: Integer;
    /// <summary>사람이 읽을 수 있는 설명.</summary>
    Text: string;
  end;

  /// <summary>게임 진행 단계.</summary>
  TGamePhase = (
    gpPlaying,            // 플레이어가 손패를 낼 차례
    gpAwaitingGoStop,     // 3점 이상 도달, 고/스톱 대기
    gpAwaitingFlipChoice, // 뒤집은 패가 바닥 2장(다른 종류)과 매칭 → 가져갈 패 선택 대기
    gpAwaitingBonusDraw,  // 보너스패를 내고 더미에서 가져올 패 선택 대기
    gpFinished            // 게임 종료
  );

  /// <summary>플레이어 1명의 상태(손패·먹은 패·고 횟수). 카드 목록의 수명을 소유한다.</summary>
  TPlayer = class
  private
    FHand: TList<THwatuCard>;
    FCaptured: TList<THwatuCard>;
    FName: string;
    FGoCount: Integer;
    FLastGoScore: Integer;
    FShakeCount: Integer;
    FCardDebt: Integer;
    FPendingShakeMonth: Integer;
  public
    /// <summary>이름을 지정해 빈 플레이어를 생성합니다.</summary>
    constructor Create(const AName: string);
    destructor Destroy; override;

    /// <summary>손패 목록.</summary>
    property Hand: TList<THwatuCard> read FHand;
    /// <summary>먹은 패 목록.</summary>
    property Captured: TList<THwatuCard> read FCaptured;
    /// <summary>플레이어 이름.</summary>
    property Name: string read FName write FName;
    /// <summary>지금까지 선언한 고 횟수.</summary>
    property GoCount: Integer read FGoCount write FGoCount;
    /// <summary>마지막으로 고를 선언(또는 점수 확정)한 시점의 점수. 재-고 판정에 사용.</summary>
    property LastGoScore: Integer read FLastGoScore write FLastGoScore;
    /// <summary>흔들기·폭탄으로 누적된 배수 횟수(정산 시 각 ×2).</summary>
    property ShakeCount: Integer read FShakeCount write FShakeCount;
    /// <summary>폭탄으로 진 카드빚. 이 횟수만큼 자기 턴에 손패 대신 '뒤집기만' 할 수 있다.</summary>
    property CardDebt: Integer read FCardDebt write FCardDebt;
    /// <summary>흔들기를 선언한 월(0=없음). 이 월을 실제로 내야 흔들기가 성립한다.</summary>
    property PendingShakeMonth: Integer read FPendingShakeMonth write FPendingShakeMonth;
  end;

  /// <summary>게임 전체 상태(플레이어들·바닥·더미·차례·단계·사건 로그). 모든 카드의 수명을 소유한다.</summary>
  TGameState = class
  private
    FPlayers: TObjectList<TPlayer>;
    FFloor: TList<THwatuCard>;
    FStock: TList<THwatuCard>;
    FCurrent: Integer;
    FPhase: TGamePhase;
    FWinner: Integer;
    FEvents: TList<TPlayEvent>;
    FBbeokCreator: TDictionary<Integer, Integer>;
    FPlayCount: Integer;
  public
    /// <summary>플레이어 이름 목록으로 게임 상태를 생성합니다(빈 손패·바닥·더미).</summary>
    constructor Create(const APlayerNames: array of string);
    destructor Destroy; override;

    /// <summary>
    ///   현재 상태를 깊은 복사한 독립 인스턴스를 반환합니다(사건 로그는 비운 채). AI 시뮬레이션용.
    /// </summary>
    /// <returns>호출자가 소유·해제하는 복제본.</returns>
    function Clone: TGameState;

    /// <summary>인덱스로 플레이어를 반환합니다.</summary>
    function Player(const AIndex: Integer): TPlayer;
    /// <summary>현재 차례 플레이어를 반환합니다.</summary>
    function CurrentPlayer: TPlayer;
    /// <summary>플레이어 수.</summary>
    function PlayerCount: Integer;

    /// <summary>바닥(패) 목록.</summary>
    property Floor: TList<THwatuCard> read FFloor;
    /// <summary>더미(스톡) 목록. 끝이 맨 위.</summary>
    property Stock: TList<THwatuCard> read FStock;
    /// <summary>현재 차례 플레이어 인덱스.</summary>
    property Current: Integer read FCurrent write FCurrent;
    /// <summary>진행 단계.</summary>
    property Phase: TGamePhase read FPhase write FPhase;
    /// <summary>승자 인덱스(미정/무승부는 -1).</summary>
    property Winner: Integer read FWinner write FWinner;
    /// <summary>사건 로그.</summary>
    property Events: TList<TPlayEvent> read FEvents;
    /// <summary>현재 바닥에 남은 뻑 더미의 월→생성자(플레이어 인덱스) 매핑.</summary>
    property BbeokCreator: TDictionary<Integer, Integer> read FBbeokCreator;
    /// <summary>지금까지 손패를 낸(플레이한) 총 횟수. 첫뻑 판정에 사용.</summary>
    property PlayCount: Integer read FPlayCount write FPlayCount;
  end;

  /// <summary>게임 종료 시 한 플레이어의 최종 정산 결과.</summary>
  TPlayerResult = record
    /// <summary>플레이어 인덱스.</summary>
    PlayerIndex: Integer;
    /// <summary>순손익(+받음 / −지불). 승자는 양수, 패자는 음수, 나가리는 0.</summary>
    Net: Integer;
    /// <summary>피박 적용 여부(패자).</summary>
    Pibak: Boolean;
    /// <summary>광박 적용 여부(패자).</summary>
    Gwangbak: Boolean;
    /// <summary>멍박(열끗박) 적용 여부(패자).</summary>
    Meongbak: Boolean;
    /// <summary>고박(고를 부르고 진 사람이 전액 부담) 적용 여부.</summary>
    Gobak: Boolean;
  end;

  /// <summary>
  ///   게임 룰 설정 묶음: 점수/정산 옵션(<see cref="TScoreOptions"/>)에 엔진 동작 토글을 더한 것.
  ///   흩어진 룰을 한곳에 모아 지역룰 변형을 쉽게 한다.
  /// </summary>
  TRuleSet = record
    /// <summary>점수·정산 규칙.</summary>
    Score: TScoreOptions;
    /// <summary>쓸/따닥/쪽/자뻑 시 상대당 뺏는 피 장수(기본 1).</summary>
    PiStealPerEvent: Integer;
    /// <summary>흔들면 그 월의 카드를 실제로 내야 하는가(기본 True).</summary>
    EnforceShakeMonth: Boolean;

    /// <summary>표준 룰 설정을 반환합니다.</summary>
    class function Default: TRuleSet; static;
  end;

  /// <summary>
  ///   고스톱 한 턴을 규칙대로 진행하는 엔진. 손패를 내면 바닥 매칭·더미 뒤집기·먹기·뻑·쪽·따닥·쓸·피 이동을
  ///   처리하고, 3점 이상이면 고/스톱 대기 단계로 전환한다. 뻑 더미의 생성자를 추적해 자뻑·연뻑·첫뻑도 판정한다.
  ///   보너스패는 즉시 획득, 폭탄 카드빚은 '뒤집기만' 턴으로 상환, 종료 시 정산(피박/광박/고박)까지 제공한다.
  /// </summary>
  TTurnEngine = class
  private
    FState: TGameState;
    FRules: TRuleSet;
    FOnEvent: TProc<TPlayEvent>;
    FFlipChoiceEnabled: Boolean;
    FBonusDrawEnabled: Boolean;
    FCollectEvents: Boolean;        // False면 이벤트 기록·콜백 생략(AI 롤아웃 성능용)
    FPlayerLuck: TArray<Integer>;   // 플레이어별 이번 판 운(0~100). 비어 있으면 보정 없음
    FPendingBonus: TArray<THwatuCard>;   // 이번 턴에 손에서 내려놓은 보너스패(뻑이면 함께 묻힘)
    FFlipBonus: TArray<THwatuCard>;      // 직전 더미 뒤집기에서 획득한 보너스패(뻑이면 함께 묻힘)
    FFlipCard: THwatuCard;
    FFlipOpt0: THwatuCard;
    FFlipOpt1: THwatuCard;
    FFlipHandMonth: Integer;
    FFlipHandCaptured: Boolean;
    FFlipHandPlaced: Boolean;
    function ScoreAndFinish(const APlayer: TPlayer): Boolean;
    procedure AddEvent(const AKind: TPlayEventKind; const APlayerIndex: Integer; const AMonth: Integer; const AText: string);
    procedure StealPiFromOthers(const AWinnerIndex: Integer);
    function StealOnePi(const AWinnerIndex: Integer; const AVictimIndex: Integer): Boolean;
    function FlipBenefit(const ACard: THwatuCard): Integer;
    procedure ResolveBbeokCapture(const AMonth: Integer);
    procedure ResolveThreePileSteal(const AMonth: Integer);
    function FlipStockAndResolve(const APlayer: TPlayer): Boolean;
    function DrawNonBonus(const APlayer: TPlayer; out ACard: THwatuCard): Boolean;
    procedure AdvanceTurn;
    function CanAct(const APlayerIndex: Integer): Boolean;
    function MatchIndices(const AMonth: Integer): TArray<Integer>;
    procedure CaptureInto(const ACaptured: TList<THwatuCard>; const AIndices: TArray<Integer>; const AChoice: Integer);
    function CaptureRank(const ACard: THwatuCard): Integer;
    procedure RemoveFloorByAsset(const AAssetId: string);
  public
    /// <summary>주어진 게임 상태와 룰 설정으로 엔진을 생성합니다(상태 수명은 호출자 소유).</summary>
    constructor Create(const AState: TGameState; const ARules: TRuleSet); overload;
    /// <summary>점수 옵션만으로 엔진을 생성합니다(엔진 토글은 기본값). 상태 수명은 호출자 소유.</summary>
    constructor Create(const AState: TGameState; const AOptions: TScoreOptions); overload;

    /// <summary>
    ///   현재 플레이어가 손패의 카드를 내고 한 턴을 끝까지 진행합니다.
    /// </summary>
    /// <param name="AHandIndex">낼 손패의 인덱스.</param>
    /// <param name="AFloorChoice">바닥에 같은 월이 2장일 때 가져갈 대상(매칭 목록 기준 0/1). 기본 0.</param>
    /// <returns>3점 이상 도달해 고/스톱 선택이 필요하면 True(단계가 대기로 전환). 아니면 False(다음 차례로 넘어감).</returns>
    /// <exception cref="EHwatuError">진행 단계가 아니거나 손패 인덱스가 잘못되면 발생.</exception>
    function PlayHandCard(const AHandIndex: Integer; const AFloorChoice: Integer = 0): Boolean;
    /// <summary>
    ///   뒤집기 선택 대기(<c>gpAwaitingFlipChoice</c>)에서, 뒤집은 패로 가져갈 바닥패를 선택해 턴을 마칩니다.
    /// </summary>
    /// <param name="AOrdinal">선택지(0/1). <see cref="FlipChoiceOptions"/> 순서와 대응.</param>
    /// <returns>3점 이상 도달해 고/스톱 선택이 필요하면 True.</returns>
    /// <exception cref="EHwatuError">뒤집기 선택 대기 단계가 아니면 발생.</exception>
    function ResolveFlipChoice(const AOrdinal: Integer): Boolean;
    /// <summary>뒤집기 선택 대기 중, 가져갈 후보 2장(바닥패)을 반환합니다.</summary>
    function FlipChoiceOptions: TArray<THwatuCard>;
    /// <summary>
    ///   보너스패 뽑기 대기(<c>gpAwaitingBonusDraw</c>)에서 더미의 지정 위치 카드를 가져옵니다.
    ///   일반패면 손패로 들어가고 같은 차례가 계속되며, 보너스패면 즉시 획득 후 계속 고릅니다.
    /// </summary>
    /// <param name="AStockIndex">더미 내 위치(0 기반).</param>
    /// <exception cref="EHwatuError">보너스 뽑기 대기 단계가 아니거나 범위를 벗어나면 발생.</exception>
    procedure ResolveBonusDraw(const AStockIndex: Integer);
    /// <summary>뒤집기로 가져올 뒤집은 패(선택 대기 중).</summary>
    function FlipDrawnCard: THwatuCard;
    /// <summary>고를 선언하고 다음 차례로 넘어갑니다.</summary>
    procedure DeclareGo;
    /// <summary>스톱을 선언하고 현재 플레이어를 승자로 게임을 종료합니다.</summary>
    procedure DeclareStop;
    /// <summary>쇼당(둘 다 수락)으로 그 판을 나가리(무효) 처리한다.</summary>
    procedure DeclareNagari;
    /// <summary>지정 플레이어의 현재 족보 점수 내역을 반환합니다.</summary>
    function ScoreOf(const APlayerIndex: Integer): TScoreBreakdown;

    /// <summary>
    ///   딜 직후 손패 총통(같은 월 4장)을 검사해, 있으면 그 판을 무효(승자 없음)로 즉시 종료합니다(자동 처리용).
    /// </summary>
    /// <returns>총통으로 종료되면 True.</returns>
    function ApplyHandChongtong: Boolean;
    /// <summary>
    ///   딜 직후 바닥에 깔린 보너스패를 선(현재 차례)이 자동 획득하고, 그 장수만큼 더미에서
    ///   일반패를 뽑아 바닥을 채웁니다(보충 중 나온 보너스패도 선이 획득). 딜 후 1회 호출.
    /// </summary>
    procedure ApplyFloorBonus;
    /// <summary>
    ///   지정 플레이어가 손패에 같은 월 4장을 들고 있어 총통을 선언할 수 있으면 True(딜 직후·플레이 중 모두).
    /// </summary>
    /// <param name="APlayerIndex">검사할 플레이어.</param>
    /// <param name="AMonth">4장이 모인 월(없으면 0).</param>
    function CanDeclareChongtong(const APlayerIndex: Integer; out AMonth: Integer): Boolean;
    /// <summary>
    ///   지정 플레이어가 총통을 선언해 즉시 승리로 게임을 끝냅니다(플레이어 선택). 계속 진행할지 끝낼지는 선택 사항.
    /// </summary>
    /// <param name="APlayerIndex">선언 플레이어.</param>
    /// <exception cref="EHwatuError">같은 월 4장 조건을 만족하지 않으면 발생.</exception>
    procedure DeclareChongtong(const APlayerIndex: Integer);
    /// <summary>현재 플레이어가 손패에 같은 월 3장을 들고 있어 흔들 수 있는 월이면 True를 반환합니다.</summary>
    /// <param name="AMonth">검사할 월(1~12).</param>
    function CanShake(const AMonth: Integer): Boolean;
    /// <summary>
    ///   현재 플레이어가 지정 월을 흔듭니다(같은 월 3장 보유 필요). 배수 횟수가 1 증가합니다.
    /// </summary>
    /// <exception cref="EHwatuError">진행 단계가 아니거나 해당 월 3장을 들고 있지 않으면 발생.</exception>
    procedure DeclareShake(const AMonth: Integer);
    /// <summary>현재 플레이어가 같은 월 3장을 보유하고 바닥에 그 월이 있어 폭탄이 가능하면 True.</summary>
    /// <param name="AMonth">검사할 월(1~12).</param>
    function CanBomb(const AMonth: Integer): Boolean;
    /// <summary>
    ///   현재 플레이어가 지정 월로 폭탄을 칩니다(손패 3장 + 바닥 같은 월 모두 획득, 상대 피 1장씩,
    ///   배수 ×2). 폭탄 후 더미 1장을 뒤집어 처리하고, 여분 장수만큼 카드빚(뒤집기만 턴)을 부여한 뒤 턴을 넘깁니다.
    /// </summary>
    /// <returns>폭탄 후 3점 이상 도달해 고/스톱 선택이 필요하면 True.</returns>
    /// <exception cref="EHwatuError">폭탄 조건을 만족하지 않으면 발생.</exception>
    function PlayBomb(const AMonth: Integer): Boolean;
    /// <summary>현재 플레이어가 카드빚이 남아 '뒤집기만' 턴을 쓸 수 있으면 True.</summary>
    function CanFlipOnly: Boolean;
    /// <summary>
    ///   카드빚을 갚습니다: 손패를 내지 않고 더미 1장만 뒤집어 처리하고 턴을 넘깁니다(빚 1 감소).
    /// </summary>
    /// <returns>3점 이상 도달해 고/스톱 선택이 필요하면 True.</returns>
    /// <exception cref="EHwatuError">진행 단계가 아니거나 갚을 카드빚이 없으면 발생.</exception>
    function FlipOnly: Boolean;

    /// <summary>
    ///   게임 종료 시 각 플레이어의 최종 정산(고·흔들 배수, 피박/광박, 고박 반영)을 계산합니다.
    ///   나가리(무승부)면 전원 0. 게임이 끝나지 않았으면 전원 0을 반환합니다.
    /// </summary>
    /// <returns>플레이어별 정산 결과 배열.</returns>
    function FinalSettlement: TArray<TPlayerResult>;

    /// <summary>
    ///   뒤집은 패가 바닥 2장(서로 다른 종류)과 매칭될 때 가져갈 패 선택을 요구할지 여부(기본 False).
    ///   UI(사람 차례)에서만 True로 켜고, AI·자동 진행에서는 False로 두어 자동(값 높은 패)으로 처리한다.
    /// </summary>
    property FlipChoiceEnabled: Boolean read FFlipChoiceEnabled write FFlipChoiceEnabled;
    /// <summary>
    ///   보너스패를 낼 때 더미를 펼쳐 가져올 패를 고르게 할지(True=<c>gpAwaitingBonusDraw</c>로 멈춤,
    ///   False=더미 맨 위에서 자동 보충). UI 게임에서 켠다. 기본 False.
    /// </summary>
    property BonusDrawEnabled: Boolean read FBonusDrawEnabled write FBonusDrawEnabled;
    /// <summary>이벤트 기록·콜백 여부(기본 True). AI 롤아웃은 False로 꺼서 할당을 줄인다.</summary>
    property CollectEvents: Boolean read FCollectEvents write FCollectEvents;
    /// <summary>이 엔진의 룰셋(읽기). AI가 시뮬 세계에 같은 룰을 적용할 때 사용.</summary>
    property Rules: TRuleSet read FRules;
    /// <summary>
    ///   플레이어별 이번 판 운(0~100, 게임 인덱스 순). 설정하면 더미 뒤집기 때 운이 높을수록
    ///   유리한 카드가, 낮을수록 불리한 카드가 나올 확률이 커진다(맨 위 2장 은밀 교환).
    ///   비어 있으면(기본) 보정 없음 — 시뮬레이션·검증기는 순수 확률로 돈다.
    /// </summary>
    property PlayerLuck: TArray<Integer> read FPlayerLuck write FPlayerLuck;
    /// <summary>진행 중인 게임 상태(읽기용).</summary>
    property State: TGameState read FState;
    /// <summary>
    ///   사건 발생 콜백. 설정하면 매 사건이 <see cref="TGameState.Events"/>에 기록되는 즉시 호출된다.
    ///   UI가 실시간으로 반응할 때 사용(폴링 불필요). 히스토리 리스트는 그대로 유지된다.
    /// </summary>
    property OnEvent: TProc<TPlayEvent> read FOnEvent write FOnEvent;
  end;

  /// <summary>
  ///   턴 엔진 위에서 한 플레이어의 행동을 결정·실행하는 에이전트 계약. AI·사람(UI)·스크립트가 각자 구현한다.
  ///   현재 차례/단계에 맞춰 손패·폭탄·뒤집기 또는 고/스톱을 수행한다.
  /// </summary>
  IPlayerAgent = interface
    ['{7A1C0E10-9B3D-4E52-8F41-6C2A9D5B3E77}']
    /// <summary>현재 게임 단계에 맞는 행동을 1회 수행합니다.</summary>
    procedure Act(const AEngine: TTurnEngine);
  end;

implementation

{$REGION 'TPlayer'}
constructor TPlayer.Create(const AName: string);
begin
  inherited Create;
  FName := AName;
  FHand := TList<THwatuCard>.Create;
  FCaptured := TList<THwatuCard>.Create;
  FGoCount := 0;
  FLastGoScore := 0;
  FShakeCount := 0;
  FCardDebt := 0;
  FPendingShakeMonth := 0;
end;

destructor TPlayer.Destroy;
begin
  FreeAndNil(FCaptured);
  FreeAndNil(FHand);
  inherited Destroy;
end;
{$ENDREGION}

{$REGION 'TGameState'}
constructor TGameState.Create(const APlayerNames: array of string);
begin
  inherited Create;
  FPlayers := TObjectList<TPlayer>.Create(True);
  for var I := 0 to High(APlayerNames) do
  begin
    FPlayers.Add(TPlayer.Create(APlayerNames[I]));
  end;

  FFloor := TList<THwatuCard>.Create;
  FStock := TList<THwatuCard>.Create;
  FCurrent := 0;
  FPhase := gpPlaying;
  FWinner := -1;
  FEvents := TList<TPlayEvent>.Create;
  FBbeokCreator := TDictionary<Integer, Integer>.Create;
  FPlayCount := 0;
end;

destructor TGameState.Destroy;
begin
  FreeAndNil(FBbeokCreator);
  FreeAndNil(FEvents);
  FreeAndNil(FStock);
  FreeAndNil(FFloor);
  FreeAndNil(FPlayers);
  inherited Destroy;
end;

function TGameState.Clone: TGameState;
begin
  var LNames: TArray<string>;
  SetLength(LNames, FPlayers.Count);
  for var I := 0 to FPlayers.Count - 1 do
  begin
    LNames[I] := FPlayers[I].Name;
  end;

  Result := TGameState.Create(LNames);
  for var I := 0 to FPlayers.Count - 1 do
  begin
    Result.Player(I).Hand.AddRange(FPlayers[I].Hand);
    Result.Player(I).Captured.AddRange(FPlayers[I].Captured);
    Result.Player(I).GoCount := FPlayers[I].GoCount;
    Result.Player(I).LastGoScore := FPlayers[I].LastGoScore;
    Result.Player(I).ShakeCount := FPlayers[I].ShakeCount;
    Result.Player(I).CardDebt := FPlayers[I].CardDebt;
    Result.Player(I).PendingShakeMonth := FPlayers[I].PendingShakeMonth;   // 흔들기 커밋 보존(누락 시 시뮬 배수 왜곡)
  end;

  Result.Floor.AddRange(FFloor);
  Result.Stock.AddRange(FStock);
  Result.Current := FCurrent;
  Result.Phase := FPhase;
  Result.Winner := FWinner;
  Result.PlayCount := FPlayCount;
  for var LPair in FBbeokCreator do
  begin
    Result.BbeokCreator.AddOrSetValue(LPair.Key, LPair.Value);
  end;
end;

function TGameState.Player(const AIndex: Integer): TPlayer;
begin
  if (AIndex < 0) or (AIndex >= FPlayers.Count) then
  begin
    raise EHwatuError.CreateFmt('플레이어 인덱스 오류: %d (총 %d명)', [AIndex, FPlayers.Count]);
  end;

  Result := FPlayers[AIndex];
end;

function TGameState.CurrentPlayer: TPlayer;
begin
  Result := FPlayers[FCurrent];
end;

function TGameState.PlayerCount: Integer;
begin
  Result := FPlayers.Count;
end;
{$ENDREGION}

{$REGION 'TRuleSet'}
class function TRuleSet.Default: TRuleSet;
begin
  Result.Score := TScoreOptions.Default;
  Result.PiStealPerEvent := 1;
  Result.EnforceShakeMonth := True;
end;
{$ENDREGION}

{$REGION 'TTurnEngine'}
constructor TTurnEngine.Create(const AState: TGameState; const ARules: TRuleSet);
begin
  inherited Create;
  FState := AState;
  FRules := ARules;
  FCollectEvents := True;
end;

constructor TTurnEngine.Create(const AState: TGameState; const AOptions: TScoreOptions);
begin
  var LRules := TRuleSet.Default;
  LRules.Score := AOptions;
  Create(AState, LRules);
end;

procedure TTurnEngine.AddEvent(const AKind: TPlayEventKind; const APlayerIndex: Integer; const AMonth: Integer; const AText: string);
var
  LEvent: TPlayEvent;
begin
  if not FCollectEvents then
  begin
    Exit;
  end;

  LEvent.Kind := AKind;
  LEvent.PlayerIndex := APlayerIndex;
  LEvent.Month := AMonth;
  LEvent.Text := AText;
  FState.Events.Add(LEvent);
  if Assigned(FOnEvent) then
  begin
    FOnEvent(LEvent);
  end;
end;

function TTurnEngine.MatchIndices(const AMonth: Integer): TArray<Integer>;
begin
  // 핫패스(AI 롤아웃) — TList 없이 단일 배열 할당으로 처리
  SetLength(Result, 8);
  var LCount := 0;
  for var I := 0 to FState.Floor.Count - 1 do
  begin
    if FState.Floor[I].Month = AMonth then
    begin
      if LCount >= Length(Result) then
      begin
        SetLength(Result, LCount + 4);
      end;

      Result[LCount] := I;
      Inc(LCount);
    end;
  end;

  SetLength(Result, LCount);
end;

procedure TTurnEngine.CaptureInto(const ACaptured: TList<THwatuCard>; const AIndices: TArray<Integer>; const AChoice: Integer);
begin
  if Length(AIndices) >= 3 then
  begin
    // 바닥에 3장(같은 월) → 모두 가져감. 높은 인덱스부터 삭제해 인덱스 유효성 유지.
    for var K := High(AIndices) downto 0 do
    begin
      ACaptured.Add(FState.Floor[AIndices[K]]);
      FState.Floor.Delete(AIndices[K]);
    end;

    Exit;
  end;

  var LPick := 0;
  if Length(AIndices) = 2 then
  begin
    if (AChoice >= 0) and (AChoice < 2) then
    begin
      LPick := AChoice;
    end
    else
    begin
      // AChoice < 0(자동): 값이 높은 카드를 가져간다(뒤집기 등 선택권 없을 때)
      if CaptureRank(FState.Floor[AIndices[1]]) > CaptureRank(FState.Floor[AIndices[0]]) then
      begin
        LPick := 1;
      end;
    end;
  end;

  ACaptured.Add(FState.Floor[AIndices[LPick]]);
  FState.Floor.Delete(AIndices[LPick]);
end;

function TTurnEngine.CaptureRank(const ACard: THwatuCard): Integer;
begin
  // 획득 우선순위: 광 > 열끗 > 띠 > 피(쌍피>피)
  case ACard.Kind of
    hkBright:
      begin
        Result := 100;
      end;
    hkAnimal:
      begin
        Result := 80;
      end;
    hkRibbon:
      begin
        Result := 60;
      end;
    hkJunk, hkBonus:
      begin
        Result := 10 + ACard.JunkValue;
      end;
  else
    begin
      Result := 0;
    end;
  end;
end;

function TTurnEngine.StealOnePi(const AWinnerIndex: Integer; const AVictimIndex: Integer): Boolean;
begin
  if AWinnerIndex = AVictimIndex then
  begin
    Exit(False);
  end;

  var LVictim := FState.Player(AVictimIndex);
  // 가장 값이 낮은 일반 피 1장을 넘긴다(값이 낮은 단피 → 쌍피 순). 쌍피만 있으면 쌍피를 넘긴다.
  var LBestIdx := -1;
  var LBestValue := MaxInt;
  for var I := 0 to LVictim.Captured.Count - 1 do
  begin
    var LCard := LVictim.Captured[I];
    if (LCard.Kind = hkJunk) or (LCard.Kind = hkBonus) then
    begin
      if LCard.JunkValue < LBestValue then
      begin
        LBestValue := LCard.JunkValue;
        LBestIdx := I;
      end;
    end;
  end;

  // 넘길 국진이면 이 값이 True (넘어간 국진만 쌍피로 계산됨)
  var LGivingGukjin := False;
  if LBestIdx < 0 then
  begin
    // 일반 피/쌍피가 하나도 없으면 국진을 쌍피 대용으로 넘긴다.
    for var I := 0 to LVictim.Captured.Count - 1 do
    begin
      if LVictim.Captured[I].IsGukjin then
      begin
        LBestIdx := I;
        LGivingGukjin := True;
        Break;
      end;
    end;
  end;

  // 넘길 피(또는 국진)가 전혀 없으면 아무것도 받지 않는다.
  if LBestIdx < 0 then
  begin
    Exit(False);
  end;

  var LWinner := FState.Player(AWinnerIndex);
  var LPi := LVictim.Captured[LBestIdx];
  if LGivingGukjin then
  begin
    LPi.GivenAsPi := True;   // 넘어간 국진은 이제부터 쌍피로 계산된다
  end;

  LVictim.Captured.Delete(LBestIdx);
  LWinner.Captured.Add(LPi);
  if LGivingGukjin then
  begin
    AddEvent(pekPiSteal, AWinnerIndex, 0, Format('%s ← %s 국진(쌍피 대용) 1장', [LWinner.Name, LVictim.Name]));
  end
  else
  begin
    AddEvent(pekPiSteal, AWinnerIndex, 0, Format('%s ← %s 피 1장', [LWinner.Name, LVictim.Name]));
  end;

  Result := True;
end;

procedure TTurnEngine.StealPiFromOthers(const AWinnerIndex: Integer);
begin
  for var P := 0 to FState.PlayerCount - 1 do
  begin
    for var K := 1 to FRules.PiStealPerEvent do
    begin
      if not StealOnePi(AWinnerIndex, P) then
      begin
        Break;   // 상대가 더 낼 피가 없으면 중단
      end;
    end;
  end;
end;

procedure TTurnEngine.ResolveBbeokCapture(const AMonth: Integer);
begin
  var LCreator: Integer;
  if not FState.BbeokCreator.TryGetValue(AMonth, LCreator) then
  begin
    Exit;
  end;

  FState.BbeokCreator.Remove(AMonth);

  var LName := FState.CurrentPlayer.Name;
  if LCreator = FState.Current then
  begin
    // 자뻑: 자기가 만든 뻑을 자기가 먹음 → 상대 전원에게서 피 2장씩("자뻑은 두 장")
    AddEvent(pekJabbeok, FState.Current, AMonth, Format('%s 자뻑! (%d월)', [LName, AMonth]));
    StealPiFromOthers(FState.Current);
    StealPiFromOthers(FState.Current);
  end
  else
  begin
    // 남의 뻑을 먹음 → 뻑을 싼 사람에게서 피 1장
    AddEvent(pekPiSteal, FState.Current, AMonth, Format('%s 뻑 회수 (%d월)', [LName, AMonth]));
    StealOnePi(FState.Current, LCreator);
  end;
end;

procedure TTurnEngine.ApplyFloorBonus;
begin
  // 딜 직후(플레이 시작 전) 1회만 유효 — 중복/뒤늦은 호출로 부당 획득 방지
  if (FState.Phase <> gpPlaying) or (FState.PlayCount > 0) then
  begin
    Exit;
  end;

  var LIdx := 0;
  while LIdx < FState.Floor.Count do
  begin
    if FState.Floor[LIdx].Kind = hkBonus then
    begin
      var LCard := FState.Floor[LIdx];
      FState.Floor.Delete(LIdx);
      FState.CurrentPlayer.Captured.Add(LCard);
      AddEvent(pekCapture, FState.Current, 0, Format('%s 바닥 보너스패 획득(선)', [FState.CurrentPlayer.Name]));

      // 더미에서 일반패 1장으로 바닥 보충(보충 중 보너스가 나오면 그것도 선이 획득)
      var LFill: THwatuCard;
      if DrawNonBonus(FState.CurrentPlayer, LFill) then
      begin
        FState.Floor.Add(LFill);
      end;
    end
    else
    begin
      Inc(LIdx);
    end;
  end;
end;

procedure TTurnEngine.ResolveThreePileSteal(const AMonth: Integer);
begin
  // 바닥 같은 월 3장을 한 번에 먹은 경우의 피 처리.
  if FState.BbeokCreator.ContainsKey(AMonth) then
  begin
    // 뻑 더미였으면 뻑 회수 규칙(자뻑=상대 전원, 남의 뻑=생성자에게서 1장)
    ResolveBbeokCapture(AMonth);
  end
  else
  begin
    // 자연 3장(뻑 아님)을 쓸어 먹으면 참가자 전원에게서 피 1장씩
    AddEvent(pekPiSteal, FState.Current, AMonth, Format('%s 바닥 %d월 3장 쓸어먹기 — 피 받기', [FState.CurrentPlayer.Name, AMonth]));
    StealPiFromOthers(FState.Current);
  end;
end;

// 뒤집었을 때의 이득 점수: 바닥 매칭(즉시 먹기)이 크고, 매칭 상대가 좋을수록 가산. 보너스도 이득
function TTurnEngine.FlipBenefit(const ACard: THwatuCard): Integer;
begin
  if ACard.Kind = hkBonus then
  begin
    Exit(6);
  end;

  Result := 0;
  for var LCard in FState.Floor do
  begin
    if LCard.Month = ACard.Month then
    begin
      var LGain := 5 + CaptureRank(LCard) div 10;
      if LGain > Result then
      begin
        Result := LGain;
      end;
    end;
  end;
end;

function TTurnEngine.DrawNonBonus(const APlayer: TPlayer; out ACard: THwatuCard): Boolean;
begin
  // 운 보정: 이번 판 운이 높으면 더미 위 2장 중 유리한 쪽이, 낮으면 불리한 쪽이 올라오도록
  // 은밀히 교환한다(뒷면이라 관측 불가). 운 50은 무보정, 배열이 비면 순수 확률.
  if (FState.Stock.Count >= 2) and (FState.Current >= 0) and (FState.Current < Length(FPlayerLuck)) then
  begin
    var LBias := FPlayerLuck[FState.Current] - 50;
    if (LBias <> 0) and (Random(100) < Abs(LBias)) then
    begin
      var LTopIdx := FState.Stock.Count - 1;
      var LTopBen := FlipBenefit(FState.Stock[LTopIdx]);
      var LSecBen := FlipBenefit(FState.Stock[LTopIdx - 1]);
      var LWantSwap: Boolean;
      if LBias > 0 then
      begin
        LWantSwap := LSecBen > LTopBen;   // 행운: 더 좋은 쪽을 위로
      end
      else
      begin
        LWantSwap := LSecBen < LTopBen;   // 불운: 더 나쁜 쪽을 위로
      end;

      if LWantSwap then
      begin
        var LTmp := FState.Stock[LTopIdx];
        FState.Stock[LTopIdx] := FState.Stock[LTopIdx - 1];
        FState.Stock[LTopIdx - 1] := LTmp;
      end;
    end;
  end;

  // 더미 맨 위부터 뒤집되, 보너스패(조커)는 즉시 획득하고 한 장 더 뒤집는다.
  // 이번 뒤집기에서 획득한 조커는 추적해 둔다(이후 뻑이 나면 함께 묻어야 하므로).
  FFlipBonus := nil;
  while FState.Stock.Count > 0 do
  begin
    var LTop := FState.Stock[FState.Stock.Count - 1];
    FState.Stock.Delete(FState.Stock.Count - 1);
    if LTop.Kind = hkBonus then
    begin
      APlayer.Captured.Add(LTop);
      FFlipBonus := FFlipBonus + [LTop];
      AddEvent(pekCapture, FState.Current, 0, Format('%s 보너스패 획득(뒤집기)', [APlayer.Name]));
      Continue;
    end;

    ACard := LTop;
    Exit(True);
  end;

  Result := False;
end;

function TTurnEngine.FlipStockAndResolve(const APlayer: TPlayer): Boolean;
begin
  var LDraw: THwatuCard;
  if not DrawNonBonus(APlayer, LDraw) then
  begin
    Exit(False);
  end;

  var LCaptured := TList<THwatuCard>.Create;
  try
    var LMatches := MatchIndices(LDraw.Month);
    if Length(LMatches) = 0 then
    begin
      FState.Floor.Add(LDraw);
    end
    else
    begin
      LCaptured.Add(LDraw);
      CaptureInto(LCaptured, LMatches, -1);
      if Length(LMatches) >= 3 then
      begin
        ResolveThreePileSteal(LDraw.Month);
      end;
    end;

    if LCaptured.Count > 0 then
    begin
      APlayer.Captured.AddRange(LCaptured);
      AddEvent(pekCapture, FState.Current, LDraw.Month, Format('%s 뒤집어 %d장 먹음', [APlayer.Name, LCaptured.Count]));
    end
    else
    begin
      AddEvent(pekPlace, FState.Current, LDraw.Month, Format('%s 뒤집은 카드 바닥에 놓음', [APlayer.Name]));
    end;

    // 뒤집기로 바닥을 비우면 쓸. 단, 손패 소진(마지막 장) 상태에선 쓸 불인정
    if (FState.Floor.Count = 0) and (LCaptured.Count > 0) and (APlayer.Hand.Count > 0) then
    begin
      AddEvent(pekSseul, FState.Current, LDraw.Month, APlayer.Name + ' 싹쓸이!');
      StealPiFromOthers(FState.Current);
    end;

    Result := LCaptured.Count > 0;
  finally
    LCaptured.Free;
  end;
end;

function TTurnEngine.CanAct(const APlayerIndex: Integer): Boolean;
begin
  // 낼 손패가 있거나, 폭탄 카드빚이 남아 있고 뒤집을 더미가 있으면 행동 가능.
  var LPlayer := FState.Player(APlayerIndex);
  Result := (LPlayer.Hand.Count > 0) or ((LPlayer.CardDebt > 0) and (FState.Stock.Count > 0));
end;

procedure TTurnEngine.AdvanceTurn;
begin
  // 턴이 끝나면 보너스패 묻힘 대기는 해제(뻑 없이 턴이 끝났으므로 획득 확정)
  FPendingBonus := nil;
  FFlipBonus := nil;

  var LAnyActive := False;
  for var P := 0 to FState.PlayerCount - 1 do
  begin
    if CanAct(P) then
    begin
      LAnyActive := True;
      Break;
    end;
  end;

  if not LAnyActive then
  begin
    FState.Phase := gpFinished;
    FState.Winner := -1;
    AddEvent(pekFinished, -1, 0, '나가리(손패 소진)');
    Exit;
  end;

  repeat
    FState.Current := (FState.Current + 1) mod FState.PlayerCount;
  until CanAct(FState.Current);

  FState.Phase := gpPlaying;
  AddEvent(pekTurnPass, FState.Current, 0, FState.CurrentPlayer.Name + ' 차례');
end;

function TTurnEngine.PlayHandCard(const AHandIndex: Integer; const AFloorChoice: Integer): Boolean;
begin
  if FState.Phase <> gpPlaying then
  begin
    raise EHwatuError.Create('지금은 손패를 낼 단계가 아닙니다.');
  end;

  var LPlayer := FState.CurrentPlayer;
  if (AHandIndex < 0) or (AHandIndex >= LPlayer.Hand.Count) then
  begin
    raise EHwatuError.CreateFmt('손패 인덱스 오류: %d (손패 %d장)', [AHandIndex, LPlayer.Hand.Count]);
  end;

  // 흔들기 커밋: 흔든 월이 있으면 그 월을 내야 한다(옵션). 보너스패는 실제 패가 아니므로 허용
  if FRules.EnforceShakeMonth and (LPlayer.PendingShakeMonth <> 0) and
    (LPlayer.Hand[AHandIndex].Kind <> hkBonus) and
    (LPlayer.Hand[AHandIndex].Month <> LPlayer.PendingShakeMonth) then
  begin
    raise EHwatuError.CreateFmt('%d월을 흔들었으므로 그 월의 카드를 내야 합니다.', [LPlayer.PendingShakeMonth]);
  end;

  var LHand := LPlayer.Hand[AHandIndex];
  // 자동 흔들기 판정용: 내기 전 같은 월 보유 수 & 명시적 흔들기 커밋 여부
  var LWasPendingShake := LPlayer.PendingShakeMonth <> 0;
  var LMonthInHand := 0;
  for var LHandCard in LPlayer.Hand do
  begin
    if LHandCard.Month = LHand.Month then
    begin
      Inc(LMonthInHand);
    end;
  end;

  LPlayer.Hand.Delete(AHandIndex);
  var LMonth := LHand.Month;

  var LCaptured := TList<THwatuCard>.Create;
  try
    var LHandMatches := MatchIndices(LMonth);

    // 자동 흔들기: 같은 월 3장 보유 + 바닥에 그 월 없음(폭탄 불가)인데 이 월 카드를 내려놓으면
    // 흔들기 성립(승리 시 배수 ×2). 명시적 흔들기 커밋이 이미 있었으면 중복 카운트하지 않는다.
    if (not LWasPendingShake) and (LHand.Kind <> hkBonus) and (LMonthInHand >= 3) and (Length(LHandMatches) = 0) then
    begin
      LPlayer.ShakeCount := LPlayer.ShakeCount + 1;
      AddEvent(pekShake, FState.Current, LMonth, Format('%s 흔들기! (%d월)', [LPlayer.Name, LMonth]));
    end;

    // 보너스패(쌍피/3피): 손에서 내면 즉시 획득더미로. 실물 규칙 — 바닥에 놓거나 뒤집지 않고
    // 더미에서 한 장을 뽑아 손을 보충한 뒤, 같은 차례에 실제 패를 한 번 더 낸다(턴을 넘기지 않음).
    // 단, 이번 턴에 뻑(싼) 경우 함께 묻히도록 대기 목록에 기록해 둔다.
    if LHand.Kind = hkBonus then
    begin
      LPlayer.Captured.Add(LHand);
      FPendingBonus := FPendingBonus + [LHand];
      AddEvent(pekCapture, FState.Current, 0, Format('%s 보너스패 획득', [LPlayer.Name]));

      // 선택 UI가 켜져 있으면 더미를 펼쳐 가져올 패를 고르게 멈춘다
      if FBonusDrawEnabled and (FState.Stock.Count > 0) then
      begin
        FState.Phase := gpAwaitingBonusDraw;
        Exit(False);
      end;

      var LRefill: THwatuCard;
      if DrawNonBonus(LPlayer, LRefill) then
      begin
        LPlayer.Hand.Add(LRefill);
      end;

      Exit(False);
    end;

    // 실제 패를 낸 시점에만 흔들기 커밋을 소모하고 판 수를 센다
    // (보너스패는 위에서 단락 — 커밋 유지, 첫뻑 판정도 소모하지 않음)
    LPlayer.PendingShakeMonth := 0;
    var LFirstPlay := FState.PlayCount = 0;
    FState.PlayCount := FState.PlayCount + 1;

    // 더미 뒤집기(보너스패는 즉시 획득하고 다음 장을 뒤집는다)
    var LDraw: THwatuCard;
    var LHasDraw := DrawNonBonus(LPlayer, LDraw);

    // 뻑: 손패가 바닥 1장과 매칭인데 뒤집은 것도 같은 월 → 3장이 바닥에 쌓이고 아무도 못 먹음
    if LHasDraw and (Length(LHandMatches) = 1) and (LDraw.Month = LMonth) then
    begin
      FState.Floor.Add(LHand);
      FState.Floor.Add(LDraw);
      AddEvent(pekBbeok, FState.Current, LMonth, Format('%s 뻑! (%d월)', [LPlayer.Name, LMonth]));

      // 이번 턴에 획득한 보너스패(손에서 낸 것 + 뒤집기에서 나온 조커)는 싼(뻑) 무더기에 함께 묻힌다
      var LBuryBonus := FPendingBonus + FFlipBonus;
      if Length(LBuryBonus) > 0 then
      begin
        for var LB in LBuryBonus do
        begin
          for var J := LPlayer.Captured.Count - 1 downto 0 do
          begin
            if LPlayer.Captured[J].AssetId = LB.AssetId then
            begin
              LPlayer.Captured.Delete(J);
              Break;
            end;
          end;

          var LBuried := LB;
          LBuried.Month := LMonth;   // 뻑 무더기와 같은 월로 묶어, 그 월을 먹을 때 함께 먹히게 한다
          FState.Floor.Add(LBuried);
        end;

        AddEvent(pekPlace, FState.Current, LMonth, Format('%s 보너스패도 뻑 더미에 묻힘', [LPlayer.Name]));
        FPendingBonus := nil;
        FFlipBonus := nil;
      end;

      // 연뻑: 이미 다른 뻑 더미가 남아 있는 상태에서 또 뻑
      if FState.BbeokCreator.Count > 0 then
      begin
        AddEvent(pekYeonbbeok, FState.Current, LMonth, Format('%s 연뻑!', [LPlayer.Name]));
      end;

      // 첫뻑: 게임의 첫 수가 뻑
      if LFirstPlay then
      begin
        AddEvent(pekCheotbbeok, FState.Current, LMonth, Format('%s 첫뻑!', [LPlayer.Name]));
      end;

      // 뻑 더미의 생성자 기록(나중에 이 월을 먹으면 자뻑/뻑 회수 판정)
      FState.BbeokCreator.AddOrSetValue(LMonth, FState.Current);
      AdvanceTurn;
      Exit(False);
    end;

    // 손패 처리(보너스패는 위에서 이미 단락 처리됨)
    var LPlayedCaptured := False;
    if Length(LHandMatches) = 0 then
    begin
      FState.Floor.Add(LHand);
    end
    else
    begin
      LPlayedCaptured := True;
      LCaptured.Add(LHand);
      CaptureInto(LCaptured, LHandMatches, AFloorChoice);
      // 바닥 3장을 먹었으면 뻑 회수 또는 자연 3장 쓸어먹기 피 처리
      if Length(LHandMatches) >= 3 then
      begin
        ResolveThreePileSteal(LMonth);
      end;
    end;

    // 더미 카드 처리
    var LTtadak := False;
    var LJjok := False;
    if LHasDraw then
    begin
      var LDrawMatches := MatchIndices(LDraw.Month);
      if Length(LDrawMatches) = 0 then
      begin
        FState.Floor.Add(LDraw);
      end
      else
      if FFlipChoiceEnabled and (Length(LDrawMatches) = 2) and
        (FState.Floor[LDrawMatches[0]].Kind <> FState.Floor[LDrawMatches[1]].Kind) then
      begin
        // 뒤집은 패가 바닥 2장(서로 다른 종류)과 매칭 → 가져갈 패 선택 대기
        // 손패로 먹은 분은 먼저 획득더미로 이관하고 멈춘다
        if LCaptured.Count > 0 then
        begin
          LPlayer.Captured.AddRange(LCaptured);
          AddEvent(pekCapture, FState.Current, LMonth, Format('%s %d장 먹음', [LPlayer.Name, LCaptured.Count]));
          LCaptured.Clear;
        end;

        FFlipCard := LDraw;
        FFlipOpt0 := FState.Floor[LDrawMatches[0]];
        FFlipOpt1 := FState.Floor[LDrawMatches[1]];
        FFlipHandMonth := LMonth;
        FFlipHandCaptured := LPlayedCaptured;
        FFlipHandPlaced := Length(LHandMatches) = 0;
        FState.Floor.Add(LDraw);   // 뒤집은 패를 바닥에 노출(선택 UI용)
        FState.Phase := gpAwaitingFlipChoice;
        Exit(False);
      end
      else
      begin
        LCaptured.Add(LDraw);
        CaptureInto(LCaptured, LDrawMatches, -1);
        if Length(LDrawMatches) >= 3 then
        begin
          ResolveThreePileSteal(LDraw.Month);
        end;

        if LPlayedCaptured and (LDraw.Month = LMonth) then
        begin
          // 손패로 먹고 뒤집은 것도 같은 월로 먹음 → 따닥
          LTtadak := True;
        end
        else
        if (Length(LHandMatches) = 0) and (LDraw.Month = LMonth) then
        begin
          // 손패를 빈 바닥에 놓았는데 뒤집은 같은 월로 그 카드를 먹음 → 쪽
          LJjok := True;
        end;
      end;
    end;

    // 획득 이관
    if LCaptured.Count > 0 then
    begin
      LPlayer.Captured.AddRange(LCaptured);
      AddEvent(pekCapture, FState.Current, LMonth, Format('%s %d장 먹음', [LPlayer.Name, LCaptured.Count]));
    end
    else
    begin
      AddEvent(pekPlace, FState.Current, LMonth, Format('%s 못 먹고 바닥에 놓음', [LPlayer.Name]));
    end;

    // 마지막 장(손패 소진)에선 쪽·따닥·쓸 등 보너스 이벤트를 인정하지 않는다.
    var LNotLast := LPlayer.Hand.Count > 0;
    var LSseul := (FState.Floor.Count = 0) and (LCaptured.Count > 0) and LNotLast;

    if LTtadak and LNotLast then
    begin
      AddEvent(pekTtadak, FState.Current, LMonth, LPlayer.Name + ' 따닥!');
      StealPiFromOthers(FState.Current);
    end;

    if LJjok and LNotLast then
    begin
      AddEvent(pekJjok, FState.Current, LMonth, LPlayer.Name + ' 쪽!');
      StealPiFromOthers(FState.Current);
    end;

    if LSseul then
    begin
      AddEvent(pekSseul, FState.Current, LMonth, LPlayer.Name + ' 싹쓸이!');
      StealPiFromOthers(FState.Current);
    end;

    // 점수 & 고/스톱
    Result := ScoreAndFinish(LPlayer);
  finally
    LCaptured.Free;
  end;
end;

procedure TTurnEngine.ResolveBonusDraw(const AStockIndex: Integer);
begin
  if FState.Phase <> gpAwaitingBonusDraw then
  begin
    raise EHwatuError.Create('보너스 뽑기 대기 단계가 아닙니다.');
  end;

  if (AStockIndex < 0) or (AStockIndex >= FState.Stock.Count) then
  begin
    raise EHwatuError.CreateFmt('더미 범위를 벗어난 선택입니다(%d).', [AStockIndex]);
  end;

  var LPlayer := FState.CurrentPlayer;
  var LCard := FState.Stock[AStockIndex];
  FState.Stock.Delete(AStockIndex);

  if LCard.Kind = hkBonus then
  begin
    // 보너스패를 집으면 그것도 즉시 획득하고, 더미가 남았으면 다시 고른다
    LPlayer.Captured.Add(LCard);
    AddEvent(pekCapture, FState.Current, 0, Format('%s 보너스패 획득(더미)', [LPlayer.Name]));
    if FState.Stock.Count > 0 then
    begin
      Exit;
    end;

    FState.Phase := gpPlaying;
    Exit;
  end;

  LPlayer.Hand.Add(LCard);
  FState.Phase := gpPlaying;   // 같은 차례 계속(실제 패를 냄)
end;

procedure TTurnEngine.RemoveFloorByAsset(const AAssetId: string);
begin
  for var I := 0 to FState.Floor.Count - 1 do
  begin
    if FState.Floor[I].AssetId = AAssetId then
    begin
      FState.Floor.Delete(I);
      Exit;
    end;
  end;
end;

function TTurnEngine.ScoreAndFinish(const APlayer: TPlayer): Boolean;
begin
  var LScore := TScorer.Evaluate(APlayer.Captured, FRules.Score);
  if (LScore.Total >= 3) and (LScore.Total > APlayer.LastGoScore) then
  begin
    FState.Phase := gpAwaitingGoStop;
    AddEvent(pekGoStop, FState.Current, 0, Format('%s %d점 — 고/스톱 선택', [APlayer.Name, LScore.Total]));
    Exit(True);
  end;

  AdvanceTurn;
  Result := False;
end;

function TTurnEngine.FlipChoiceOptions: TArray<THwatuCard>;
begin
  Result := [FFlipOpt0, FFlipOpt1];
end;

function TTurnEngine.FlipDrawnCard: THwatuCard;
begin
  Result := FFlipCard;
end;

function TTurnEngine.ResolveFlipChoice(const AOrdinal: Integer): Boolean;
begin
  if FState.Phase <> gpAwaitingFlipChoice then
  begin
    raise EHwatuError.Create('뒤집기 선택 대기 단계가 아닙니다.');
  end;

  if (AOrdinal < 0) or (AOrdinal > 1) then
  begin
    raise EHwatuError.CreateFmt('뒤집기 선택지는 0/1이어야 합니다(%d).', [AOrdinal]);
  end;

  var LPlayer := FState.CurrentPlayer;
  var LChosen := FFlipOpt0;
  if AOrdinal = 1 then
  begin
    LChosen := FFlipOpt1;
  end;

  // 뒤집은 패 + 선택한 짝을 바닥에서 제거해 획득더미로
  RemoveFloorByAsset(FFlipCard.AssetId);
  RemoveFloorByAsset(LChosen.AssetId);
  LPlayer.Captured.Add(FFlipCard);
  LPlayer.Captured.Add(LChosen);
  AddEvent(pekCapture, FState.Current, FFlipCard.Month, Format('%s 뒤집어 2장 먹음', [LPlayer.Name]));

  // 따닥/쪽 (마지막 장이면 인정 안 함)
  if (LPlayer.Hand.Count > 0) and FFlipHandCaptured and (FFlipCard.Month = FFlipHandMonth) then
  begin
    AddEvent(pekTtadak, FState.Current, FFlipCard.Month, LPlayer.Name + ' 따닥!');
    StealPiFromOthers(FState.Current);
  end
  else
  if (LPlayer.Hand.Count > 0) and FFlipHandPlaced and (FFlipCard.Month = FFlipHandMonth) then
  begin
    AddEvent(pekJjok, FState.Current, FFlipCard.Month, LPlayer.Name + ' 쪽!');
    StealPiFromOthers(FState.Current);
  end;

  // 쓸(마지막 장 제외)
  if (FState.Floor.Count = 0) and (LPlayer.Hand.Count > 0) then
  begin
    AddEvent(pekSseul, FState.Current, FFlipCard.Month, LPlayer.Name + ' 싹쓸이!');
    StealPiFromOthers(FState.Current);
  end;

  // 전이 상태 클리어(스테일 조회 방지)
  FFlipCard := Default(THwatuCard);
  FFlipOpt0 := Default(THwatuCard);
  FFlipOpt1 := Default(THwatuCard);

  Result := ScoreAndFinish(LPlayer);
end;

procedure TTurnEngine.DeclareGo;
begin
  if FState.Phase <> gpAwaitingGoStop then
  begin
    raise EHwatuError.Create('고/스톱 대기 단계가 아닙니다.');
  end;

  var LPlayer := FState.CurrentPlayer;
  LPlayer.GoCount := LPlayer.GoCount + 1;
  LPlayer.LastGoScore := ScoreOf(FState.Current).Total;
  AddEvent(pekGo, FState.Current, 0, Format('%s %d고!', [LPlayer.Name, LPlayer.GoCount]));
  AdvanceTurn;
end;

procedure TTurnEngine.DeclareStop;
begin
  if FState.Phase <> gpAwaitingGoStop then
  begin
    raise EHwatuError.Create('고/스톱 대기 단계가 아닙니다.');
  end;

  FState.Phase := gpFinished;
  FState.Winner := FState.Current;
  AddEvent(pekStop, FState.Current, 0, FState.CurrentPlayer.Name + ' 스톱! 승리');
end;

// 쇼당(둘 다 수락) 등으로 그 판을 무효(나가리) 처리한다.
procedure TTurnEngine.DeclareNagari;
begin
  FState.Phase := gpFinished;
  FState.Winner := -1;
  AddEvent(pekPlace, FState.Current, 0, '쇼당 — 나가리');
end;

function TTurnEngine.ScoreOf(const APlayerIndex: Integer): TScoreBreakdown;
begin
  Result := TScorer.Evaluate(FState.Player(APlayerIndex).Captured, FRules.Score);
end;

function TTurnEngine.FinalSettlement: TArray<TPlayerResult>;
begin
  SetLength(Result, FState.PlayerCount);
  for var P := 0 to FState.PlayerCount - 1 do
  begin
    Result[P].PlayerIndex := P;
    Result[P].Net := 0;
    Result[P].Pibak := False;
    Result[P].Gwangbak := False;
    Result[P].Meongbak := False;
    Result[P].Gobak := False;
  end;

  // 나가리 또는 미종료 → 전원 0
  if FState.Winner < 0 then
  begin
    Exit;
  end;

  var LWinner := FState.Winner;
  var LWinnerP := FState.Player(LWinner);
  var LWinBreak := TScorer.Evaluate(LWinnerP.Captured, FRules.Score);

  var LTotalToWinner := 0;
  var LGobakLoser := -1;
  for var P := 0 to FState.PlayerCount - 1 do
  begin
    if P = LWinner then
    begin
      Continue;
    end;

    var LLoserBreak := TScorer.Evaluate(FState.Player(P).Captured, FRules.Score);
    var LSettle := TScorer.Settle(LWinBreak, LLoserBreak, LWinnerP.GoCount, LWinnerP.ShakeCount, FRules.Score);
    Result[P].Net := -LSettle.Points;
    Result[P].Pibak := LSettle.Pibak;
    Result[P].Gwangbak := LSettle.Gwangbak;
    Result[P].Meongbak := LSettle.Meongbak;
    LTotalToWinner := LTotalToWinner + LSettle.Points;

    // 고를 부르고 진 사람(고박 대상)
    if FState.Player(P).GoCount > 0 then
    begin
      LGobakLoser := P;
    end;
  end;

  // 고박: 고를 부르고 진 사람이 있으면 그 사람이 전액(다른 패자 몫까지)을 배수(×2)로 부담, 나머지 패자는 면제
  if LGobakLoser >= 0 then
  begin
    for var P := 0 to FState.PlayerCount - 1 do
    begin
      if P <> LWinner then
      begin
        Result[P].Net := 0;
      end;
    end;

    var LGobakTotal := LTotalToWinner * FRules.Score.GobakMultiplier;
    Result[LGobakLoser].Net := -LGobakTotal;
    Result[LGobakLoser].Gobak := True;
    LTotalToWinner := LGobakTotal;   // 승자 수령액도 배수 적용
  end;

  Result[LWinner].Net := LTotalToWinner;
end;

function TTurnEngine.CanDeclareChongtong(const APlayerIndex: Integer; out AMonth: Integer): Boolean;
var
  LCounts: array [1 .. 12] of Integer;
begin
  for var M := 1 to 12 do
  begin
    LCounts[M] := 0;
  end;

  for var LCard in FState.Player(APlayerIndex).Hand do
  begin
    if (LCard.Month >= 1) and (LCard.Month <= 12) then
    begin
      Inc(LCounts[LCard.Month]);
    end;
  end;

  for var M := 1 to 12 do
  begin
    if LCounts[M] >= 4 then
    begin
      AMonth := M;
      Exit(True);
    end;
  end;

  AMonth := 0;
  Result := False;
end;

procedure TTurnEngine.DeclareChongtong(const APlayerIndex: Integer);
begin
  var LMonth: Integer;
  if not CanDeclareChongtong(APlayerIndex, LMonth) then
  begin
    raise EHwatuError.CreateFmt('%d번 플레이어는 총통 조건(같은 월 4장)이 아닙니다.', [APlayerIndex]);
  end;

  if FState.Phase <> gpPlaying then
  begin
    raise EHwatuError.Create('총통은 플레이 중에만 선언할 수 있습니다.');
  end;

  // 총통 = 무효 판(승자 없이 종료) — ApplyHandChongtong과 동일 규칙
  FState.Phase := gpFinished;
  FState.Winner := -1;
  AddEvent(pekChongtong, APlayerIndex, LMonth, Format('%s 총통 선언! (%d월 4장) — 무효 판', [FState.Player(APlayerIndex).Name, LMonth]));
end;

function TTurnEngine.ApplyHandChongtong: Boolean;
begin
  // 딜 직후 총통(같은 월 4장)이 나오면 그 판은 무효 — 승자 없이 끝내고 다음 게임으로
  if FState.Phase <> gpPlaying then
  begin
    Exit(False);
  end;

  for var P := 0 to FState.PlayerCount - 1 do
  begin
    var LMonth: Integer;
    if CanDeclareChongtong(P, LMonth) then
    begin
      FState.Phase := gpFinished;
      FState.Winner := -1;
      AddEvent(pekChongtong, P, LMonth, Format('%s 총통! (%d월 4장) — 무효 판', [FState.Player(P).Name, LMonth]));
      Exit(True);
    end;
  end;

  Result := False;
end;

function TTurnEngine.CanShake(const AMonth: Integer): Boolean;
begin
  var LCount := 0;
  for var LCard in FState.CurrentPlayer.Hand do
  begin
    if LCard.Month = AMonth then
    begin
      Inc(LCount);
    end;
  end;

  Result := LCount >= 3;
end;

procedure TTurnEngine.DeclareShake(const AMonth: Integer);
begin
  if FState.Phase <> gpPlaying then
  begin
    raise EHwatuError.Create('지금은 흔들 수 있는 단계가 아닙니다.');
  end;

  if not CanShake(AMonth) then
  begin
    raise EHwatuError.CreateFmt('%d월 3장을 들고 있지 않아 흔들 수 없습니다.', [AMonth]);
  end;

  var LPlayer := FState.CurrentPlayer;
  if LPlayer.PendingShakeMonth <> 0 then
  begin
    raise EHwatuError.Create('이미 흔들기를 선언했습니다(중복 선언으로 배수를 불릴 수 없음).');
  end;

  LPlayer.ShakeCount := LPlayer.ShakeCount + 1;
  LPlayer.PendingShakeMonth := AMonth;   // 이 월을 실제로 내야 성립(커밋)
  AddEvent(pekShake, FState.Current, AMonth, Format('%s 흔들기! (%d월)', [LPlayer.Name, AMonth]));
end;

function TTurnEngine.CanBomb(const AMonth: Integer): Boolean;
begin
  if not CanShake(AMonth) then
  begin
    Exit(False);
  end;

  Result := Length(MatchIndices(AMonth)) >= 1;
end;

function TTurnEngine.PlayBomb(const AMonth: Integer): Boolean;
begin
  if FState.Phase <> gpPlaying then
  begin
    raise EHwatuError.Create('지금은 폭탄을 칠 단계가 아닙니다.');
  end;

  if not CanBomb(AMonth) then
  begin
    raise EHwatuError.CreateFmt('폭탄 조건 미충족: %d월 손패 3장 + 바닥 같은 월이 필요합니다.', [AMonth]);
  end;

  FState.PlayCount := FState.PlayCount + 1;

  var LPlayer := FState.CurrentPlayer;
  var LCaptured := TList<THwatuCard>.Create;
  try
    // 손패에서 해당 월 3장 제거해 획득에 포함(높은 인덱스부터)
    var LTaken := 0;
    for var I := LPlayer.Hand.Count - 1 downto 0 do
    begin
      if (LPlayer.Hand[I].Month = AMonth) and (LTaken < 3) then
      begin
        LCaptured.Add(LPlayer.Hand[I]);
        LPlayer.Hand.Delete(I);
        Inc(LTaken);
      end;
    end;

    // 바닥의 같은 월 모두 획득
    CaptureInto(LCaptured, MatchIndices(AMonth), 0);

    LPlayer.Captured.AddRange(LCaptured);
    AddEvent(pekBomb, FState.Current, AMonth, Format('%s 폭탄! (%d월)', [LPlayer.Name, AMonth]));

    // 폭탄은 흔들기처럼 배수 ×2, 상대 피 1장씩
    LPlayer.ShakeCount := LPlayer.ShakeCount + 1;
    StealPiFromOthers(FState.Current);

    // 카드빚: 일반 턴(1장) 대비 여분 (낸 장수 - 1)장 → 이후 '뒤집기만' 턴으로 갚는다
    LPlayer.CardDebt := LPlayer.CardDebt + (LTaken - 1);
  finally
    LCaptured.Free;
  end;

  // 폭탄 낸 후 더미 1장 뒤집기
  FlipStockAndResolve(LPlayer);

  // 점수 도달 시 고/스톱, 아니면 턴 넘김
  Result := ScoreAndFinish(LPlayer);
end;

function TTurnEngine.CanFlipOnly: Boolean;
begin
  Result := (FState.Phase = gpPlaying) and (FState.CurrentPlayer.CardDebt > 0) and (FState.Stock.Count > 0);
end;

function TTurnEngine.FlipOnly: Boolean;
begin
  if FState.Phase <> gpPlaying then
  begin
    raise EHwatuError.Create('지금은 뒤집기만 할 단계가 아닙니다.');
  end;

  var LPlayer := FState.CurrentPlayer;
  if LPlayer.CardDebt <= 0 then
  begin
    raise EHwatuError.Create('갚을 카드빚이 없어 뒤집기만 할 수 없습니다.');
  end;

  LPlayer.CardDebt := LPlayer.CardDebt - 1;
  AddEvent(pekTurnPass, FState.Current, 0, Format('%s 뒤집기만(카드빚 갚기, %d 남음)', [LPlayer.Name, LPlayer.CardDebt]));
  FlipStockAndResolve(LPlayer);

  Result := ScoreAndFinish(LPlayer);
end;
{$ENDREGION}

end.
