unit Main;

interface

{$REGION 'uses'}
uses
  System.SysUtils,
  System.IOUtils,
  System.IniFiles,
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
  ///   자체 렌더링하고, 폼은 보드를 전체 화면으로 얹고 종료 요청·창 위치/크기 기억만 담당한다.
  /// </summary>
  TfrmMain = class(TForm)
    procedure FormCreate(Sender: TObject);
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
    procedure FormKeyDown(Sender: TObject; var Key: Word; var KeyChar: WideChar; Shift: TShiftState);
  private
    FBoard: TGostopBoard;
    procedure BoardExitRequest(Sender: TObject);
    function IniPath: string;
    procedure LoadWindowGeometry;
    procedure SaveWindowGeometry;
  end;

var
  frmMain: TfrmMain;

implementation

{$R *.fmx}

const
  MIN_WIDTH = 900;   // 좌석 패널이 고정 픽셀 크기라 이보다 작으면 레이아웃이 깨짐
  MIN_HEIGHT = 700;

// 게임 본체(Gostop.Board.pas)와 같은 exe 옆 gostop.ini를 [Window] 섹션으로 공유
function TfrmMain.IniPath: string;
begin
  Result := TPath.Combine(TPath.GetDirectoryName(ParamStr(0)), 'gostop.ini');
end;

// 저장된 창 위치/크기가 있으면 그대로 복원하고, 없으면 디자인 크기 그대로 화면 중앙에 배치
procedure TfrmMain.LoadWindowGeometry;
begin
  var LIni := TIniFile.Create(IniPath);
  try
    if not LIni.ValueExists('Window', 'Width') then
    begin
      Position := TFormPosition.ScreenCenter;
      Exit;
    end;

    var LWidth := LIni.ReadInteger('Window', 'Width', Round(Width));
    var LHeight := LIni.ReadInteger('Window', 'Height', Round(Height));
    if (LWidth < MIN_WIDTH) or (LHeight < MIN_HEIGHT) then
    begin
      // 손상되었거나 너무 작게 저장된 값은 무시하고 기본 크기로 중앙 배치
      Position := TFormPosition.ScreenCenter;
      Exit;
    end;

    Position := TFormPosition.Designed;
    Width := LWidth;
    Height := LHeight;
    Left := LIni.ReadInteger('Window', 'Left', Round(Left));
    Top := LIni.ReadInteger('Window', 'Top', Round(Top));
  finally
    LIni.Free;
  end;
end;

procedure TfrmMain.SaveWindowGeometry;
begin
  try
    var LIni := TIniFile.Create(IniPath);
    try
      LIni.WriteInteger('Window', 'Left', Round(Left));
      LIni.WriteInteger('Window', 'Top', Round(Top));
      LIni.WriteInteger('Window', 'Width', Round(Width));
      LIni.WriteInteger('Window', 'Height', Round(Height));
    finally
      LIni.Free;
    end;
  except
    // 저장 실패(쓰기 금지 폴더 등)는 종료를 막지 않도록 무시
  end;
end;

procedure TfrmMain.FormCreate(Sender: TObject);
begin
  LoadWindowGeometry;

  // 보드를 폼 전체에 얹는다(모든 기능은 보드 안에 있음)
  FBoard := TGostopBoard.Create(Self);
  FBoard.Parent := Self;   // Parent 먼저 지정
  FBoard.Align := TAlignLayout.Client;
  FBoard.OnExitRequest := BoardExitRequest;

  // 스페이스바 일시정지: 닉네임 입력 등 별도 컨트롤이 포커스를 갖지 않은 한 폼이 키를 받는다
  // (FMX는 VCL의 KeyPreview가 없음 — 포커스된 자식이 없을 때 폼으로 키 이벤트가 온다)
  OnKeyDown := FormKeyDown;
end;

procedure TfrmMain.FormClose(Sender: TObject; var Action: TCloseAction);
begin
  SaveWindowGeometry;
end;

procedure TfrmMain.FormKeyDown(Sender: TObject; var Key: Word; var KeyChar: WideChar; Shift: TShiftState);
begin
  if (Key = vkSpace) and Assigned(FBoard) and (not FBoard.IsTextInputActive) then
  begin
    FBoard.TogglePause;
    Key := 0;
    KeyChar := #0;
  end;
end;

procedure TfrmMain.BoardExitRequest(Sender: TObject);
begin
  Close;
end;

end.
