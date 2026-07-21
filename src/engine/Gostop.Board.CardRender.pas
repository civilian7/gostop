unit Gostop.Board.CardRender;

// 보드에서 빠져나온 순수 렌더 조각 모음. 게임 상태(FGame 등)에 의존하지 않고, Canvas·좌표·표시
// 데이터(비트맵·텍스트·선택/호버/눌림 상태)만 파라미터로 받아 그린다. private 접근이 필요 없으므로
// 외부 유닛으로 완전히 분리된다(호버·눌림 판정은 보드가 계산해 Boolean 으로 넘긴다).
// 첫 입주: 선택형 아바타 카드(새 게임 다이얼로그의 인원수·AI 난이도 카드).

interface

{$REGION 'uses'}
uses
  System.Types,
  System.UITypes,
  FMX.Graphics;
{$ENDREGION}

type
  /// <summary>
  ///   선택형 아바타 카드 렌더러. 공통 배경 셸 + 아바타 1장(난이도) / 아바타 N장 겹침(인원수)을
  ///   그린다. 선택·호버·눌림 상태에 따라 배경 명암과 테두리가 달라진다(보드의 버튼 상태 효과와 동일).
  /// </summary>
  TSelectCardRender = record
  public
    /// <summary>카드 공통 배경(둥근 사각형 + 상태별 채움·테두리). Avatar/AvatarStack 이 먼저 호출한다.</summary>
    class procedure Shell(const ACanvas: TCanvas; const ARect: TRectF;
      const ASelected, AHover, APressed: Boolean); static;
    /// <summary>아바타 1장이 카드를 채우고 하단에 명칭 오버레이(AI 난이도 등).</summary>
    class procedure Avatar(const ACanvas: TCanvas; const ARect: TRectF; const ABitmap: TBitmap;
      const ACaption: string; const ASelected, AHover, APressed: Boolean); static;
    /// <summary>아바타 여러 장을 겹쳐 표시 + 하단 명칭(인원수 등). 그릴 비트맵들을 배열로 받는다.</summary>
    class procedure AvatarStack(const ACanvas: TCanvas; const ARect: TRectF; const AAvatars: TArray<TBitmap>;
      const ACaption: string; const ASelected, AHover, APressed: Boolean); static;
  end;

implementation

{$REGION 'uses'}
uses
  System.Math,
  Gostop.Canvas.Helper;
{$ENDREGION}

{$REGION 'TSelectCardRender'}
class procedure TSelectCardRender.Shell(const ACanvas: TCanvas; const ARect: TRectF;
  const ASelected, AHover, APressed: Boolean);
begin
  if ASelected then
  begin
    var LColor: TAlphaColor := $FF2E7D32;
    if APressed then
    begin
      LColor := AdjustColor(LColor, -30);
    end
    else
    if AHover then
    begin
      LColor := AdjustColor(LColor, 20);
    end;

    ACanvas.FillRound(ARect, 10, LColor);
    ACanvas.StrokeRound(ARect, 10, $FFFFD54A, 2.5);
  end
  else
  begin
    var LColor: TAlphaColor := $FF2F4436;
    var LBorder: TAlphaColor := $50FFFFFF;
    if APressed then
    begin
      LColor := AdjustColor(LColor, -14);
    end
    else
    if AHover then
    begin
      LColor := AdjustColor(LColor, 18);
      LBorder := $90FFD54A;
    end;

    ACanvas.FillRound(ARect, 10, LColor);
    ACanvas.StrokeRound(ARect, 10, LBorder, 1);
  end;
end;

class procedure TSelectCardRender.Avatar(const ACanvas: TCanvas; const ARect: TRectF; const ABitmap: TBitmap;
  const ACaption: string; const ASelected, AHover, APressed: Boolean);
const
  INSET = 3.0;
  LABEL_H = 26.0;
begin
  Shell(ACanvas, ARect, ASelected, AHover, APressed);

  var LImgR := RectF(ARect.Left + INSET, ARect.Top + INSET, ARect.Right - INSET, ARect.Bottom - INSET);
  if Assigned(ABitmap) then
  begin
    ACanvas.DrawBitmap(ABitmap, RectF(0, 0, ABitmap.Width, ABitmap.Height), LImgR, 1, False);
  end;

  // 하단 반투명 스크림 + 명칭 오버레이(선택 시 금색 톤으로 강조)
  var LLabelR := RectF(LImgR.Left, LImgR.Bottom - LABEL_H, LImgR.Right, LImgR.Bottom);
  var LCapColor := TAlphaColors.White;
  if ASelected then
  begin
    ACanvas.FillRound(LLabelR, 6, $B0B8860B);
    LCapColor := TAlphaColors.Gold;
  end
  else
  begin
    ACanvas.FillRound(LLabelR, 6, $A0182018);
  end;

  ACanvas.DrawLabel(LLabelR, ACaption, LCapColor, 14, ASelected);   // 선택된 카드는 굵게
end;

class procedure TSelectCardRender.AvatarStack(const ACanvas: TCanvas; const ARect: TRectF; const AAvatars: TArray<TBitmap>;
  const ACaption: string; const ASelected, AHover, APressed: Boolean);
const
  CAPTION_H = 24.0;
begin
  Shell(ACanvas, ARect, ASelected, AHover, APressed);

  var LCount := Length(AAvatars);
  var LAvSize := ARect.Height - CAPTION_H - 14;
  var LStep := LAvSize * 0.6;
  var LTotalW := LAvSize + LStep * (LCount - 1);
  if LTotalW > ARect.Width - 12 then
  begin
    // 폭이 부족하면 겹침 간격을 좁혀서라도 맞춘다
    LStep := (ARect.Width - 12 - LAvSize) / Max(1, LCount - 1);
    LTotalW := LAvSize + LStep * (LCount - 1);
  end;

  var LStartX := (ARect.Left + ARect.Right) / 2 - LTotalW / 2;
  var LAvY := ARect.Top + 8;
  for var K := 0 to LCount - 1 do
  begin
    var LBmp := AAvatars[K];
    if Assigned(LBmp) then
    begin
      var LAvR := RectF(LStartX + K * LStep, LAvY, LStartX + K * LStep + LAvSize, LAvY + LAvSize);
      ACanvas.DrawBitmap(LBmp, RectF(0, 0, LBmp.Width, LBmp.Height), LAvR, 1, False);
    end;
  end;

  var LCapColor: TAlphaColor := $FFCBD6C8;
  if ASelected then
  begin
    LCapColor := TAlphaColors.White;
  end;

  ACanvas.DrawLabel(RectF(ARect.Left, LAvY + LAvSize + 2, ARect.Right, ARect.Bottom - 4), ACaption,
    LCapColor, 13, ASelected);   // 선택된 카드는 굵게
end;
{$ENDREGION}

end.
