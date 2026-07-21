unit Gostop.Dialog.Shodang;

// 쇼당(AI가 쇼당을 걸어 사람에게 수락/거절을 묻는) 다이얼로그. TGostopDialog 분리의 세 번째 사례이자
// "게임 카드를 그리는" 첫 다이얼로그 — 공개 위협 패를 캔버스 무관 렌더러(TCardFaceRender)로 자기
// Canvas 에 그린다(이미지 캐시는 보드 소유를 참조만). 결과(받기/거절)는 콜백으로 반환하고, 표시/숨김은
// 보드가 게임 상태(FShodangPending)를 설정/응답 두 지점에서 토글한다.

interface

{$REGION 'uses'}
uses
  System.SysUtils,
  System.Types,
  FMX.Graphics,
  Gostop.Dialog,
  Gostop.CardImages;
{$ENDREGION}

type
  /// <summary>AI 쇼당 → 사람 수락/거절 다이얼로그(공개 위협 패 + [받기]/[거절]). 결과는 OnRespond 콜백.</summary>
  TShodangDialog = class(TGostopDialog)
  strict private
    FCards: TArray<string>;      // 공개 위협 패(AssetId)
    FCardW: Single;              // 원본 카드 폭(표시 시 0.7배)
    FCardH: Single;
    FImages: TCardImageCache;    // 카드 이미지 캐시(보드 소유 — 참조만)
    FOnRespond: TProc<Boolean>;  // 결과 콜백(True=받기, False=거절)
    FBtnYes: TDialogButton;
    FBtnNo: TDialogButton;
  strict protected
    procedure BuildButtons; override;
    procedure DrawContent(const ACanvas: TCanvas; const APanel: TRectF); override;
  public
    /// <summary>공개 패·콜백을 세팅하고 다이얼로그를 띄운다.</summary>
    procedure Present(const ACallerName: string; const ACards: TArray<string>;
      const ACardW, ACardH: Single; const AImages: TCardImageCache; const AOnRespond: TProc<Boolean>);
  end;

implementation

{$REGION 'uses'}
uses
  System.Math,
  System.UITypes,
  Gostop.Canvas.Helper,
  Gostop.Board.CardRender,
  Gostop.Board.Widgets;
{$ENDREGION}

{$REGION 'TShodangDialog'}
procedure TShodangDialog.Present(const ACallerName: string; const ACards: TArray<string>;
  const ACardW, ACardH: Single; const AImages: TCardImageCache; const AOnRespond: TProc<Boolean>);
begin
  SetupDialog(Format('%s 쇼당! — 받으시겠습니까?', [ACallerName]), Max(Width * 0.4, 420.0), 260.0);
  FCards := ACards;
  FCardW := ACardW;
  FCardH := ACardH;
  FImages := AImages;
  FOnRespond := AOnRespond;
  Popup;
end;

procedure TShodangDialog.BuildButtons;
begin
  FBtnYes := AddButton('받기', dbkPrimary,
    procedure
    begin
      if Assigned(FOnRespond) then
      begin
        FOnRespond(True);
      end;
    end);

  FBtnNo := AddButton('거절', dbkDanger,
    procedure
    begin
      if Assigned(FOnRespond) then
      begin
        FOnRespond(False);
      end;
    end);
end;

procedure TShodangDialog.DrawContent(const ACanvas: TCanvas; const APanel: TRectF);
begin
  // 공개 위협 패(가로로 겹쳐 나열, 원본 카드 크기의 0.7배)
  var LCW := FCardW * 0.7;
  var LCH := FCardH * 0.7;
  var LN := Length(FCards);
  if LN > 0 then
  begin
    var LTotW := LCW + (LN - 1) * LCW * 1.2;
    var LSX := (APanel.Left + APanel.Right) / 2 - LTotW / 2;
    var LCY := APanel.Top + 62;
    for var I := 0 to LN - 1 do
    begin
      TCardFaceRender.Front(ACanvas, RectF(LSX + I * LCW * 1.2, LCY, LSX + I * LCW * 1.2 + LCW, LCY + LCH),
        FImages, FCards[I]);
    end;
  end;

  ACanvas.DrawLabel(RectF(APanel.Left, APanel.Bottom - 96, APanel.Right, APanel.Bottom - 74),
    '받으면 이 판 나가리(둘 다 받을 때), 거절 시 밀리면 독박', $FFB8C4B8, 13);

  var LBtnW := 130.0;
  var LBtnH := 46.0;
  var LGap := 24.0;
  var LCX := (APanel.Left + APanel.Right) / 2;
  var LBtnY := APanel.Bottom - LBtnH - 16;

  FBtnYes.Rect := RectF(LCX - LBtnW - LGap / 2, LBtnY, LCX - LGap / 2, LBtnY + LBtnH);
  FBtnNo.Rect := RectF(LCX + LGap / 2, LBtnY, LCX + LGap / 2 + LBtnW, LBtnY + LBtnH);
end;
{$ENDREGION}

end.
