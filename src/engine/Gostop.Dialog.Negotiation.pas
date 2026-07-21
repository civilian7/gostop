unit Gostop.Dialog.Negotiation;

// 4인 광 협상에서 사람이 이번 판에 "참가/포기"를 고르는 다이얼로그. 목함 패널에 내 손패(정렬된 순서,
// 팔 수 있는 광·족보패는 살짝 들어 올림)를 부채꼴로 보여주고 [참가]/[포기] 버튼을 제시한다. 손패 카드는
// 캔버스 무관 렌더(TCardFaceRender.Front)로 자기 Canvas 에 그린다. 결과(참가=True/포기=False)는 콜백으로
// 보드에 돌려주고, 보드가 좌석 참가 판정(P2/P3/P4)과 후속 흐름을 처리한다. (광팔기 결정은 별도 화면.)

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
  /// <summary>참가/포기 결정 다이얼로그(내 손패 부채 + [참가]/[포기]). 결과는 OnDecide 콜백(True=참가).</summary>
  TNegotiationDialog = class(TGostopDialog)
  strict private
    FHand: TArray<string>;       // 정렬된 내 손패(AssetId)
    FRaiseIds: TArray<string>;   // 살짝 들어 올릴 패(팔 수 있는 광·족보)
    FCardW: Single;
    FCardH: Single;
    FImages: TCardImageCache;    // 카드 이미지 캐시(보드 소유 — 참조만)
    FOnDecide: TProc<Boolean>;   // 결과 콜백(True=참가, False=포기)
    FBtnJoin: TDialogButton;
    FBtnPass: TDialogButton;
  strict protected
    function  PanelWidth: Single; override;   // 보드 폭에 비례(넓은 손패 부채) — Paint 시점 컨트롤 크기 기준
    procedure BuildButtons; override;
    procedure DrawContent(const ACanvas: TCanvas; const APanel: TRectF); override;
  public
    /// <summary>손패·콜백을 세팅하고 다이얼로그를 띄운다.</summary>
    procedure Present(const AHand, ARaiseIds: TArray<string>; const ACardW, ACardH: Single;
      const AImages: TCardImageCache; const AOnDecide: TProc<Boolean>);
  end;

implementation

{$REGION 'uses'}
uses
  System.Math,
  Gostop.Board.CardRender,
  Gostop.Board.Widgets;
{$ENDREGION}

{$REGION 'TNegotiationDialog'}
function TNegotiationDialog.PanelWidth: Single;
begin
  Result := Min(Width * 0.86, 760.0);
end;

procedure TNegotiationDialog.Present(const AHand, ARaiseIds: TArray<string>; const ACardW, ACardH: Single;
  const AImages: TCardImageCache; const AOnDecide: TProc<Boolean>);
begin
  SetupDialog('이번 판, 붙으시겠습니까?', Min(Width * 0.86, 760.0), 300.0);
  FHand := AHand;
  FRaiseIds := ARaiseIds;
  FCardW := ACardW;
  FCardH := ACardH;
  FImages := AImages;
  FOnDecide := AOnDecide;
  Popup;
end;

procedure TNegotiationDialog.BuildButtons;
begin
  FBtnJoin := AddButton('참가', dbkPrimary,
    procedure
    begin
      if Assigned(FOnDecide) then
      begin
        FOnDecide(True);
      end;
    end);

  FBtnPass := AddButton('포기', dbkDanger,
    procedure
    begin
      if Assigned(FOnDecide) then
      begin
        FOnDecide(False);
      end;
    end);
end;

procedure TNegotiationDialog.DrawContent(const ACanvas: TCanvas; const APanel: TRectF);
begin
  // 내 손패를 부채꼴로(오른쪽이 위로 겹침), 팔 수 있는 패는 살짝 들어 올려 표시.
  // 다이얼로그 패널엔 공간이 넉넉하므로 카드를 패널 높이에 맞춰 크게 그리고 겹침도 뚜렷하게(50%) 준다
  // — 플레이 화면의 좁은 손패 부채(DrawHandList)보다 크고 부채꼴이 분명히 드러나게.
  var LRegion := RectF(APanel.Left + 24, APanel.Top + 64, APanel.Right - 24, APanel.Bottom - 84);
  var LCount := Length(FHand);
  if (LCount > 0) and (FCardH > 0) then
  begin
    var LCardH := LRegion.Height * 0.94;
    var LCardW := LCardH * (FCardW / FCardH);   // 원본 카드 비율 유지
    var LStep := Min(LCardW * 0.5, (LRegion.Width - 24) / LCount);   // 카드 폭의 절반씩 겹침(뚜렷한 부채)
    var LStartX := (LRegion.Left + LRegion.Right) / 2 - (LStep * (LCount - 1) + LCardW) / 2;
    var LBottom := LRegion.Bottom;
    for var D := 0 to LCount - 1 do
    begin
      var LR := RectF(LStartX + D * LStep, LBottom - LCardH, LStartX + D * LStep + LCardW, LBottom);
      var LDrawR := LR;
      for var LRaiseId in FRaiseIds do
      begin
        if LRaiseId = FHand[D] then
        begin
          LDrawR.Offset(0, -LCardH * 0.1);
          Break;
        end;
      end;

      TCardFaceRender.Front(ACanvas, LDrawR, FImages, FHand[D]);
    end;
  end;

  var LBtnW := 140.0;
  var LBtnH := 48.0;
  var LGap := 30.0;
  var LCX := (APanel.Left + APanel.Right) / 2;
  var LBtnY := APanel.Bottom - LBtnH - 18;

  FBtnJoin.Rect := RectF(LCX - LBtnW - LGap / 2, LBtnY, LCX - LGap / 2, LBtnY + LBtnH);
  FBtnPass.Rect := RectF(LCX + LGap / 2, LBtnY, LCX + LGap / 2 + LBtnW, LBtnY + LBtnH);
end;
{$ENDREGION}

end.
