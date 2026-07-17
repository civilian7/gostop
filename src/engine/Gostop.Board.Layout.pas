unit Gostop.Board.Layout;

interface

{$REGION 'uses'}
uses
  System.Types,
  System.Math;
{$ENDREGION}

type
  /// <summary>보드 위 좌석의 화면 위치.</summary>
  TSeatPos = (
    spTop,
    spLeft,
    spBottom,
    spRight
  );

const
  PANEL_W = 200;   // 플레이어 정보 패널 너비(전 자리 동일)
  PANEL_H = 116;   // 플레이어 정보 패널 높이(전 자리 동일)

type
  /// <summary>
  ///   보드 좌표 계산(순수 기하). 컨트롤 크기(Width·Height)만으로 좌석 영역·카드 크기·패널 위치를
  ///   결정한다. 렌더링·상태에 의존하지 않아 단독 테스트 가능.
  /// </summary>
  TBoardLayout = record
  public
    /// <summary>카드 한 장 크기(높이=보드의 15%, 화투 비율 600:978).</summary>
    class function CardSize(const AHeight: Single): TSizeF; static;
    /// <summary>좌석 영역(항상 4인 구조 고정: 좌/우 세로 기둥, 상/하/중앙은 기둥 사이).</summary>
    class function SeatRegion(const AWidth, AHeight: Single; const APos: TSeatPos): TRectF; static;
    /// <summary>중앙 영역(바닥패·더미).</summary>
    class function CenterRegion(const AWidth, AHeight: Single): TRectF; static;
    /// <summary>좌석의 정보 패널 rect(크기 고정, 앵커만 자리별로 다름).</summary>
    class function PlayerPanelRect(const AWidth, AHeight: Single; const APos: TSeatPos): TRectF; static;
    /// <summary>좌석에서 카드가 놓일 공간(정보 패널 제외 영역).</summary>
    class function SeatCardArea(const AWidth, AHeight: Single; const APos: TSeatPos): TRectF; static;
    /// <summary>딜 애니메이션의 덱(무더기) 위치(중앙 영역 우측).</summary>
    class function DealDeckPoint(const AWidth, AHeight: Single): TPointF; static;
  end;

implementation

{$REGION 'TBoardLayout'}
class function TBoardLayout.CardSize(const AHeight: Single): TSizeF;
begin
  var LH := AHeight * 0.15;
  Result := TSizeF.Create(LH * 600 / 978, LH);
end;

class function TBoardLayout.SeatRegion(const AWidth, AHeight: Single; const APos: TSeatPos): TRectF;
begin
  // 항상 4인 구조로 고정: 좌/우 좌석은 세로 전체, 상/하/중앙은 두 기둥 사이(서로 침범 없음)
  case APos of
    spTop:
      begin
        Result := RectF(AWidth * 0.19, AHeight * 0.012, AWidth * 0.81, AHeight * 0.25);
      end;
    spBottom:
      begin
        // 아래는 하단 컨트롤 바(볼륨·속도) 자리를 남기고 끝냄
        Result := RectF(AWidth * 0.19, AHeight * 0.70, AWidth * 0.81, AHeight * 0.95);
      end;
    spLeft:
      begin
        Result := RectF(AWidth * 0.005, AHeight * 0.02, AWidth * 0.18, AHeight * 0.95);
      end;
  else
    begin
      Result := RectF(AWidth * 0.82, AHeight * 0.02, AWidth * 0.995, AHeight * 0.95);
    end;
  end;
end;

class function TBoardLayout.CenterRegion(const AWidth, AHeight: Single): TRectF;
begin
  // 위 영역(P1)을 키운 만큼 중앙을 아래로
  Result := RectF(AWidth * 0.19, AHeight * 0.265, AWidth * 0.81, AHeight * 0.685);
end;

class function TBoardLayout.PlayerPanelRect(const AWidth, AHeight: Single; const APos: TSeatPos): TRectF;
begin
  var LR := SeatRegion(AWidth, AHeight, APos);
  var LW := Min(Single(PANEL_W), LR.Width - 8);   // 좁은 창 안전 클램프
  case APos of
    spTop:
      begin
        Result := RectF(LR.Right - 4 - LW, LR.Top + 4, LR.Right - 4, LR.Top + 4 + PANEL_H);
      end;
    spBottom:
      begin
        Result := RectF(LR.Left + 4, LR.Top + 4, LR.Left + 4 + LW, LR.Top + 4 + PANEL_H);
      end;
    spLeft:
      begin
        Result := RectF(LR.Left + 4, LR.Top + 4, LR.Left + 4 + LW, LR.Top + 4 + PANEL_H);
      end;
  else
    begin
      Result := RectF(LR.Left + 4, LR.Bottom - 4 - PANEL_H, LR.Left + 4 + LW, LR.Bottom - 4);
    end;
  end;
end;

class function TBoardLayout.SeatCardArea(const AWidth, AHeight: Single; const APos: TSeatPos): TRectF;
begin
  var LR := SeatRegion(AWidth, AHeight, APos);
  case APos of
    spTop:
      begin
        Result := RectF(LR.Left, LR.Top, LR.Right - PANEL_W - 12, LR.Bottom);
      end;
    spBottom:
      begin
        Result := RectF(LR.Left + PANEL_W + 12, LR.Top, LR.Right, LR.Bottom);
      end;
    spLeft:
      begin
        Result := RectF(LR.Left, LR.Top + PANEL_H + 10, LR.Right, LR.Bottom);
      end;
  else
    begin
      Result := RectF(LR.Left, LR.Top, LR.Right, LR.Bottom - PANEL_H - 10);
    end;
  end;
end;

class function TBoardLayout.DealDeckPoint(const AWidth, AHeight: Single): TPointF;
begin
  var LCen := CenterRegion(AWidth, AHeight);
  Result := PointF(LCen.Right - CardSize(AHeight).Width * 0.7, (LCen.Top + LCen.Bottom) / 2);
end;
{$ENDREGION}

end.
