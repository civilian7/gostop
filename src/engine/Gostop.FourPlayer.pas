unit Gostop.FourPlayer;

interface

{$REGION 'uses'}
uses
  System.SysUtils,
  System.Generics.Collections,
  Gostop.Cards,
  Gostop.Score,
  Gostop.Deal,
  Gostop.Play;
{$ENDREGION}

type
  /// <summary>광팔기 정산 결과(선불).</summary>
  TGwangSale = record
    /// <summary>광을 팔았는지 여부.</summary>
    Sold: Boolean;
    /// <summary>판 사람 좌석(P4=3). 안 팔았으면 -1.</summary>
    SellerSeat: Integer;
    /// <summary>판 광 개수(5광 + 쌍피 인정).</summary>
    GwangCount: Integer;
    /// <summary>지불자 1인당 광값 = 단가 × 광개수.</summary>
    ValuePerPayer: Integer;
    /// <summary>광값을 선불로 내는 좌석들(P2·P3 = 1·2). 선(0)은 제외.</summary>
    PayerSeats: TArray<Integer>;
  end;

  /// <summary>4인 광팔기 협상 결과: 실제 치는 3명과 광 정산.</summary>
  TFourPlayerRound = record
    /// <summary>실제 게임을 치는 3좌석(선 먼저, 원래 좌석 인덱스).</summary>
    PlaySeats: TArray<Integer>;
    /// <summary>빠지는 좌석(광 판 P4, 또는 포기한 P2/P3).</summary>
    SitOutSeat: Integer;
    /// <summary>광팔기 정산.</summary>
    Gwang: TGwangSale;
  end;

  /// <summary>
  ///   4인 고스톱 광팔기 규칙 처리. 선(P1)은 항상 참가, P2→P3 순으로 포기 가능하며,
  ///   한 명 포기 시 아래 순번이 자동 참가해 항상 3명이 친다. P2·P3가 모두 참가할 때만
  ///   P4가 광을 팔 수 있고, 광값(광 개수 × 단가)은 선을 제외한 P2·P3가 선불로 낸다.
  ///   광 개수는 5광에 더해 쌍피도 광으로 인정한다.
  /// </summary>
  TFourPlayer = record
  public
    /// <summary>
    ///   광팔기 값(광값)을 셉니다: 광(밝은 패)+조커 장수 + 실제 완성된 족보(고도리·홍단·청단·초단) 점수.
    ///   흔들기 가능(같은 월 3장 이상)이면 전체 값 ×2.
    /// </summary>
    /// <param name="AHand">P4의 손패.</param>
    /// <param name="AOptions">족보 점수 규칙 옵션.</param>
    class function GwangCount(const AHand: TList<THwatuCard>; const AOptions: TScoreOptions): Integer; static;
    /// <summary>
    ///   광팔기 다이얼로그에 보여줄 패를 모읍니다: 광(밝은 패)+조커, 그리고 실제 완성된 족보(고도리·홍단·청단·초단)의 카드.
    /// </summary>
    /// <param name="AHand">보여줄 손패.</param>
    /// <param name="AOptions">족보 완성 판정에 쓰는 옵션.</param>
    /// <returns>표시 대상 카드 배열(중복 없음).</returns>
    class function SaleCards(const AHand: TList<THwatuCard>; const AOptions: TScoreOptions): TArray<THwatuCard>; static;
    /// <summary>
    ///   포기·광팔기 결정을 적용해 실제 치는 3명과 광 정산을 계산합니다.
    /// </summary>
    /// <param name="ATable4">4인 딜 결과(각 7장, 바닥 6).</param>
    /// <param name="AP2GiveUp">P2(좌석1)가 게임을 포기하는가.</param>
    /// <param name="AP3GiveUp">P2가 참가하고 P3(좌석2)가 포기하는가.</param>
    /// <param name="AP4Sell">P2·P3 모두 참가 시 P4(좌석3)가 광을 파는가.</param>
    /// <param name="AGwangUnitPrice">광 1개당 단가.</param>
    /// <param name="AOptions">광 개수 산정에 쓰는 족보 점수 옵션.</param>
    class function Resolve(const ATable4: TTableState;
      const AP2GiveUp: Boolean; const AP3GiveUp: Boolean; const AP4Sell: Boolean;
      const AGwangUnitPrice: Integer; const AOptions: TScoreOptions): TFourPlayerRound; static;
    /// <summary>
    ///   협상 결과로 실제 치는 3인 게임 상태를 만듭니다. 선이 0번, 빠진 좌석의 손패는 더미(스톡)로 편입.
    /// </summary>
    /// <param name="ATable4">4인 딜 결과.</param>
    /// <param name="ARound">협상 결과.</param>
    /// <param name="APlayerNames">3인 이름(치는 좌석 순서에 대응).</param>
    class function BuildGame(const ATable4: TTableState; const ARound: TFourPlayerRound;
      const APlayerNames: array of string): TGameState; static;
  end;

implementation

{$REGION 'TFourPlayer'}
class function TFourPlayer.GwangCount(const AHand: TList<THwatuCard>; const AOptions: TScoreOptions): Integer;
begin
  // 광값 = 광(밝은 패)+조커 개수 + 실제 완성된 족보(고도리·홍단·청단·초단) 점수
  // (표시하는 카드와 값이 일치하도록 실제 보유 패 기준으로 계산)
  Result := 0;
  for var LI := 0 to AHand.Count - 1 do
  begin
    if (AHand[LI].Kind = hkBright) or (AHand[LI].Kind = hkBonus) then
    begin
      Inc(Result);
    end;
  end;

  // 완성된 족보 점수 가산(미완성이면 각 필드가 0)
  var LBreak := TScorer.Evaluate(AHand, AOptions);
  Result := Result + LBreak.GodoriPoints + LBreak.HongdanPoints + LBreak.CheongdanPoints + LBreak.ChodanPoints;

  // 흔들기 가능(같은 월 3장 이상 보유)이면 전체 값 ×2
  var LMonthCount: array [1 .. 12] of Integer;
  for var M := 1 to 12 do
  begin
    LMonthCount[M] := 0;
  end;

  for var LI := 0 to AHand.Count - 1 do
  begin
    var LM := AHand[LI].Month;
    if (LM >= 1) and (LM <= 12) then
    begin
      Inc(LMonthCount[LM]);
    end;
  end;

  for var M := 1 to 12 do
  begin
    if LMonthCount[M] >= 3 then
    begin
      Result := Result * 2;
      Break;
    end;
  end;
end;

class function TFourPlayer.SaleCards(const AHand: TList<THwatuCard>; const AOptions: TScoreOptions): TArray<THwatuCard>;
begin
  Result := nil;

  // 광(밝은 패) + 조커(보너스패)는 항상 표시
  for var LI := 0 to AHand.Count - 1 do
  begin
    if (AHand[LI].Kind = hkBright) or (AHand[LI].Kind = hkBonus) then
    begin
      Result := Result + [AHand[LI]];
    end;
  end;

  // 실제 완성된 족보의 카드도 표시(고도리·홍단·청단·초단)
  var LBreak := TScorer.Evaluate(AHand, AOptions);
  for var LI := 0 to AHand.Count - 1 do
  begin
    var LCard := AHand[LI];
    if (LBreak.GodoriPoints > 0) and (LCard.Kind = hkAnimal) and LCard.IsGodori then
    begin
      Result := Result + [LCard];
    end
    else
    if (LCard.Kind = hkRibbon) and
      (((LBreak.HongdanPoints > 0) and (LCard.Ribbon = rkHong)) or
       ((LBreak.CheongdanPoints > 0) and (LCard.Ribbon = rkCheong)) or
       ((LBreak.ChodanPoints > 0) and (LCard.Ribbon = rkCho))) then
    begin
      Result := Result + [LCard];
    end;
  end;
end;

class function TFourPlayer.Resolve(const ATable4: TTableState;
  const AP2GiveUp: Boolean; const AP3GiveUp: Boolean; const AP4Sell: Boolean;
  const AGwangUnitPrice: Integer; const AOptions: TScoreOptions): TFourPlayerRound;
begin
  if ATable4.PlayerCount <> 4 then
  begin
    raise EHwatuError.CreateFmt('4인 딜이 아닙니다(플레이어 %d명).', [ATable4.PlayerCount]);
  end;

  Result.Gwang.Sold := False;
  Result.Gwang.SellerSeat := -1;
  Result.Gwang.GwangCount := 0;
  Result.Gwang.ValuePerPayer := 0;
  Result.Gwang.PayerSeats := [];

  if AP2GiveUp then
  begin
    // P2 포기 → P3·P4 자동 참가
    Result.SitOutSeat := 1;
    Result.PlaySeats := [0, 2, 3];
    Exit;
  end;

  if AP3GiveUp then
  begin
    // P2 참가·P3 포기 → P4 자동 참가
    Result.SitOutSeat := 2;
    Result.PlaySeats := [0, 1, 3];
    Exit;
  end;

  // P2·P3 모두 참가 → P4는 광을 팔거나 그냥 빠진다(어느 쪽이든 3인 = 선·P2·P3)
  Result.SitOutSeat := 3;
  Result.PlaySeats := [0, 1, 2];
  if AP4Sell then
  begin
    Result.Gwang.Sold := True;
    Result.Gwang.SellerSeat := 3;
    Result.Gwang.GwangCount := GwangCount(ATable4.Hand(3), AOptions);
    Result.Gwang.ValuePerPayer := Result.Gwang.GwangCount * AGwangUnitPrice;
    Result.Gwang.PayerSeats := [1, 2];   // 선(0) 제외
  end;
end;

class function TFourPlayer.BuildGame(const ATable4: TTableState; const ARound: TFourPlayerRound;
  const APlayerNames: array of string): TGameState;
begin
  Result := TGameState.Create(APlayerNames);
  try
    // 치는 3좌석의 손패를 선(0번)부터 순서대로
    for var I := 0 to High(ARound.PlaySeats) do
    begin
      Result.Player(I).Hand.AddRange(ATable4.Hand(ARound.PlaySeats[I]));
    end;

    Result.Floor.AddRange(ATable4.Floor);
    Result.Stock.AddRange(ATable4.Stock);
    // 빠진 좌석의 손패는 더미로 편입(카드 경제 유지: 3인 7/6/21)
    Result.Stock.AddRange(ATable4.Hand(ARound.SitOutSeat));
    Result.Current := 0;
  except
    Result.Free;
    raise;
  end;
end;
{$ENDREGION}

end.
