unit Gostop.Deal;

interface

{$REGION 'uses'}
uses
  System.SysUtils,
  System.Generics.Collections,
  System.Generics.Defaults,
  Gostop.Cards,
  Gostop.Deck;
{$ENDREGION}

type
  /// <summary>딜(분배) 구성: 인원수·플레이어당 손패·바닥 장수.</summary>
  TDealConfig = record
    /// <summary>플레이어 수(2 이상).</summary>
    PlayerCount: Integer;
    /// <summary>플레이어당 손패 장수.</summary>
    HandSize: Integer;
    /// <summary>바닥에 까는 장수.</summary>
    FloorSize: Integer;

    /// <summary>인원수에 맞는 표준 구성을 반환합니다. 2인=10/8, 3인=7/6.</summary>
    /// <param name="APlayerCount">플레이어 수(2 또는 3).</param>
    /// <exception cref="EHwatuError">표준값이 정의되지 않은 인원수면 발생(<see cref="Custom"/> 사용).</exception>
    class function ForPlayers(const APlayerCount: Integer): TDealConfig; static;
    /// <summary>사용자 지정 구성을 반환합니다.</summary>
    class function Custom(const APlayerCount: Integer; const AHandSize: Integer; const AFloorSize: Integer): TDealConfig; static;
    /// <summary>이 구성이 나눠 주는 총 장수(손패 합계 + 바닥).</summary>
    function DealtCount: Integer;
  end;

  /// <summary>
  ///   딜 직후의 게임 테이블 상태. 플레이어별 손패·바닥(패)·더미(스톡)를 담으며,
  ///   담긴 모든 카드 목록의 수명을 소유한다. 각 목록에서 끝이 '맨 위(다음 뽑을 카드)'.
  /// </summary>
  TTableState = class
  private
    FHands: TObjectList<TList<THwatuCard>>;
    FFloor: TList<THwatuCard>;
    FStock: TList<THwatuCard>;
    function MonthWithCount(const ACards: TList<THwatuCard>; const AThreshold: Integer; out AMonth: Integer): Boolean;
  public
    /// <summary>플레이어 수만큼 빈 손패를 준비해 상태를 생성합니다.</summary>
    /// <param name="APlayerCount">플레이어 수.</param>
    constructor Create(const APlayerCount: Integer);
    destructor Destroy; override;

    /// <summary>지정한 플레이어의 손패 목록을 반환합니다(0-기반).</summary>
    function Hand(const APlayerIndex: Integer): TList<THwatuCard>;
    /// <summary>플레이어 수.</summary>
    function PlayerCount: Integer;

    /// <summary>바닥에 보너스패가 깔려 있으면 True.</summary>
    function FloorHasBonus: Boolean;
    /// <summary>바닥에 같은 월 4장(총통)이 있으면 True를 반환하고 그 월을 out으로 돌려줍니다.</summary>
    function FloorHasFourOfAKind(out AMonth: Integer): Boolean;
    /// <summary>지정 플레이어 손패에 같은 월 4장(총통)이 있으면 True를 반환하고 그 월을 out으로 돌려줍니다.</summary>
    function HandHasFourOfAKind(const APlayerIndex: Integer; out AMonth: Integer): Boolean;

    /// <summary>모든 손패를 월→종류 순으로 정렬합니다(표시용).</summary>
    procedure SortHands;
    /// <summary>사람이 읽을 수 있는 상태 요약 문자열(손패/바닥/더미 장수)을 반환합니다.</summary>
    function Summary: string;

    /// <summary>바닥(패) 목록. 끝이 맨 위.</summary>
    property Floor: TList<THwatuCard> read FFloor;
    /// <summary>더미(스톡) 목록. 끝이 맨 위(다음 뽑을 카드).</summary>
    property Stock: TList<THwatuCard> read FStock;
  end;

  /// <summary>덱을 받아 고스톱 규칙대로 분배해 <see cref="TTableState"/>를 만드는 정적 딜러.</summary>
  TDealer = record
  public
    /// <summary>
    ///   주어진 덱을 구성대로 분배합니다. 손패는 카드 단위 라운드로빈으로, 이어서 바닥, 남은 것은 더미가 됩니다.
    ///   덱은 이 호출로 소진됩니다(전달한 덱의 카드 목록은 비워짐).
    /// </summary>
    /// <param name="ADeck">분배할 덱(셔플되어 있어야 함).</param>
    /// <param name="AConfig">딜 구성.</param>
    /// <returns>딜 결과 테이블 상태(호출자가 Free).</returns>
    /// <exception cref="EHwatuError">인원수가 2 미만이거나 덱 장수가 부족하면 발생.</exception>
    class function Deal(const ADeck: TDeck; const AConfig: TDealConfig): TTableState; static;
    /// <summary>
    ///   덱을 새로 만들어 셔플한 뒤 분배합니다. 바닥에 보너스패나 총통이 나오면 지정 횟수까지 다시 섞어 분배합니다.
    /// </summary>
    /// <param name="AConfig">딜 구성.</param>
    /// <param name="ADeckOptions">덱 구성 옵션(보너스 포함 여부 등).</param>
    /// <param name="AMaxRedeals">바닥이 무효일 때 재분배 최대 횟수. 0이면 재분배하지 않음.</param>
    /// <returns>딜 결과 테이블 상태(호출자가 Free).</returns>
    class function DealFresh(const AConfig: TDealConfig; const ADeckOptions: TDeckOptions; const AMaxRedeals: Integer = 0): TTableState; static;
    /// <summary>바닥에 보너스패 또는 총통이 있어 재분배가 필요한지 판정합니다.</summary>
    class function NeedsRedeal(const AState: TTableState): Boolean; static;
  end;

implementation

{$REGION 'TDealConfig'}
class function TDealConfig.ForPlayers(const APlayerCount: Integer): TDealConfig;
begin
  case APlayerCount of
    2:
      begin
        Result := Custom(2, 10, 8);
      end;
    3:
      begin
        Result := Custom(3, 7, 6);
      end;
  else
    begin
      raise EHwatuError.CreateFmt('%d인 표준 딜 구성이 정의되지 않았습니다. TDealConfig.Custom을 사용하세요.', [APlayerCount]);
    end;
  end;
end;

class function TDealConfig.Custom(const APlayerCount: Integer; const AHandSize: Integer; const AFloorSize: Integer): TDealConfig;
begin
  Result.PlayerCount := APlayerCount;
  Result.HandSize := AHandSize;
  Result.FloorSize := AFloorSize;
end;

function TDealConfig.DealtCount: Integer;
begin
  Result := PlayerCount * HandSize + FloorSize;
end;
{$ENDREGION}

{$REGION 'TTableState'}
constructor TTableState.Create(const APlayerCount: Integer);
begin
  inherited Create;
  FHands := TObjectList<TList<THwatuCard>>.Create(True);
  for var I := 0 to APlayerCount - 1 do
  begin
    FHands.Add(TList<THwatuCard>.Create);
  end;

  FFloor := TList<THwatuCard>.Create;
  FStock := TList<THwatuCard>.Create;
end;

destructor TTableState.Destroy;
begin
  FreeAndNil(FStock);
  FreeAndNil(FFloor);
  FreeAndNil(FHands);
  inherited Destroy;
end;

function TTableState.Hand(const APlayerIndex: Integer): TList<THwatuCard>;
begin
  Result := FHands[APlayerIndex];
end;

function TTableState.PlayerCount: Integer;
begin
  Result := FHands.Count;
end;

function TTableState.MonthWithCount(const ACards: TList<THwatuCard>; const AThreshold: Integer; out AMonth: Integer): Boolean;
var
  LCounts: array [1 .. 12] of Integer;
begin
  for var M := 1 to 12 do
  begin
    LCounts[M] := 0;
  end;

  for var LCard in ACards do
  begin
    if (LCard.Month >= 1) and (LCard.Month <= 12) then
    begin
      Inc(LCounts[LCard.Month]);
    end;
  end;

  for var M := 1 to 12 do
  begin
    if LCounts[M] >= AThreshold then
    begin
      AMonth := M;
      Exit(True);
    end;
  end;

  AMonth := 0;
  Result := False;
end;

function TTableState.FloorHasBonus: Boolean;
begin
  for var LCard in FFloor do
  begin
    if LCard.Kind = hkBonus then
    begin
      Exit(True);
    end;
  end;

  Result := False;
end;

function TTableState.FloorHasFourOfAKind(out AMonth: Integer): Boolean;
begin
  Result := MonthWithCount(FFloor, 4, AMonth);
end;

function TTableState.HandHasFourOfAKind(const APlayerIndex: Integer; out AMonth: Integer): Boolean;
begin
  Result := MonthWithCount(FHands[APlayerIndex], 4, AMonth);
end;

procedure TTableState.SortHands;
begin
  var LComparer := TComparer<THwatuCard>.Construct(
    function(const ALeft: THwatuCard; const ARight: THwatuCard): Integer
    begin
      Result := ALeft.Month - ARight.Month;
      if Result = 0 then
      begin
        Result := Ord(ALeft.Kind) - Ord(ARight.Kind);
      end;

      if Result = 0 then
      begin
        Result := ALeft.Ordinal - ARight.Ordinal;
      end;
    end);

  for var LHand in FHands do
  begin
    LHand.Sort(LComparer);
  end;
end;

function TTableState.Summary: string;
begin
  var LBuilder := TStringBuilder.Create;
  try
    for var I := 0 to FHands.Count - 1 do
    begin
      LBuilder.AppendFormat('P%d 손패=%d  ', [I + 1, FHands[I].Count]);
    end;

    LBuilder.AppendFormat('바닥=%d  더미=%d', [FFloor.Count, FStock.Count]);
    Result := LBuilder.ToString;
  finally
    LBuilder.Free;
  end;
end;
{$ENDREGION}

{$REGION 'TDealer'}
class function TDealer.Deal(const ADeck: TDeck; const AConfig: TDealConfig): TTableState;
begin
  if AConfig.PlayerCount < 2 then
  begin
    raise EHwatuError.CreateFmt('플레이어 수는 2명 이상이어야 합니다(요청: %d).', [AConfig.PlayerCount]);
  end;

  if ADeck.Count < AConfig.DealtCount then
  begin
    raise EHwatuError.CreateFmt('덱이 %d장뿐이라 %d장을 분배할 수 없습니다.', [ADeck.Count, AConfig.DealtCount]);
  end;

  Result := TTableState.Create(AConfig.PlayerCount);
  try
    // 손패: 카드 단위 라운드로빈(실제 분배 방식 모사)
    for var LRound := 1 to AConfig.HandSize do
    begin
      for var LPlayer := 0 to AConfig.PlayerCount - 1 do
      begin
        Result.Hand(LPlayer).Add(ADeck.Draw);
      end;
    end;

    // 바닥
    for var I := 1 to AConfig.FloorSize do
    begin
      Result.Floor.Add(ADeck.Draw);
    end;

    // 더미: 남은 카드를 순서 그대로(끝=맨 위) 이관
    Result.Stock.AddRange(ADeck.Cards);
    ADeck.Cards.Clear;
  except
    Result.Free;
    raise;
  end;
end;

class function TDealer.NeedsRedeal(const AState: TTableState): Boolean;
var
  LMonth: Integer;
begin
  Result := AState.FloorHasBonus or AState.FloorHasFourOfAKind(LMonth);
end;

class function TDealer.DealFresh(const AConfig: TDealConfig; const ADeckOptions: TDeckOptions; const AMaxRedeals: Integer): TTableState;
begin
  var LDeck := TDeck.Create(ADeckOptions);
  try
    Result := nil;
    try
      var LAttempt := 0;
      while True do
      begin
        LDeck.Build(ADeckOptions);
        LDeck.Shuffle;

        FreeAndNil(Result);
        Result := Deal(LDeck, AConfig);

        if (LAttempt >= AMaxRedeals) or (not NeedsRedeal(Result)) then
        begin
          Break;
        end;

        Inc(LAttempt);
      end;
    except
      FreeAndNil(Result);
      raise;
    end;
  finally
    LDeck.Free;
  end;
end;
{$ENDREGION}

end.
