unit Gostop.Board.Settlement;

interface

{$REGION 'uses'}
uses
  System.SysUtils,
  System.Generics.Collections,
  Gostop.Play,
  Gostop.Score,
  Gostop.Shodang;
{$ENDREGION}

type
  /// <summary>정산창 한 줄. 아바타·금액·박 뱃지를 구조적으로 담아 렌더링과 데이터를 분리한다.</summary>
  TResultRow = record
    /// <summary>아바타 풀 인덱스(-1 = 아바타 없음, 안내문 줄).</summary>
    AvatarIdx: Integer;
    /// <summary>True면 승자 줄(환호 아바타 + 강조 스타일).</summary>
    IsWinner: Boolean;
    /// <summary>True면 Amount·Flags 표시, False면 Text만 표시.</summary>
    HasAmount: Boolean;
    /// <summary>이번 게임에서 딴/잃은 금액(부호 포함).</summary>
    Amount: Integer;
    /// <summary>이번 정산 반영 후 그 좌석의 총 보유 금액.</summary>
    BalanceAfter: Integer;
    /// <summary>박 뱃지들(피박/광박/고박/멍박/쇼당독박 등).</summary>
    Flags: TArray<string>;
    /// <summary>승자 줄에만 채워지는 점수 내역 뱃지들(광 3·열끗 1·띠 3·피 3 형태).</summary>
    ScoreParts: TArray<string>;
    /// <summary>승자 줄에만 채워지는 족보 합계 점수(고·박 적용 전, ScoreParts와 함께 표시).</summary>
    ScoreTotal: Integer;
    /// <summary>아바타 없는 안내문(나가리·쓰리뻑 등).</summary>
    Text: string;
  end;

  /// <summary>정산 계산에 필요한 매치 상태를 한데 모은 입력 묶음(TGostopBoard가 채워 전달).</summary>
  TSettlementInput = record
    /// <summary>대전 인원(2/3/4).</summary>
    PlayerCount: Integer;
    /// <summary>점당 금액.</summary>
    MoneyPerPoint: Integer;
    /// <summary>판돈 배수(나가리 이월분). 이번 정산에 곱해질 값.</summary>
    Stakes: Integer;
    /// <summary>선(FNextStartPos)의 물리 좌석 서수(0..3) — 4인 좌석 로테이션 계산용.</summary>
    NextStartPos: Integer;
    /// <summary>4인 전용: 게임 인덱스 → 좌석(0..3).</summary>
    SeatMap: TArray<Integer>;
    /// <summary>4인 전용(이번 판에 빠진 좌석), 없으면 -1.</summary>
    SitOutSeat: Integer;
    /// <summary>길이 4. 물리 좌석(0..3)별 아바타 풀 인덱스.</summary>
    SeatAvatar: TArray<Integer>;
    /// <summary>관전 모드(사람 없음)면 True — 오링 카운트 집계 생략.</summary>
    Spectator: Boolean;
    /// <summary>이 매치에 실제로 쓰이는 물리 좌석 목록(오링 카운트 판정 대상 — 사람 좌석은 호출부가 이미 제외하고 전달).</summary>
    ActiveOpponentSeats: TArray<Integer>;
    /// <summary>길이 4. 정산 전 물리 좌석별 보유 머니.</summary>
    MoneyBefore: TArray<Integer>;
    /// <summary>게임 인덱스 → 물리 좌석(0..3). 호출부의 PhysicalPos(I) 결과를 미리 계산해 전달.</summary>
    GameToPhysical: TArray<Integer>;
    /// <summary>쇼당 독박 성립 여부.</summary>
    ShodangActive: Boolean;
    ShodangCaller: Integer;
    ShodangAccepter: Integer;
    ShodangDecliner: Integer;
  end;

  /// <summary>정산 계산 결과. TGostopBoard는 이 값을 그대로 자신의 필드·배열에 반영하기만 한다.</summary>
  TSettlementOutput = record
    /// <summary>정산창 렌더링용 결과 줄 목록.</summary>
    ResultRows: TArray<TResultRow>;
    /// <summary>정산창 제목(판돈 배수 안내, 없으면 빈 문자열).</summary>
    ResultTitle: string;
    /// <summary>상태 표시줄 요약 텍스트.</summary>
    StatusText: string;
    /// <summary>다음 판에 적용할 새 판돈 배수.</summary>
    NewStakes: Integer;
    /// <summary>길이 4. 정산 반영된 물리 좌석별 새 보유 머니.</summary>
    MoneyAfter: TArray<Integer>;
    /// <summary>승자 물리 좌석(0..3). 나가리면 -1.</summary>
    WinnerSeat: Integer;
    /// <summary>이번 게임 참가자 물리 좌석 목록(승자 포함 — 전적 갱신 대상).</summary>
    ParticipantSeats: TArray<Integer>;
    /// <summary>이번 정산으로 새로 파산한 상대 수(오링 카운트 증가분). 관전 모드면 항상 0.</summary>
    NewlyBrokeCount: Integer;
  end;

  /// <summary>
  ///   게임 종료 시 최종 정산(머니 반영·전적·오링 카운트·정산창 결과 줄·판돈 배수 이월)을 계산하는
  ///   순수 로직. TGostopBoard.BuildFinalSummary에서 추출됨 — 부작용 없이 값만 계산해 반환하고,
  ///   실제 필드 반영(FMoney/FWins/FLosses/FConfig.KillCount/FStakes 등)은 호출부가 담당한다.
  /// </summary>
  TGostopSettlement = record
  public
    /// <summary>주어진 매치 상태로 최종 정산을 계산합니다.</summary>
    /// <param name="AGame">종료된 게임 상태(Winner/PlayerCount/ThreeBbeok/Events 참조).</param>
    /// <param name="AEngine">정산 계산에 쓰이는 턴 엔진(FinalSettlement 호출).</param>
    /// <param name="AInput">매치·좌석 상태 입력 묶음.</param>
    /// <returns>반영할 값들을 담은 결과 묶음.</returns>
    class function Build(const AGame: TGameState; const AEngine: TTurnEngine;
      const AInput: TSettlementInput): TSettlementOutput; static;
  end;

implementation

function FlagLabelsOf(const AResult: TPlayerResult): TArray<string>;
begin
  Result := nil;
  if AResult.Gobak then
  begin
    Result := Result + ['고박'];
  end;

  if AResult.Pibak then
  begin
    Result := Result + ['피박'];
  end;

  if AResult.Gwangbak then
  begin
    Result := Result + ['광박'];
  end;

  if AResult.Meongbak then
  begin
    Result := Result + ['멍박'];
  end;
end;

// 승자 결과 줄에 표시할 점수 내역 뱃지 — 장수가 아니라 "그 항목이 실제로 낸 점수"를 보여준다
// (광(3)·열끗(3)·청단(3) 식. 문턱 미달로 0점인 항목은 표시하지 않음 — 예: 열끗 1장은 열끗(0)이 아니라 아예 생략)
function ScorePartsOf(const ABreakdown: TScoreBreakdown): TArray<string>;
begin
  Result := nil;
  if ABreakdown.BrightPoints > 0 then
  begin
    Result := Result + [Format('광(%d)', [ABreakdown.BrightPoints])];
  end;

  if ABreakdown.AnimalPoints > 0 then
  begin
    Result := Result + [Format('열끗(%d)', [ABreakdown.AnimalPoints])];
  end;

  if ABreakdown.GodoriPoints > 0 then
  begin
    Result := Result + [Format('고도리(%d)', [ABreakdown.GodoriPoints])];
  end;

  if ABreakdown.RibbonPoints > 0 then
  begin
    Result := Result + [Format('띠(%d)', [ABreakdown.RibbonPoints])];
  end;

  if ABreakdown.HongdanPoints > 0 then
  begin
    Result := Result + [Format('홍단(%d)', [ABreakdown.HongdanPoints])];
  end;

  if ABreakdown.CheongdanPoints > 0 then
  begin
    Result := Result + [Format('청단(%d)', [ABreakdown.CheongdanPoints])];
  end;

  if ABreakdown.ChodanPoints > 0 then
  begin
    Result := Result + [Format('초단(%d)', [ABreakdown.ChodanPoints])];
  end;

  if ABreakdown.JunkPoints > 0 then
  begin
    Result := Result + [Format('피(%d)', [ABreakdown.JunkPoints])];
  end;
end;

{$REGION 'TGostopSettlement'}
class function TGostopSettlement.Build(const AGame: TGameState; const AEngine: TTurnEngine;
  const AInput: TSettlementInput): TSettlementOutput;
begin
  Result := Default (TSettlementOutput);
  Result.WinnerSeat := -1;

  // 오링 카운트 집계용: 이번 정산 전에 이미 파산 상태였던 상대 좌석(중복 집계 방지)
  var LWasBroke: set of 0 .. 3 := [];
  for var LSeat in AInput.ActiveOpponentSeats do
  begin
    if AInput.MoneyBefore[LSeat] <= 0 then
    begin
      Include(LWasBroke, LSeat);
    end;
  end;

  var LSettle := AEngine.FinalSettlement;

  // 쇼당 독박: 수락자(밀어줄 대상)가 이겼으면 거절자가 전액(호출자 몫까지)을 독박,
  // 호출자는 면제(피박·광박은 각 패자별 계산이 이미 반영됨 — 합만 거절자에게 몰아줌)
  var LDokbakIdx := -1;
  if AInput.ShodangActive then
  begin
    LDokbakIdx := TShodang.ApplyDokbak(LSettle, AInput.PlayerCount, AGame.Winner,
      AInput.ShodangCaller, AInput.ShodangAccepter, AInput.ShodangDecliner);
  end;

  var LSeatFlag: array [0 .. 3] of TArray<string>;
  for var S := 0 to 3 do
  begin
    LSeatFlag[S] := nil;
  end;

  // 4인: 게임 정산을 좌석별로 합산해 최종 손익 확정 + 좌석별 박 플래그(한 판에 한 번만 쓰이는 로컬 누산)
  var LNet4: array [0 .. 3] of Integer;
  for var S := 0 to 3 do
  begin
    LNet4[S] := 0;
  end;

  if AInput.PlayerCount = 4 then
  begin
    for var I := 0 to High(AInput.SeatMap) do
    begin
      LNet4[AInput.SeatMap[I]] := LNet4[AInput.SeatMap[I]] + LSettle[I].Net;
      LSeatFlag[AInput.SeatMap[I]] := FlagLabelsOf(LSettle[I]);
    end;
  end;

  // 물리 자리별 머니 반영(최종 손익 × 단가 × 판돈 배수)
  var LMoney: TArray<Integer>;
  SetLength(LMoney, 4);
  for var S := 0 to 3 do
  begin
    LMoney[S] := AInput.MoneyBefore[S];
  end;

  if AInput.PlayerCount = 4 then
  begin
    for var S := 0 to 3 do
    begin
      var LPos := (AInput.NextStartPos + S) mod 4;
      LMoney[LPos] := LMoney[LPos] + LNet4[S] * AInput.MoneyPerPoint * AInput.Stakes;
    end;
  end
  else
  begin
    for var I := 0 to AGame.PlayerCount - 1 do
    begin
      var LPos := AInput.GameToPhysical[I];
      LMoney[LPos] := LMoney[LPos] + LSettle[I].Net * AInput.MoneyPerPoint * AInput.Stakes;
    end;
  end;

  Result.MoneyAfter := LMoney;

  // 오링 카운트: 이번 정산으로 새로 파산한 상대 수만큼(이미 파산 상태였던 좌석은 제외)
  if not AInput.Spectator then
  begin
    for var LSeat in AInput.ActiveOpponentSeats do
    begin
      if (LMoney[LSeat] <= 0) and (not (LSeat in LWasBroke)) then
      begin
        Inc(Result.NewlyBrokeCount);
      end;
    end;
  end;

  // 전적(참가자만): 승자 물리 좌석 + 참가자 물리 좌석 목록(승자 포함 — 승/패 반영은 호출부 몫)
  if AGame.Winner >= 0 then
  begin
    Result.WinnerSeat := AInput.GameToPhysical[AGame.Winner];
    SetLength(Result.ParticipantSeats, AGame.PlayerCount);
    for var I := 0 to AGame.PlayerCount - 1 do
    begin
      Result.ParticipantSeats[I] := AInput.GameToPhysical[I];
    end;
  end;

  // 총통(즉시 승리) 판인지 — 안내 줄 표시용
  var LChongtong := False;
  for var LEvt in AGame.Events do
  begin
    if LEvt.Kind = pekChongtong then
    begin
      LChongtong := True;
      Break;
    end;
  end;

  // 결과 줄(아바타·금액·박 뱃지 구조화 — 정산창 렌더링용)
  var LRows := TList<TResultRow>.Create;
  try
    if AGame.ThreeBbeok then
    begin
      var LRow: TResultRow;
      LRow.AvatarIdx := -1;
      LRow.IsWinner := False;
      LRow.HasAmount := False;
      LRow.Text := '쓰리뻑! — 즉시 승리 (기본 점수)';
      LRows.Add(LRow);
    end;

    if LChongtong and (AGame.Winner >= 0) then
    begin
      var LRow: TResultRow;
      LRow.AvatarIdx := -1;
      LRow.IsWinner := False;
      LRow.HasAmount := False;
      LRow.Text := '총통! — 즉시 승리 (기본 점수)';
      LRows.Add(LRow);
    end;

    if AGame.Winner < 0 then
    begin
      var LRow: TResultRow;
      LRow.AvatarIdx := -1;
      LRow.IsWinner := False;
      LRow.HasAmount := False;
      LRow.Text := '나가리 (무승부)';
      LRows.Add(LRow);
      LRow.Text := Format('다음 판 판돈 ×%d!', [AInput.Stakes * 2]);
      LRows.Add(LRow);
    end
    else
    if AInput.PlayerCount = 4 then
    begin
      // LWinnerSeat·S(아래 루프)는 "선=0..말번=3" 논리 좌석(SeatMap 공간). SeatAvatar는 물리 좌석
      // 배열이므로 (NextStartPos+논리좌석) mod 4로 반드시 회전해서 인덱싱해야 한다 — 이 회전을
      // 빠뜨리면 선이 바뀐 판(대부분의 판)에서 정산창에 엉뚱한 사람 얼굴이 뜬다.
      var LWinnerSeat := AInput.SeatMap[AGame.Winner];
      var LWinRow: TResultRow;
      LWinRow.AvatarIdx := AInput.SeatAvatar[AInput.GameToPhysical[AGame.Winner]];
      LWinRow.IsWinner := True;
      LWinRow.HasAmount := True;
      LWinRow.Amount := LNet4[LWinnerSeat] * AInput.MoneyPerPoint * AInput.Stakes;
      LWinRow.BalanceAfter := LMoney[AInput.GameToPhysical[AGame.Winner]];
      LWinRow.Flags := nil;
      var LWinBreakdown4 := AEngine.ScoreOf(AGame.Winner);
      LWinRow.ScoreParts := ScorePartsOf(LWinBreakdown4);
      LWinRow.ScoreTotal := LWinBreakdown4.Total;
      LRows.Add(LWinRow);

      for var S := 0 to 3 do
      begin
        // 승자 제외 + 게임에 참가하지 않은(빠진/관전) 좌석은 정산에 표시하지 않음
        if (S <> LWinnerSeat) and (S <> AInput.SitOutSeat) then
        begin
          var LRow: TResultRow;
          LRow.AvatarIdx := AInput.SeatAvatar[(AInput.NextStartPos + S) mod 4];
          LRow.IsWinner := False;
          LRow.HasAmount := True;
          LRow.Amount := LNet4[S] * AInput.MoneyPerPoint * AInput.Stakes;
          LRow.BalanceAfter := LMoney[(AInput.NextStartPos + S) mod 4];
          LRow.Flags := LSeatFlag[S];
          LRows.Add(LRow);
        end;
      end;
    end
    else
    begin
      var LWinRow: TResultRow;
      LWinRow.AvatarIdx := AInput.SeatAvatar[AInput.GameToPhysical[AGame.Winner]];
      LWinRow.IsWinner := True;
      LWinRow.HasAmount := True;
      LWinRow.Amount := LSettle[AGame.Winner].Net * AInput.MoneyPerPoint * AInput.Stakes;
      LWinRow.BalanceAfter := LMoney[AInput.GameToPhysical[AGame.Winner]];
      LWinRow.Flags := nil;
      var LWinBreakdown3 := AEngine.ScoreOf(AGame.Winner);
      LWinRow.ScoreParts := ScorePartsOf(LWinBreakdown3);
      LWinRow.ScoreTotal := LWinBreakdown3.Total;
      LRows.Add(LWinRow);

      for var I := 0 to AGame.PlayerCount - 1 do
      begin
        if I <> AGame.Winner then
        begin
          var LFlags := FlagLabelsOf(LSettle[I]);
          if I = LDokbakIdx then
          begin
            LFlags := ['쇼당독박'] + LFlags;
          end;

          var LRow: TResultRow;
          LRow.AvatarIdx := AInput.SeatAvatar[AInput.GameToPhysical[I]];
          LRow.IsWinner := False;
          LRow.HasAmount := True;
          LRow.Amount := LSettle[I].Net * AInput.MoneyPerPoint * AInput.Stakes;
          LRow.BalanceAfter := LMoney[AInput.GameToPhysical[I]];
          LRow.Flags := LFlags;
          LRows.Add(LRow);
        end;
      end;
    end;

    Result.ResultRows := LRows.ToArray;
  finally
    LRows.Free;
  end;

  // 정산창 제목(판돈 배수 안내) — FStakes 갱신 전 값(AInput.Stakes) 기준
  if AInput.Stakes > 1 then
  begin
    Result.ResultTitle := Trim(Format(' (판돈 ×%d)', [AInput.Stakes]));
  end
  else
  begin
    Result.ResultTitle := '';
  end;

  // 상태 표시줄용 요약 텍스트(다이얼로그와 별개, 간단 요약)
  var LStatusParts := TList<string>.Create;
  try
    for var LRow in Result.ResultRows do
    begin
      if LRow.HasAmount then
      begin
        LStatusParts.Add(Format('%s원 %s', [FormatFloat('#,##0', LRow.Amount), string.Join(' ', LRow.Flags)]).Trim)
      end
      else
      begin
        LStatusParts.Add(LRow.Text);
      end;
    end;

    Result.StatusText := string.Join('   ', LStatusParts.ToArray);
  finally
    LStatusParts.Free;
  end;

  // 판돈 배수 갱신: 나가리면 다음 판 ×2 이월, 승부가 나면(총통 즉시 승리 포함) 1로 복귀
  if AGame.Winner < 0 then
  begin
    Result.NewStakes := AInput.Stakes * 2;
  end
  else
  begin
    Result.NewStakes := 1;
  end;
end;
{$ENDREGION}

end.
