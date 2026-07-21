unit Gostop.Canvas.Helper;

interface

{$REGION 'uses'}
uses
  System.Types,
  System.UITypes,
  FMX.Types,
  FMX.Graphics;
{$ENDREGION}

type
  /// <summary>
  ///   보드 렌더링에서 반복되는 Canvas 패턴을 한 줄로 줄이는 <c>TCanvas</c> 클래스 헬퍼.
  ///   기존 코드가 매번 하던 브러시 설정 + 4모서리 둥근 사각형/원 그리기를 그대로 캡슐화한다
  ///   (동작·출력 동일, 호출부만 간결).
  /// </summary>
  TGostopCanvasHelper = class helper for TCanvas
  public
    /// <summary>단색으로 채운 둥근 사각형(4모서리 동일 반경).</summary>
    procedure FillRound(const R: TRectF; const ARadius: Single; const AColor: TAlphaColor);
    /// <summary>단색 테두리 둥근 사각형(4모서리 동일 반경).</summary>
    procedure StrokeRound(const R: TRectF; const ARadius: Single; const AColor: TAlphaColor; const AThickness: Single = 1);
    /// <summary>단색으로 채운 타원/원.</summary>
    procedure FillCircle(const R: TRectF; const AColor: TAlphaColor);
    /// <summary>단색 테두리 타원/원.</summary>
    procedure StrokeCircle(const R: TRectF; const AColor: TAlphaColor; const AThickness: Single = 1);
    /// <summary>사각형 안에 게임 전역 글꼴로 가운데 정렬 텍스트를 그린다(색·크기·굵기 지정).</summary>
    procedure DrawLabel(const R: TRectF; const AText: string; const AColor: TAlphaColor;
      const ASize: Single; const ABold: Boolean = False);
  end;

/// <summary>색의 RGB 각 채널을 ADelta 만큼 밝게(양수)/어둡게(음수) 조정한다(hover·pressed 명암용).</summary>
function AdjustColor(const AColor: TAlphaColor; const ADelta: Integer): TAlphaColor;

implementation

{$REGION 'uses'}
uses
  System.Math,
  Gostop.Fonts;
{$ENDREGION}

const
  ALL_CORNERS = [TCorner.TopLeft, TCorner.TopRight, TCorner.BottomLeft, TCorner.BottomRight];

function AdjustColor(const AColor: TAlphaColor; const ADelta: Integer): TAlphaColor;
begin
  var LRec := TAlphaColorRec(AColor);
  LRec.R := EnsureRange(LRec.R + ADelta, 0, 255);
  LRec.G := EnsureRange(LRec.G + ADelta, 0, 255);
  LRec.B := EnsureRange(LRec.B + ADelta, 0, 255);
  Result := LRec.Color;
end;

{$REGION 'TGostopCanvasHelper'}
procedure TGostopCanvasHelper.FillRound(const R: TRectF; const ARadius: Single; const AColor: TAlphaColor);
begin
  Self.Fill.Kind := TBrushKind.Solid;
  Self.Fill.Color := AColor;
  Self.FillRect(R, ARadius, ARadius, ALL_CORNERS, 1);
end;

procedure TGostopCanvasHelper.StrokeRound(const R: TRectF; const ARadius: Single; const AColor: TAlphaColor; const AThickness: Single);
begin
  Self.Stroke.Kind := TBrushKind.Solid;
  Self.Stroke.Color := AColor;
  Self.Stroke.Thickness := AThickness;
  Self.DrawRect(R, ARadius, ARadius, ALL_CORNERS, 1);
end;

procedure TGostopCanvasHelper.FillCircle(const R: TRectF; const AColor: TAlphaColor);
begin
  Self.Fill.Kind := TBrushKind.Solid;
  Self.Fill.Color := AColor;
  Self.FillEllipse(R, 1);
end;

procedure TGostopCanvasHelper.StrokeCircle(const R: TRectF; const AColor: TAlphaColor; const AThickness: Single);
begin
  Self.Stroke.Kind := TBrushKind.Solid;
  Self.Stroke.Color := AColor;
  Self.Stroke.Thickness := AThickness;
  Self.DrawEllipse(R, 1);
end;

procedure TGostopCanvasHelper.DrawLabel(const R: TRectF; const AText: string; const AColor: TAlphaColor;
  const ASize: Single; const ABold: Boolean);
begin
  Self.Fill.Kind := TBrushKind.Solid;
  Self.Fill.Color := AColor;
  TGostopFonts.Apply(Self, ASize, ABold);
  Self.FillText(R, AText, False, 1, [], TTextAlign.Center, TTextAlign.Center);
end;
{$ENDREGION}

end.
