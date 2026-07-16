unit Gostop.Board;

interface

{$REGION 'uses'}
uses
  System.SysUtils,
  System.Classes,
  System.Types,
  System.UITypes,
  System.Math,
  System.Math.Vectors,
  System.Generics.Collections,
  FMX.Types,
  FMX.Controls,
  FMX.Graphics,
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

  /// <summary>
  ///   고스톱 플레이 보드(FMX 커스텀 컨트롤). 2/3/4인 모드·좌석 배치(반시계)·렌더링·클릭 입력·AI 진행·
  ///   4인 광팔기 협상·고/스톱을 모두 담당한다. 사람은 항상 아래 자리, 나머지는 AI.
  /// </summary>
  TGostopBoard = class(TControl)
  private
    FImages: TCardImageCache;
    FFeltTile: TBitmap;
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
    procedure BuildFinalSummary;
    function FlagStr(const AResult: TPlayerResult): string;
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
    procedure DrawRegionInfo(const APos: TSeatPos);
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
    /// <summary>상태가 바뀔 때(폼이 버튼·상태표시 갱신용).</summary>
    property OnStateChanged: TNotifyEvent read FOnStateChanged write FOnStateChanged;
    /// <summary>게임이 끝났을 때.</summary>
    property OnGameOver: TNotifyEvent read FOnGameOver write FOnGameOver;
  end;

implementation

const
  GWANG_UNIT_PRICE = 1;      // 광 1개당 단가(광값 = 광개수 × 단가)
  MONEY_PER_POINT = 100;     // 1점 = 100원
  SEED_MONEY = 30000;        // 참가 시드머니

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
end;

destructor TGostopBoard.Destroy;
begin
  ClearGame;
  FreeAndNil(FAiObjects);
  FreeAndNil(FTurnEvents);
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
  // 논리 좌석 기준 라벨(0=선=P1). 사람의 논리 좌석은 '나'로 표시
  if APhysicalSeat = FHumanLogical then
  begin
    Result := '나';
  end
  else
  begin
    Result := Format('P%d', [APhysicalSeat + 1]);
  end;
end;

function TGostopBoard.PhysicalPos(const AGameIndex: Integer): TSeatPos;
begin
  if FPlayerCount = 2 then
  begin
    // P1(위)=game0 선, P2(아래=사람)=game1
    if AGameIndex = 0 then
    begin
      Result := spTop;
    end
    else
    begin
      Result := spBottom;
    end;

    Exit;
  end;

  if FPlayerCount = 3 then
  begin
    case AGameIndex of
      0:
        begin
          Result := spTop;
        end;
      1:
        begin
          Result := spLeft;
        end;
    else
      begin
        Result := spBottom;
      end;
    end;

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

  // 새 매치면 시드머니·전적 리셋
  if ANewMatch then
  begin
    for var LP := spTop to spRight do
    begin
      FMoney[LP] := SEED_MONEY;
      FWins[LP] := 0;
      FLosses[LP] := 0;
    end;
  end;

  if FPlayerCount = 4 then
  begin
    StartNegotiation;
  end
  else
  begin
    // 2/3인: 바로 딜 후 플레이
    var LDeck := TDeck.Create;
    try
      LDeck.ShuffleSecure;
      var LConfig := TDealConfig.ForPlayers(2);
      if FPlayerCount = 3 then
      begin
        LConfig := TDealConfig.Custom(3, 7, 6);
      end;

      var LTable := TDealer.Deal(LDeck, LConfig);
      try
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

    // 이름 부여(물리 위치 기준)
    for var I := 0 to FPlayerCount - 1 do
    begin
      case PhysicalPos(I) of
        spBottom:
          begin
            FGame.Player(I).Name := '나';
          end;
        spTop:
          begin
            FGame.Player(I).Name := 'P1';
          end;
        spLeft:
          begin
            FGame.Player(I).Name := 'P2';
          end;
      else
        begin
          FGame.Player(I).Name := 'P4';
        end;
      end;
    end;

    StartPlay;
  end;
end;

procedure TGostopBoard.StartNegotiation;
begin
  // 4인 딜
  var LDeck := TDeck.Create;
  try
    LDeck.ShuffleSecure;
    FTable4 := TDealer.Deal(LDeck, TDealConfig.Custom(4, 7, 6));
  finally
    LDeck.Free;
  end;

  TGostopAudio.Instance.Play('sfx_negotiate');

  // 선 기준 사람의 논리 좌석(아래 자리 = 물리 spBottom)
  FHumanLogical := (Ord(spBottom) - Ord(FNextStartPos) + 4) mod 4;

  // 사람이 선(논리0)이면 결정할 것이 없음 → 자동 진행(AI 모두 참가, P4 광팔기)
  if FHumanLogical = 0 then
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
end;

procedure TGostopBoard.ResolveNegotiation(const AP2Give, AP3Give, AP4Sell: Boolean);
begin
  FNegotiating := False;

  var LRound := TFourPlayer.Resolve(FTable4, AP2Give, AP3Give, AP4Sell, GWANG_UNIT_PRICE, TScoreOptions.Default);
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
  // 사람의 게임 인덱스(아래 자리) 찾기
  FHumanIndex := -1;
  for var I := 0 to FGame.PlayerCount - 1 do
  begin
    if PhysicalPos(I) = spBottom then
    begin
      FHumanIndex := I;
      Break;
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
      var LAi := TAiPlayer.Create(FAiSkill, UInt64(987654321 + I * 1013904223));
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

  FEngine := TTurnEngine.Create(FGame, TRuleSet.Default);
  FEngine.OnEvent := procedure(AEvt: TPlayEvent)
    begin
      FTurnEvents.Add(AEvt);
    end;
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

  // 물리 자리별 머니 반영(최종 손익 × 단가)
  if FPlayerCount = 4 then
  begin
    for var S := 0 to 3 do
    begin
      var LPos := TSeatPos((Ord(FNextStartPos) + S) mod 4);
      FMoney[LPos] := FMoney[LPos] + FNet4[S] * MONEY_PER_POINT;
    end;
  end
  else
  begin
    for var I := 0 to FGame.PlayerCount - 1 do
    begin
      FMoney[PhysicalPos(I)] := FMoney[PhysicalPos(I)] + LSettle[I].Net * MONEY_PER_POINT;
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

  // 결과 라인
  var LLines := TList<string>.Create;
  try
    if FGame.Winner < 0 then
    begin
      LLines.Add('나가리 (무승부)');
    end
    else
    if FPlayerCount = 4 then
    begin
      var LWinnerSeat := FSeatMap[FGame.Winner];
      LLines.Add(Format('%s 승', [SeatLabel(LWinnerSeat)]));
      for var S := 0 to 3 do
      begin
        if S <> LWinnerSeat then
        begin
          LLines.Add(Trim(Format('%s   %d원  %s', [SeatLabel(S), FNet4[S] * MONEY_PER_POINT, LSeatFlag[S]])));
        end;
      end;
    end
    else
    begin
      LLines.Add(Format('%s 승', [FGame.Player(FGame.Winner).Name]));
      for var I := 0 to FGame.PlayerCount - 1 do
      begin
        if I <> FGame.Winner then
        begin
          LLines.Add(Trim(Format('%s   %d원  %s', [FGame.Player(I).Name, LSettle[I].Net * MONEY_PER_POINT, FlagStr(LSettle[I])])));
        end;
      end;
    end;

    FResultLines := LLines.ToArray;
  finally
    LLines.Free;
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
        Result := RectF(Width * 0.19, Height * 0.015, Width * 0.81, Height * 0.19);
      end;
    spBottom:
      begin
        Result := RectF(Width * 0.19, Height * 0.70, Width * 0.81, Height * 0.985);
      end;
    spLeft:
      begin
        Result := RectF(Width * 0.005, Height * 0.02, Width * 0.18, Height * 0.985);
      end;
  else
    begin
      Result := RectF(Width * 0.82, Height * 0.02, Width * 0.995, Height * 0.985);
    end;
  end;
end;

function TGostopBoard.CenterRegion: TRectF;
begin
  Result := RectF(Width * 0.19, Height * 0.205, Width * 0.81, Height * 0.685);
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

  // 획득 더미(그룹) — 영역 상단
  DrawCapturedGrouped(RState.Player(FHumanIndex).Captured, ARegion.Left + 10, ARegion.Top + 22, 0.5);
  DrawHandList(RState.Player(FHumanIndex).Hand, ARegion, not Assigned(FDisplay));
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

procedure TGostopBoard.DrawRegionInfo(const APos: TSeatPos);
begin
  var LRegion := SeatRegion(APos);
  var LIdx := PlayerAtPos(APos);

  // 라벨(참가 중이면 이름, 4인 빠진 자리는 선 기준 논리 라벨)
  var LLabel := '';
  if LIdx >= 0 then
  begin
    LLabel := FGame.Player(LIdx).Name;
  end
  else
  begin
    LLabel := SeatLabel((Ord(APos) - Ord(FNextStartPos) + 4) mod 4);
  end;

  // 1행: 라벨 + 점수·고
  var LLine1 := LLabel;
  if LIdx >= 0 then
  begin
    LLine1 := LLine1 + Format('   %d점', [FEngine.ScoreOf(LIdx).Total]);
    if FGame.Player(LIdx).GoCount > 0 then
    begin
      LLine1 := LLine1 + Format(' %d고', [FGame.Player(LIdx).GoCount]);
    end;
  end;

  // 2행: 보유머니 + 전적
  var LLine2 := Format('%s원  %d승%d패', [FormatFloat('#,##0', FMoney[APos]), FWins[APos], FLosses[APos]]);

  // 어두운 배경 알약 + 흰 글자(카드 위에서도 읽힘)
  var LBoxW := Min(LRegion.Width - 8, 160);
  var LBox := RectF(LRegion.Left + 5, LRegion.Top + 4, LRegion.Left + 5 + LBoxW, LRegion.Top + 46);
  Canvas.Fill.Kind := TBrushKind.Solid;
  Canvas.Fill.Color := $B0000000;
  Canvas.FillRect(LBox, 7, 7, [TCorner.TopLeft, TCorner.TopRight, TCorner.BottomLeft, TCorner.BottomRight], 1);

  Canvas.Fill.Color := TAlphaColors.White;
  Canvas.Font.Size := 13;
  Canvas.FillText(RectF(LBox.Left + 8, LBox.Top + 2, LBox.Right - 4, LBox.Top + 22), LLine1, False, 1, [], TTextAlign.Leading, TTextAlign.Center);
  Canvas.Font.Size := 12;
  Canvas.FillText(RectF(LBox.Left + 8, LBox.Top + 22, LBox.Right - 4, LBox.Bottom - 2), LLine2, False, 1, [], TTextAlign.Leading, TTextAlign.Center);
end;

procedure TGostopBoard.DrawOpponent(const AGameIndex: Integer; const APos: TSeatPos; const ARegion: TRectF);
begin
  var CS := CardSize;
  var LBackW := CS.Width * 0.58;
  var LBackH := CS.Height * 0.58;
  var LCapW := CS.Width * 0.45;
  var LCapH := CS.Height * 0.45;
  var LHand := RState.Player(AGameIndex).Hand;
  var LCaptured := RState.Player(AGameIndex).Captured;
  var LHandCount := LHand.Count;
  var LHandStep := LBackW * 0.45;

  case APos of
    spTop:
      begin
        // 가로 배치(회전 없음)
        var LCX0 := (ARegion.Left + ARegion.Right) / 2 - LHandStep * (LHandCount - 1) / 2;
        var LCY := ARegion.Top + 6 + LBackH / 2;
        for var I := 0 to LHandCount - 1 do
        begin
          DrawCardRotated(LCX0 + I * LHandStep, LCY, LBackW, LBackH, 0, '', True);
        end;

        DrawCapturedGrouped(LCaptured, ARegion.Left + 8, LCY + LBackH / 2 + 6, 0.45);
      end;

    spLeft:
      begin
        // 세로 배치 + 90도 회전
        var LXC := ARegion.Left + 6 + LBackH / 2;
        var LCY0 := ARegion.Top + 8 + LBackW / 2;
        for var I := 0 to LHandCount - 1 do
        begin
          DrawCardRotated(LXC, LCY0 + I * LHandStep, LBackW, LBackH, 90, '', True);
        end;

        var LCapXC := ARegion.Left + 6 + LBackH + 10 + LCapH / 2;
        DrawCapturedLine(LCaptured, LCapXC, ARegion.Top + 8 + LCapW / 2, 0, LCapW * 0.5, LCapW, LCapH, 90);
      end;

    spRight:
      begin
        // 세로 배치 + 270도 회전
        var LXC := ARegion.Right - 6 - LBackH / 2;
        var LCY0 := ARegion.Top + 8 + LBackW / 2;
        for var I := 0 to LHandCount - 1 do
        begin
          DrawCardRotated(LXC, LCY0 + I * LHandStep, LBackW, LBackH, 270, '', True);
        end;

        var LCapXC := ARegion.Right - 6 - LBackH - 10 - LCapH / 2;
        DrawCapturedLine(LCaptured, LCapXC, ARegion.Top + 8 + LCapW / 2, 0, LCapW * 0.5, LCapW, LCapH, 270);
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

  // 다음게임 버튼(이전 승자가 선)
  var LBtnW := 150.0;
  var LCX := (LPanel.Left + LPanel.Right) / 2;
  FBtnNext := RectF(LCX - LBtnW / 2, LY + 12, LCX + LBtnW / 2, LY + 12 + LBtnH);
  Canvas.Fill.Kind := TBrushKind.Solid;
  Canvas.Fill.Color := $FF2E7D32;
  Canvas.FillRect(FBtnNext, 8, 8, [TCorner.TopLeft, TCorner.TopRight, TCorner.BottomLeft, TCorner.BottomRight], 1);
  DrawLabel(FBtnNext, '다음게임', TAlphaColors.White, 18);
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

  // 협상 단계
  if FNegotiating then
  begin
    DrawNegotiation;
    Exit;
  end;

  if FGame = nil then
  begin
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

  // 좌석별 카드(참가 중인 플레이어만)
  for var I := 0 to FGame.PlayerCount - 1 do
  begin
    var LPos := PhysicalPos(I);
    if LPos = spBottom then
    begin
      DrawHumanHand(SeatRegion(spBottom));
    end
    else
    begin
      DrawOpponent(I, LPos, SeatRegion(LPos));
    end;
  end;

  // 자리별 정보(점수·고·보유머니·전적) — 매치의 모든 자리(빠진 자리 포함)
  DrawRegionInfo(spTop);
  DrawRegionInfo(spBottom);
  if FPlayerCount >= 3 then
  begin
    DrawRegionInfo(spLeft);
  end;

  if FPlayerCount >= 4 then
  begin
    DrawRegionInfo(spRight);
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
        // 뒤집기: 더미에서 들어올림(놓기와 동일 처리)
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

        // 소스는 얹혀있던 위치(FRest) 또는 바닥 위치, 타깃은 획득더미
        SetLength(FFlySources, Length(FAnimCaptured));
        SetLength(FFlyTargets, Length(FAnimCaptured));
        var LAnchor := CapturedAnchor(FAnimActor);
        for var I := 0 to High(FAnimCaptured) do
        begin
          FFlyTargets[I] := LAnchor;
          var LFound := False;
          for var J := 0 to High(FRestCards) do
          begin
            if FRestCards[J].AssetId = FAnimCaptured[I].AssetId then
            begin
              FFlySources[I] := FRestPts[J];
              LFound := True;
              Break;
            end;
          end;

          if not LFound then
          begin
            FFlySources[I] := CardCenterInFloor(FDisplay.Floor, FAnimCaptured[I].AssetId);
          end;
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

  FAnimT := FAnimT + FAnimTimer.Interval / LDur;
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
  // 애니메이션 진행 중엔 입력 무시
  if Assigned(FDisplay) then
  begin
    Exit;
  end;

  var LPoint := PointF(X, Y);

  // 게임 종료: 다음게임 버튼(이전 승자가 선으로 새 게임)
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

      var LMatchCount := 0;
      for var LFloorCard in FGame.Floor do
      begin
        if LFloorCard.Month = LMonth then
        begin
          Inc(LMatchCount);
        end;
      end;

      if (LMatchCount = 2) and (LCard.Kind <> hkBonus) then
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

procedure TGostopBoard.MouseMove(Shift: TShiftState; X, Y: Single);
begin
  inherited;
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
  if FHoverHand <> -1 then
  begin
    FHoverHand := -1;
    Repaint;
  end;
end;
{$ENDREGION}

end.
