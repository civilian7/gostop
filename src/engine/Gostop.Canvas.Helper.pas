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
  end;

implementation

const
  ALL_CORNERS = [TCorner.TopLeft, TCorner.TopRight, TCorner.BottomLeft, TCorner.BottomRight];

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
{$ENDREGION}

end.
