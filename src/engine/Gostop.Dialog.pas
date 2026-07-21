unit Gostop.Dialog;

// 다이얼로그 기반 클래스. 보드 god-class 에서 각 모달 화면을 자기완결 컴포넌트로 분리하기 위한 공용
// 컨트롤이다. TControl 로 보드 위에 얹히는 full-client 모달 오버레이 — 딤·목함 패널·팝인 애니·표준
// 버튼(호버/눌림/클릭)·마우스 추적 같은 "공용 기계"를 base 가 소유하고, 각 다이얼로그는 DrawContent
// 로 본문만 그린다. 클릭은 최상단 컨트롤인 base 가 FMX 라우팅으로 직접 받으므로 보드의 수동 히트박스
// (FxxxRects+MouseDownXxx)가 사라진다. 입력 계약은 서브클래스별 타입(레코드 주입 + 결과 콜백)으로
// 주고받는다 — 인메모리 호출이라 JSON 이 아니라 타입 안전을 우선한다.
//
// 버튼은 공통 클래스 TDialogButton 으로, BuildButtons 에서 표시 때 1회 생성해 재사용한다(매 프레임
// 재생성하지 않는다 — 애니메이션으로 계속 리페인트되는 다이얼로그에서 클로저·객체 재할당을 없앤다).
// 위치(Rect)·활성(Enabled)만 DrawContent 에서 매 프레임 갱신하고, 그리기·히트테스트·클릭은 버튼이 스스로.

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
  ///   다이얼로그 버튼 공통 클래스. 캡션·종류·클릭 콜백은 생성 시 1회 고정하고, 위치(Rect)·활성(Enabled)
  ///   은 레이아웃에 따라 매 프레임 갱신된다. 그리기(호버/눌림 반영)·히트테스트·클릭을 스스로 처리한다.
  /// </summary>
  TDialogButton = class
  strict private
    FCaption: string;
    FKind: TDlgBtnKind;
    FOnClick: TProc;
    FRect: TRectF;
    FEnabled: Boolean;
    FFontSize: Single;
  public
    constructor Create(const ACaption: string; const AKind: TDlgBtnKind; const AOnClick: TProc; const AFontSize: Single);
    /// <summary>현재 Rect·Enabled 로 그린다(호버/눌림 상태는 base 가 계산해 넘긴다).</summary>
    procedure Draw(const ACanvas: TCanvas; const AHover, APressed: Boolean);
    /// <summary>활성 상태에서 그 점을 포함하는가(클릭 판정).</summary>
    function  Contains(const APoint: TPointF): Boolean;
    /// <summary>활성이면 클릭 콜백을 호출한다.</summary>
    procedure Click;
    /// <summary>버튼 위치(레이아웃에서 매 프레임 갱신).</summary>
    property Rect: TRectF read FRect write FRect;
    /// <summary>활성 여부(비활성은 회색 표시 + 클릭 무시).</summary>
    property Enabled: Boolean read FEnabled write FEnabled;
  end;

  /// <summary>
  ///   모든 게임 다이얼로그의 기반 컨트롤. 보드 위 full-client 모달 오버레이로 얹혀 딤·목함 패널·팝인·
  ///   버튼·마우스 추적을 공통 처리한다. 서브클래스는 <see cref="BuildButtons"/> 에서 버튼을 1회 만들고,
  ///   <see cref="DrawContent"/> 에서 패널 안 본문을 그리며 버튼의 Rect·Enabled 를 갱신한다. 입력/결과는
  ///   서브클래스가 타입 모델 주입 + 콜백으로 주고받는다.
  /// </summary>
  TGostopDialog = class(TControl)
  strict private
    FTitle: string;
    FPanelW: Single;
    FPanelH: Single;
    FPopT: Single;             // 팝인 진행도(0~1, 1=정착)
    FPopTimer: TTimer;
    FMousePos: TPointF;
    FMouseDown: Boolean;
    FButtons: TObjectList<TDialogButton>;   // 표시 때 1회 생성(BuildButtons), 매 프레임 재생성 안 함

    FOnClose: TProc;
    function  IsHot(const ARect: TRectF): Boolean;
    function  IsPressed(const ARect: TRectF): Boolean;
    procedure PopTimerTick(Sender: TObject);
  strict protected
    /// <summary>서브클래스가 목함 패널(APanel) 안에 본문을 그리고, 자기 버튼의 Rect·Enabled 를 갱신한다.</summary>
    procedure DrawContent(const ACanvas: TCanvas; const APanel: TRectF); virtual; abstract;
    /// <summary>표시(Popup) 때 1회 호출 — 서브클래스가 AddButton 으로 버튼을 만들어 필드에 보관한다.</summary>
    procedure BuildButtons; virtual;
    /// <summary>제목·패널 크기를 설정한다.</summary>
    procedure SetupDialog(const ATitle: string; const AWidth, AHeight: Single);
    /// <summary>
    ///   패널 폭/높이. 기본은 SetupDialog 값이지만, 컨트롤 크기에 비례하는 동적 폭이 필요하면
    ///   오버라이드한다 — Paint 시점에 호출되므로 이때 컨트롤은 이미 올바른 크기(보드 전체)이다.
    /// </summary>
    function  PanelWidth: Single; virtual;
    function  PanelHeight: Single; virtual;
    /// <summary>버튼을 1회 생성해 등록하고 인스턴스를 돌려준다(서브클래스가 필드에 보관). BuildButtons 에서 호출.</summary>
    function  AddButton(const ACaption: string; const AKind: TDlgBtnKind; const AOnClick: TProc): TDialogButton;
    procedure Paint; override;
    procedure MouseMove(Shift: TShiftState; X, Y: Single); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Single); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Single); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    /// <summary>다이얼로그를 띄운다(버튼 구성 + 가시화 + 최상단 + 팝인 애니 시작).</summary>
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
  Gostop.Audio;
{$ENDREGION}

const
  DIALOG_POP_MS = 170.0;    // 팝인 지속 시간(보드 원본 DrawStdDialog 과 동일)
  DIALOG_BTN_FONT = 17.0;   // 표준 버튼 폰트 크기(DrawStdButton 기본값과 동일)

{$REGION 'TDialogButton'}
constructor TDialogButton.Create(const ACaption: string; const AKind: TDlgBtnKind; const AOnClick: TProc; const AFontSize: Single);
begin
  inherited Create;
  FCaption := ACaption;
  FKind := AKind;
  FOnClick := AOnClick;
  FFontSize := AFontSize;
  FEnabled := True;
end;

procedure TDialogButton.Draw(const ACanvas: TCanvas; const AHover, APressed: Boolean);
begin
  TWidgetRender.StdButton(ACanvas, FRect, FCaption, FKind, FEnabled, FFontSize, AHover, APressed);
end;

function TDialogButton.Contains(const APoint: TPointF): Boolean;
begin
  Result := FEnabled and FRect.Contains(APoint);
end;

procedure TDialogButton.Click;
begin
  if FEnabled and Assigned(FOnClick) then
  begin
    FOnClick();
  end;
end;
{$ENDREGION}

{$REGION 'TGostopDialog'}
constructor TGostopDialog.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FButtons := TObjectList<TDialogButton>.Create(True);   // OwnsObjects — 버튼 해제
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

procedure TGostopDialog.BuildButtons;
begin
  // 기본: 버튼 없음. 서브클래스가 AddButton 으로 구성한다.
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

function TGostopDialog.AddButton(const ACaption: string; const AKind: TDlgBtnKind; const AOnClick: TProc): TDialogButton;
begin
  Result := TDialogButton.Create(ACaption, AKind, AOnClick, DIALOG_BTN_FONT);
  FButtons.Add(Result);
end;

procedure TGostopDialog.Popup;
begin
  FButtons.Clear;
  BuildButtons;   // 버튼을 이번 표시에 맞춰 1회 구성(이후 프레임에선 Rect·Enabled 만 갱신)
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

procedure TGostopDialog.Paint;
begin
  var LPreMatrix: TMatrix;
  var LPanel := TDialogFrame.Draw(Canvas, LocalRect, FTitle, PanelWidth, PanelHeight, FPopT, LPreMatrix);

  DrawContent(Canvas, LPanel);   // 본문 + 버튼 Rect·Enabled 갱신(버튼 자체는 BuildButtons 에서 이미 생성됨)

  // 버튼을 팝인 매트릭스 안에서(패널과 함께 스케일) 호버/눌림 반영해 그린다
  for var LBtn in FButtons do
  begin
    LBtn.Draw(Canvas, IsHot(LBtn.Rect), IsPressed(LBtn.Rect));
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

  for var LBtn in FButtons do
  begin
    if LBtn.Contains(FMousePos) then
    begin
      TGostopAudio.Instance.Play('ui_click');
      LBtn.Click;
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
