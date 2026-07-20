unit Gostop.AI;

interface

{$REGION 'uses'}
uses
  System.SysUtils,
  System.Generics.Collections,
  Gostop.Cards,
  Gostop.Score,
  Gostop.Play;
{$ENDREGION}

type
  /// <summary>AI가 선택할 행동의 종류.</summary>
  TAiMoveKind = (
    amkPlayHand,   // 손패를 냄
    amkBomb,       // 폭탄
    amkFlipOnly    // 뒤집기만(카드빚 갚기)
  );

  /// <summary>AI가 평가한 하나의 후보 수.</summary>
  TAiMove = record
    Kind: TAiMoveKind;
    HandIndex: Integer;   // amkPlayHand
    FloorChoice: Integer; // amkPlayHand: 바닥 2장 매칭 시 선택(0/1)
    Month: Integer;       // amkBomb
    Value: Double;        // 1-플라이 휴리스틱 평가값
  end;

  /// <summary>
  ///   능력치(0~100) 하나로 4축(실수·무작위성 / 고·스톱 위험판단 / 카드기억·상대패 추정 / 방어·방해)을
  ///   연동해 플레이하는 컴퓨터 플레이어.
  ///   능력치가 높으면 결정화 몬테카를로(안 보이는 카드를 크기 맞춰 무작위 분배한 가상 세계에서 게임 끝까지
  ///   시뮬레이션)로 수읽기를 하고, 낮으면 1-플라이 휴리스틱 + 무작위로 둔다. 시드 LCG로 결정론적.
  /// </summary>
  TAiPlayer = class(TObject, IPlayerAgent)
  protected
    // IInterface: 참조 카운팅 비활성(수명은 수동 관리)
    function QueryInterface(const IID: TGUID; out Obj): HResult; stdcall;
    function _AddRef: Integer; stdcall;
    function _Release: Integer; stdcall;
  private
    FSkill: Integer;
    FGoBias: Integer;   // 배짱(0~100, 기본 50): 고/스톱 판단을 고 쪽으로 기울임
    FGreed: Integer;    // 욕심(0~100, 기본 50): 높으면 득점 우선, 낮으면 방어(견제) 우선
    FSeed: UInt64;

    // 족보 완성 카드 봉쇄: MC 평가가 사실상 동점인 후보들 사이에서만, 상대 족보를
    // 완성시켜 주는 수를 피한다(후보 선별 자체는 건드리지 않는다)
    FDenyTieBreak: Boolean;   // 동점 갈림수 사용 여부(A/B 측정용)
    FDenyTieCount: Integer;   // 동점 갈림으로 선택이 바뀐 횟수(검증용)
    function NextRandom(const ABound: Integer): Integer;
    function NextFloat: Double;
    function SkillFactor: Double;
    function SimCount: Integer;
    function CardValue(const ACard: THwatuCard): Double;
    function OpponentThreat(const AState: TGameState; const ASelfIndex: Integer): Double;
    function OpponentGiftRisk(const AState: TGameState; const ASelfIndex: Integer;
      const ACard: THwatuCard): Double;
    function MoveGiftRisk(const AState: TGameState; const ASelfIndex: Integer;
      const AMove: TAiMove): Double;
    function BestFloorChoice(const AState: TGameState; const AMonth: Integer; out AChoiceValue: Double): Integer;
    function EvaluateHandMove(const AState: TGameState; const ASelfIndex: Integer; const AHandIndex: Integer;
      const AThreat: Double; out AFloorChoice: Integer): Double;
    function GenerateMoves(const AEngine: TTurnEngine): TArray<TAiMove>;
    function ChooseMove(const AMoves: TArray<TAiMove>): TAiMove;
    function PickWithMistakes(const AMoves: TArray<TAiMove>; const ABest: TAiMove): TAiMove;
    function TopKMoves(const AMoves: TArray<TAiMove>; const AK: Integer): TArray<TAiMove>;
    procedure ExecuteMove(const AEngine: TTurnEngine; const AMove: TAiMove);
    // 몬테카를로(수읽기)
    function Determinize(const AReal: TGameState; const ASelfIndex: Integer): TGameState;
    procedure RolloutStep(const AEngine: TTurnEngine);
    procedure RunToTerminal(const AEngine: TTurnEngine);
    function OutcomeFromEngine(const AEngine: TTurnEngine; const ASelfIndex: Integer): Double;
    function GreedyBest(const AMoves: TArray<TAiMove>): TAiMove;
    procedure DoPlay(const AEngine: TTurnEngine);
    procedure DoGoStop(const AEngine: TTurnEngine);
  public
    /// <summary>능력치(0~100)와 난수 시드로 AI를 생성합니다.</summary>
    /// <param name="ASkill">0(초보)~100(고수). 범위를 벗어나면 보정.</param>
    /// <param name="ASeed">난수 시드(결정론적 재현용).</param>
    constructor Create(const ASkill: Integer; const ASeed: UInt64 = 88172645463325252);

    /// <summary>현재 게임 단계에 맞는 행동을 1회 수행합니다.</summary>
    /// <param name="AEngine">이 AI가 현재 차례인 턴 엔진.</param>
    procedure Act(const AEngine: TTurnEngine);

    /// <summary>능력치(0~100).</summary>
    property Skill: Integer read FSkill write FSkill;
    /// <summary>배짱(0~100, 기본 50). 높을수록 고를 외치는 성향.</summary>
    property GoBias: Integer read FGoBias write FGoBias;
    /// <summary>욕심(0~100, 기본 50). 높을수록 득점 우선, 낮을수록 방어(상대 견제) 우선.</summary>
    property Greed: Integer read FGreed write FGreed;

    /// <summary>
    ///   수읽기 결과가 사실상 동점일 때 상대 족보를 완성시켜 주는 수를 피할지 여부(기본 켬).
    ///   후보 선별에는 개입하지 않으므로 실력에는 영향이 없고, 눈에 띄는 악수만 걸러낸다.
    /// </summary>
    property DenyTieBreak: Boolean read FDenyTieBreak write FDenyTieBreak;
    /// <summary>동점 갈림으로 선택이 바뀐 누적 횟수(검증용). 0이면 로직이 죽어 있는 것이다.</summary>
    property DenyTieCount: Integer read FDenyTieCount;
  end;

implementation

{$REGION 'uses'}
uses
  System.Math;
{$ENDREGION}

const
  LCG_MULTIPLIER: UInt64 = 6364136223846793005;
  LCG_INCREMENT: UInt64 = 1442695040888963407;
  MAX_DETERMINIZATIONS = 12;   // 능력 100일 때 후보당 시뮬 세계 수
  TOP_K = 3;                   // 몬테카를로로 정밀 평가할 상위 후보 수
  ROLLOUT_ITER_CAP = 4000;     // 롤아웃 안전 상한
  // 수읽기 값이 이 폭 안이면 사실상 동점으로 보고, 상대 족보를 덜 완성시키는 쪽을 고른다.
  // 후보 선별에 봉쇄를 섞으면 좋은 수가 밀려나 손해였으므로(6,000판 실측 판당 -0.217,
  // docs/balance.md 9절) 봉쇄는 여기서만 쓴다.
  DENY_TIE_EPS = 0.3;

{$REGION 'TAiPlayer'}
constructor TAiPlayer.Create(const ASkill: Integer; const ASeed: UInt64);
begin
  inherited Create;
  FSkill := EnsureRange(ASkill, 0, 100);
  FGoBias := 50;
  FGreed := 50;
  FDenyTieBreak := True;
  FDenyTieCount := 0;
  FSeed := ASeed;
  if FSeed = 0 then
  begin
    FSeed := 88172645463325252;
  end;
end;

function TAiPlayer.QueryInterface(const IID: TGUID; out Obj): HResult;
begin
  if GetInterface(IID, Obj) then
  begin
    Result := 0;   // S_OK
  end
  else
  begin
    Result := HResult($80004002);   // E_NOINTERFACE
  end;
end;

function TAiPlayer._AddRef: Integer;
begin
  Result := -1;   // 참조 카운팅 안 함
end;

function TAiPlayer._Release: Integer;
begin
  Result := -1;
end;

function TAiPlayer.NextRandom(const ABound: Integer): Integer;
begin
  if ABound <= 1 then
  begin
    Exit(0);
  end;

  FSeed := FSeed * LCG_MULTIPLIER + LCG_INCREMENT;
  Result := Integer((FSeed shr 33) mod UInt64(ABound));
end;

function TAiPlayer.NextFloat: Double;
begin
  FSeed := FSeed * LCG_MULTIPLIER + LCG_INCREMENT;
  Result := (FSeed shr 11) / 9007199254740992.0;
end;

function TAiPlayer.SkillFactor: Double;
begin
  Result := FSkill / 100.0;
end;

function TAiPlayer.SimCount: Integer;
begin
  // 능력치에 비례한 결정화 세계 수(수읽기 깊이). 능력 0이면 0(순수 휴리스틱).
  Result := Round(SkillFactor * MAX_DETERMINIZATIONS);
end;

function TAiPlayer.CardValue(const ACard: THwatuCard): Double;
begin
  case ACard.Kind of
    hkBright:
      begin
        Result := 20;
      end;
    hkAnimal:
      begin
        if ACard.IsGodori then
        begin
          Result := 13;
        end
        else
        if ACard.IsGukjin then
        begin
          Result := 11;
        end
        else
        begin
          Result := 8;
        end;
      end;
    hkRibbon:
      begin
        if ACard.Ribbon = rkNone then
        begin
          Result := 5;
        end
        else
        begin
          Result := 8;
        end;
      end;
    hkJunk:
      begin
        if ACard.JunkValue >= 2 then
        begin
          Result := 4;
        end
        else
        begin
          Result := 2;
        end;
      end;
    hkBonus:
      begin
        Result := 2 + ACard.JunkValue;
      end;
  else
    begin
      Result := 1;
    end;
  end;
end;

function TAiPlayer.OpponentThreat(const AState: TGameState; const ASelfIndex: Integer): Double;
begin
  Result := 0;
  for var P := 0 to AState.PlayerCount - 1 do
  begin
    if P = ASelfIndex then
    begin
      Continue;
    end;

    var LBreak := TScorer.Evaluate(AState.Player(P).Captured, TScoreOptions.Default);
    var LThreat: Double := LBreak.Total;
    if LBreak.BrightCount = 2 then
    begin
      LThreat := LThreat + 3;
    end;

    if LBreak.BrightCount = 4 then
    begin
      LThreat := LThreat + 2;
    end;

    Result := Max(Result, LThreat);
  end;
end;

// 이 카드를 바닥에 남기면 상대가 가져가 족보를 완성할 수 있는 위험도(상대 중 최대 상승 점수).
// 조건을 손으로 나열하는 대신 실제 채점기로 "상대가 이 카드를 먹었을 때 오르는 점수"를 직접 재
// 청단·홍단·초단·고도리·광은 물론 비광 삼광 같은 예외까지 규칙 그대로 반영된다.
function TAiPlayer.OpponentGiftRisk(const AState: TGameState; const ASelfIndex: Integer;
  const ACard: THwatuCard): Double;
begin
  Result := 0;
  var LWith := TList<THwatuCard>.Create;
  try
    for var P := 0 to AState.PlayerCount - 1 do
    begin
      if P = ASelfIndex then
      begin
        Continue;
      end;

      var LCaptured := AState.Player(P).Captured;
      var LBase := TScorer.Evaluate(LCaptured, TScoreOptions.Default).Total;

      LWith.Clear;
      LWith.AddRange(LCaptured);
      LWith.Add(ACard);
      Result := Max(Result, TScorer.Evaluate(LWith, TScoreOptions.Default).Total - LBase);
    end;
  finally
    LWith.Free;
  end;
end;

// 이 수를 두면 상대에게 족보 완성 카드를 내주게 되는가(바닥에 남는 경우만).
// 바닥에 같은 월이 있으면 내가 먹으므로 내주는 게 아니고, 보너스패도 바닥에 남지 않는다.
function TAiPlayer.MoveGiftRisk(const AState: TGameState; const ASelfIndex: Integer;
  const AMove: TAiMove): Double;
begin
  Result := 0;
  if AMove.Kind <> amkPlayHand then
  begin
    Exit;
  end;

  var LHand := AState.Player(ASelfIndex).Hand;
  if (AMove.HandIndex < 0) or (AMove.HandIndex >= LHand.Count) then
  begin
    Exit;
  end;

  var LCard := LHand[AMove.HandIndex];
  if LCard.Kind = hkBonus then
  begin
    Exit;
  end;

  for var I := 0 to AState.Floor.Count - 1 do
  begin
    if AState.Floor[I].Month = LCard.Month then
    begin
      Exit;   // 짝이 있어 내가 먹는다
    end;
  end;

  Result := OpponentGiftRisk(AState, ASelfIndex, LCard);
end;

function TAiPlayer.BestFloorChoice(const AState: TGameState; const AMonth: Integer; out AChoiceValue: Double): Integer;
begin
  Result := 0;
  AChoiceValue := 0;
  var LSeen := 0;
  for var I := 0 to AState.Floor.Count - 1 do
  begin
    if AState.Floor[I].Month = AMonth then
    begin
      var LV := CardValue(AState.Floor[I]);
      if LV > AChoiceValue then
      begin
        AChoiceValue := LV;
        Result := LSeen;
      end;

      Inc(LSeen);
    end;
  end;
end;

function TAiPlayer.EvaluateHandMove(const AState: TGameState; const ASelfIndex: Integer; const AHandIndex: Integer;
  const AThreat: Double; out AFloorChoice: Integer): Double;
begin
  var LCard := AState.Player(ASelfIndex).Hand[AHandIndex];

  // 보너스패는 공짜 획득 + 재행동이므로 항상 우선 사용(들고 있을 이유가 없음)
  if LCard.Kind = hkBonus then
  begin
    AFloorChoice := 0;
    Result := CardValue(LCard) + 5;
    Exit;
  end;

  var LMatchCount := 0;
  for var I := 0 to AState.Floor.Count - 1 do
  begin
    if AState.Floor[I].Month = LCard.Month then
    begin
      Inc(LMatchCount);
    end;
  end;

  AFloorChoice := 0;
  // 욕심이 높을수록 방어(견제) 가중을 줄이고 득점을 우선한다
  var LDefWeight := SkillFactor * (AThreat / 10.0) * ((100 - FGreed) / 50.0);

  if LMatchCount = 0 then
  begin
    // 상대 족보를 완성시키는 카드인지는 여기서 보지 않는다. 이 점수는 MC로 정밀 평가할
    // 상위 후보를 고르는 데 쓰이는데, 여기에 봉쇄 가중을 얹으면 정작 좋은 수가 후보에서
    // 밀려나 손해였다(6,000판 실측 판당 -0.217, docs/balance.md 9절).
    // 봉쇄는 MC 평가가 사실상 동점일 때의 갈림수로만 쓴다(DoPlay 참조).
    Result := -CardValue(LCard) * (0.2 + LDefWeight);
    Exit;
  end;

  var LChoiceValue: Double;
  AFloorChoice := BestFloorChoice(AState, LCard.Month, LChoiceValue);
  if LMatchCount >= 3 then
  begin
    LChoiceValue := 0;
    for var I := 0 to AState.Floor.Count - 1 do
    begin
      if AState.Floor[I].Month = LCard.Month then
      begin
        LChoiceValue := LChoiceValue + CardValue(AState.Floor[I]);
      end;
    end;
  end;

  Result := LChoiceValue + CardValue(LCard) * 0.5 + LChoiceValue * LDefWeight;
end;

function TAiPlayer.GenerateMoves(const AEngine: TTurnEngine): TArray<TAiMove>;
begin
  var LState := AEngine.State;
  var LSelf := LState.Current;
  var LThreat := OpponentThreat(LState, LSelf);
  var LList := TList<TAiMove>.Create;
  try
    var LHand := LState.CurrentPlayer.Hand;
    for var I := 0 to LHand.Count - 1 do
    begin
      var LMove: TAiMove;
      LMove.Kind := amkPlayHand;
      LMove.HandIndex := I;
      LMove.Month := LHand[I].Month;
      LMove.Value := EvaluateHandMove(LState, LSelf, I, LThreat, LMove.FloorChoice);
      LList.Add(LMove);
    end;

    var LSeenMonth: array [0 .. 12] of Boolean;
    for var M := 0 to 12 do
    begin
      LSeenMonth[M] := False;
    end;

    begin
      for var I := 0 to LHand.Count - 1 do
      begin
        var LM := LHand[I].Month;
        if (LM < 0) or (LM > 12) or LSeenMonth[LM] then
        begin
          Continue;
        end;

        LSeenMonth[LM] := True;
        if AEngine.CanBomb(LM) then
        begin
          var LBomb: TAiMove;
          LBomb.Kind := amkBomb;
          LBomb.Month := LM;
          LBomb.HandIndex := -1;
          LBomb.FloorChoice := 0;
          var LBombValue: Double := 6;
          for var J := 0 to LState.Floor.Count - 1 do
          begin
            if LState.Floor[J].Month = LM then
            begin
              LBombValue := LBombValue + CardValue(LState.Floor[J]);
            end;
          end;

          LBomb.Value := LBombValue;
          LList.Add(LBomb);
        end;
      end;
    end;

    Result := LList.ToArray;
  finally
    LList.Free;
  end;
end;

function TAiPlayer.GreedyBest(const AMoves: TArray<TAiMove>): TAiMove;
begin
  var LBestIdx := 0;
  for var I := 1 to High(AMoves) do
  begin
    if AMoves[I].Value > AMoves[LBestIdx].Value then
    begin
      LBestIdx := I;
    end;
  end;

  Result := AMoves[LBestIdx];
end;

function TAiPlayer.PickWithMistakes(const AMoves: TArray<TAiMove>; const ABest: TAiMove): TAiMove;
begin
  // 능력치가 낮을수록 최선수(ABest) 대신 무작위 수를 고른다(실수·무작위성 축).
  // 능력 0 → 15%만 최선수, 능력 100 → 항상 최선수.
  var LBestProb := 0.15 + 0.85 * SkillFactor;
  if (Length(AMoves) = 1) or (NextFloat <= LBestProb) then
  begin
    Result := ABest;
    Exit;
  end;

  Result := AMoves[NextRandom(Length(AMoves))];
end;

function TAiPlayer.ChooseMove(const AMoves: TArray<TAiMove>): TAiMove;
begin
  Result := PickWithMistakes(AMoves, GreedyBest(AMoves));
end;

function TAiPlayer.TopKMoves(const AMoves: TArray<TAiMove>; const AK: Integer): TArray<TAiMove>;
begin
  var LSorted := Copy(AMoves);
  // 값 내림차순 정렬(후보 수가 적어 선택정렬로 충분)
  for var I := 0 to High(LSorted) - 1 do
  begin
    for var J := I + 1 to High(LSorted) do
    begin
      if LSorted[J].Value > LSorted[I].Value then
      begin
        var LTmp := LSorted[I];
        LSorted[I] := LSorted[J];
        LSorted[J] := LTmp;
      end;
    end;
  end;

  var LN := Min(AK, Length(LSorted));
  SetLength(Result, LN);
  for var I := 0 to LN - 1 do
  begin
    Result[I] := LSorted[I];
  end;
end;

procedure TAiPlayer.ExecuteMove(const AEngine: TTurnEngine; const AMove: TAiMove);
begin
  case AMove.Kind of
    amkBomb:
      begin
        AEngine.PlayBomb(AMove.Month);
      end;
    amkFlipOnly:
      begin
        AEngine.FlipOnly;
      end;
  else
    begin
      AEngine.PlayHandCard(AMove.HandIndex, AMove.FloorChoice);
    end;
  end;
end;

function TAiPlayer.Determinize(const AReal: TGameState; const ASelfIndex: Integer): TGameState;
begin
  Result := AReal.Clone;

  var LPool := TList<THwatuCard>.Create;
  var LSizes := TList<Integer>.Create;
  try
    // 안 보이는 카드 = 다른 플레이어 손패 + 뒷패 → 풀에 모아 무작위 재분배
    for var P := 0 to Result.PlayerCount - 1 do
    begin
      if P = ASelfIndex then
      begin
        LSizes.Add(-1);
        Continue;
      end;

      LSizes.Add(Result.Player(P).Hand.Count);
      LPool.AddRange(Result.Player(P).Hand);
      Result.Player(P).Hand.Clear;
    end;

    LPool.AddRange(Result.Stock);
    Result.Stock.Clear;

    for var I := LPool.Count - 1 downto 1 do
    begin
      var LJ := NextRandom(I + 1);
      var LTmp := LPool[I];
      LPool[I] := LPool[LJ];
      LPool[LJ] := LTmp;
    end;

    var LIdx := 0;
    for var P := 0 to Result.PlayerCount - 1 do
    begin
      if P = ASelfIndex then
      begin
        Continue;
      end;

      for var K := 0 to LSizes[P] - 1 do
      begin
        Result.Player(P).Hand.Add(LPool[LIdx]);
        Inc(LIdx);
      end;
    end;

    while LIdx < LPool.Count do
    begin
      Result.Stock.Add(LPool[LIdx]);
      Inc(LIdx);
    end;
  finally
    LSizes.Free;
    LPool.Free;
  end;
end;

procedure TAiPlayer.RolloutStep(const AEngine: TTurnEngine);
begin
  var LState := AEngine.State;

  if LState.Phase = gpAwaitingGoStop then
  begin
    var LMe := LState.Current;
    var LScore := AEngine.ScoreOf(LMe).Total;
    if (LState.CurrentPlayer.Hand.Count >= 2) and (LScore < 7) then
    begin
      AEngine.DeclareGo;
    end
    else
    begin
      AEngine.DeclareStop;
    end;

    Exit;
  end;

  if LState.Phase <> gpPlaying then
  begin
    Exit;
  end;

  if LState.CurrentPlayer.Hand.Count = 0 then
  begin
    if AEngine.CanFlipOnly then
    begin
      AEngine.FlipOnly;
    end;

    Exit;
  end;

  var LMoves := GenerateMoves(AEngine);
  if Length(LMoves) = 0 then
  begin
    Exit;
  end;

  ExecuteMove(AEngine, GreedyBest(LMoves));
end;

procedure TAiPlayer.RunToTerminal(const AEngine: TTurnEngine);
begin
  var LIter := 0;
  while (AEngine.State.Phase <> gpFinished) and (LIter < ROLLOUT_ITER_CAP) do
  begin
    RolloutStep(AEngine);
    Inc(LIter);
  end;
end;

// 정산 순손익(고 보너스·배수·박 반영)을 결과값으로 — 고/스톱·수읽기 판단이 실제 손익과 일치
function TAiPlayer.OutcomeFromEngine(const AEngine: TTurnEngine; const ASelfIndex: Integer): Double;
begin
  if AEngine.State.Winner < 0 then
  begin
    Exit(0);
  end;

  var LSettle := AEngine.FinalSettlement;
  if (ASelfIndex >= 0) and (ASelfIndex <= High(LSettle)) then
  begin
    Result := LSettle[ASelfIndex].Net;
  end
  else
  begin
    Result := 0;
  end;
end;

procedure TAiPlayer.DoPlay(const AEngine: TTurnEngine);
begin
  var LState := AEngine.State;
  var LSelf := LState.Current;

  // 낼 손패가 없으면 카드빚을 뒤집기로 갚는다(강제)
  if LState.CurrentPlayer.Hand.Count = 0 then
  begin
    if AEngine.CanFlipOnly then
    begin
      AEngine.FlipOnly;
    end;

    Exit;
  end;

  var LMoves := GenerateMoves(AEngine);
  if Length(LMoves) = 0 then
  begin
    Exit;
  end;

  var LSims := SimCount;
  if LSims = 0 then
  begin
    // 저능력: 1-플라이 휴리스틱 + 무작위(실수)
    ExecuteMove(AEngine, ChooseMove(LMoves));
    Exit;
  end;

  // 고능력: 상위 후보를 결정화 몬테카를로로 정밀 평가
  var LTopK := TopKMoves(LMoves, TOP_K);
  var LBestValue := -1.0e18;
  var LBestMove := LTopK[0];
  var LBestGift := 1.0e18;   // 첫 후보가 항상 기준이 되도록 크게 시작
  for var C := 0 to High(LTopK) do
  begin
    var LSum: Double := 0;
    for var D := 1 to LSims do
    begin
      var LWorld := Determinize(LState, LSelf);
      try
        var LWEngine := TTurnEngine.Create(LWorld, AEngine.Rules);
        try
          LWEngine.CollectEvents := False;
          ExecuteMove(LWEngine, LTopK[C]);
          RunToTerminal(LWEngine);
          LSum := LSum + OutcomeFromEngine(LWEngine, LSelf);
        finally
          LWEngine.Free;
        end;
      finally
        LWorld.Free;
      end;
    end;

    var LAvg := LSum / LSims;

    // 수읽기 값이 확실히 더 좋으면 그대로 채택하고, 사실상 동점이면 상대 족보를 덜
    // 완성시켜 주는 쪽을 고른다(상대가 청단 2장인데 3번째 청띠를 깔아주는 악수 회피).
    var LGift: Double := 0;
    if FDenyTieBreak then
    begin
      LGift := MoveGiftRisk(LState, LSelf, LTopK[C]);
    end;

    if LAvg > LBestValue + DENY_TIE_EPS then
    begin
      LBestValue := LAvg;
      LBestMove := LTopK[C];
      LBestGift := LGift;
    end
    else
    if FDenyTieBreak and (LAvg >= LBestValue - DENY_TIE_EPS) and (LGift < LBestGift) then
    begin
      // 동점 갈림 — 값은 그대로 두고(더 낮을 수 있으므로) 수만 바꾼다
      LBestValue := Max(LBestValue, LAvg);
      LBestMove := LTopK[C];
      LBestGift := LGift;
      Inc(FDenyTieCount);
    end
    else
    if LAvg > LBestValue then
    begin
      LBestValue := LAvg;
      LBestMove := LTopK[C];
      LBestGift := LGift;
    end;
  end;

  // MC 최선수에도 능력치 비례 실수를 적용(고수↔하수 격차 확대)
  ExecuteMove(AEngine, PickWithMistakes(LMoves, LBestMove));
end;

procedure TAiPlayer.DoGoStop(const AEngine: TTurnEngine);
begin
  var LState := AEngine.State;
  var LSelf := LState.Current;
  var LScore := AEngine.ScoreOf(LSelf).Total;
  var LSims := SimCount;

  if LSims = 0 then
  begin
    // 저능력: 단순 휴리스틱 + 무작위(배짱이 높으면 고 쪽으로 기울임)
    var LGrowth := LState.CurrentPlayer.Hand.Count;
    var LThreat := OpponentThreat(LState, LSelf) * SkillFactor;
    var LWantGo := (LGrowth >= 2) and (LThreat < LScore + 2 + (FGoBias - 50) / 12.5) and (LScore < 7);
    var LQuality := 0.4 + 0.6 * SkillFactor;
    var LDecideGo: Boolean;
    if NextFloat <= LQuality then
    begin
      LDecideGo := LWantGo;
    end
    else
    begin
      LDecideGo := NextRandom(2) = 0;
    end;

    if LDecideGo then
    begin
      AEngine.DeclareGo;
    end
    else
    begin
      AEngine.DeclareStop;
    end;

    Exit;
  end;

  // 고능력: 스톱(지금 승리) vs 고(롤아웃 기대값)를 실제 정산 손익 기준으로 비교.
  // 스톱값 = 지금 스톱 시 내 순손익(고 보너스·박 반영)
  var LStopWorld := Determinize(LState, LSelf);
  var LStopValue: Double;
  try
    var LSE := TTurnEngine.Create(LStopWorld, AEngine.Rules);
    try
      LSE.CollectEvents := False;
      LSE.DeclareStop;
      LStopValue := OutcomeFromEngine(LSE, LSelf);
    finally
      LSE.Free;
    end;
  finally
    LStopWorld.Free;
  end;
  var LGoSum: Double := 0;
  for var D := 1 to LSims do
  begin
    var LWorld := Determinize(LState, LSelf);
    try
      var LWEngine := TTurnEngine.Create(LWorld, AEngine.Rules);
      try
        LWEngine.CollectEvents := False;
        LWEngine.DeclareGo;
        RunToTerminal(LWEngine);
        LGoSum := LGoSum + OutcomeFromEngine(LWEngine, LSelf);
      finally
        LWEngine.Free;
      end;
    finally
      LWorld.Free;
    end;
  end;

  // 배짱 보정: 높으면 고 기대값을 후하게 본다(±2점 범위)
  if (LGoSum / LSims) + (FGoBias - 50) / 25.0 > LStopValue then
  begin
    AEngine.DeclareGo;
  end
  else
  begin
    AEngine.DeclareStop;
  end;
end;

procedure TAiPlayer.Act(const AEngine: TTurnEngine);
begin
  case AEngine.State.Phase of
    gpPlaying:
      begin
        DoPlay(AEngine);
      end;
    gpAwaitingGoStop:
      begin
        DoGoStop(AEngine);
      end;
  end;
end;
{$ENDREGION}

end.
