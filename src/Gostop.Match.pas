unit Gostop.Match;

interface

{$REGION 'uses'}
uses
  System.SysUtils,
  Gostop.Cards,
  Gostop.Score,
  Gostop.Deck,
  Gostop.Play,
  Gostop.FourGame;
{$ENDREGION}

type
  /// <summary>4인 매치(여러 라운드) 설정.</summary>
  TFourMatchConfig = record
    /// <summary>진행할 라운드 수.</summary>
    Rounds: Integer;
    /// <summary>광 1개당 단가.</summary>
    GwangUnitPrice: Integer;
    /// <summary>점수 규칙 옵션.</summary>
    Options: TScoreOptions;
    /// <summary>나가리 시 다음 판돈을 2배로 이월(전원 동의 가정).</summary>
    DoubleOnNagari: Boolean;
    /// <summary>매 라운드 덱 셔플 기본 시드(라운드마다 +r). 0이면 보안 셔플 사용.</summary>
    BaseSeed: Cardinal;

    /// <summary>표준 매치 설정을 반환합니다.</summary>
    class function Standard(const ARounds: Integer; const AGwangUnitPrice: Integer): TFourMatchConfig; static;
  end;

  /// <summary>4인 매치 결과.</summary>
  TFourMatchResult = record
    /// <summary>플레이어별 누적 순손익(좌석 아닌 고정 플레이어 기준). 합은 0(제로섬).</summary>
    Cumulative: array [0 .. 3] of Integer;
    /// <summary>플레이어별 승리 라운드 수.</summary>
    Wins: array [0 .. 3] of Integer;
    /// <summary>나가리 라운드 수.</summary>
    Nagari: Integer;
    /// <summary>실제 진행한 라운드 수.</summary>
    RoundsPlayed: Integer;
  end;

  /// <summary>
  ///   4인 고스톱 매치(여러 라운드) 드라이버. 매 라운드 선(좌석0)을 로테이션하고, 나가리 시 판돈을 이월하며,
  ///   플레이어별 누적 손익을 집계한다. 각 라운드는 <see cref="TFourGame"/>가 진행한다.
  /// </summary>
  TFourMatch = record
  public
    /// <summary>
    ///   고정된 4명의 에이전트로 매치를 진행합니다. 라운드 r에서 좌석 s는 플레이어 (s+r) mod 4가 맡습니다(선 로테이션).
    /// </summary>
    /// <param name="AAgents">플레이어 4명(고정 정체성).</param>
    /// <param name="AConfig">매치 설정.</param>
    /// <exception cref="EHwatuError">에이전트가 4명이 아니면 발생.</exception>
    class function Run(const AAgents: array of IPlayerAgent; const AConfig: TFourMatchConfig): TFourMatchResult; static;
  end;

implementation

{$REGION 'uses'}
uses
  Gostop.Deal;
{$ENDREGION}

{$REGION 'TFourMatchConfig'}
class function TFourMatchConfig.Standard(const ARounds: Integer; const AGwangUnitPrice: Integer): TFourMatchConfig;
begin
  Result.Rounds := ARounds;
  Result.GwangUnitPrice := AGwangUnitPrice;
  Result.Options := TScoreOptions.Default;
  Result.DoubleOnNagari := True;
  Result.BaseSeed := 1;
end;
{$ENDREGION}

{$REGION 'TFourMatch'}
class function TFourMatch.Run(const AAgents: array of IPlayerAgent; const AConfig: TFourMatchConfig): TFourMatchResult;
begin
  if Length(AAgents) <> 4 then
  begin
    raise EHwatuError.CreateFmt('4인 매치에는 에이전트 4명이 필요합니다(전달 %d명).', [Length(AAgents)]);
  end;

  for var P := 0 to 3 do
  begin
    Result.Cumulative[P] := 0;
    Result.Wins[P] := 0;
  end;

  Result.Nagari := 0;
  Result.RoundsPlayed := 0;

  var LStakes := 1;
  for var R := 0 to AConfig.Rounds - 1 do
  begin
    var LDeck := TDeck.Create;
    try
      if AConfig.BaseSeed = 0 then
      begin
        LDeck.ShuffleSecure;
      end
      else
      begin
        LDeck.Shuffle(AConfig.BaseSeed + Cardinal(R));
      end;

      // 선 로테이션: 좌석 s → 플레이어 (s+r) mod 4
      var LSeatAgents: array [0 .. 3] of IPlayerAgent;
      for var S := 0 to 3 do
      begin
        LSeatAgents[S] := AAgents[(S + R) mod 4];
      end;

      var LRes := TFourGame.RunAuto(LDeck, LSeatAgents, AConfig.GwangUnitPrice, AConfig.Options, LStakes);

      // 좌석 결과를 고정 플레이어에 합산
      for var S := 0 to 3 do
      begin
        var LPlayer := (S + R) mod 4;
        Result.Cumulative[LPlayer] := Result.Cumulative[LPlayer] + LRes.Net[S];
      end;

      if LRes.WinnerSeat < 0 then
      begin
        Inc(Result.Nagari);
      end
      else
      begin
        Inc(Result.Wins[(LRes.WinnerSeat + R) mod 4]);
      end;

      // 나가리 판돈 이월
      LStakes := TFourGame.NextStakes(LStakes, LRes.WinnerSeat < 0, AConfig.DoubleOnNagari);
      Inc(Result.RoundsPlayed);
    finally
      LDeck.Free;
    end;
  end;
end;
{$ENDREGION}

end.
