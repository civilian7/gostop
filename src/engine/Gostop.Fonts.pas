unit Gostop.Fonts;

interface

{$REGION 'uses'}
uses
  System.UITypes,
  FMX.Graphics;
{$ENDREGION}

type
  /// <summary>
  ///   게임 전역 글꼴을 한 곳에서 관리하는 정적 헬퍼. 지금까지는 Canvas.Font.Family를 지정하는
  ///   코드가 어디에도 없어 플랫폼 기본 글꼴에 암묵적으로 의존했는데, 그러면 환경에 따라 다르게
  ///   보일 수 있어 명시적으로 통일한다.
  /// </summary>
  TGostopFonts = record
  public
    /// <summary>게임 전역에서 쓰는 기본 글꼴 이름을 반환합니다.</summary>
    class function FamilyName: string; static;
    /// <summary>지정 Canvas의 글꼴을 게임 전역 글꼴+크기로 맞춥니다(Canvas.Font.Size 단독 대입 대체).</summary>
    /// <param name="ACanvas">적용할 Canvas.</param>
    /// <param name="ASize">글꼴 크기(pt).</param>
    /// <param name="ABold">굵게 표시할지. Style을 항상 명시적으로 덮어써서 이전 그리기의 굵기가 새지 않게 한다.</param>
    class procedure Apply(const ACanvas: TCanvas; const ASize: Single; const ABold: Boolean = False); static;
  end;

implementation

const
  // 맑은 고딕 — Windows Vista 이후 기본 내장, 한글·라틴 문자 모두 가독성 좋은 UI 글꼴.
  // 지정 안 해도 지금까지 플랫폼이 알아서 비슷하게 대체해 왔지만, 환경마다 달라질 수 있어 명시한다.
  GOSTOP_FONT_FAMILY = '맑은 고딕';

class function TGostopFonts.FamilyName: string;
begin
  Result := GOSTOP_FONT_FAMILY;
end;

class procedure TGostopFonts.Apply(const ACanvas: TCanvas; const ASize: Single; const ABold: Boolean);
begin
  ACanvas.Font.Family := GOSTOP_FONT_FAMILY;
  ACanvas.Font.Size := ASize;
  // Style은 Canvas에 남아 다음 그리기까지 따라가므로 굵기 여부와 무관하게 매번 지정한다
  if ABold then
  begin
    ACanvas.Font.Style := [TFontStyle.fsBold];
  end
  else
  begin
    ACanvas.Font.Style := [];
  end;
end;

end.
