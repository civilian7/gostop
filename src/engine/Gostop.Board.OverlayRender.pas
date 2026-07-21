unit Gostop.Board.OverlayRender;

// 보드에서 빠져나온 오버레이/배지 렌더러. 게임 상태에 의존하지 않고 Canvas·좌표·표시 데이터만 받아
// 그린다(보드가 텍스트·좌표·오프셋 등을 값으로 뽑아 넘긴다). 말풍선·특수상황 배너·일시정지·획득 배지.

interface

{$REGION 'uses'}
uses
  System.Types,
  System.UITypes,
  FMX.Types,
  FMX.Graphics;
{$ENDREGION}

type
  /// <summary>오버레이/배지 렌더러(순수 렌더 — 게임 상태 비의존).</summary>
  TOverlayRender = record
  public
    /// <summary>캐릭터 말풍선. ADirX 는 아바타 기준 좌우 방향(+1=오른쪽, -1=왼쪽).</summary>
    class procedure SpeechBubble(const ACanvas: TCanvas; const AText: string; const AAvatarRect: TRectF;
      const ADirX: Single); static;
    /// <summary>특수 상황 배너(뻑!·따닥! 등). ACenterRect 는 중앙 영역, AShakeOffsetX 는 흔들림 상쇄용.</summary>
    class procedure EffectBanner(const ACanvas: TCanvas; const AText: string; const ACenterRect: TRectF;
      const AShakeOffsetX: Single); static;
    /// <summary>일시정지 딤 + 안내. AScreenRect 는 화면 전체(0,0,W,H).</summary>
    class procedure PauseOverlay(const ACanvas: TCanvas; const AScreenRect: TRectF); static;
    /// <summary>획득 패 그룹 장수 배지. ABadgeSize 는 보드가 계산한 배지 크기.</summary>
    class procedure CapturedCount(const ACanvas: TCanvas; const ACenterX, ACenterY: Single; const ACount: Integer;
      const ABadgeSize: TSizeF); static;
  end;

implementation

{$REGION 'uses'}
uses
  System.Math,
  System.SysUtils,
  Gostop.Canvas.Helper,
  Gostop.Fonts,
  Gostop.Palette;
{$ENDREGION}

{$REGION 'TOverlayRender'}
class procedure TOverlayRender.SpeechBubble(const ACanvas: TCanvas; const AText: string; const AAvatarRect: TRectF;
  const ADirX: Single);
const
  BUBBLE_FILL = TPalette.BubbleFill;
begin
  var LAvCx := (AAvatarRect.Left + AAvatarRect.Right) / 2;
  var LAvCy := (AAvatarRect.Top + AAvatarRect.Bottom) / 2;
  var LDX := ADirX;
  var LDY := 0.0;   // 방향은 좌우 고정이라 세로 성분은 항상 0

  TGostopFonts.Apply(ACanvas, 14);
  var LTextW := EnsureRange(ACanvas.TextWidth(AText) + 30, 70, 200);
  var LTextH := 40.0;

  var LOffset := AAvatarRect.Width / 2 + Max(LTextW, LTextH) / 2 + 14;
  var LBx := LAvCx + LDX * LOffset;
  var LBy := LAvCy + LDY * LOffset;
  var LR := RectF(LBx - LTextW / 2, LBy - LTextH / 2, LBx + LTextW / 2, LBy + LTextH / 2);

  ACanvas.FillRound(LR, 12, BUBBLE_FILL);
  ACanvas.StrokeRound(LR, 12, TPalette.BubbleBorder, 1.5);

  // 말꼬리: 말풍선에서 아바타를 향하는 작은 삼각형
  var LTailW := 14.0;
  var LTailLen := 12.0;
  var LTailBaseCx := LBx - LDX * (LTextW / 2 - 2);
  var LTailBaseCy := LBy - LDY * (LTextH / 2 - 2);
  var LPerpX := -LDY;
  var LPerpY := LDX;
  var LTailTip := PointF(LTailBaseCx - LDX * LTailLen, LTailBaseCy - LDY * LTailLen);
  var LTailP1 := PointF(LTailBaseCx + LPerpX * LTailW / 2, LTailBaseCy + LPerpY * LTailW / 2);
  var LTailP2 := PointF(LTailBaseCx - LPerpX * LTailW / 2, LTailBaseCy - LPerpY * LTailW / 2);
  ACanvas.Fill.Kind := TBrushKind.Solid;
  ACanvas.Fill.Color := BUBBLE_FILL;
  ACanvas.FillPolygon([LTailTip, LTailP1, LTailP2], 1);

  ACanvas.Fill.Color := TPalette.BubbleText;
  TGostopFonts.Apply(ACanvas, 14);
  ACanvas.FillText(LR, AText, True, 1, [], TTextAlign.Center, TTextAlign.Center);
end;

class procedure TOverlayRender.EffectBanner(const ACanvas: TCanvas; const AText: string; const ACenterRect: TRectF;
  const AShakeOffsetX: Single);
begin
  // 흔들기 연출 중이라도 배너는 제자리에 둔다(글자가 같이 떨리면 읽기 어렵다)
  var LMidX := (ACenterRect.Left + ACenterRect.Right) / 2 - AShakeOffsetX;
  var LMidY := (ACenterRect.Top + ACenterRect.Bottom) / 2;

  TGostopFonts.Apply(ACanvas, 42);
  var LRectW := ACanvas.TextWidth(AText) + 56;
  var LRectH := 78.0;
  var LRect := RectF(LMidX - LRectW / 2, LMidY - LRectH / 2, LMidX + LRectW / 2, LMidY + LRectH / 2);
  ACanvas.FillRound(LRect, 16, TPalette.BannerFill);
  ACanvas.StrokeRound(LRect, 16, TPalette.Gold, 2);
  ACanvas.DrawLabel(LRect, AText, TPalette.BannerText, 42);
end;

class procedure TOverlayRender.PauseOverlay(const ACanvas: TCanvas; const AScreenRect: TRectF);
begin
  var LW := AScreenRect.Width;
  var LH := AScreenRect.Height;
  ACanvas.FillRound(AScreenRect, 0, TPalette.OverlayDim);
  ACanvas.DrawLabel(RectF(0, LH * 0.44, LW, LH * 0.52), '일시정지', TAlphaColors.Gold, 40);
  ACanvas.DrawLabel(RectF(0, LH * 0.52, LW, LH * 0.57), '스페이스바 또는 하단 재개 버튼을 눌러 재개', TAlphaColors.White, 18);
end;

class procedure TOverlayRender.CapturedCount(const ACanvas: TCanvas; const ACenterX, ACenterY: Single; const ACount: Integer;
  const ABadgeSize: TSizeF);
begin
  var LR := RectF(ACenterX - ABadgeSize.Width / 2, ACenterY - ABadgeSize.Height / 2,
    ACenterX + ABadgeSize.Width / 2, ACenterY + ABadgeSize.Height / 2);
  ACanvas.FillCircle(LR, TPalette.BadgeFill);
  ACanvas.DrawLabel(LR, ACount.ToString, TPalette.BadgeText, ABadgeSize.Height * 0.56, True);
end;
{$ENDREGION}

end.
