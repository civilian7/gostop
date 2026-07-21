unit Gostop.Dialog.GoStop;

// 고·스톱 결정 다이얼로그. 사람이 3점 이상 내서 고/스톱을 골라야 할 때 뜬다(제목에 현재 점수). 카드
// 렌더가 없는(점수 정수 + 버튼 2개뿐인) 가장 단순한 게임 중 프롬프트라 TGostopDialog 분리의 두 번째
// 사례로 삼는다. 결과(고/스톱)는 콜백으로 보드에 돌려주고, 표시/숨김은 보드가 게임 상태(FAwaitingGoStop)
// 를 단일 퍼널(AfterAction)에서 동기화한다 — 다이얼로그는 시각·클릭만 소유.

interface

{$REGION 'uses'}
uses
  System.SysUtils,
  System.Types,
  FMX.Graphics,
  Gostop.Dialog;
{$ENDREGION}

type
  /// <summary>고·스톱 결정 다이얼로그(점수 표시 + [고]/[스톱]). 결과는 OnGo/OnStop 콜백으로 반환.</summary>
  TGoStopPromptDialog = class(TGostopDialog)
  strict private
    FOnGo: TProc;
    FOnStop: TProc;
    FBtnGo: TDialogButton;
    FBtnStop: TDialogButton;
  strict protected
    procedure BuildButtons; override;
    procedure DrawContent(const ACanvas: TCanvas; const APanel: TRectF); override;
  public
    /// <summary>현재 점수·콜백을 세팅하고 다이얼로그를 띄운다.</summary>
    procedure Present(const AScore: Integer; const AOnGo, AOnStop: TProc);
  end;

implementation

{$REGION 'uses'}
uses
  System.Math,
  Gostop.Board.Widgets;
{$ENDREGION}

{$REGION 'TGoStopPromptDialog'}
procedure TGoStopPromptDialog.Present(const AScore: Integer; const AOnGo, AOnStop: TProc);
begin
  SetupDialog(Format('%d점! 고냐, 스톱이냐!', [AScore]), Max(Width * 0.34, 340.0), 128.0);
  FOnGo := AOnGo;
  FOnStop := AOnStop;
  Popup;
end;

procedure TGoStopPromptDialog.BuildButtons;
begin
  FBtnGo := AddButton('고', dbkPrimary,
    procedure
    begin
      if Assigned(FOnGo) then
      begin
        FOnGo();
      end;
    end);

  FBtnStop := AddButton('스톱', dbkDanger,
    procedure
    begin
      if Assigned(FOnStop) then
      begin
        FOnStop();
      end;
    end);
end;

procedure TGoStopPromptDialog.DrawContent(const ACanvas: TCanvas; const APanel: TRectF);
begin
  var LBtnW := 120.0;
  var LBtnH := 46.0;
  var LGap := 24.0;
  var LCX := (APanel.Left + APanel.Right) / 2;
  var LBtnY := APanel.Bottom - LBtnH - 16;

  FBtnGo.Rect := RectF(LCX - LBtnW - LGap / 2, LBtnY, LCX - LGap / 2, LBtnY + LBtnH);
  FBtnStop.Rect := RectF(LCX + LGap / 2, LBtnY, LCX + LGap / 2 + LBtnW, LBtnY + LBtnH);
end;
{$ENDREGION}

end.
