unit Gostop.Dialog;

// 다이얼로그 기반 클래스. 보드 god-class 에서 각 모달 화면을 자기완결 컴포넌트로 분리하기 위한 공용
// 컨트롤이다. TControl 로 보드 위에 얹히는 full-client 모달 오버레이 — 딤·목함 패널·팝인 애니·표준
// 버튼(호버/눌림/클릭)·마우스 추적 같은 "공용 기계"를 base 가 소유하고, 각 다이얼로그는 DrawContent
// 로 본문만 그린다. 클릭은 최상단 컨트롤인 base 가 FMX 라우팅으로 직접 받으므로 보드의 수동 히트박스
// (FxxxRects+MouseDownXxx)가 사라진다. 입력 계약은 서브클래스별 타입(레코드 주입 + 결과 콜백)으로
// 주고받는다 — 인메모리 호출이라 JSON 이 아니라 타입 안전을 우선한다.

interface

{$REGION 'uses'}
uses
  System.SysUtils,
  System.Types,
  System.UITypes,
  System.Classes,
  System.Math.Vectors,
  System.Generics.Collections,
  FMX.Types,
  FMX.Controls,
  FMX.Graphics,
  Gostop.Board.Widgets;
{$ENDREGION}

type
  /// <summary>
  ///   모든 게임 다이얼로그의 기반 컨트롤. 보드 위 full-client 모달 오버레이로 얹혀 딤·목함 패널·팝인·
  ///   표준 버튼·마우스 추적을 공통 처리한다. 서브클래스는 <see cref="DrawContent"/> 에서 패널 안 본문을
  ///   그리고 <see cref="AddButton"/> 로 버튼을 등록하기만 하면 된다. 입력/결과는 서브클래스가 타입 모델
  ///   주입 + 콜백으로 주고받는다.
  /// </summary>
  TGostopDialog = class(TControl)
  strict private
    type
      // DrawContent 에서 AddButton 으로 등록되는 버튼 1개(base 가 렌더·히트테스트·클릭 콜백을 담당)
      TDlgButton = record
        Rect: TRectF;
        Caption: string;
        Kind: TDlgBtnKind;
        Enabled: Boolean;
        OnClick: TProc;
      end;
  strict private
    FTitle: string;
    FPanelW: Single;
    FPanelH: Single;
    FPopT: Single;             // 팝인 진행도(0~1, 1=정착)
    FPopTimer: TTimer;
    FMousePos: TPointF;
    FMouseDown: Boolean;
    FButtons: TList<TDlgButton>;

    FOnClose: TProc;
    function  IsHot(const ARect: TRectF): Boolean;
    function  IsPressed(const ARect: TRectF): Boolean;
    procedure PopTimerTick(Sender: TObject);
  strict protected
    /// <summary>서브클래스가 목함 패널(APanel) 안에 본문을 그린다. 버튼은 AddButton 으로 등록한다.</summary>
    procedure DrawContent(const ACanvas: TCanvas; const APanel: TRectF); virtual; abstract;
    /// <summary>제목·패널 크기를 설정한다(보통 서브클래스 생성자에서 1회 호출).</summary>
    procedure SetupDialog(const ATitle: string; const AWidth, AHeight: Single);
    /// <summary>
    ///   패널 폭/높이. 기본은 SetupDialog 값이지만, 컨트롤 크기에 비례하는 동적 폭이 필요하면
    ///   오버라이드한다 — Paint 시점에 호출되므로 이때 컨트롤은 이미 올바른 크기(보드 전체)이다.
    ///   (SetupDialog 는 Present 시점에 불려 컨트롤이 아직 리사이즈 전일 수 있어 Width 가 부정확하다.)
    /// </summary>
    function  PanelWidth: Single; virtual;
    function  PanelHeight: Single; virtual;
    /// <summary>DrawContent 안에서 버튼을 등록한다 — base 가 호버/눌림 렌더 + 클릭 시 AOnClick 을 호출한다.</summary>
    procedure AddButton(const ARect: TRectF; const ACaption: string; const AKind: TDlgBtnKind;
      const AOnClick: TProc; const AEnabled: Boolean = True);
    procedure Paint; override;
    procedure MouseMove(Shift: TShiftState; X, Y: Single); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Single); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Single); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    /// <summary>다이얼로그를 띄운다(가시화 + 최상단 + 팝인 애니 시작).</summary>
    procedure Popup;
    /// <summary>다이얼로그를 닫는다(숨김 + OnClose 콜백). 보통 서브클래스의 닫기 버튼이 호출한다.</summary>
    procedure Dismiss;
    /// <summary>닫힐 때 호출되는 콜백(보드가 화면 복귀·후속 흐름을 잇는다).</summary>
    property OnClose: TProc read FOnClose write FOnClose;
  end;

implementation

{$REGION 'uses'}
uses
  Gostop.Board.Dialog,
  Gostop.Canvas.Helper,
  Gostop.Audio;
{$ENDREGION}

const
  DIALOG_POP_MS = 170.0;    // 팝인 지속 시간(보드 원본 DrawStdDialog 과 동일)
  DIALOG_BTN_FONT = 17.0;   // 표준 버튼 폰트 크기(DrawStdButton 기본값과 동일)

{$REGION 'TGostopDialog'}
constructor TGostopDialog.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FButtons := TList<TDlgButton>.Create;
  FMousePos := PointF(-1, -1);
  FPopT := 1;
  HitTest := True;     // 딤 전체가 클릭을 흡수 → 뒤 보드는 클릭을 못 받는다(모달)
  Visible := False;

  FPopTimer := TTimer.Create(Self);
  FPopTimer.Interval := 16;   // ~60fps
  FPopTimer.Enabled := False;
  FPopTimer.OnTimer := PopTimerTick;
end;

destructor TGostopDialog.Destroy;
begin
  FButtons.Free;
  inherited;
end;

procedure TGostopDialog.SetupDialog(const ATitle: string; const AWidth, AHeight: Single);
begin
  FTitle := ATitle;
  FPanelW := AWidth;
  FPanelH := AHeight;
end;

function TGostopDialog.PanelWidth: Single;
begin
  Result := FPanelW;
end;

function TGostopDialog.PanelHeight: Single;
begin
  Result := FPanelH;
end;

procedure TGostopDialog.Popup;
begin
  Visible := True;
  BringToFront;
  FPopT := 0;
  FPopTimer.Enabled := True;
  Repaint;
end;

procedure TGostopDialog.Dismiss;
begin
  FPopTimer.Enabled := False;
  Visible := False;
  if Assigned(FOnClose) then
  begin
    FOnClose();
  end;
end;

procedure TGostopDialog.PopTimerTick(Sender: TObject);
begin
  FPopT := FPopT + FPopTimer.Interval / DIALOG_POP_MS;
  if FPopT >= 1 then
  begin
    FPopT := 1;
    FPopTimer.Enabled := False;
  end;

  Repaint;
end;

function TGostopDialog.IsHot(const ARect: TRectF): Boolean;
begin
  Result := ARect.Contains(FMousePos);
end;

function TGostopDialog.IsPressed(const ARect: TRectF): Boolean;
begin
  Result := FMouseDown and ARect.Contains(FMousePos);
end;

procedure TGostopDialog.AddButton(const ARect: TRectF; const ACaption: string; const AKind: TDlgBtnKind;
  const AOnClick: TProc; const AEnabled: Boolean);
begin
  var LBtn: TDlgButton;
  LBtn.Rect := ARect;
  LBtn.Caption := ACaption;
  LBtn.Kind := AKind;
  LBtn.Enabled := AEnabled;
  LBtn.OnClick := AOnClick;
  FButtons.Add(LBtn);
end;

procedure TGostopDialog.Paint;
begin
  var LPreMatrix: TMatrix;
  var LPanel := TDialogFrame.Draw(Canvas, LocalRect, FTitle, PanelWidth, PanelHeight, FPopT, LPreMatrix);

  FButtons.Clear;
  DrawContent(Canvas, LPanel);   // 본문 + AddButton 등록(버튼 rect 는 여기서 채워짐)

  // 등록된 버튼을 팝인 매트릭스 안에서(패널과 함께 스케일) 호버/눌림 반영해 그린다
  for var I := 0 to FButtons.Count - 1 do
  begin
    var LBtn := FButtons[I];
    TWidgetRender.StdButton(Canvas, LBtn.Rect, LBtn.Caption, LBtn.Kind, LBtn.Enabled, DIALOG_BTN_FONT,
      IsHot(LBtn.Rect), IsPressed(LBtn.Rect));
  end;

  TDialogFrame.Restore(Canvas, LPreMatrix);
end;

procedure TGostopDialog.MouseMove(Shift: TShiftState; X, Y: Single);
begin
  inherited;
  FMousePos := PointF(X, Y);
  Repaint;
end;

procedure TGostopDialog.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Single);
begin
  inherited;
  FMousePos := PointF(X, Y);
  FMouseDown := True;

  for var I := 0 to FButtons.Count - 1 do
  begin
    var LBtn := FButtons[I];
    if LBtn.Enabled and LBtn.Rect.Contains(FMousePos) then
    begin
      TGostopAudio.Instance.Play('ui_click');
      if Assigned(LBtn.OnClick) then
      begin
        LBtn.OnClick();
      end;

      Break;   // 한 번에 버튼 하나만 반응
    end;
  end;

  Repaint;
end;

procedure TGostopDialog.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Single);
begin
  inherited;
  FMouseDown := False;
  Repaint;
end;
{$ENDREGION}

end.
