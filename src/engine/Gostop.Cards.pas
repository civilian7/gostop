unit Gostop.Cards;

interface

{$REGION 'uses'}
uses
  System.SysUtils,
  System.Generics.Collections;
{$ENDREGION}

type
  /// <summary>화투 카드의 종류(족보 분류).</summary>
  THwatuKind = (
    hkBright,   // 광(光)
    hkAnimal,   // 열끗(십)
    hkRibbon,   // 띠(단)
    hkJunk,     // 피(껍데기)
    hkBonus     // 보너스패(조커)
  );

  THwatuKindHelper = record helper for THwatuKind
    /// <summary>종류의 한글 명칭을 반환합니다. (광/열끗/띠/피/보너스)</summary>
    function ToString: string;
  end;

  /// <summary>띠(단) 카드의 색 분류.</summary>
  TRibbonKind = (
    rkNone,     // 띠 아님 또는 일반 띠(예: 12월 비 띠)
    rkHong,     // 홍단
    rkCheong,   // 청단
    rkCho       // 초단
  );

  TRibbonKindHelper = record helper for TRibbonKind
    /// <summary>띠 색 분류의 한글 명칭을 반환합니다.</summary>
    function ToString: string;
  end;

  /// <summary>
  ///   화투 카드 한 장을 나타내는 값 타입(레코드).
  ///   식별 정보(월·종류·순번·에셋 ID)와 점수 계산에 필요한 메타(피 값·고도리·비광·국진·띠 색)를 담는다.
  /// </summary>
  THwatuCard = record
  public
    /// <summary>월(1~12). 보너스패는 0.</summary>
    Month: Integer;
    /// <summary>카드 종류(족보 분류).</summary>
    Kind: THwatuKind;
    /// <summary>같은 월·종류 내 구분 순번(피 1/2/3 등). 1부터 시작.</summary>
    Ordinal: Integer;
    /// <summary>이미지 파일 stem(확장자 제외). 예: 'november_kasu_1', 'bonus_sampi'.</summary>
    AssetId: string;
    /// <summary>피로 계산될 때의 값. 0=피 아님, 1=일반 피, 2=쌍피, 3=3피.</summary>
    JunkValue: Integer;
    /// <summary>띠 색 분류(홍단/청단/초단). 띠가 아니면 rkNone.</summary>
    Ribbon: TRibbonKind;
    /// <summary>고도리 새(2월 매조·4월 흑싸리·8월 공산 열끗)이면 True.</summary>
    IsGodori: Boolean;
    /// <summary>비광(12월 비의 광)이면 True. 3광 계산 시 특별 취급.</summary>
    IsBiGwang: Boolean;
    /// <summary>국진(9월 국화 열끗)이면 True. 룰에 따라 쌍피로 사용 가능.</summary>
    IsGukjin: Boolean;
    /// <summary>
    ///   국진 전용: 피 뺏기 대상인데 낼 일반 피가 하나도 없어 국진 자신도 넘기지 않고 버틴 경우 True.
    ///   이후 이 판에서는 열끗↔쌍피 자동 전환 권한을 잃고 항상 열끗으로만 계산된다.
    /// </summary>
    GukjinLocked: Boolean;

    /// <summary>사람이 읽을 수 있는 한글 카드 이름을 반환합니다. 예: '11월 똥 광'.</summary>
    function DisplayName: string;
    /// <summary>이미지 파일명을 반환합니다. 예: ImageFileName('png') → 'january_hikari.png'.</summary>
    /// <param name="AExt">확장자(점 제외). 기본값 'png'.</param>
    function ImageFileName(const AExt: string = 'png'): string;
  end;

  /// <summary>표준 화투 카드 정본(定本) 테이블을 제공하는 정적 카탈로그.</summary>
  THwatuCatalog = record
  public
    /// <summary>표준 48장 카드 배열을 생성해 반환합니다(월 1→12, 종류 순).</summary>
    class function Standard: TArray<THwatuCard>; static;
    /// <summary>보너스패 3장 배열을 생성해 반환합니다(쌍피 2 · 3피 1). 실물 정통 구성.</summary>
    class function Bonus: TArray<THwatuCard>; static;
  end;

  /// <summary>화투/고스톱 도메인 공통 베이스 예외.</summary>
  EHwatuError = class(Exception);

implementation

{$REGION 'THwatuKindHelper'}
function THwatuKindHelper.ToString: string;
begin
  case Self of
    hkBright:
      begin
        Result := '광';
      end;
    hkAnimal:
      begin
        Result := '열끗';
      end;
    hkRibbon:
      begin
        Result := '띠';
      end;
    hkJunk:
      begin
        Result := '피';
      end;
    hkBonus:
      begin
        Result := '보너스';
      end;
  else
    begin
      Result := '';
    end;
  end;
end;
{$ENDREGION}

{$REGION 'TRibbonKindHelper'}
function TRibbonKindHelper.ToString: string;
begin
  case Self of
    rkHong:
      begin
        Result := '홍단';
      end;
    rkCheong:
      begin
        Result := '청단';
      end;
    rkCho:
      begin
        Result := '초단';
      end;
  else
    begin
      Result := '';
    end;
  end;
end;
{$ENDREGION}

{$REGION 'THwatuCard'}
const
  // 월별 한글 명칭(1~12). 화투 관례: 11월=똥, 12월=비.
  MONTH_NAMES: array [1 .. 12] of string = (
    '송학', '매조', '벚꽃', '흑싸리', '난초', '모란',
    '홍싸리', '공산', '국화', '단풍', '똥', '비'
  );

function THwatuCard.DisplayName: string;
begin
  if Kind = hkBonus then
  begin
    case JunkValue of
      3:
        begin
          Result := '보너스 3피';
        end;
      2:
        begin
          Result := '보너스 쌍피';
        end;
    else
      begin
        Result := '보너스패';
      end;
    end;

    Exit;
  end;

  if (Month < 1) or (Month > 12) then
  begin
    Result := AssetId;
    Exit;
  end;

  if Kind = hkJunk then
  begin
    Result := Format('%d월 %s 피%d', [Month, MONTH_NAMES[Month], Ordinal]);
    Exit;
  end;

  Result := Format('%d월 %s %s', [Month, MONTH_NAMES[Month], Kind.ToString]);
end;

function THwatuCard.ImageFileName(const AExt: string): string;
begin
  Result := AssetId + '.' + AExt;
end;
{$ENDREGION}

{$REGION 'THwatuCatalog'}
class function THwatuCatalog.Standard: TArray<THwatuCard>;
var
  LList: TList<THwatuCard>;

  procedure Add(const AMonth: Integer; const AKind: THwatuKind; const AOrdinal: Integer;
    const AAssetId: string; const AJunkValue: Integer; const ARibbon: TRibbonKind;
    const AGodori: Boolean; const ABiGwang: Boolean; const AGukjin: Boolean);
  var
    LCard: THwatuCard;
  begin
    LCard := Default(THwatuCard);
    LCard.Month := AMonth;
    LCard.Kind := AKind;
    LCard.Ordinal := AOrdinal;
    LCard.AssetId := AAssetId;
    LCard.JunkValue := AJunkValue;
    LCard.Ribbon := ARibbon;
    LCard.IsGodori := AGodori;
    LCard.IsBiGwang := ABiGwang;
    LCard.IsGukjin := AGukjin;
    LList.Add(LCard);
  end;

begin
  LList := TList<THwatuCard>.Create;
  try
    // 1월 송학: 광 · 홍단 · 피2
    Add(1, hkBright, 1, 'january_hikari', 0, rkNone, False, False, False);
    Add(1, hkRibbon, 1, 'january_tanzaku', 0, rkHong, False, False, False);
    Add(1, hkJunk, 1, 'january_kasu_1', 1, rkNone, False, False, False);
    Add(1, hkJunk, 2, 'january_kasu_2', 1, rkNone, False, False, False);

    // 2월 매조: 열끗(고도리) · 홍단 · 피2
    Add(2, hkAnimal, 1, 'february_tane', 0, rkNone, True, False, False);
    Add(2, hkRibbon, 1, 'february_tanzaku', 0, rkHong, False, False, False);
    Add(2, hkJunk, 1, 'february_kasu_1', 1, rkNone, False, False, False);
    Add(2, hkJunk, 2, 'february_kasu_2', 1, rkNone, False, False, False);

    // 3월 벚꽃: 광 · 홍단 · 피2
    Add(3, hkBright, 1, 'march_hikari', 0, rkNone, False, False, False);
    Add(3, hkRibbon, 1, 'march_tanzaku', 0, rkHong, False, False, False);
    Add(3, hkJunk, 1, 'march_kasu_1', 1, rkNone, False, False, False);
    Add(3, hkJunk, 2, 'march_kasu_2', 1, rkNone, False, False, False);

    // 4월 흑싸리: 열끗(고도리) · 초단 · 피2
    Add(4, hkAnimal, 1, 'april_tane', 0, rkNone, True, False, False);
    Add(4, hkRibbon, 1, 'april_tanzaku', 0, rkCho, False, False, False);
    Add(4, hkJunk, 1, 'april_kasu_1', 1, rkNone, False, False, False);
    Add(4, hkJunk, 2, 'april_kasu_2', 1, rkNone, False, False, False);

    // 5월 난초: 열끗 · 초단 · 피2
    Add(5, hkAnimal, 1, 'may_tane', 0, rkNone, False, False, False);
    Add(5, hkRibbon, 1, 'may_tanzaku', 0, rkCho, False, False, False);
    Add(5, hkJunk, 1, 'may_kasu_1', 1, rkNone, False, False, False);
    Add(5, hkJunk, 2, 'may_kasu_2', 1, rkNone, False, False, False);

    // 6월 모란: 열끗 · 청단 · 피2
    Add(6, hkAnimal, 1, 'june_tane', 0, rkNone, False, False, False);
    Add(6, hkRibbon, 1, 'june_tanzaku', 0, rkCheong, False, False, False);
    Add(6, hkJunk, 1, 'june_kasu_1', 1, rkNone, False, False, False);
    Add(6, hkJunk, 2, 'june_kasu_2', 1, rkNone, False, False, False);

    // 7월 홍싸리: 열끗 · 초단 · 피2
    Add(7, hkAnimal, 1, 'july_tane', 0, rkNone, False, False, False);
    Add(7, hkRibbon, 1, 'july_tanzaku', 0, rkCho, False, False, False);
    Add(7, hkJunk, 1, 'july_kasu_1', 1, rkNone, False, False, False);
    Add(7, hkJunk, 2, 'july_kasu_2', 1, rkNone, False, False, False);

    // 8월 공산: 광 · 열끗(고도리) · 피2
    Add(8, hkBright, 1, 'august_hikari', 0, rkNone, False, False, False);
    Add(8, hkAnimal, 1, 'august_tane', 0, rkNone, True, False, False);
    Add(8, hkJunk, 1, 'august_kasu_1', 1, rkNone, False, False, False);
    Add(8, hkJunk, 2, 'august_kasu_2', 1, rkNone, False, False, False);

    // 9월 국화: 열끗(국진) · 청단 · 피2
    Add(9, hkAnimal, 1, 'september_tane', 0, rkNone, False, False, True);
    Add(9, hkRibbon, 1, 'september_tanzaku', 0, rkCheong, False, False, False);
    Add(9, hkJunk, 1, 'september_kasu_1', 1, rkNone, False, False, False);
    Add(9, hkJunk, 2, 'september_kasu_2', 1, rkNone, False, False, False);

    // 10월 단풍: 열끗 · 청단 · 피2
    Add(10, hkAnimal, 1, 'october_tane', 0, rkNone, False, False, False);
    Add(10, hkRibbon, 1, 'october_tanzaku', 0, rkCheong, False, False, False);
    Add(10, hkJunk, 1, 'october_kasu_1', 1, rkNone, False, False, False);
    Add(10, hkJunk, 2, 'october_kasu_2', 1, rkNone, False, False, False);

    // 11월 똥: 똥광 · 똥쌍피 · 똥피2
    Add(11, hkBright, 1, 'november_hikari', 0, rkNone, False, False, False);
    Add(11, hkJunk, 1, 'november_kasu_1', 1, rkNone, False, False, False);
    Add(11, hkJunk, 2, 'november_kasu_2', 1, rkNone, False, False, False);
    Add(11, hkJunk, 3, 'november_kasu_3', 2, rkNone, False, False, False);   // 똥쌍피

    // 12월 비: 광(비광) · 열끗 · 띠 · 쌍피(비쌍피=2피)
    Add(12, hkBright, 1, 'december_hikari', 0, rkNone, False, True, False);
    Add(12, hkAnimal, 1, 'december_tane', 0, rkNone, False, False, False);
    Add(12, hkRibbon, 1, 'december_tanzaku', 0, rkNone, False, False, False);
    Add(12, hkJunk, 1, 'december_kasu', 2, rkNone, False, False, False);   // 비쌍피(실물 12월 비 피는 쌍피)

    Result := LList.ToArray;
  finally
    LList.Free;
  end;
end;

class function THwatuCatalog.Bonus: TArray<THwatuCard>;
var
  LList: TList<THwatuCard>;

  procedure Add(const AOrdinal: Integer; const AAssetId: string; const AJunkValue: Integer);
  var
    LCard: THwatuCard;
  begin
    LCard := Default(THwatuCard);
    LCard.Month := 0;
    LCard.Kind := hkBonus;
    LCard.Ordinal := AOrdinal;
    LCard.AssetId := AAssetId;
    LCard.JunkValue := AJunkValue;
    LCard.Ribbon := rkNone;
    LList.Add(LCard);
  end;

begin
  LList := TList<THwatuCard>.Create;
  try
    Add(1, 'bonus_ssangpi_1', 2);
    Add(2, 'bonus_ssangpi_2', 2);
    Add(3, 'bonus_sampi', 3);
    Result := LList.ToArray;
  finally
    LList.Free;
  end;
end;
{$ENDREGION}

end.
