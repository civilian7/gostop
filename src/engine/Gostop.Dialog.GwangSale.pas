unit Gostop.Dialog.GwangSale;

// 광 팔기 발표 다이얼로그. 4인 광팔기에서 판매자가 판 광 패를 판매자 아바타(환호)와 함께 발표한다.
// 입력 버튼이 없고(발표 전용) 아무 곳이나 클릭하면 스킵(OnSkip 콜백 → 보드가 다음 연출로 진행), 별도
// 자동진행 타이머는 보드가 유지한다. 판 광 패는 캔버스 무관 회전 렌더(TCardFaceRender.FrontRotated)로
// 자기 Canvas 에 좌우로 살짝 흔들며 그린다 — 흔들림 위상은 이 다이얼로그가 자체 타이머로 구동한다.

interface

{$REGION 'uses'}
uses
  System.SysUtils,
  System.Classes,
  System.Types,
  System.UITypes,
  FMX.Types,
  FMX.Graphics,
  Gostop.Dialog,
  Gostop.CardImages;
{$ENDREGION}

type
  /// <summary>광 팔기 발표 다이얼로그(판매자 아바타 + 판 광 패, 클릭 시 스킵). 결과 없음 — 발표 전용.</summary>
  TGwangSaleDialog = class(TGostopDialog)
  strict private
    FSellerLabel: string;
    FAvatar: TBitmap;            // 판매자 환호 아바타(보드 소유 — 참조만)
    FCards: TArray<string>;      // 판 광 패(AssetId)
    FCardW: Single;
    FCardH: Single;
    FImages: TCardImageCache;    // 카드 이미지 캐시(보드 소유 — 참조만)
    FOnSkip: TProc;              // 클릭 스킵 콜백
    FPhase: Single;              // 좌우 흔들림 위상
    FShakeTimer: TTimer;
    procedure ShakeTick(Sender: TObject);
  strict protected
    procedure DrawContent(const ACanvas: TCanvas; const APanel: TRectF); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Single); override;
  public
    constructor Create(AOwner: TComponent); override;
    /// <summary>발표 데이터·스킵 콜백을 세팅하고 흔들림을 시작하며 다이얼로그를 띄운다.</summary>
    procedure Present(const ASellerLabel: string; const AAvatar: TBitmap; const ACards: TArray<string>;
      const ACardW, ACardH: Single; const AImages: TCardImageCache; const AOnSkip: TProc);
  end;

implementation

{$REGION 'uses'}
uses
  System.Math,
  Gostop.Canvas.Helper,
  Gostop.Board.CardRender;
{$ENDREGION}

{$REGION 'TGwangSaleDialog'}
constructor TGwangSaleDialog.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FShakeTimer := TTimer.Create(Self);
  FShakeTimer.Interval := 33;   // ~30fps 흔들림
  FShakeTimer.Enabled := False;
  FShakeTimer.OnTimer := ShakeTick;
end;

procedure TGwangSaleDialog.ShakeTick(Sender: TObject);
begin
  if not Visible then
  begin
    FShakeTimer.Enabled := False;   // 보드가 숨기면 스스로 멈춘다
    Exit;
  end;

  FPhase := FPhase + 0.35;
  Repaint;
end;

procedure TGwangSaleDialog.Present(const ASellerLabel: string; const AAvatar: TBitmap; const ACards: TArray<string>;
  const ACardW, ACardH: Single; const AImages: TCardImageCache; const AOnSkip: TProc);
begin
  SetupDialog('광 팔기!', Max(Width * 0.5, 460.0), 260.0);
  FSellerLabel := ASellerLabel;
  FAvatar := AAvatar;
  FCards := ACards;
  FCardW := ACardW;
  FCardH := ACardH;
  FImages := AImages;
  FOnSkip := AOnSkip;
  FPhase := 0;
  FShakeTimer.Enabled := True;
  Popup;
end;

// 발표 전용이라 버튼이 없다 — 아무 곳이나 클릭하면 스킵한다.
procedure TGwangSaleDialog.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Single);
begin
  if Assigned(FOnSkip) then
  begin
    FOnSkip();
  end;
end;

procedure TGwangSaleDialog.DrawContent(const ACanvas: TCanvas; const APanel: TRectF);
begin
  var LBodyCy := (APanel.Top + APanel.Bottom) / 2 + 10;   // 제목 영역만큼 살짝 아래로

  // 좌측: 판매자 아바타(크게) + 아래에 닉네임
  var LAvSz := 130.0;
  var LAvColW := Max(LAvSz, 150.0);
  var LAvCx := APanel.Left + 24 + LAvColW / 2;
  var LAvR := RectF(LAvCx - LAvSz / 2, LBodyCy - LAvSz / 2 - 12, LAvCx + LAvSz / 2, LBodyCy + LAvSz / 2 - 12);
  if Assigned(FAvatar) then
  begin
    ACanvas.DrawBitmap(FAvatar, RectF(0, 0, FAvatar.Width, FAvatar.Height), LAvR, 1, False);
  end;

  ACanvas.DrawLabel(RectF(LAvCx - LAvColW / 2, LAvR.Bottom + 8, LAvCx + LAvColW / 2, LAvR.Bottom + 34),
    FSellerLabel, TAlphaColors.Gold, 18);

  // 우측: 판 광 패(가로 나열, 좌우로 살짝 흔들며)
  var LCW := FCardW * 0.8;
  var LCH := FCardH * 0.8;
  var LN := Length(FCards);
  if LN > 0 then
  begin
    var LCardAreaL := APanel.Left + 24 + LAvColW + 20;
    var LCardAreaR := APanel.Right - 24;
    var LTotW := LCW + (LN - 1) * LCW * 1.12;
    var LStartX := (LCardAreaL + LCardAreaR) / 2 - LTotW / 2;
    for var I := 0 to LN - 1 do
    begin
      var LCX := LStartX + I * LCW * 1.12;
      var LPh := FPhase + I * 0.9;   // 카드마다 위상 어긋남
      var LDX := Sin(LPh) * LCW * 0.16;
      var LAng := Sin(LPh) * 3.0;
      TCardFaceRender.FrontRotated(ACanvas, LCX + LCW / 2 + LDX, LBodyCy, LCW, LCH, LAng, FImages, FCards[I]);
    end;
  end;
end;
{$ENDREGION}

end.
