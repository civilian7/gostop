unit Main;

interface

{$REGION 'uses'}
uses
  System.SysUtils,
  System.Classes,
  System.UITypes,
  FMX.Types,
  FMX.Controls,
  FMX.Forms,
  FMX.StdCtrls,
  FMX.Controls.Presentation,
  Gostop.Audio,
  Gostop.Board;
{$ENDREGION}

type
  /// <summary>
  ///   메인 폼(얇게 유지). 실제 게임 기능은 <see cref="TGostopBoard"/>에 있고,
  ///   폼은 보드를 얹고 툴바 버튼(새 게임/고/스톱/종료)과 상태표시줄을 보드에 연결만 한다.
  /// </summary>
  TfrmMain = class(TForm)
    tbTop: TToolBar;
    btnNew2: TButton;
    btnNew3: TButton;
    btnNew4: TButton;
    btnGo: TButton;
    btnStop: TButton;
    btnMute: TButton;
    btnExit: TButton;
    lblStatus: TLabel;
    procedure FormCreate(Sender: TObject);
    procedure btnNew2Click(Sender: TObject);
    procedure btnNew3Click(Sender: TObject);
    procedure btnNew4Click(Sender: TObject);
    procedure btnGoClick(Sender: TObject);
    procedure btnStopClick(Sender: TObject);
    procedure btnMuteClick(Sender: TObject);
    procedure btnExitClick(Sender: TObject);
  private
    FBoard: TGostopBoard;
    procedure BoardStateChanged(Sender: TObject);
    procedure BoardGameOver(Sender: TObject);
  end;

var
  frmMain: TfrmMain;

implementation

{$R *.fmx}

procedure TfrmMain.FormCreate(Sender: TObject);
begin
  // 보드를 폼에 얹는다(대부분의 기능은 보드 안에 있음)
  FBoard := TGostopBoard.Create(Self);
  FBoard.Parent := Self;   // Parent 먼저 지정
  FBoard.Align := TAlignLayout.Client;
  FBoard.OnStateChanged := BoardStateChanged;
  FBoard.OnGameOver := BoardGameOver;

  btnGo.Enabled := False;
  btnStop.Enabled := False;
  btnMute.Text := 'Sound On';
  lblStatus.Text := '새 게임을 시작하세요';
end;

procedure TfrmMain.btnNew2Click(Sender: TObject);
begin
  FBoard.NewGame(2, 70);
end;

procedure TfrmMain.btnNew3Click(Sender: TObject);
begin
  FBoard.NewGame(3, 70);
end;

procedure TfrmMain.btnNew4Click(Sender: TObject);
begin
  FBoard.NewGame(4, 70);
end;

procedure TfrmMain.btnGoClick(Sender: TObject);
begin
  FBoard.HumanGo;
end;

procedure TfrmMain.btnStopClick(Sender: TObject);
begin
  FBoard.HumanStop;
end;

procedure TfrmMain.btnMuteClick(Sender: TObject);
begin
  var LAudio := TGostopAudio.Instance;
  LAudio.Muted := not LAudio.Muted;
  if LAudio.Muted then
  begin
    btnMute.Text := 'Sound Off';
  end
  else
  begin
    btnMute.Text := 'Sound On';
  end;
end;

procedure TfrmMain.btnExitClick(Sender: TObject);
begin
  Close;
end;

procedure TfrmMain.BoardStateChanged(Sender: TObject);
begin
  lblStatus.Text := FBoard.StatusText;
  btnGo.Enabled := FBoard.AwaitingGoStop;
  btnStop.Enabled := FBoard.AwaitingGoStop;
end;

procedure TfrmMain.BoardGameOver(Sender: TObject);
begin
  lblStatus.Text := FBoard.StatusText;
  btnGo.Enabled := False;
  btnStop.Enabled := False;
end;

end.
