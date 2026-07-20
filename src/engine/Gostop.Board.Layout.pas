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
  // 가로형(P1/P3): 아바타 위+정보 아래 → 세로 패널(좁고 높게, 컴팩트)
  PANEL_W = 112;
  PANEL_H = 154;
  // 세로형(P2/P4): 가로형의 W×H를 뒤바꾼 비율(H×W) — 넓고 낮게
  PANEL_VW = PANEL_H;   // 154
  PANEL_VH = PANEL_W;   // 112

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
    /// <summary>중앙 영역(바닥패·뒷패).</summary>
    class function CenterRegion(const AWidth, AHeight: Single): TRectF; static;
    /// <summary>좌석의 정보 패널 rect(크기 고정, 앵커만 자리별로 다름).</summary>
    class function PlayerPanelRect(const AWidth, AHeight: Single; const APos: TSeatPos): TRectF; static;
    /// <summary>좌석에서 카드가 놓일 공간(정보 패널 제외 영역).</summary>
    class function SeatCardArea(const AWidth, AHeight: Single; const APos: TSeatPos): TRectF; static;
    /// <summary>딜 애니메이션의 뒷패 위치(중앙 영역 우측).</summary>
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
        Result := RectF(AWidth * 0.21, AHeight * 0.006, AWidth * 0.79, AHeight * 0.245);
      end;
    spBottom:
      begin
        // 하단 중앙 패널 + 손패 + 획득 2행 공간 확보를 위해 위로 확장
        Result := RectF(AWidth * 0.21, AHeight * 0.50, AWidth * 0.79, AHeight * 0.955);
      end;
    spLeft:
      begin
        Result := RectF(AWidth * 0.004, AHeight * 0.02, AWidth * 0.20, AHeight * 0.955);
      end;
  else
    begin
      Result := RectF(AWidth * 0.80, AHeight * 0.02, AWidth * 0.996, AHeight * 0.955);
    end;
  end;
end;

class function TBoardLayout.CenterRegion(const AWidth, AHeight: Single): TRectF;
begin
  // 상/하 구역 사이 정중앙(바닥패·뒷패). 좌우 기둥 안쪽
  Result := RectF(AWidth * 0.21, AHeight * 0.255, AWidth * 0.79, AHeight * 0.49);
end;

class function TBoardLayout.PlayerPanelRect(const AWidth, AHeight: Single; const APos: TSeatPos): TRectF;
begin
  // 아바타 카드는 자리 관계없이 전부 세로형(PANEL_W×PANEL_H). 위치만 자리별로 조정
  var LR := SeatRegion(AWidth, AHeight, APos);
  var LW := Min(Single(PANEL_W), LR.Width - 8);
  var LCx := (LR.Left + LR.Right) / 2;
  case APos of
    spTop:
      begin
        // P1(위): 상단 우측, 카드는 왼쪽
        Result := RectF(LR.Right - 6 - LW, LR.Top + 6, LR.Right - 6, LR.Top + 6 + PANEL_H);
      end;
    spBottom:
      begin
        // P3(아래/사람): 하단 좌측, 카드는 오른쪽 — 하단 컨트롤 바와 겹치지 않게 8px 위로
        Result := RectF(LR.Left + 6, LR.Bottom - 14 - PANEL_H, LR.Left + 6 + LW, LR.Bottom - 14);
      end;
    spLeft:
      begin
        // P2(왼쪽): 좌측 기둥 상단, 카드는 아래
        Result := RectF(LCx - LW / 2, LR.Top + 6, LCx + LW / 2, LR.Top + 6 + PANEL_H);
      end;
  else
    begin
      // P4(오른쪽): 우측 기둥 하단, 카드는 위 — 하단 컨트롤 바와 겹치지 않게 8px 위로
      Result := RectF(LCx - LW / 2, LR.Bottom - 14 - PANEL_H, LCx + LW / 2, LR.Bottom - 14);
    end;
  end;
end;

class function TBoardLayout.SeatCardArea(const AWidth, AHeight: Single; const APos: TSeatPos): TRectF;
begin
  // 패널이 각 변 중앙으로 이동 → 카드는 패널을 피해 안쪽(중앙 방향) 공간에 배치.
  // 상세 배치는 DrawOpponent/DrawHumanHand가 패널 위치 기준으로 처리하고,
  // 여기서는 사람(하단, 패널 위) 기준 영역만 제공한다.
  var LR := SeatRegion(AWidth, AHeight, APos);
  case APos of
    spBottom:
      begin
        // P3(아래/사람): 패널이 하단 중앙 → 카드 공간은 패널 위
        Result := RectF(LR.Left, LR.Top, LR.Right, LR.Bottom - PANEL_H - 10);
      end;
  else
    begin
      Result := LR;
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
