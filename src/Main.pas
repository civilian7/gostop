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
  Gostop.Board;
{$ENDREGION}

type
  /// <summary>
  ///   메인 폼(초박형). 모든 UI(타이틀 메뉴·컨트롤 바·상태 문구·팝업)는 <see cref="TGostopBoard"/>가
  ///   자체 렌더링하고, 폼은 보드를 전체 화면으로 얹고 종료 요청만 연결한다.
  /// </summary>
  TfrmMain = class(TForm)
    procedure FormCreate(Sender: TObject);
  private
    FBoard: TGostopBoard;
    procedure BoardExitRequest(Sender: TObject);
  end;

var
  frmMain: TfrmMain;

implementation

{$R *.fmx}

procedure TfrmMain.FormCreate(Sender: TObject);
begin
  // 보드를 폼 전체에 얹는다(모든 기능은 보드 안에 있음)
  FBoard := TGostopBoard.Create(Self);
  FBoard.Parent := Self;   // Parent 먼저 지정
  FBoard.Align := TAlignLayout.Client;
  FBoard.OnExitRequest := BoardExitRequest;
end;

procedure TfrmMain.BoardExitRequest(Sender: TObject);
begin
  Close;
end;

end.
