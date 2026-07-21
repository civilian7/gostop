unit Gostop.Dialog.MatchSetup;

// 대전 설정 다이얼로그. 슬롯머신 릴이 돌며 AI 캐릭터를 좌석에 배정하는 화면 — 좌석별 표시 행(릴 아바타
// + 이름, 휴먼 행은 금테 강조) + [다시 돌리기]/[관전 모드]/[시작]/[취소] 버튼. 좌석 선택 기능은 없어
// (휴먼 고정) 커스텀 히트영역이 필요 없고 버튼만이라, 게임오버처럼 "행 데이터·관전 상태는 라이브 접근자
// 로 읽고(보드의 슬롯 타이머 Repaint 가 이 자식 다이얼로그도 그림) 버튼은 base 버튼" 패턴으로 만든다.
// 슬롯 스핀·좌석 배정·시작 로직은 전부 보드가 소유한다.

interface

{$REGION 'uses'}
uses
  System.SysUtils,
  System.Types,
  FMX.Graphics,
  Gostop.Dialog;
{$ENDREGION}

type
  /// <summary>대전 설정 한 좌석 행의 라이브 표시 데이터(보드가 슬롯 상태로부터 매 프레임 계산).</summary>
  TMatchRowInfo = record
    AvatarBmp: TBitmap;   // 이 좌석 릴에 현재 표시할 아바타(보드 소유 — 참조만)
    Name: string;         // 이름(스핀 중이면 '…' 접미어, 휴먼은 '나')
    IsHuman: Boolean;     // 휴먼 좌석(금테 강조)
  end;

  /// <summary>대전 설정 다이얼로그 모델(행 데이터·관전 상태는 라이브 접근자).</summary>
  TMatchSetupModel = record
    Title: string;
    Count: Integer;                        // 좌석 수(2/3/4)
    RowInfo: TFunc<Integer, TMatchRowInfo>; // 좌석 행 라이브 데이터
    IsSpectator: TFunc<Boolean>;            // 관전 모드 여부(라이브)
    OnSpin: TProc;                          // 다시 돌리기
    OnWatch: TProc;                         // 관전 모드 토글
    OnStart: TProc;                         // 시작
    OnCancel: TProc;                        // 취소
  end;

  /// <summary>대전 설정(슬롯머신 좌석 배정) 다이얼로그.</summary>
  TMatchSetupDialog = class(TGostopDialog)
  strict private
    FModel: TMatchSetupModel;
    FBtnSpin: TDialogButton;
    FBtnWatch: TDialogButton;
    FBtnStart: TDialogButton;
    FBtnCancel: TDialogButton;
  strict protected
    function  PanelHeight: Single; override;
    procedure BuildButtons; override;
    procedure DrawContent(const ACanvas: TCanvas; const APanel: TRectF); override;
  public
    procedure Present(const AModel: TMatchSetupModel);
  end;

implementation

{$REGION 'uses'}
uses
  System.UITypes,
  FMX.Types,
  Gostop.Canvas.Helper,
  Gostop.Fonts,
  Gostop.Board.Widgets;
{$ENDREGION}

const
  ROW_H = 60.0;
  ROW_GAP = 10.0;
  BTN_H = 40.0;
  BTN_GAP = 16.0;
  ROW_GAP2 = 12.0;
  PAD = 22.0;
  BTN_W = 160.0;
  ALL_CORNERS = [TCorner.TopLeft, TCorner.TopRight, TCorner.BottomLeft, TCorner.BottomRight];

{$REGION 'TMatchSetupDialog'}
function TMatchSetupDialog.PanelHeight: Single;
begin
  Result := 48 + FModel.Count * ROW_H + 12 + BTN_H + ROW_GAP2 + BTN_H + 22;
end;

procedure TMatchSetupDialog.Present(const AModel: TMatchSetupModel);
begin
  FModel := AModel;
  SetupDialog(AModel.Title, 500.0, PanelHeight);
  Popup;
end;

procedure TMatchSetupDialog.BuildButtons;
begin
  FBtnSpin := AddButton('다시 돌리기', dbkNeutral,
    procedure
    begin
      if Assigned(FModel.OnSpin) then
      begin
        FModel.OnSpin();
      end;
    end);

  FBtnWatch := AddButton('관전 모드', dbkNeutral,
    procedure
    begin
      if Assigned(FModel.OnWatch) then
      begin
        FModel.OnWatch();
      end;
    end);

  FBtnStart := AddButton('시작', dbkPrimary,
    procedure
    begin
      if Assigned(FModel.OnStart) then
      begin
        FModel.OnStart();
      end;
    end);

  FBtnCancel := AddButton('취소', dbkDanger,
    procedure
    begin
      if Assigned(FModel.OnCancel) then
      begin
        FModel.OnCancel();
      end;
    end);
end;

procedure TMatchSetupDialog.DrawContent(const ACanvas: TCanvas; const APanel: TRectF);
begin
  var LCx := (APanel.Left + APanel.Right) / 2;

  // 좌석 행(릴 아바타 + 이름). 휴먼 행은 금테 강조. 좌석 선택은 없음(표시 전용).
  for var R := 0 to FModel.Count - 1 do
  begin
    var LY := APanel.Top + 50 + R * ROW_H;
    var LRow := RectF(APanel.Left + PAD, LY, APanel.Right - PAD, LY + ROW_H - ROW_GAP);
    var LInfo := FModel.RowInfo(R);

    ACanvas.Fill.Kind := TBrushKind.Solid;
    if LInfo.IsHuman then
    begin
      ACanvas.Fill.Color := $FF2F4A2E;
    end
    else
    begin
      ACanvas.Fill.Color := $FF20301F;
    end;

    ACanvas.FillRect(LRow, 10, 10, ALL_CORNERS, 1);
    if LInfo.IsHuman then
    begin
      ACanvas.Stroke.Color := $FFFFD54A;
      ACanvas.Stroke.Thickness := 2;
      ACanvas.DrawRect(LRow, 10, 10, ALL_CORNERS, 1);
    end;

    ACanvas.DrawLabel(RectF(LRow.Left + 12, LRow.Top, LRow.Left + 48, LRow.Bottom), Format('P%d', [R + 1]), $FFB8C4B8, 15);

    var LAvSize := LRow.Height - 12;
    var LAvY := LRow.Top + (LRow.Height - LAvSize) / 2;
    var LAv := RectF(LRow.Left + 54, LAvY, LRow.Left + 54 + LAvSize, LAvY + LAvSize);
    if Assigned(LInfo.AvatarBmp) then
    begin
      ACanvas.DrawBitmap(LInfo.AvatarBmp, RectF(0, 0, LInfo.AvatarBmp.Width, LInfo.AvatarBmp.Height), LAv, 1, False);
    end;

    ACanvas.StrokeRound(LAv, 6, $80FFFFFF, 1);

    ACanvas.Fill.Color := TAlphaColors.White;
    TGostopFonts.Apply(ACanvas, 16);
    ACanvas.FillText(RectF(LAv.Right + 14, LRow.Top, LRow.Right - 12, LRow.Bottom), LInfo.Name,
      False, 1, [], TTextAlign.Leading, TTextAlign.Center);
  end;

  // 버튼 2행: [다시 돌리기][관전 모드] / [시작][취소]. 관전 버튼은 상태에 따라 캡션·색이 바뀐다.
  var LBY := APanel.Top + 50 + FModel.Count * ROW_H + 12;
  FBtnSpin.Rect := RectF(LCx - BTN_W - BTN_GAP / 2, LBY, LCx - BTN_GAP / 2, LBY + BTN_H);
  FBtnWatch.Rect := RectF(LCx + BTN_GAP / 2, LBY, LCx + BTN_GAP / 2 + BTN_W, LBY + BTN_H);

  if FModel.IsSpectator() then
  begin
    FBtnWatch.Caption := '관전 모드: 켬';
    FBtnWatch.Kind := dbkAccent;
  end
  else
  begin
    FBtnWatch.Caption := '관전 모드: 끔';
    FBtnWatch.Kind := dbkNeutral;
  end;

  LBY := LBY + BTN_H + ROW_GAP2;
  FBtnStart.Rect := RectF(LCx - BTN_W - BTN_GAP / 2, LBY, LCx - BTN_GAP / 2, LBY + BTN_H);
  FBtnCancel.Rect := RectF(LCx + BTN_GAP / 2, LBY, LCx + BTN_GAP / 2 + BTN_W, LBY + BTN_H);
end;
{$ENDREGION}

end.
