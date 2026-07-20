unit Gostop.Score;

interface

{$REGION 'uses'}
uses
  System.SysUtils,
  System.Math,
  System.Generics.Collections,
  Gostop.Cards;
{$ENDREGION}

type
  /// <summary>
  ///   점수 계산 규칙 옵션(지역 룰 편차 흡수용). <see cref="Default"/>는 널리 쓰이는 표준값을 반환한다.
  /// </summary>
  TScoreOptions = record
    /// <summary>일반 3광 점수(기본 3).</summary>
    Bright3: Integer;
    /// <summary>비광 포함 3광 점수(기본 2).</summary>
    Bright3WithBi: Integer;
    /// <summary>4광 점수(기본 4).</summary>
    Bright4: Integer;
    /// <summary>5광 점수(기본 15).</summary>
    Bright5: Integer;
    /// <summary>열끗 점수 시작 장수(기본 5 → 5장부터 1점).</summary>
    AnimalThreshold: Integer;
    /// <summary>띠 점수 시작 장수(기본 5).</summary>
    RibbonThreshold: Integer;
    /// <summary>피 점수 시작 값(기본 10 → 피값 10부터 1점).</summary>
    JunkThreshold: Integer;
    /// <summary>고도리 점수(기본 5).</summary>
    GodoriPoints: Integer;
    /// <summary>홍단/청단/초단 각 점수(기본 3).</summary>
    DanPoints: Integer;

    /// <summary>고 1회당 추가 점수(기본 1).</summary>
    GoBonusPerGo: Integer;
    /// <summary>이 고 횟수부터 점수를 2배씩 불린다(기본 3 → 3고=×2, 4고=×4...).</summary>
    GoDoubleFromCount: Integer;
    /// <summary>피박 활성화(기본 True).</summary>
    PibakEnabled: Boolean;
    /// <summary>피박 판정 기준: 패자의 피값이 이 값 이하면 피박(기본 7).</summary>
    PibakMaxJunk: Integer;
    /// <summary>광박 활성화(기본 True). 승자가 광 점수를 냈고 패자 광 0장이면 2배.</summary>
    GwangbakEnabled: Boolean;
    /// <summary>멍박(열끗박) 활성화(기본 True). 승자가 멍따(열끗 다수)를 냈고 패자 열끗 0장이면 2배.</summary>
    MeongbakEnabled: Boolean;
    /// <summary>멍박(멍따) 판정 기준: 승자 열끗이 이 장수 이상이어야 멍박 성립(기본 7).</summary>
    MeongbakMinAnimal: Integer;
    /// <summary>
    ///   고박 배수(기본 2). 고를 부른 사람이 그 판에서 못 이기고 상대가 스톱해 이기면,
    ///   고를 부른 사람이 다른 패자 몫까지 전액을 이 배수로 물어준다(나머지 패자는 면제). 1이면 배수 없음.
    /// </summary>
    GobakMultiplier: Integer;

    /// <summary>널리 쓰이는 표준 규칙값을 반환합니다.</summary>
    class function Default: TScoreOptions; static;
  end;

  /// <summary>한 플레이어가 먹은 패의 점수 상세 내역(고·박 적용 전 족보 점수).</summary>
  TScoreBreakdown = record
    /// <summary>광 장수.</summary>
    BrightCount: Integer;
    /// <summary>광 점수.</summary>
    BrightPoints: Integer;
    /// <summary>열끗 장수(피로 지급된 국진은 쌍피로 계산되어 제외).</summary>
    AnimalCount: Integer;
    /// <summary>열끗 개수 점수.</summary>
    AnimalPoints: Integer;
    /// <summary>고도리 점수(성립 시 GodoriPoints, 아니면 0).</summary>
    GodoriPoints: Integer;
    /// <summary>띠 장수.</summary>
    RibbonCount: Integer;
    /// <summary>띠 개수 점수.</summary>
    RibbonPoints: Integer;
    /// <summary>홍단 점수.</summary>
    HongdanPoints: Integer;
    /// <summary>청단 점수.</summary>
    CheongdanPoints: Integer;
    /// <summary>초단 점수.</summary>
    ChodanPoints: Integer;
    /// <summary>피 총값(장수 기준, 쌍피=2·3피=3).</summary>
    JunkValue: Integer;
    /// <summary>피 점수.</summary>
    JunkPoints: Integer;
    /// <summary>족보 합계 점수(고·박 적용 전).</summary>
    Total: Integer;

    /// <summary>내역을 사람이 읽을 수 있는 문자열로 반환합니다.</summary>
    function ToString: string;
  end;

  /// <summary>정산 결과(한 패자가 승자에게 지불할 점수와 배수·박 정보).</summary>
  TSettlement = record
    /// <summary>최종 지불 점수(승자 기준 획득).</summary>
    Points: Integer;
    /// <summary>적용된 총 배수.</summary>
    Multiplier: Integer;
    /// <summary>고 보너스로 더해진 점수.</summary>
    GoBonus: Integer;
    /// <summary>고로만 적용된 배수(표시용, 예: 4고=4). 3고 미만이면 1.</summary>
    GoMultiplier: Integer;
    /// <summary>피박 적용 여부.</summary>
    Pibak: Boolean;
    /// <summary>광박 적용 여부.</summary>
    Gwangbak: Boolean;
    /// <summary>멍박(열끗박) 적용 여부.</summary>
    Meongbak: Boolean;
  end;

  /// <summary>먹은 패로부터 점수를 계산하고 고·박 정산을 수행하는 정적 계산기.</summary>
  TScorer = record
  public
    /// <summary>먹은 패 목록(리스트)의 족보 점수 내역을 계산합니다(고·박 적용 전, 할당 없이).</summary>
    /// <param name="ACaptured">플레이어가 먹은 카드 리스트.</param>
    /// <param name="AOptions">점수 규칙 옵션.</param>
    class function Evaluate(const ACaptured: TList<THwatuCard>; const AOptions: TScoreOptions): TScoreBreakdown; overload; static;
    /// <summary>먹은 패 목록(배열)의 족보 점수 내역을 계산합니다(고·박 적용 전).</summary>
    /// <param name="ACaptured">플레이어가 먹은 카드 배열.</param>
    /// <param name="AOptions">점수 규칙 옵션.</param>
    class function Evaluate(const ACaptured: array of THwatuCard; const AOptions: TScoreOptions): TScoreBreakdown; overload; static;
    /// <summary>
    ///   패자 관점으로 족보 내역을 계산합니다. 소유 국진이 있으면 <see cref="Evaluate"/>처럼
    ///   총점이 아니라 "피박을 면하는지"를 우선 기준으로 열끗/쌍피 해석을 고릅니다(패자의 총점 자체는
    ///   정산에 쓰이지 않고 피값·광 장수·열끗 장수 문턱만 쓰이므로, 점수보다 피박 회피가 항상 유리함).
    ///   피박 회피 여부가 두 해석에서 같으면(둘 다 면함/둘 다 못 면함) 그때는 총점이 높은 쪽을 고릅니다.
    /// </summary>
    /// <param name="ACaptured">플레이어가 먹은 카드 리스트.</param>
    /// <param name="AOptions">점수 규칙 옵션.</param>
    class function EvaluateAsLoser(const ACaptured: TList<THwatuCard>; const AOptions: TScoreOptions): TScoreBreakdown; static;
    /// <summary>
    ///   승자가 한 패자로부터 받을 점수를 고·흔들기·피박·광박을 반영해 정산합니다.
    /// </summary>
    /// <param name="AWinner">승자 족보 내역.</param>
    /// <param name="ALoser">패자 족보 내역.</param>
    /// <param name="AGoCount">승자 고 횟수.</param>
    /// <param name="AShakeCount">승자 흔들기 횟수(각 ×2).</param>
    /// <param name="AOptions">점수 규칙 옵션.</param>
    class function Settle(const AWinner: TScoreBreakdown; const ALoser: TScoreBreakdown;
      const AGoCount: Integer; const AShakeCount: Integer; const AOptions: TScoreOptions): TSettlement; static;
  end;

implementation

{$REGION 'TScoreOptions'}
class function TScoreOptions.Default: TScoreOptions;
begin
  Result.Bright3 := 3;
  Result.Bright3WithBi := 2;
  Result.Bright4 := 4;
  Result.Bright5 := 15;
  Result.AnimalThreshold := 5;
  Result.RibbonThreshold := 5;
  Result.JunkThreshold := 10;
  Result.GodoriPoints := 5;
  Result.DanPoints := 3;
  Result.GoBonusPerGo := 1;
  Result.GoDoubleFromCount := 3;
  Result.PibakEnabled := True;
  Result.PibakMaxJunk := 7;
  Result.GwangbakEnabled := True;
  Result.MeongbakEnabled := True;
  Result.MeongbakMinAnimal := 7;
  Result.GobakMultiplier := 2;
end;
{$ENDREGION}

{$REGION 'TScoreBreakdown'}
function TScoreBreakdown.ToString: string;
begin
  Result := Format(
    '총 %d점 [광 %d장=%d, 열끗 %d장=%d(고도리 %d), 띠 %d장=%d(홍%d 청%d 초%d), 피값 %d=%d]',
    [Total, BrightCount, BrightPoints, AnimalCount, AnimalPoints, GodoriPoints,
     RibbonCount, RibbonPoints, HongdanPoints, CheongdanPoints, ChodanPoints,
     JunkValue, JunkPoints]);
end;
{$ENDREGION}

{$REGION 'TScorer'}
class function TScorer.Evaluate(const ACaptured: array of THwatuCard; const AOptions: TScoreOptions): TScoreBreakdown;
begin
  // 배열 버전은 리스트 버전에 위임(테스트·저빈도용). 핫패스는 TList 오버로드를 쓴다.
  var LList := TList<THwatuCard>.Create;
  try
    for var LCard in ACaptured do
    begin
      LList.Add(LCard);
    end;

    Result := Evaluate(LList, AOptions);
  finally
    LList.Free;
  end;
end;

// 먹은 패의 족보 점수를 단일-패스로 계산(내부용).
// 국진: 쌍피 전환권을 잃은(GukjinLocked) 국진은 항상 열끗. 그 외 소유 국진은 AGukjinAsPi에 따라 열끗/쌍피로 계산한다.
function DoEvaluate(const ACaptured: TList<THwatuCard>; const AOptions: TScoreOptions;
  const AGukjinAsPi: Boolean): TScoreBreakdown;
var
  LHasBi: Boolean;
  LGodoriCount: Integer;
  LHong: Integer;
  LCheong: Integer;
  LCho: Integer;
begin
  Result := Default(TScoreBreakdown);
  LHasBi := False;
  LGodoriCount := 0;
  LHong := 0;
  LCheong := 0;
  LCho := 0;

  for var LI := 0 to ACaptured.Count - 1 do
  begin
    var LCard := ACaptured[LI];
    case LCard.Kind of
      hkBright:
        begin
          Inc(Result.BrightCount);
          if LCard.IsBiGwang then
          begin
            LHasBi := True;
          end;
        end;

      hkAnimal:
        begin
          // 쌍피 전환권을 잃은 국진은 항상 열끗. 그 외 소유 국진은 호출자가 정한 해석(AGukjinAsPi)을 따른다
          if LCard.IsGukjin and (not LCard.GukjinLocked) and AGukjinAsPi then
          begin
            Inc(Result.JunkValue, 2);
          end
          else
          begin
            Inc(Result.AnimalCount);
            if LCard.IsGodori then
            begin
              Inc(LGodoriCount);
            end;
          end;
        end;

      hkRibbon:
        begin
          Inc(Result.RibbonCount);
          case LCard.Ribbon of
            rkHong:
              begin
                Inc(LHong);
              end;
            rkCheong:
              begin
                Inc(LCheong);
              end;
            rkCho:
              begin
                Inc(LCho);
              end;
          end;
        end;

      hkJunk, hkBonus:
        begin
          Inc(Result.JunkValue, LCard.JunkValue);
        end;
    end;
  end;

  // 광
  if Result.BrightCount >= 5 then
  begin
    Result.BrightPoints := AOptions.Bright5;
  end
  else
  if Result.BrightCount = 4 then
  begin
    Result.BrightPoints := AOptions.Bright4;
  end
  else
  if Result.BrightCount = 3 then
  begin
    if LHasBi then
    begin
      Result.BrightPoints := AOptions.Bright3WithBi;
    end
    else
    begin
      Result.BrightPoints := AOptions.Bright3;
    end;
  end;

  // 열끗(개수) + 고도리
  if Result.AnimalCount >= AOptions.AnimalThreshold then
  begin
    Result.AnimalPoints := Result.AnimalCount - (AOptions.AnimalThreshold - 1);
  end;

  if LGodoriCount >= 3 then
  begin
    Result.GodoriPoints := AOptions.GodoriPoints;
  end;

  // 띠(개수) + 홍/청/초단
  if Result.RibbonCount >= AOptions.RibbonThreshold then
  begin
    Result.RibbonPoints := Result.RibbonCount - (AOptions.RibbonThreshold - 1);
  end;

  if LHong >= 3 then
  begin
    Result.HongdanPoints := AOptions.DanPoints;
  end;

  if LCheong >= 3 then
  begin
    Result.CheongdanPoints := AOptions.DanPoints;
  end;

  if LCho >= 3 then
  begin
    Result.ChodanPoints := AOptions.DanPoints;
  end;

  // 피
  if Result.JunkValue >= AOptions.JunkThreshold then
  begin
    Result.JunkPoints := Result.JunkValue - (AOptions.JunkThreshold - 1);
  end;

  Result.Total :=
    Result.BrightPoints +
    Result.AnimalPoints + Result.GodoriPoints +
    Result.RibbonPoints + Result.HongdanPoints + Result.CheongdanPoints + Result.ChodanPoints +
    Result.JunkPoints;
end;

class function TScorer.Evaluate(const ACaptured: TList<THwatuCard>; const AOptions: TScoreOptions): TScoreBreakdown;
begin
  // 기본: 소유 국진은 열끗으로 계산. 전환권이 남은 소유 국진이 있으면 쌍피 해석도 계산해 유리한 쪽을 자동 선택한다.
  // (쌍피 전환권을 잃은 국진은 두 해석 모두에서 항상 열끗)
  Result := DoEvaluate(ACaptured, AOptions, False);
  for var LCard in ACaptured do
  begin
    if LCard.IsGukjin and (not LCard.GukjinLocked) then
    begin
      var LAsPi := DoEvaluate(ACaptured, AOptions, True);
      if LAsPi.Total > Result.Total then
      begin
        Result := LAsPi;
      end;

      Break;
    end;
  end;
end;

// 이 피값이면 피박을 면하는지(0장이면 면제, 기준 초과면 면제 — Settle의 피박 판정과 동일 기준)
function IsPibakSafe(const AJunkValue: Integer; const AOptions: TScoreOptions): Boolean;
begin
  Result := (AJunkValue = 0) or (AJunkValue > AOptions.PibakMaxJunk);
end;

class function TScorer.EvaluateAsLoser(const ACaptured: TList<THwatuCard>; const AOptions: TScoreOptions): TScoreBreakdown;
begin
  Result := DoEvaluate(ACaptured, AOptions, False);

  var LHasOwnedGukjin := False;
  for var LCard in ACaptured do
  begin
    if LCard.IsGukjin and (not LCard.GukjinLocked) then
    begin
      LHasOwnedGukjin := True;
      Break;
    end;
  end;

  if not LHasOwnedGukjin then
  begin
    Exit;
  end;

  var LAsPi := DoEvaluate(ACaptured, AOptions, True);
  var LAnimalSafe := IsPibakSafe(Result.JunkValue, AOptions);
  var LPiSafe := IsPibakSafe(LAsPi.JunkValue, AOptions);

  if LPiSafe and (not LAnimalSafe) then
  begin
    // 쌍피로 봐야만 피박을 면함 → 총점이 낮아져도 그쪽을 선택(패자 총점은 정산에 안 쓰임)
    Result := LAsPi;
  end
  else
  if (LAnimalSafe = LPiSafe) and (LAsPi.Total > Result.Total) then
  begin
    // 피박 면부가 두 해석에서 같으면(둘 다 면하거나 둘 다 못 면하거나) 그때는 총점 높은 쪽
    Result := LAsPi;
  end;
end;

class function TScorer.Settle(const AWinner: TScoreBreakdown; const ALoser: TScoreBreakdown;
  const AGoCount: Integer; const AShakeCount: Integer; const AOptions: TScoreOptions): TSettlement;
begin
  Result := Default(TSettlement);

  // 고 보너스(가산) + 고 배수
  Result.GoBonus := AGoCount * AOptions.GoBonusPerGo;
  var LBase := AWinner.Total + Result.GoBonus;

  Result.Multiplier := 1;
  if AGoCount >= AOptions.GoDoubleFromCount then
  begin
    Result.Multiplier := Result.Multiplier * (1 shl Min(AGoCount - (AOptions.GoDoubleFromCount - 1), 10));
  end;
  Result.GoMultiplier := Result.Multiplier;

  // 흔들기: 각 ×2
  if AShakeCount > 0 then
  begin
    Result.Multiplier := Result.Multiplier * (1 shl Min(AShakeCount, 10));
  end;

  // 광박: 승자가 광 점수를 냈고 패자가 광을 하나도 못 먹음
  if AOptions.GwangbakEnabled and (AWinner.BrightPoints > 0) and (ALoser.BrightCount = 0) then
  begin
    Result.Gwangbak := True;
    Result.Multiplier := Result.Multiplier * 2;
  end;

  // 피박: 승자가 피 점수를 냈고 패자의 피값이 기준 이하. 단, 피가 한 장도 없으면(피값 0) 면제
  if AOptions.PibakEnabled and (AWinner.JunkPoints > 0) and (ALoser.JunkValue > 0)
    and (ALoser.JunkValue <= AOptions.PibakMaxJunk) then
  begin
    Result.Pibak := True;
    Result.Multiplier := Result.Multiplier * 2;
  end;

  // 멍박(열끗박): 승자가 멍따(열끗 MeongbakMinAnimal장 이상)로 열끗 점수를 냈고 패자 열끗 0장
  if AOptions.MeongbakEnabled and (AWinner.AnimalPoints > 0)
    and (AWinner.AnimalCount >= AOptions.MeongbakMinAnimal) and (ALoser.AnimalCount = 0) then
  begin
    Result.Meongbak := True;
    Result.Multiplier := Result.Multiplier * 2;
  end;

  Result.Points := LBase * Result.Multiplier;
end;
{$ENDREGION}

end.
