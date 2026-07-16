unit Gostop.FourGame;

interface

{$REGION 'uses'}
uses
  System.SysUtils,
  Gostop.Cards,
  Gostop.Score,
  Gostop.Deck,
  Gostop.Deal,
  Gostop.Play,
  Gostop.FourPlayer,
  Gostop.AI;
{$ENDREGION}

type
  /// <summary>4인 라운드의 협상 결정(포기·광팔기).</summary>
  TFourDecisions = record
    /// <summary>P2(좌석1)가 포기하는가.</summary>
    P2GiveUp: Boolean;
    /// <summary>P3(좌석2)가 포기하는가(P2가 참가한 경우).</summary>
    P3GiveUp: Boolean;
    /// <summary>P4(좌석3)가 광을 파는가(P2·P3 모두 참가한 경우).</summary>
    P4Sell: Boolean;

    /// <summary>표준 진행: 아무도 포기하지 않고 P4가 광을 판다.</summary>
    class function Standard: TFourDecisions; static;
  end;

  /// <summary>4인 한 라운드의 최종 결과.</summary>
  TFourGameResult = record
    /// <summary>좌석별 순손익(+받음/−지불). 광값 선불 + 게임 정산 합산. 합은 0(제로섬).</summary>
    Net: array [0 .. 3] of Integer;
    /// <summary>이긴 좌석(0~3) 또는 -1(나가리).</summary>
    WinnerSeat: Integer;
    /// <summary>빠진 좌석(광 판 P4 또는 포기한 P2/P3).</summary>
    SitOutSeat: Integer;
    /// <summary>광팔기 정산 내역.</summary>
    Gwang: TGwangSale;
    /// <summary>실제 진행한 수(디버그/통계용).</summary>
    Plays: Integer;
  end;

  /// <summary>
  ///   4인 고스톱 한 라운드를 조립·진행하는 관리자. 4인 딜 → 광팔기 협상 → 3인 플레이 →
  ///   광값(선불)과 게임 정산(피박/광박/고박)을 합쳐 좌석별 순손익을 낸다.
  /// </summary>
  TFourGame = record
  public
    /// <summary>
    ///   주어진 덱·AI·결정으로 한 라운드를 끝까지 진행하고 결과를 반환합니다.
    /// </summary>
    /// <param name="ADeck">셔플된 덱(4인 딜에 사용, 이 호출로 소비).</param>
    /// <param name="AAis">좌석 0~3에 대응하는 AI 4명.</param>
    /// <param name="ADecisions">협상 결정.</param>
    /// <param name="AGwangUnitPrice">광 1개당 단가.</param>
    /// <param name="AOptions">점수 규칙 옵션.</param>
    /// <param name="AStakes">판돈 배수(기본 1). 게임 정산(승패)에 곱해진다. 광값은 배수 미적용.</param>
    /// <exception cref="EHwatuError">AI가 4명이 아니면 발생.</exception>
    class function Run(const ADeck: TDeck; const AAis: array of TAiPlayer; const ADecisions: TFourDecisions;
      const AGwangUnitPrice: Integer; const AOptions: TScoreOptions; const AStakes: Integer = 1): TFourGameResult; static;
    /// <summary>표준 결정(광팔기)으로 한 라운드를 진행합니다.</summary>
    class function RunAuto(const ADeck: TDeck; const AAis: array of TAiPlayer;
      const AGwangUnitPrice: Integer; const AOptions: TScoreOptions; const AStakes: Integer = 1): TFourGameResult; static;
    /// <summary>
    ///   나가리 판돈 이월 규칙: 나가리이고 참가자 전원이 동의하면 다음 판돈을 2배로, 아니면 1로 리셋합니다.
    /// </summary>
    /// <param name="ACurrentStakes">이번 판돈 배수.</param>
    /// <param name="AWasNagari">이번 판이 나가리였는가(승자 없음).</param>
    /// <param name="AAllAgree">참가자 전원이 판돈 2배에 동의하는가.</param>
    /// <returns>다음 라운드에 쓸 판돈 배수.</returns>
    class function NextStakes(const ACurrentStakes: Integer; const AWasNagari: Boolean; const AAllAgree: Boolean): Integer; static;
  end;

implementation

{$REGION 'TFourDecisions'}
class function TFourDecisions.Standard: TFourDecisions;
begin
  Result.P2GiveUp := False;
  Result.P3GiveUp := False;
  Result.P4Sell := True;
end;
{$ENDREGION}

{$REGION 'TFourGame'}
class function TFourGame.Run(const ADeck: TDeck; const AAis: array of TAiPlayer; const ADecisions: TFourDecisions;
  const AGwangUnitPrice: Integer; const AOptions: TScoreOptions; const AStakes: Integer): TFourGameResult;
begin
  if Length(AAis) <> 4 then
  begin
    raise EHwatuError.CreateFmt('4인 게임에는 AI 4명이 필요합니다(전달 %d명).', [Length(AAis)]);
  end;

  Result.WinnerSeat := -1;
  Result.SitOutSeat := -1;
  Result.Plays := 0;
  for var S := 0 to 3 do
  begin
    Result.Net[S] := 0;
  end;

  // 1) 4인 딜(덱은 호출자가 셔플해 전달)
  var LTable := TDealer.Deal(ADeck, TDealConfig.Custom(4, 7, 6));
  try
    // 2) 광팔기 협상
    var LRound := TFourPlayer.Resolve(LTable, ADecisions.P2GiveUp, ADecisions.P3GiveUp, ADecisions.P4Sell,
      AGwangUnitPrice, AOptions);
    Result.SitOutSeat := LRound.SitOutSeat;
    Result.Gwang := LRound.Gwang;

    // 3) 광값 선불(선 제외, P2·P3 → P4)
    if LRound.Gwang.Sold then
    begin
      for var LP := 0 to High(LRound.Gwang.PayerSeats) do
      begin
        var LPayer := LRound.Gwang.PayerSeats[LP];
        Result.Net[LPayer] := Result.Net[LPayer] - LRound.Gwang.ValuePerPayer;
        Result.Net[LRound.Gwang.SellerSeat] := Result.Net[LRound.Gwang.SellerSeat] + LRound.Gwang.ValuePerPayer;
      end;
    end;

    // 4) 실제 치는 3인 게임 구성·진행
    var LGame := TFourPlayer.BuildGame(LTable, LRound, ['P0', 'P1', 'P2']);
    try
      var LEngine := TTurnEngine.Create(LGame, AOptions);
      try
        LEngine.ApplyHandChongtong;
        while (LGame.Phase <> gpFinished) and (Result.Plays < 8000) do
        begin
          var LSeat := LRound.PlaySeats[LGame.Current];   // 현재 게임 좌석 → 원래 좌석의 AI
          AAis[LSeat].Act(LEngine);
          Inc(Result.Plays);
        end;

        // 5) 게임 정산 → 원래 좌석에 합산
        var LSettle := LEngine.FinalSettlement;
        for var I := 0 to High(LRound.PlaySeats) do
        begin
          var LSeat := LRound.PlaySeats[I];
          // 게임 정산(승패)에 판돈 배수 적용(광값은 배수 미적용)
          Result.Net[LSeat] := Result.Net[LSeat] + LSettle[I].Net * AStakes;
        end;

        if LGame.Winner >= 0 then
        begin
          Result.WinnerSeat := LRound.PlaySeats[LGame.Winner];
        end;
      finally
        LEngine.Free;
      end;
    finally
      LGame.Free;
    end;
  finally
    LTable.Free;
  end;
end;

class function TFourGame.RunAuto(const ADeck: TDeck; const AAis: array of TAiPlayer;
  const AGwangUnitPrice: Integer; const AOptions: TScoreOptions; const AStakes: Integer): TFourGameResult;
begin
  Result := Run(ADeck, AAis, TFourDecisions.Standard, AGwangUnitPrice, AOptions, AStakes);
end;

class function TFourGame.NextStakes(const ACurrentStakes: Integer; const AWasNagari: Boolean; const AAllAgree: Boolean): Integer;
begin
  if AWasNagari and AAllAgree then
  begin
    Result := ACurrentStakes * 2;
  end
  else
  begin
    Result := 1;
  end;
end;
{$ENDREGION}

end.
