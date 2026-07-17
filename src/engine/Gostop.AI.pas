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
    FSeed: UInt64;
    function NextRandom(const ABound: Integer): Integer;
    function NextFloat: Double;
    function SkillFactor: Double;
    function SimCount: Integer;
    function CardValue(const ACard: THwatuCard): Double;
    function OpponentThreat(const AState: TGameState; const ASelfIndex: Integer): Double;
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
    function OutcomeOf(const AState: TGameState; const ASelfIndex: Integer): Double;
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

{$REGION 'TAiPlayer'}
constructor TAiPlayer.Create(const ASkill: Integer; const ASeed: UInt64);
begin
  inherited Create;
  FSkill := EnsureRange(ASkill, 0, 100);
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
  var LDefWeight := SkillFactor * (AThreat / 10.0);

  if LMatchCount = 0 then
  begin
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

    var LSeenMonth := TDictionary<Integer, Boolean>.Create;
    try
      for var I := 0 to LHand.Count - 1 do
      begin
        var LM := LHand[I].Month;
        if LSeenMonth.ContainsKey(LM) then
        begin
          Continue;
        end;

        LSeenMonth.Add(LM, True);
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
    finally
      LSeenMonth.Free;
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
    // 안 보이는 카드 = 다른 플레이어 손패 + 더미 → 풀에 모아 무작위 재분배
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

function TAiPlayer.OutcomeOf(const AState: TGameState; const ASelfIndex: Integer): Double;
begin
  if AState.Winner < 0 then
  begin
    Exit(0);
  end;

  var LBreak := TScorer.Evaluate(AState.Player(AState.Winner).Captured, TScoreOptions.Default);
  if AState.Winner = ASelfIndex then
  begin
    Result := LBreak.Total;
  end
  else
  begin
    Result := -LBreak.Total;
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
  for var C := 0 to High(LTopK) do
  begin
    var LSum: Double := 0;
    for var D := 1 to LSims do
    begin
      var LWorld := Determinize(LState, LSelf);
      try
        var LWEngine := TTurnEngine.Create(LWorld, TScoreOptions.Default);
        try
          ExecuteMove(LWEngine, LTopK[C]);
          RunToTerminal(LWEngine);
        finally
          LWEngine.Free;
        end;

        LSum := LSum + OutcomeOf(LWorld, LSelf);
      finally
        LWorld.Free;
      end;
    end;

    var LAvg := LSum / LSims;
    if LAvg > LBestValue then
    begin
      LBestValue := LAvg;
      LBestMove := LTopK[C];
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
    // 저능력: 단순 휴리스틱 + 무작위
    var LGrowth := LState.CurrentPlayer.Hand.Count;
    var LThreat := OpponentThreat(LState, LSelf) * SkillFactor;
    var LWantGo := (LGrowth >= 2) and (LThreat < LScore + 2) and (LScore < 7);
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

  // 고능력: 스톱(지금 승리, 값=내 점수) vs 고(롤아웃 기대값)를 비교. 고박 위험이 자동 반영됨.
  var LStopValue: Double := LScore;
  var LGoSum: Double := 0;
  for var D := 1 to LSims do
  begin
    var LWorld := Determinize(LState, LSelf);
    try
      var LWEngine := TTurnEngine.Create(LWorld, TScoreOptions.Default);
      try
        LWEngine.DeclareGo;
        RunToTerminal(LWEngine);
      finally
        LWEngine.Free;
      end;

      LGoSum := LGoSum + OutcomeOf(LWorld, LSelf);
    finally
      LWorld.Free;
    end;
  end;

  if (LGoSum / LSims) > LStopValue then
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
