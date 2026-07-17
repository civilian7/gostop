unit Gostop.Shodang;

interface

{$REGION 'uses'}
uses
  System.Generics.Collections,
  Gostop.Cards,
  Gostop.Play;
{$ENDREGION}

type
  /// <summary>쇼당 판정 대상 족보.</summary>
  TShodangGroup = (
    sgGwang,
    sgGodori,
    sgHong,
    sgCheong,
    sgCho
  );

  /// <summary>쇼당 위협 1건: 어느 상대의 어떤 족보를, 내 어떤 패가 완성시키는지.</summary>
  TShodangThreat = record
    /// <summary>위협받는 상대의 게임 인덱스.</summary>
    Opponent: Integer;
    /// <summary>족보 이름('광'/'고도리'/'홍단'/'청단'/'초단').</summary>
    Group: string;
    /// <summary>내가 가진 완성패 AssetId.</summary>
    CardId: string;
  end;

  /// <summary>쇼당 판정 결과.</summary>
  TShodangResult = record
    /// <summary>쇼당을 걸 수 있는가(3인에서 두 상대 모두 완성 위협 시 True).</summary>
    Callable: Boolean;
    /// <summary>위협 목록(상대별 최소 1건).</summary>
    Threats: TArray<TShodangThreat>;
  end;

  /// <summary>쇼당 응답 결과 종류.</summary>
  TShodangOutcome = (
    soNagari,     // 두 상대 모두 수락 → 나가리(무효)
    soContinue,   // 두 상대 모두 거절 → 아무 일 없이 계속 진행
    soPushed      // 한 명 수락 → 수락자를 밀어주고 거절자는 독박 대기
  );

  /// <summary>쇼당 응답을 종합한 결정(역할 확정).</summary>
  TShodangDecision = record
    /// <summary>응답 결과.</summary>
    Outcome: TShodangOutcome;
    /// <summary>쇼당을 건 사람.</summary>
    Caller: Integer;
    /// <summary>수락자(밀어줄 대상). soPushed일 때만 유효(그 외 -1).</summary>
    Accepter: Integer;
    /// <summary>거절자(독박 대상). soPushed일 때만 유효(그 외 -1).</summary>
    Decliner: Integer;
  end;

  /// <summary>
  ///   쇼당 판정(3인). 상대가 먹어간 패로 미완성 족보(2장)를 갖고, 호출자가 그 족보를 완성시키는
  ///   패를 손에 들고 있으면 위협이 성립한다. 두 상대 모두 위협하면 쇼당을 걸 수 있다.
  /// </summary>
  TShodang = record
  public
    /// <summary>ACaller가 쇼당을 걸 수 있는지 판정한다.</summary>
    /// <param name="AGame">현재 게임 상태(3인).</param>
    /// <param name="ACaller">쇼당을 거는 플레이어의 게임 인덱스.</param>
    /// <returns>쇼당 가능 여부와 위협 목록.</returns>
    class function Detect(const AGame: TGameState; const ACaller: Integer): TShodangResult; static;

    /// <summary>
    ///   두 상대(AOppA/AOppB)의 수락 여부(AAccA/AAccB)를 종합해 쇼당 결정을 반환한다.
    ///   둘 다 수락=나가리, 둘 다 거절=계속, 한 명만 수락=밀어주기(수락자/거절자 확정).
    /// </summary>
    /// <param name="ACaller">쇼당을 건 사람.</param>
    /// <param name="AOppA">상대 A.</param>
    /// <param name="AOppB">상대 B.</param>
    /// <param name="AAccA">상대 A가 수락했는가.</param>
    /// <param name="AAccB">상대 B가 수락했는가.</param>
    class function Resolve(const ACaller, AOppA, AOppB: Integer; const AAccA, AAccB: Boolean): TShodangDecision; static;

    /// <summary>
    ///   독박 재분배: 수락자가 그 판을 이겼으면 거절자가 호출자+거절자 두 몫 전액을 부담하고
    ///   호출자는 면제된다. ASettle을 제자리에서 수정하며, 재분배가 일어나면 독박 대상(거절자)
    ///   인덱스를, 조건에 맞지 않으면 -1을 반환한다.
    /// </summary>
    /// <param name="ASettle">FinalSettlement 결과(수정됨).</param>
    /// <param name="APlayerCount">플레이어 수(3인에서만 적용).</param>
    /// <param name="AWinner">승자 인덱스.</param>
    /// <param name="ACaller">쇼당 호출자.</param>
    /// <param name="AAccepter">수락자.</param>
    /// <param name="ADecliner">거절자.</param>
    /// <returns>독박 대상(거절자) 인덱스, 미적용 시 -1.</returns>
    class function ApplyDokbak(var ASettle: TArray<TPlayerResult>; const APlayerCount, AWinner,
      ACaller, AAccepter, ADecliner: Integer): Integer; static;
  end;

implementation

function InGroup(const ACard: THwatuCard; const AGroup: TShodangGroup): Boolean;
begin
  case AGroup of
    sgGwang:
      begin
        Result := ACard.Kind = hkBright;
      end;
    sgGodori:
      begin
        Result := (ACard.Kind = hkAnimal) and ACard.IsGodori;
      end;
    sgHong:
      begin
        Result := (ACard.Kind = hkRibbon) and (ACard.Ribbon = rkHong);
      end;
    sgCheong:
      begin
        Result := (ACard.Kind = hkRibbon) and (ACard.Ribbon = rkCheong);
      end;
  else
    begin
      Result := (ACard.Kind = hkRibbon) and (ACard.Ribbon = rkCho);
    end;
  end;
end;

function GroupName(const AGroup: TShodangGroup): string;
begin
  case AGroup of
    sgGwang:
      begin
        Result := '광';
      end;
    sgGodori:
      begin
        Result := '고도리';
      end;
    sgHong:
      begin
        Result := '홍단';
      end;
    sgCheong:
      begin
        Result := '청단';
      end;
  else
    begin
      Result := '초단';
    end;
  end;
end;

class function TShodang.Detect(const AGame: TGameState; const ACaller: Integer): TShodangResult;
begin
  Result.Callable := False;
  Result.Threats := nil;
  if AGame.PlayerCount <> 3 then
  begin
    Exit;
  end;

  var LThreatenedCount := 0;

  for var LOpp := 0 to AGame.PlayerCount - 1 do
  begin
    if LOpp = ACaller then
    begin
      Continue;
    end;

    var LOppThreat := False;
    for var LGroup := Low(TShodangGroup) to High(TShodangGroup) do
    begin
      // 상대 먹은패에서 이 족보 장수 + 월 수집
      var LCount := 0;
      var LMonths := TList<Integer>.Create;
      try
        for var LC in AGame.Player(LOpp).Captured do
        begin
          if InGroup(LC, LGroup) then
          begin
            Inc(LCount);
            LMonths.Add(LC.Month);
          end;
        end;

        // 미완성(정확히 2장)이고, 호출자가 완성패(그 족보이면서 상대가 없는 월)를 보유?
        if LCount = 2 then
        begin
          for var LH in AGame.Player(ACaller).Hand do
          begin
            if InGroup(LH, LGroup) and (LMonths.IndexOf(LH.Month) < 0) then
            begin
              var LThreat: TShodangThreat;
              LThreat.Opponent := LOpp;
              LThreat.Group := GroupName(LGroup);
              LThreat.CardId := LH.AssetId;
              Result.Threats := Result.Threats + [LThreat];
              LOppThreat := True;
              Break;
            end;
          end;
        end;
      finally
        LMonths.Free;
      end;

      if LOppThreat then
      begin
        Break;   // 이 상대는 한 건이면 충분
      end;
    end;

    if LOppThreat then
    begin
      Inc(LThreatenedCount);
    end;
  end;

  // 두 상대 모두 완성 위협해야 쇼당 성립
  Result.Callable := LThreatenedCount = 2;
end;

class function TShodang.Resolve(const ACaller, AOppA, AOppB: Integer; const AAccA, AAccB: Boolean): TShodangDecision;
begin
  Result.Caller := ACaller;
  Result.Accepter := -1;
  Result.Decliner := -1;

  if AAccA and AAccB then
  begin
    Result.Outcome := soNagari;
    Exit;
  end;

  if (not AAccA) and (not AAccB) then
  begin
    Result.Outcome := soContinue;
    Exit;
  end;

  // 한 명만 수락 → 수락자를 밀어주고 거절자는 독박 대기
  Result.Outcome := soPushed;
  if AAccA then
  begin
    Result.Accepter := AOppA;
    Result.Decliner := AOppB;
  end
  else
  begin
    Result.Accepter := AOppB;
    Result.Decliner := AOppA;
  end;
end;

class function TShodang.ApplyDokbak(var ASettle: TArray<TPlayerResult>; const APlayerCount, AWinner,
  ACaller, AAccepter, ADecliner: Integer): Integer;
begin
  Result := -1;

  // 수락자가 승리했고 호출자·거절자가 모두 유효하며 승자와 겹치지 않을 때만 재분배
  if (APlayerCount = 3) and (AWinner >= 0) and (AWinner = AAccepter)
    and (ACaller >= 0) and (ADecliner >= 0)
    and (ACaller <> AWinner) and (ADecliner <> AWinner) then
  begin
    var LCallerLoss := -ASettle[ACaller].Net;
    var LDeclinerLoss := -ASettle[ADecliner].Net;
    ASettle[ACaller].Net := 0;                                 // 호출자 면제
    ASettle[ADecliner].Net := -(LCallerLoss + LDeclinerLoss);  // 거절자 독박(양쪽 몫)
    Result := ADecliner;
  end;
end;

end.
