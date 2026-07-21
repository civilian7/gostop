unit Gostop.Board.Dialog;

// 다이얼로그 공통 프레임(옻칠 목함 느낌 + 팝인 스케일). 게임 상태에 의존하지 않고 Canvas·화면 rect·
// 제목·팝인 진행도만 받아 그린다 — 순수 렌더. 팝인 상태 추적(어느 다이얼로그가 열렸는지, 진행도)은
// 보드 도메인이라 보드에 남고, 여기는 진행도(APopT) 값만 받는다. 각 다이얼로그의 '내용(세부)'은
// 이 프레임이 반환한 패널 rect 안에 각자 그린다.

interface

{$REGION 'uses'}
uses
  System.Types,
  System.Math.Vectors,
  FMX.Graphics;
{$ENDREGION}

type
  /// <summary>다이얼로그 공통 프레임 렌더러(순수 — 게임 상태 비의존).</summary>
  TDialogFrame = record
  public
    /// <summary>
    ///   배경 딤 + 목함 배경 + 금테 + 제목을 그리고, 팝인 진행도(APopT 0~1)에 따라 등장 스케일 매트릭스를
    ///   적용한다. 내용이 프레임과 함께 스케일되도록, 그리기 전 매트릭스를 APrevMatrix 로 돌려주며
    ///   호출측은 내용을 다 그린 뒤 Restore 로 복원해야 한다. 반환값은 내용을 담을 패널 rect.
    /// </summary>
    class function Draw(const ACanvas: TCanvas; const AScreenRect: TRectF; const ATitle: string;
      const AWidth, AHeight, APopT: Single; out APrevMatrix: TMatrix): TRectF; static;
    /// <summary>팝인 매트릭스를 그리기 전 상태로 복원한다(Draw 가 돌려준 APrevMatrix 전달).</summary>
    class procedure Restore(const ACanvas: TCanvas; const APrevMatrix: TMatrix); static;
  end;

implementation

{$REGION 'uses'}
uses
  System.UITypes,
  System.Math,
  FMX.Types,
  Gostop.Canvas.Helper,
  Gostop.Palette;
{$ENDREGION}

class function TDialogFrame.Draw(const ACanvas: TCanvas; const AScreenRect: TRectF; const ATitle: string;
  const AWidth, AHeight, APopT: Single; out APrevMatrix: TMatrix): TRectF;
begin
  ACanvas.FillRound(AScreenRect, 0, TPalette.DialogDim);   // 배경 딤

  var LScreenCx := (AScreenRect.Left + AScreenRect.Right) / 2;
  var LScreenCy := (AScreenRect.Top + AScreenRect.Bottom) / 2;
  Result := RectF(LScreenCx - AWidth / 2, LScreenCy - AHeight / 2, LScreenCx + AWidth / 2, LScreenCy + AHeight / 2);

  APrevMatrix := ACanvas.Matrix;
  if APopT < 1 then
  begin
    // ease-out-back: 0에서 살짝 넘치듯(오버슈트) 1로 정착
    const OVERSHOOT = 1.70158;
    var LK := APopT - 1;
    var LBack := 1 + (OVERSHOOT + 1) * LK * LK * LK + OVERSHOOT * LK * LK;
    var LScale := 0.6 + LBack * 0.4;   // 60% 크기에서 시작해 튀며 100%로 정착

    var LCx := (Result.Left + Result.Right) / 2;
    var LCy := (Result.Top + Result.Bottom) / 2;
    var LMx := TMatrix.CreateTranslation(-LCx, -LCy) * TMatrix.CreateScaling(LScale, LScale) * TMatrix.CreateTranslation(LCx, LCy);
    ACanvas.SetMatrix(LMx * APrevMatrix);
  end;

  // 뒤에 그림자를 깔아 떠 있는 느낌
  ACanvas.FillRound(RectF(Result.Left + 5, Result.Top + 7, Result.Right + 5, Result.Bottom + 7), 18, TPalette.DialogShadow);

  // 옻칠 목함 느낌: 판(펠트)과 톤이 이어지는 짙은 녹색 세로 그라데이션 + 금테
  ACanvas.Fill.Kind := TBrushKind.Gradient;
  ACanvas.Fill.Gradient.Style := TGradientStyle.Linear;
  ACanvas.Fill.Gradient.StartPosition.Point := PointF(0.5, 0);
  ACanvas.Fill.Gradient.StopPosition.Point := PointF(0.5, 1);
  ACanvas.Fill.Gradient.Color := TPalette.DialogGradTop;
  ACanvas.Fill.Gradient.Color1 := TPalette.DialogGradBottom;
  ACanvas.FillRect(Result, 18, 18, [TCorner.TopLeft, TCorner.TopRight, TCorner.BottomLeft, TCorner.BottomRight], 1);
  ACanvas.Fill.Kind := TBrushKind.Solid;

  ACanvas.StrokeRound(Result, 18, TPalette.DialogGold, 2.5);   // 금색 외곽 테두리(액자 느낌)
  ACanvas.StrokeRound(RectF(Result.Left + 4, Result.Top + 4, Result.Right - 4, Result.Bottom - 4), 14, TPalette.DialogGoldInner, 1);   // 안쪽 이너라인

  if ATitle <> '' then
  begin
    // 제목: 그림자 얹은 금색 글자 + 아래 금색 구분선(중앙 ◆ 장식)으로 현판 느낌
    ACanvas.DrawLabel(RectF(Result.Left + 1, Result.Top + 18, Result.Right + 1, Result.Top + 52), ATitle, TPalette.TitleShadow, 22);
    ACanvas.DrawLabel(RectF(Result.Left, Result.Top + 16, Result.Right, Result.Top + 50), ATitle, TAlphaColors.Gold, 22);

    var LCx := (Result.Left + Result.Right) / 2;
    var LLineY := Result.Top + 56;
    var LHalf := Min(Result.Width * 0.30, 150.0);
    ACanvas.Fill.Kind := TBrushKind.Solid;
    ACanvas.Fill.Color := TPalette.DialogGoldLine;
    ACanvas.FillRect(RectF(LCx - LHalf, LLineY, LCx - 10, LLineY + 1), 0, 0, [], 1);
    ACanvas.FillRect(RectF(LCx + 10, LLineY, LCx + LHalf, LLineY + 1), 0, 0, [], 1);
    ACanvas.Fill.Color := TPalette.DialogGold;
    ACanvas.FillPolygon([PointF(LCx, LLineY - 4), PointF(LCx + 4, LLineY), PointF(LCx, LLineY + 4), PointF(LCx - 4, LLineY)], 1);
  end;
end;

class procedure TDialogFrame.Restore(const ACanvas: TCanvas; const APrevMatrix: TMatrix);
begin
  ACanvas.SetMatrix(APrevMatrix);
end;

end.
