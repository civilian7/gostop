unit Gostop.Score;

interface

{$REGION 'uses'}
uses
  System.SysUtils,
  Gostop.Cards;
{$ENDREGION}

type
  /// <summary>
  ///   점수 계산 규칙 옵션(지역 룰 편차 흡수용). <see cref="Default"/>는 널리 쓰이는 표준값을 반환한다.
  /// </summary>
  TScoreOptions = record
    /// <summary>국진(9월 열끗)을 쌍피(피값 2)로 계산할지 여부. False면 열끗으로 계산.</summary>
    GukjinAsDoubleJunk: Boolean;
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

    /// <summary>널리 쓰이는 표준 규칙값을 반환합니다.</summary>
    class function Default: TScoreOptions; static;
  end;

  /// <summary>한 플레이어가 먹은 패의 점수 상세 내역(고·박 적용 전 족보 점수).</summary>
  TScoreBreakdown = record
    /// <summary>광 장수.</summary>
    BrightCount: Integer;
    /// <summary>광 점수.</summary>
    BrightPoints: Integer;
    /// <summary>열끗 장수(국진을 쌍피로 계산 시 제외).</summary>
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
    /// <summary>피박 적용 여부.</summary>
    Pibak: Boolean;
    /// <summary>광박 적용 여부.</summary>
    Gwangbak: Boolean;
  end;

  /// <summary>먹은 패로부터 점수를 계산하고 고·박 정산을 수행하는 정적 계산기.</summary>
  TScorer = record
  public
    /// <summary>먹은 패 목록의 족보 점수 내역을 계산합니다(고·박 적용 전).</summary>
    /// <param name="ACaptured">플레이어가 먹은 카드 배열.</param>
    /// <param name="AOptions">점수 규칙 옵션.</param>
    class function Evaluate(const ACaptured: array of THwatuCard; const AOptions: TScoreOptions): TScoreBreakdown; static;
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
  Result.GukjinAsDoubleJunk := False;
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

  for var LCard in ACaptured do
  begin
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
          // 국진을 쌍피로 계산하는 옵션이면 열끗에서 제외하고 피값에 가산
          if LCard.IsGukjin and AOptions.GukjinAsDoubleJunk then
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
    Result.Multiplier := Result.Multiplier * (1 shl (AGoCount - (AOptions.GoDoubleFromCount - 1)));
  end;

  // 흔들기: 각 ×2
  if AShakeCount > 0 then
  begin
    Result.Multiplier := Result.Multiplier * (1 shl AShakeCount);
  end;

  // 광박: 승자가 광 점수를 냈고 패자가 광을 하나도 못 먹음
  if AOptions.GwangbakEnabled and (AWinner.BrightPoints > 0) and (ALoser.BrightCount = 0) then
  begin
    Result.Gwangbak := True;
    Result.Multiplier := Result.Multiplier * 2;
  end;

  // 피박: 승자가 피 점수를 냈고 패자의 피값이 기준 이하
  if AOptions.PibakEnabled and (AWinner.JunkPoints > 0) and (ALoser.JunkValue <= AOptions.PibakMaxJunk) then
  begin
    Result.Pibak := True;
    Result.Multiplier := Result.Multiplier * 2;
  end;

  Result.Points := LBase * Result.Multiplier;
end;
{$ENDREGION}

end.
