unit Gostop.SaveGame;

interface

{$REGION 'uses'}
uses
  System.SysUtils,
  System.Generics.Collections,
  Gostop.Cards;
{$ENDREGION}

type
  /// <summary>저장된 카드 1장(에셋 ID + 런타임 상태 플래그).</summary>
  TSaveCard = record
    AssetId: string;
    GivenAsPi: Boolean;
  end;

  /// <summary>저장된 좌석(자리) 1곳의 매치 진행 정보.</summary>
  TSaveSeat = record
    Avatar: Integer;
    Skill: Integer;
    Money: Integer;
    Wins: Integer;
    Losses: Integer;
    GaveUpLast: Boolean;
  end;

  /// <summary>저장된 플레이어 1명의 게임 진행 정보.</summary>
  TSavePlayer = record
    NameStr: string;
    Hand: TArray<TSaveCard>;
    Captured: TArray<TSaveCard>;
    GoCount: Integer;
    LastGoScore: Integer;
    ShakeCount: Integer;
    CardDebt: Integer;
    PendingShakeMonth: Integer;
    BbeokCount: Integer;
  end;

  /// <summary>저장된 뻑 더미 1건(월 → 생성자 플레이어 인덱스).</summary>
  TSaveBbeok = record
    Month: Integer;
    Creator: Integer;
  end;

  /// <summary>
  ///   진행 중인 매치 + 현재 게임을 통째로 담는 저장 데이터.
  ///   좌석 배열(Seats)은 항상 TSeatPos 순서(spTop, spLeft, spBottom, spRight) 4칸 고정.
  /// </summary>
  TSaveData = record
    // 매치(좌석) 정보
    PlayerCount: Integer;
    Spectator: Boolean;
    NextStartPos: Integer;    // TSeatPos 서수
    Stakes: Integer;
    SitOutSeat: Integer;      // 4인 전용(빠진 좌석), 없으면 -1
    SeatMap: TArray<Integer>; // 4인 전용: 게임 인덱스 → 좌석(0~3)
    RowPos: TArray<Integer>;  // 2/3인 전용: 게임 인덱스 → TSeatPos 서수(4칸)
    Seats: array [0 .. 3] of TSaveSeat;   // TSeatPos 서수로 색인

    // 현재 게임(TGameState) 정보
    Current: Integer;
    Phase: Integer;   // TGamePhase 서수
    Winner: Integer;
    PlayCount: Integer;
    ThreeBbeok: Boolean;
    BbeokCreator: TArray<TSaveBbeok>;
    Players: TArray<TSavePlayer>;
    Floor: TArray<TSaveCard>;
    Stock: TArray<TSaveCard>;

    // 쇼당 독박 대기(성립 후 정산까지 유지되는 판 단위 상태)
    ShodangActive: Boolean;
    ShodangCaller: Integer;
    ShodangAccepter: Integer;
    ShodangDecliner: Integer;
  end;

  /// <summary>
  ///   진행 중인 게임을 실행 파일 옆 JSON 파일로 저장·복원하는 정적 헬퍼("이어서 하기" 기능).
  ///   카드 매칭은 자체 보유한 <c>AssetId → THwatuCard</c> 카탈로그로 처리한다.
  /// </summary>
  TGostopSaveGame = record
  public
    /// <summary>저장 파일 경로(실행 파일 옆 gostop_save.json — 포터블).</summary>
    class function FilePath: string; static;
    /// <summary>저장 파일이 있으면 True("이어서 하기" 버튼 표시 여부 판단용).</summary>
    class function Exists: Boolean; static;
    /// <summary>저장 파일을 삭제합니다(없어도 예외 없음).</summary>
    class procedure Delete; static;
    /// <summary>현재 진행 데이터를 저장합니다. 실패해도 예외를 던지지 않고 조용히 무시합니다.</summary>
    class procedure Save(const AData: TSaveData); static;
    /// <summary>저장 파일을 읽어 데이터를 복원합니다. 손상/부재 시 False.</summary>
    class function TryLoad(out AData: TSaveData): Boolean; static;
  end;

/// <summary>런타임 카드를 저장용 레코드로 변환합니다.</summary>
function CardToSave(const ACard: THwatuCard): TSaveCard;
/// <summary>저장용 레코드를 카탈로그에서 찾아 런타임 카드로 복원합니다.</summary>
/// <exception cref="EHwatuError">에셋 ID가 카탈로그에 없으면 발생.</exception>
function CardFromSave(const ASaved: TSaveCard): THwatuCard;

implementation

{$REGION 'uses'}
uses
  System.Math,
  System.IOUtils,
  System.JSON;
{$ENDREGION}

var
  GCatalog: TDictionary<string, THwatuCard>;

procedure EnsureCatalog;
begin
  if Assigned(GCatalog) then
  begin
    Exit;
  end;

  GCatalog := TDictionary<string, THwatuCard>.Create;
  for var LCard in THwatuCatalog.Standard do
  begin
    GCatalog.AddOrSetValue(LCard.AssetId, LCard);
  end;

  for var LCard in THwatuCatalog.Bonus do
  begin
    GCatalog.AddOrSetValue(LCard.AssetId, LCard);
  end;
end;

function CardToSave(const ACard: THwatuCard): TSaveCard;
begin
  Result.AssetId := ACard.AssetId;
  Result.GivenAsPi := ACard.GivenAsPi;
end;

function CardFromSave(const ASaved: TSaveCard): THwatuCard;
begin
  EnsureCatalog;
  if not GCatalog.TryGetValue(ASaved.AssetId, Result) then
  begin
    raise EHwatuError.CreateFmt('저장 파일의 카드 ID를 찾을 수 없습니다: %s', [ASaved.AssetId]);
  end;

  Result.GivenAsPi := ASaved.GivenAsPi;
end;

function CardArrayToJson(const ACards: TArray<TSaveCard>): TJSONArray;
begin
  Result := TJSONArray.Create;
  for var LCard in ACards do
  begin
    var LObj := TJSONObject.Create;
    LObj.AddPair('id', LCard.AssetId);
    LObj.AddPair('pi', TJSONBool.Create(LCard.GivenAsPi));
    Result.AddElement(LObj);
  end;
end;

function CardArrayFromJson(const AArr: TJSONArray): TArray<TSaveCard>;
begin
  Result := nil;
  if not Assigned(AArr) then
  begin
    Exit;
  end;

  SetLength(Result, AArr.Count);
  for var I := 0 to AArr.Count - 1 do
  begin
    var LObj := AArr.Items[I] as TJSONObject;
    Result[I].AssetId := LObj.GetValue<string>('id', '');
    Result[I].GivenAsPi := LObj.GetValue<Boolean>('pi', False);
  end;
end;

{$REGION 'TGostopSaveGame'}
class function TGostopSaveGame.FilePath: string;
begin
  Result := TPath.Combine(TPath.GetDirectoryName(ParamStr(0)), 'gostop_save.json');
end;

class function TGostopSaveGame.Exists: Boolean;
begin
  Result := TFile.Exists(FilePath);
end;

class procedure TGostopSaveGame.Delete;
begin
  try
    if TFile.Exists(FilePath) then
    begin
      TFile.Delete(FilePath);
    end;
  except
    // 삭제 실패는 무시(다음 저장이 덮어쓴다)
  end;
end;

class procedure TGostopSaveGame.Save(const AData: TSaveData);
begin
  try
    var LRoot := TJSONObject.Create;
    try
      LRoot.AddPair('playerCount', TJSONNumber.Create(AData.PlayerCount));
      LRoot.AddPair('spectator', TJSONBool.Create(AData.Spectator));
      LRoot.AddPair('nextStartPos', TJSONNumber.Create(AData.NextStartPos));
      LRoot.AddPair('stakes', TJSONNumber.Create(AData.Stakes));
      LRoot.AddPair('sitOutSeat', TJSONNumber.Create(AData.SitOutSeat));

      var LSeatMapArr := TJSONArray.Create;
      for var LV in AData.SeatMap do
      begin
        LSeatMapArr.Add(LV);
      end;
      LRoot.AddPair('seatMap', LSeatMapArr);

      var LRowPosArr := TJSONArray.Create;
      for var LV in AData.RowPos do
      begin
        LRowPosArr.Add(LV);
      end;
      LRoot.AddPair('rowPos', LRowPosArr);

      var LSeatsArr := TJSONArray.Create;
      for var S := 0 to 3 do
      begin
        var LSeatObj := TJSONObject.Create;
        LSeatObj.AddPair('avatar', TJSONNumber.Create(AData.Seats[S].Avatar));
        LSeatObj.AddPair('skill', TJSONNumber.Create(AData.Seats[S].Skill));
        LSeatObj.AddPair('money', TJSONNumber.Create(AData.Seats[S].Money));
        LSeatObj.AddPair('wins', TJSONNumber.Create(AData.Seats[S].Wins));
        LSeatObj.AddPair('losses', TJSONNumber.Create(AData.Seats[S].Losses));
        LSeatObj.AddPair('gaveUpLast', TJSONBool.Create(AData.Seats[S].GaveUpLast));
        LSeatsArr.AddElement(LSeatObj);
      end;
      LRoot.AddPair('seats', LSeatsArr);

      LRoot.AddPair('current', TJSONNumber.Create(AData.Current));
      LRoot.AddPair('phase', TJSONNumber.Create(AData.Phase));
      LRoot.AddPair('winner', TJSONNumber.Create(AData.Winner));
      LRoot.AddPair('playCount', TJSONNumber.Create(AData.PlayCount));
      LRoot.AddPair('threeBbeok', TJSONBool.Create(AData.ThreeBbeok));

      var LBbeokArr := TJSONArray.Create;
      for var LB in AData.BbeokCreator do
      begin
        var LBObj := TJSONObject.Create;
        LBObj.AddPair('month', TJSONNumber.Create(LB.Month));
        LBObj.AddPair('creator', TJSONNumber.Create(LB.Creator));
        LBbeokArr.AddElement(LBObj);
      end;
      LRoot.AddPair('bbeokCreator', LBbeokArr);

      var LPlayersArr := TJSONArray.Create;
      for var LP in AData.Players do
      begin
        var LPObj := TJSONObject.Create;
        LPObj.AddPair('name', LP.NameStr);
        LPObj.AddPair('hand', CardArrayToJson(LP.Hand));
        LPObj.AddPair('captured', CardArrayToJson(LP.Captured));
        LPObj.AddPair('goCount', TJSONNumber.Create(LP.GoCount));
        LPObj.AddPair('lastGoScore', TJSONNumber.Create(LP.LastGoScore));
        LPObj.AddPair('shakeCount', TJSONNumber.Create(LP.ShakeCount));
        LPObj.AddPair('cardDebt', TJSONNumber.Create(LP.CardDebt));
        LPObj.AddPair('pendingShakeMonth', TJSONNumber.Create(LP.PendingShakeMonth));
        LPObj.AddPair('bbeokCount', TJSONNumber.Create(LP.BbeokCount));
        LPlayersArr.AddElement(LPObj);
      end;
      LRoot.AddPair('players', LPlayersArr);

      LRoot.AddPair('floor', CardArrayToJson(AData.Floor));
      LRoot.AddPair('stock', CardArrayToJson(AData.Stock));

      LRoot.AddPair('shodangActive', TJSONBool.Create(AData.ShodangActive));
      LRoot.AddPair('shodangCaller', TJSONNumber.Create(AData.ShodangCaller));
      LRoot.AddPair('shodangAccepter', TJSONNumber.Create(AData.ShodangAccepter));
      LRoot.AddPair('shodangDecliner', TJSONNumber.Create(AData.ShodangDecliner));

      TFile.WriteAllText(FilePath, LRoot.ToJSON, TEncoding.UTF8);
    finally
      LRoot.Free;
    end;
  except
    // 저장 실패(쓰기 금지 폴더 등)는 게임 진행에 영향이 없으므로 무시한다
  end;
end;

class function TGostopSaveGame.TryLoad(out AData: TSaveData): Boolean;
begin
  Result := False;
  AData := Default (TSaveData);
  if not TFile.Exists(FilePath) then
  begin
    Exit;
  end;

  try
    var LText := TFile.ReadAllText(FilePath, TEncoding.UTF8);
    var LValue := TJSONObject.ParseJSONValue(LText);
    try
      if not (LValue is TJSONObject) then
      begin
        Exit;
      end;

      var LRoot := TJSONObject(LValue);
      AData.PlayerCount := LRoot.GetValue<Integer>('playerCount', 0);
      AData.Spectator := LRoot.GetValue<Boolean>('spectator', False);
      AData.NextStartPos := LRoot.GetValue<Integer>('nextStartPos', 0);
      AData.Stakes := LRoot.GetValue<Integer>('stakes', 1);
      AData.SitOutSeat := LRoot.GetValue<Integer>('sitOutSeat', -1);

      var LSeatMapArr: TJSONArray;
      if LRoot.TryGetValue<TJSONArray>('seatMap', LSeatMapArr) then
      begin
        SetLength(AData.SeatMap, LSeatMapArr.Count);
        for var I := 0 to LSeatMapArr.Count - 1 do
        begin
          AData.SeatMap[I] := (LSeatMapArr.Items[I] as TJSONNumber).AsInt;
        end;
      end;

      var LRowPosArr: TJSONArray;
      if LRoot.TryGetValue<TJSONArray>('rowPos', LRowPosArr) then
      begin
        SetLength(AData.RowPos, LRowPosArr.Count);
        for var I := 0 to LRowPosArr.Count - 1 do
        begin
          AData.RowPos[I] := (LRowPosArr.Items[I] as TJSONNumber).AsInt;
        end;
      end;

      var LSeatsArr: TJSONArray;
      if LRoot.TryGetValue<TJSONArray>('seats', LSeatsArr) then
      begin
        for var S := 0 to Min(3, LSeatsArr.Count - 1) do
        begin
          var LSeatObj := LSeatsArr.Items[S] as TJSONObject;
          AData.Seats[S].Avatar := LSeatObj.GetValue<Integer>('avatar', -1);
          AData.Seats[S].Skill := LSeatObj.GetValue<Integer>('skill', 70);
          AData.Seats[S].Money := LSeatObj.GetValue<Integer>('money', 0);
          AData.Seats[S].Wins := LSeatObj.GetValue<Integer>('wins', 0);
          AData.Seats[S].Losses := LSeatObj.GetValue<Integer>('losses', 0);
          AData.Seats[S].GaveUpLast := LSeatObj.GetValue<Boolean>('gaveUpLast', False);
        end;
      end;

      AData.Current := LRoot.GetValue<Integer>('current', 0);
      AData.Phase := LRoot.GetValue<Integer>('phase', 0);
      AData.Winner := LRoot.GetValue<Integer>('winner', -1);
      AData.PlayCount := LRoot.GetValue<Integer>('playCount', 0);
      AData.ThreeBbeok := LRoot.GetValue<Boolean>('threeBbeok', False);

      var LBbeokArr: TJSONArray;
      if LRoot.TryGetValue<TJSONArray>('bbeokCreator', LBbeokArr) then
      begin
        SetLength(AData.BbeokCreator, LBbeokArr.Count);
        for var I := 0 to LBbeokArr.Count - 1 do
        begin
          var LBObj := LBbeokArr.Items[I] as TJSONObject;
          AData.BbeokCreator[I].Month := LBObj.GetValue<Integer>('month', 0);
          AData.BbeokCreator[I].Creator := LBObj.GetValue<Integer>('creator', -1);
        end;
      end;

      var LPlayersArr: TJSONArray;
      if LRoot.TryGetValue<TJSONArray>('players', LPlayersArr) then
      begin
        SetLength(AData.Players, LPlayersArr.Count);
        for var I := 0 to LPlayersArr.Count - 1 do
        begin
          var LPObj := LPlayersArr.Items[I] as TJSONObject;
          AData.Players[I].NameStr := LPObj.GetValue<string>('name', '');
          var LHandArr: TJSONArray;
          LPObj.TryGetValue<TJSONArray>('hand', LHandArr);
          AData.Players[I].Hand := CardArrayFromJson(LHandArr);
          var LCapArr: TJSONArray;
          LPObj.TryGetValue<TJSONArray>('captured', LCapArr);
          AData.Players[I].Captured := CardArrayFromJson(LCapArr);
          AData.Players[I].GoCount := LPObj.GetValue<Integer>('goCount', 0);
          AData.Players[I].LastGoScore := LPObj.GetValue<Integer>('lastGoScore', 0);
          AData.Players[I].ShakeCount := LPObj.GetValue<Integer>('shakeCount', 0);
          AData.Players[I].CardDebt := LPObj.GetValue<Integer>('cardDebt', 0);
          AData.Players[I].PendingShakeMonth := LPObj.GetValue<Integer>('pendingShakeMonth', 0);
          AData.Players[I].BbeokCount := LPObj.GetValue<Integer>('bbeokCount', 0);
        end;
      end;

      var LFloorArr: TJSONArray;
      LRoot.TryGetValue<TJSONArray>('floor', LFloorArr);
      AData.Floor := CardArrayFromJson(LFloorArr);

      var LStockArr: TJSONArray;
      LRoot.TryGetValue<TJSONArray>('stock', LStockArr);
      AData.Stock := CardArrayFromJson(LStockArr);

      AData.ShodangActive := LRoot.GetValue<Boolean>('shodangActive', False);
      AData.ShodangCaller := LRoot.GetValue<Integer>('shodangCaller', -1);
      AData.ShodangAccepter := LRoot.GetValue<Integer>('shodangAccepter', -1);
      AData.ShodangDecliner := LRoot.GetValue<Integer>('shodangDecliner', -1);

      // AData.PlayerCount는 매치 좌석 수(4인 매치=4)이고 Players는 "이번 판" 실제 참가자 수다.
      // 4인 매치에서 말번 협상 때 누군가 포기(SitOutSeat)하면 이번 판은 3인으로 진행되므로
      // Players 길이가 PlayerCount보다 작을 수 있다(반대로 클 수는 없음). 예전엔 완전히 같아야
      // 한다고 검사해 말번이 빠진 4인 판을 저장한 뒤에는 항상 "이어하기"가 실패했다.
      Result := (AData.PlayerCount >= 2) and (Length(AData.Players) >= 2) and (Length(AData.Players) <= AData.PlayerCount);
    finally
      LValue.Free;
    end;
  except
    Result := False;
  end;
end;
{$ENDREGION}

initialization

finalization
  FreeAndNil(GCatalog);

end.
