unit Gostop.Board.Widgets;

// 보드에서 빠져나온 공용 위젯 렌더러. 게임 상태에 의존하지 않고 Canvas·좌표·표시 데이터 + 호버/눌림
// Boolean 만 받아 그린다(호버·눌림 판정은 보드가 IsHot/IsPressed 로 계산해 넘긴다).
// 첫 입주: 표준 다이얼로그 버튼.

interface

{$REGION 'uses'}
uses
  System.Types,
  System.UITypes,
  FMX.Graphics;
{$ENDREGION}

type
  /// <summary>표준 다이얼로그 버튼 종류(색상 통일).</summary>
  TDlgBtnKind = (
    dbkNeutral,   // 회색(기본)
    dbkPrimary,   // 녹색(긍정/확인)
    dbkDanger,    // 빨강(취소/부정)
    dbkAccent     // 금색(강조)
  );

  /// <summary>공용 위젯 렌더러(순수 렌더 — 게임 상태 비의존).</summary>
  TWidgetRender = record
  public
    /// <summary>표준 다이얼로그 버튼을 그린다. 반환값은 클릭 판정용 rect(=ARect).</summary>
    class function StdButton(const ACanvas: TCanvas; const ARect: TRectF; const ACaption: string;
      const AKind: TDlgBtnKind; const AEnabled: Boolean; const AFontSize: Single;
      const AHover, APressed: Boolean): TRectF; static;
    /// <summary>설정 다이얼로그의 값 변경 버튼(텍스트형).</summary>
    class procedure CfgValueButton(const ACanvas: TCanvas; const ARect: TRectF; const AText: string;
      const AHover, APressed: Boolean); static;
    /// <summary>설정 다이얼로그의 켬/끔 토글 스위치.</summary>
    class procedure CfgToggle(const ACanvas: TCanvas; const ARect: TRectF;
      const AOn, AHover, APressed: Boolean); static;
  end;

implementation

{$REGION 'uses'}
uses
  Gostop.Canvas.Helper;
{$ENDREGION}

{$REGION 'TWidgetRender'}
class function TWidgetRender.StdButton(const ACanvas: TCanvas; const ARect: TRectF; const ACaption: string;
  const AKind: TDlgBtnKind; const AEnabled: Boolean; const AFontSize: Single;
  const AHover, APressed: Boolean): TRectF;
begin
  Result := ARect;

  if not AEnabled then
  begin
    ACanvas.FillRound(ARect, 9, $60333A33);
    ACanvas.StrokeRound(ARect, 9, $30FFFFFF, 1);
    ACanvas.DrawLabel(ARect, ACaption, $806E786E, AFontSize);
    Exit;
  end;

  var LColor: TAlphaColor := $FF37474F;   // dbkNeutral
  case AKind of
    dbkPrimary:
      begin
        LColor := $FF2E7D32;
      end;
    dbkDanger:
      begin
        LColor := $FF8E2430;
      end;
    dbkAccent:
      begin
        LColor := $FFB8860B;
      end;
  end;

  var LFillR := ARect;
  if APressed then
  begin
    LColor := AdjustColor(LColor, -30);
    LFillR := RectF(ARect.Left + 2, ARect.Top + 2, ARect.Right - 1, ARect.Bottom - 1);   // 눌림: 살짝 안쪽으로
  end
  else
  if AHover then
  begin
    LColor := AdjustColor(LColor, 24);
  end;

  ACanvas.FillRound(LFillR, 9, LColor);
  ACanvas.StrokeRound(LFillR, 9, $50FFFFFF, 1);
  ACanvas.DrawLabel(LFillR, ACaption, TAlphaColors.White, AFontSize);
end;

class procedure TWidgetRender.CfgValueButton(const ACanvas: TCanvas; const ARect: TRectF; const AText: string;
  const AHover, APressed: Boolean);
begin
  var LBtnColor: TAlphaColor := $FF2F4436;
  var LBtnBorder: TAlphaColor := $60FFFFFF;
  if APressed then
  begin
    LBtnColor := AdjustColor(LBtnColor, -14);
  end
  else
  if AHover then
  begin
    LBtnColor := AdjustColor(LBtnColor, 18);
    LBtnBorder := $90FFD54A;
  end;

  ACanvas.FillRound(ARect, 8, LBtnColor);
  ACanvas.StrokeRound(ARect, 8, LBtnBorder, 1);
  ACanvas.DrawLabel(ARect, AText, $FFFFE082, 15);
end;

class procedure TWidgetRender.CfgToggle(const ACanvas: TCanvas; const ARect: TRectF;
  const AOn, AHover, APressed: Boolean);
const
  TRACK_W = 50.0;
  TRACK_H = 26.0;
begin
  var LCy := (ARect.Top + ARect.Bottom) / 2;
  var LTrack := RectF(ARect.Right - TRACK_W, LCy - TRACK_H / 2, ARect.Right, LCy + TRACK_H / 2);

  var LTrackColor: TAlphaColor := $FF44504A;
  if AOn then
  begin
    LTrackColor := $FF2E7D32;
  end;

  var LBorder: TAlphaColor := $50FFFFFF;
  if APressed then
  begin
    LTrackColor := AdjustColor(LTrackColor, -24);
  end
  else
  if AHover then
  begin
    LTrackColor := AdjustColor(LTrackColor, 22);
    LBorder := $90FFD54A;
  end;

  ACanvas.FillRound(LTrack, TRACK_H / 2, LTrackColor);
  ACanvas.StrokeRound(LTrack, TRACK_H / 2, LBorder, 1);

  var LKnobD := TRACK_H - 6;
  var LKnobX := LTrack.Left + 3;
  if AOn then
  begin
    LKnobX := LTrack.Right - 3 - LKnobD;
  end;

  ACanvas.FillCircle(RectF(LKnobX, LTrack.Top + 3, LKnobX + LKnobD, LTrack.Top + 3 + LKnobD), TAlphaColors.White);
end;
{$ENDREGION}

end.
