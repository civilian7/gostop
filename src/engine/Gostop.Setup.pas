unit Gostop.Setup;

interface

{$REGION 'uses'}
uses
  System.SysUtils,
  Gostop.Cards,
  Gostop.Deal,
  Gostop.Play;
{$ENDREGION}

type
  /// <summary>
  ///   딜 결과(<see cref="TTableState"/>)로부터 게임 상태(<see cref="TGameState"/>)를 구성하는 빌더.
  ///   턴 엔진(Gostop.Play)이 딜(Gostop.Deal)을 알 필요가 없도록 둘을 잇는 얇은 계층이다.
  /// </summary>
  TGameSetup = record
  public
    /// <summary>딜 결과로 기존 게임 상태의 손패·바닥·더미를 채웁니다(카드 값 복사).</summary>
    /// <param name="AGame">채울 게임 상태(플레이어 수가 딜과 일치해야 함).</param>
    /// <param name="ATable">분배 결과.</param>
    /// <exception cref="EHwatuError">플레이어 수가 다르면 발생.</exception>
    class procedure Load(const AGame: TGameState; const ATable: TTableState); static;
    /// <summary>딜 결과로 새 게임 상태를 만들어 반환합니다(호출자가 소유·해제).</summary>
    /// <param name="ATable">분배 결과.</param>
    /// <param name="ANames">플레이어 이름(딜 좌석 순서에 대응).</param>
    class function FromDeal(const ATable: TTableState; const ANames: array of string): TGameState; static;
  end;

implementation

{$REGION 'TGameSetup'}
class procedure TGameSetup.Load(const AGame: TGameState; const ATable: TTableState);
begin
  if ATable.PlayerCount <> AGame.PlayerCount then
  begin
    raise EHwatuError.CreateFmt('딜 플레이어 수(%d)가 게임 상태(%d)와 다릅니다.', [ATable.PlayerCount, AGame.PlayerCount]);
  end;

  for var I := 0 to AGame.PlayerCount - 1 do
  begin
    AGame.Player(I).Hand.Clear;
    AGame.Player(I).Hand.AddRange(ATable.Hand(I));
    AGame.Player(I).Captured.Clear;
  end;

  AGame.Floor.Clear;
  AGame.Floor.AddRange(ATable.Floor);
  AGame.Stock.Clear;
  AGame.Stock.AddRange(ATable.Stock);
  AGame.Current := 0;
  AGame.Phase := gpPlaying;
  AGame.Winner := -1;
  AGame.Events.Clear;
  AGame.BbeokCreator.Clear;
  AGame.PlayCount := 0;
end;

class function TGameSetup.FromDeal(const ATable: TTableState; const ANames: array of string): TGameState;
begin
  Result := TGameState.Create(ANames);
  try
    Load(Result, ATable);
  except
    Result.Free;
    raise;
  end;
end;
{$ENDREGION}

end.
