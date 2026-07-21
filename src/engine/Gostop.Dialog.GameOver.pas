unit Gostop.Dialog.GameOver;

// 정산(게임 종료) 다이얼로그. 좌석별 결과 줄(아바타 + 박 뱃지 + 애니메이션 금액 + 승자 점수 뱃지),
// 자동 진행 카운트다운, [다음 판]/[그만하기](또는 오링 시 [타이틀로]) 버튼을 그린다. 이번 세션 다이얼로그
// 중 가장 복잡 — 머니 카운트·카운트다운 두 연속 애니메이션과 "머니 카운트가 끝나야 버튼·카운트다운 활성"
// 게이팅이 얽혀 있다. 이 애니·상태·자동진행 플로우는 전부 보드(게임 상태)에 두고, 다이얼로그는 렌더만
// 한다: 실시간으로 변하는 값(머니 진행·카운트다운·버튼 활성)은 TFunc 접근자로 읽고, 보드 타이머의
// Repaint 가 자식 컨트롤인 이 다이얼로그도 다시 그리므로 값이 매 프레임 갱신된다. 아바타 비트맵은 보드가
// 미리 골라(승자=환호/박=화남/패자=슬픔) 주입한다.

interface

{$REGION 'uses'}
uses
  System.SysUtils,
  System.Types,
  FMX.Graphics,
  Gostop.Dialog;
{$ENDREGION}

type
  /// <summary>정산 다이얼로그의 결과 줄 한 개(보드가 아바타 비트맵을 미리 골라 채워 넘긴다).</summary>
  TGameOverRow = record
    Avatar: TBitmap;             // 미리 계산된 아바타(보드 소유 — 참조만). nil이면 안내문 줄
    IsWinner: Boolean;
    HasAmount: Boolean;
    Amount: Integer;             // 이번 판 손익(부호 포함)
    BalanceAfter: Integer;       // 정산 후 총 보유금
    Flags: TArray<string>;       // 박 뱃지
    ScoreParts: TArray<string>;  // 승자 점수 내역 뱃지
    ScoreTotal: Integer;         // 승자 족보 합계
    Text: string;                // 안내문(아바타 없는 줄)
  end;

  /// <summary>정산(게임 종료) 다이얼로그. 결과 줄·카운트다운·버튼을 그린다. 애니·플로우는 보드가 소유.</summary>
  TGameOverDialog = class(TGostopDialog)
  strict private
    FRows: TArray<TGameOverRow>;
    FHasTitle: Boolean;          // 판돈 배수 제목 유무(상단 여백 결정)
    FHumanBroke: Boolean;        // True면 [타이틀로]만, False면 [다음 판]/[그만하기]
    FMoneyProgress: TFunc<Single>;    // 0~1 머니 카운트 진행도(라이브)
    FCountdownActive: TFunc<Boolean>; // 카운트다운 표시 여부(라이브)
    FCountdownRemain: TFunc<Single>;  // 카운트다운 남은 초(라이브)
    FButtonsEnabled: TFunc<Boolean>;  // 버튼 활성 여부(머니 카운트 완료 후)(라이브)
    FOnNext: TProc;              // [다음 판] 콜백
    FOnQuit: TProc;              // [그만하기]/[타이틀로] 콜백
    FBtnNext: TDialogButton;     // 오링이면 nil(타이틀로만)
    FBtnQuit: TDialogButton;
    function RowHeight(const ARow: TGameOverRow): Single;
  strict protected
    function  PanelHeight: Single; override;   // 결과 줄 수·승자 뱃지 유무에 따라 동적
    procedure BuildButtons; override;
    procedure DrawContent(const ACanvas: TCanvas; const APanel: TRectF); override;
  public
    procedure Present(const ATitle: string; const ARows: TArray<TGameOverRow>; const AHumanBroke: Boolean;
      const AMoneyProgress: TFunc<Single>; const ACountdownActive: TFunc<Boolean>;
      const ACountdownRemain: TFunc<Single>; const AButtonsEnabled: TFunc<Boolean>;
      const AOnNext, AOnQuit: TProc);
  end;

implementation

{$REGION 'uses'}
uses
  System.UITypes,
  System.Math,
  FMX.Types,
  Gostop.Canvas.Helper,
  Gostop.Fonts,
  Gostop.Board.Widgets;
{$ENDREGION}

const
  ROW_H = 108.0;
  AV_SIZE = 84.0;
  WIN_AV_SIZE = 100.0;
  AMOUNT_COL_W = 130.0;
  BTN_H = 44.0;
  COUNTDOWN_H = 56.0;
  SCORE_ROW_EXTRA_H = 32.0;
  BADGE_RED = TAlphaColor($FF8E2430);      // 박 뱃지
  SCORE_BADGE_FILL = TAlphaColor($FF2E5F4E);
  SCORE_BADGE_LINE = TAlphaColor($FF5FA98A);
  TOTAL_BADGE_FILL = TAlphaColor($FF6B5610);
  CD_CIRCLE_FILL = TAlphaColor($302E7D32);
  CD_CIRCLE_LINE = TAlphaColor($FFFFD54A);
  DIM_TEXT = TAlphaColor($FF8A968A);
  NET_GAIN = TAlphaColor($FF7ED9A0);
  NET_LOSS = TAlphaColor($FFE08080);
  NET_NEUTRAL = TAlphaColor($FFB8C4B8);

{$REGION 'TGameOverDialog'}
function TGameOverDialog.RowHeight(const ARow: TGameOverRow): Single;
begin
  Result := ROW_H;
  if ARow.IsWinner and (Length(ARow.ScoreParts) > 0) then
  begin
    Result := ROW_H + SCORE_ROW_EXTRA_H;   // 승자 점수 뱃지 한 줄 추가
  end;
end;

function TGameOverDialog.PanelHeight: Single;
begin
  var LTopPad := 20.0;
  if FHasTitle then
  begin
    LTopPad := 52.0;
  end;

  var LRowsTotalH := 0.0;
  for var I := 0 to High(FRows) do
  begin
    LRowsTotalH := LRowsTotalH + RowHeight(FRows[I]);
  end;

  Result := LTopPad + LRowsTotalH + 18 + COUNTDOWN_H + BTN_H + 18;
end;

procedure TGameOverDialog.Present(const ATitle: string; const ARows: TArray<TGameOverRow>; const AHumanBroke: Boolean;
  const AMoneyProgress: TFunc<Single>; const ACountdownActive: TFunc<Boolean>;
  const ACountdownRemain: TFunc<Single>; const AButtonsEnabled: TFunc<Boolean>;
  const AOnNext, AOnQuit: TProc);
begin
  FRows := ARows;
  FHasTitle := ATitle <> '';
  FHumanBroke := AHumanBroke;
  FMoneyProgress := AMoneyProgress;
  FCountdownActive := ACountdownActive;
  FCountdownRemain := ACountdownRemain;
  FButtonsEnabled := AButtonsEnabled;
  FOnNext := AOnNext;
  FOnQuit := AOnQuit;
  SetupDialog(ATitle, 480.0, PanelHeight);   // 폭 고정, 높이는 PanelHeight(동적)로 프레임에 전달
  Popup;
end;

// 오링(휴먼 파산)이면 [타이틀로]만, 아니면 [다음 판]/[그만하기]. FHumanBroke 는 Present 에서 Popup 전에
// 세팅되므로 여기서 올바르게 반영된다. 활성 여부는 DrawContent 에서 매 프레임 갱신한다.
procedure TGameOverDialog.BuildButtons;
begin
  FBtnNext := nil;
  if FHumanBroke then
  begin
    FBtnQuit := AddButton('타이틀로', dbkDanger,
      procedure
      begin
        if Assigned(FOnQuit) then
        begin
          FOnQuit();
        end;
      end);
  end
  else
  begin
    FBtnNext := AddButton('다음 판', dbkPrimary,
      procedure
      begin
        if Assigned(FOnNext) then
        begin
          FOnNext();
        end;
      end);

    FBtnQuit := AddButton('그만하기', dbkDanger,
      procedure
      begin
        if Assigned(FOnQuit) then
        begin
          FOnQuit();
        end;
      end);
  end;
end;

procedure TGameOverDialog.DrawContent(const ACanvas: TCanvas; const APanel: TRectF);
begin
  var LN := Length(FRows);
  if LN = 0 then
  begin
    Exit;
  end;

  var LTopPad := 20.0;
  if FHasTitle then
  begin
    LTopPad := 52.0;
  end;

  var LCX := (APanel.Left + APanel.Right) / 2;
  var LAmountR0 := APanel.Right - 18 - AMOUNT_COL_W;

  var LY := APanel.Top + LTopPad;
  for var I := 0 to LN - 1 do
  begin
    var LRow := FRows[I];
    var LAvSz := AV_SIZE;
    if LRow.IsWinner then
    begin
      LAvSz := WIN_AV_SIZE;
    end;

    var LTextLeft := APanel.Left + 18;
    if Assigned(LRow.Avatar) then
    begin
      var LAvR := RectF(APanel.Left + 16, LY + (ROW_H - LAvSz) / 2,
        APanel.Left + 16 + LAvSz, LY + (ROW_H - LAvSz) / 2 + LAvSz);
      ACanvas.DrawBitmap(LRow.Avatar, RectF(0, 0, LRow.Avatar.Width, LRow.Avatar.Height), LAvR, 1, False);
      LTextLeft := LAvR.Right + 14;
    end;

    if LRow.HasAmount then
    begin
      // 박 뱃지(아바타 오른쪽)
      var LBadgeH := 24.0;
      var LBadgeY := LY + (ROW_H - LBadgeH) / 2;
      var LBadgeX := LTextLeft;
      TGostopFonts.Apply(ACanvas, 13);
      for var LFlag in LRow.Flags do
      begin
        var LBadgeW := ACanvas.TextWidth(LFlag) + 20;
        var LBadgeR := RectF(LBadgeX, LBadgeY, LBadgeX + LBadgeW, LBadgeY + LBadgeH);
        ACanvas.FillRound(LBadgeR, LBadgeH / 2, BADGE_RED);
        ACanvas.DrawLabel(LBadgeR, LFlag, TAlphaColors.White, 13);
        LBadgeX := LBadgeR.Right + 6;
      end;

      // 금액 두 줄(위=보유금 강조, 아래=이번 판 손익), 고정폭 안에서 우측 정렬
      var LAmtR := RectF(LAmountR0 - 20, LY, APanel.Right - 18, LY + ROW_H);
      var LBalR := RectF(LAmtR.Left, LAmtR.Top + ROW_H * 0.10, LAmtR.Right, LAmtR.Top + ROW_H * 0.58);
      var LNetR := RectF(LAmtR.Left, LBalR.Bottom, LAmtR.Right, LAmtR.Bottom - ROW_H * 0.06);

      var LBalColor := TAlphaColors.White;
      var LBalSize := 24.0;
      if LRow.IsWinner then
      begin
        LBalColor := TAlphaColors.Gold;
        LBalSize := 27.0;
      end;

      // 머니 카운트 애니메이션: 100원 단위로 스냅해 차오르거나 깎여내려감(라이브 진행도)
      var LDisplayBalance := LRow.BalanceAfter;
      if FMoneyProgress() < 1 then
      begin
        var LEase := 1 - Power(1 - FMoneyProgress(), 3);
        var LBefore := LRow.BalanceAfter - LRow.Amount;
        LDisplayBalance := LBefore + Round(LRow.Amount * LEase / 100) * 100;
      end;

      ACanvas.Fill.Color := LBalColor;
      TGostopFonts.Apply(ACanvas, LBalSize);
      ACanvas.FillText(LBalR, Format('%s원', [FormatFloat('#,##0', LDisplayBalance)]),
        False, 1, [], TTextAlign.Trailing, TTextAlign.Center);

      var LNetSign := '';
      if LRow.Amount > 0 then
      begin
        LNetSign := '+';
      end;

      var LNetColor := NET_NEUTRAL;
      if LRow.Amount > 0 then
      begin
        LNetColor := NET_GAIN;
      end
      else
      if LRow.Amount < 0 then
      begin
        LNetColor := NET_LOSS;
      end;

      ACanvas.Fill.Color := LNetColor;
      TGostopFonts.Apply(ACanvas, 14);
      ACanvas.FillText(LNetR, Format('%s%s원', [LNetSign, FormatFloat('#,##0', LRow.Amount)]),
        False, 1, [], TTextAlign.Trailing, TTextAlign.Center);
    end
    else
    begin
      var LTextColor := TAlphaColors.White;
      var LFontSize := 17.0;
      if LRow.IsWinner then
      begin
        LTextColor := TAlphaColors.Gold;
        LFontSize := 21.0;
      end;

      ACanvas.DrawLabel(RectF(LTextLeft, LY, APanel.Right - 18, LY + ROW_H), LRow.Text, LTextColor, LFontSize);
    end;

    // 승자 점수 내역 뱃지(아바타 아래 별도 줄)
    if LRow.IsWinner and (Length(LRow.ScoreParts) > 0) then
    begin
      var LScoreBadgeH := 24.0;
      var LScoreBadgeY := LY + ROW_H + (SCORE_ROW_EXTRA_H - LScoreBadgeH) / 2;
      var LScoreBadgeX := APanel.Left + 18;
      TGostopFonts.Apply(ACanvas, 13);
      for var LPart in LRow.ScoreParts do
      begin
        var LScoreBadgeW := ACanvas.TextWidth(LPart) + 20;
        var LScoreBadgeR := RectF(LScoreBadgeX, LScoreBadgeY, LScoreBadgeX + LScoreBadgeW, LScoreBadgeY + LScoreBadgeH);
        ACanvas.FillRound(LScoreBadgeR, LScoreBadgeH / 2, SCORE_BADGE_FILL);
        ACanvas.StrokeRound(LScoreBadgeR, LScoreBadgeH / 2, SCORE_BADGE_LINE, 1);
        ACanvas.DrawLabel(LScoreBadgeR, LPart, TAlphaColors.White, 13);
        LScoreBadgeX := LScoreBadgeR.Right + 6;
      end;

      var LTotalText := Format('합계(%d)', [LRow.ScoreTotal]);
      var LTotalBadgeW := ACanvas.TextWidth(LTotalText) + 20;
      var LTotalBadgeR := RectF(LScoreBadgeX, LScoreBadgeY, LScoreBadgeX + LTotalBadgeW, LScoreBadgeY + LScoreBadgeH);
      ACanvas.FillRound(LTotalBadgeR, LScoreBadgeH / 2, TOTAL_BADGE_FILL);
      ACanvas.StrokeRound(LTotalBadgeR, LScoreBadgeH / 2, TAlphaColors.Gold, 1);
      ACanvas.DrawLabel(LTotalBadgeR, LTotalText, TAlphaColors.Gold, 13);
    end;

    LY := LY + RowHeight(LRow);
  end;

  // 자동 진행 카운트다운(가운데, 매초 크게 나타났다가 작아짐)
  if FCountdownActive() then
  begin
    var LRemain := FCountdownRemain();
    var LCdCY := LY + COUNTDOWN_H / 2 - 6;
    var LSecLeft := Trunc(LRemain) + 1;
    if LSecLeft < 1 then
    begin
      LSecLeft := 1;
    end;

    var LLocalT := Frac(LRemain);
    if LRemain <= 0 then
    begin
      LLocalT := 0;
    end;

    var LScale := 1.0 + LLocalT * 0.9;
    var LBaseR := 20.0;
    var LR := LBaseR * LScale;
    var LCircle := RectF(LCX - LR, LCdCY - LR, LCX + LR, LCdCY + LR);
    ACanvas.FillCircle(LCircle, CD_CIRCLE_FILL);
    ACanvas.StrokeCircle(LCircle, CD_CIRCLE_LINE, 2);
    ACanvas.DrawLabel(LCircle, IntToStr(LSecLeft), TAlphaColors.White, 16 * LScale);
    ACanvas.DrawLabel(RectF(LCX - 100, LCdCY + LBaseR + 6, LCX + 100, LCdCY + LBaseR + 22), '자동 진행까지', DIM_TEXT, 11);
  end;

  LY := LY + COUNTDOWN_H;   // 카운트다운이 아직 안 떠도 자리는 확보(패널 높이 고정)

  // 버튼 위치·활성 갱신(버튼 자체는 BuildButtons 에서 생성). 머니 카운트 완료 전엔 비활성.
  var LEnabled := FButtonsEnabled();
  var LBtnW := 140.0;
  var LGap := 16.0;
  if Assigned(FBtnNext) then
  begin
    FBtnNext.Rect := RectF(LCX - LBtnW - LGap / 2, LY + 12, LCX - LGap / 2, LY + 12 + BTN_H);
    FBtnNext.Enabled := LEnabled;
    FBtnQuit.Rect := RectF(LCX + LGap / 2, LY + 12, LCX + LGap / 2 + LBtnW, LY + 12 + BTN_H);
  end
  else
  begin
    FBtnQuit.Rect := RectF(LCX - LBtnW / 2, LY + 12, LCX + LBtnW / 2, LY + 12 + BTN_H);
  end;

  FBtnQuit.Enabled := LEnabled;
end;
{$ENDREGION}

end.
