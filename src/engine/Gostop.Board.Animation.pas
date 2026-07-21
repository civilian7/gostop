unit Gostop.Board.Animation;

// 보드 애니메이션 프레임워크. Gostop.Board 가 비대해져(1만 줄+) 개별 연출마다 타이머·시작·틱·
// 렌더 세트를 중복 보유하던 것을, 단일 타이머로 구동되는 애니메이션 매니저 + 추상 애니 클래스로
// 분리한다. 각 애니는 IAnimationHost 로 보드의 최소 표면(Canvas·좌표·카드 렌더·배속 등)에만
// 접근하므로 보드 내부 필드에 강결합되지 않는다. 첫 입주자는 나가리(무승부) 연출.

interface

{$REGION 'uses'}
uses
  System.SysUtils,
  System.Types,
  System.UITypes,
  System.Generics.Collections,
  FMX.Types,
  FMX.Graphics,
  Gostop.Cards,
  Gostop.Board.Layout;
{$ENDREGION}

type
  /// <summary>
  ///   애니메이션이 보드(호스트)에 요구하는 최소 표면. TGostopBoard 가 구현한다.
  ///   여기에 없는 보드 내부 상태에는 애니가 접근하지 못하도록 의도적으로 좁게 유지한다.
  /// </summary>
  IAnimationHost = interface
    ['{A3F1C2D4-5E6B-4A7C-8D9E-0F1A2B3C4D5E}']
    /// <summary>렌더 대상 Canvas.</summary>
    function GetCanvas: TCanvas;
    /// <summary>애니 속도 배율(0.5~2.0). 매니저가 델타에 곱해 전달하므로 애니는 직접 곱하지 않아도 된다.</summary>
    function GetGameSpeed: Single;
    /// <summary>바닥·더미가 놓이는 중앙 영역(흔들림 오프셋 반영됨).</summary>
    function CenterRegion: TRectF;
    /// <summary>현재 카드 한 장의 크기.</summary>
    function CardSize: TSizeF;
    /// <summary>흔들기 연출의 현재 좌우 오프셋(px). 고정 표시물은 이 값을 상쇄해 안 떨게 한다.</summary>
    function ShakeOffsetX: Single;
    /// <summary>중심 좌표·각도로 카드 한 장을 그린다(보드의 렌더 프리미티브 위임).</summary>
    procedure DrawCardRotated(const ACenterX, ACenterY, ACardW, ACardH, AAngle: Single; const AAssetId: string; const ABack: Boolean);
    /// <summary>플레이어 패널(아바타·점수·머니 등)을 그린다. 단계형 전체화면 연출의 배경용.</summary>
    procedure DrawPanels;
    /// <summary>딜/보너스에서 카드가 출발하는 뒷패(더미) 중심 좌표.</summary>
    function DealDeckPoint: TPointF;
    /// <summary>화면 흔들림 연출을 시작한다.</summary>
    procedure BeginShakeEffect(const AAmplitude: Single);
    /// <summary>효과음을 재생한다.</summary>
    procedure PlaySound(const AName: string);
    /// <summary>보드에 다시 그리기를 요청한다.</summary>
    procedure RequestRepaint;
  end;

  /// <summary>모든 보드 애니메이션의 추상 기반. 시간축(델타 ms)으로 진행하며 스스로 렌더한다.</summary>
  TBoardAnimation = class abstract
  protected
    FHost: IAnimationHost;
    FDone: Boolean;
    FOnDone: TProc;
  public
    constructor Create(const AHost: IAnimationHost);
    /// <summary>배속이 이미 반영된 델타(ms)만큼 진행시킨다. 끝나면 FDone 을 True 로 세운다.</summary>
    procedure Update(const ADeltaMs: Single); virtual; abstract;
    /// <summary>현재 진행 상태를 Canvas 에 그린다.</summary>
    procedure Draw; virtual; abstract;
    /// <summary>연출이 끝났는가.</summary>
    property Done: Boolean read FDone;
    /// <summary>연출 완료 시 매니저가 한 번 호출하는 콜백(정산창 진행 등).</summary>
    property OnDone: TProc read FOnDone write FOnDone;
  end;

  /// <summary>
  ///   활성 애니메이션들을 단일 타이머(~60fps)로 함께 구동하는 매니저. 완료된 애니는 OnDone 을
  ///   호출한 뒤 해제한다. 남은 애니가 없으면 타이머를 멈춰 유휴 부하를 없앤다.
  /// </summary>
  TAnimationManager = class
  strict private
    FHost: IAnimationHost;
    FAnims: TObjectList<TBoardAnimation>;
    FTimer: TTimer;
    procedure TimerTick(Sender: TObject);
  public
    constructor Create(const AHost: IAnimationHost);
    destructor Destroy; override;
    /// <summary>애니를 등록하고 구동을 시작한다.</summary>
    procedure Add(const AAnim: TBoardAnimation);
    /// <summary>등록된 모든 애니를 그린다(보드의 최상단 렌더 단계에서 호출).</summary>
    procedure DrawAll;
    /// <summary>모든 애니를 즉시 제거한다(판 전환·타이틀 복귀 등).</summary>
    procedure Clear;
    /// <summary>진행 중인 애니가 있는가.</summary>
    function Busy: Boolean;
  end;

  /// <summary>나가리 던지기 렌더에 쓰는 먹은 패 한 장의 스냅샷(출발=좌석 아바타, 도착=중앙 바닥).</summary>
  TNagariCard = record
    AssetId: string;
    FromX: Single;   // 출발 중심(좌석 아바타)
    FromY: Single;
    ToX: Single;     // 도착 중심(중앙 바닥에 흩뿌려짐)
    ToY: Single;
    Delay: Single;   // 던지기 시작 지연(정규화 진행도 0~NAGARI_THROW_WINDOW)
    Rot: Single;     // 도착 시 회전각(도)
  end;

  /// <summary>
  ///   나가리(무승부) 연출. 시작 시 받은 '먹은 패' 스냅샷들을 각 좌석 아바타에서 중앙 바닥으로
  ///   시차를 두고 우르르 던져 쌓은 뒤, 가운데 '나가리' 붉은 도장이 크게 나타나 제 크기로
  ///   정착(쾅)하며 화면을 흔든다. 좌표 스냅샷만 받으므로 게임 상태에 의존하지 않는 자기완결형.
  /// </summary>
  TNagariAnimation = class(TBoardAnimation)
  strict private
    FT: Single;                  // 진행도 0~1
    FCards: TArray<TNagariCard>;
    FStamped: Boolean;           // 쾅 시점(흔들림·소리)을 한 번만 발동
    procedure DrawThrownCards;
    procedure DrawStamp;
  public
    constructor Create(const AHost: IAnimationHost; const ACards: TArray<TNagariCard>);
    procedure Update(const ADeltaMs: Single); override;
    procedure Draw; override;
  end;

  /// <summary>
  ///   딜 직전 셔플 연출. 바닥 중앙에 뒷면 카드 다발을 무작위 위치·각도로 짧은 주기마다 재배치하며
  ///   잠시 보여줘 '섞는' 느낌을 준다. 단계형 전체화면(PaintGame 이 이 단계에서 Exit)으로, 배경
  ///   패널까지 스스로 그린다. 게임 데이터에 의존하지 않는 자기완결형.
  /// </summary>
  TShuffleAnimation = class(TBoardAnimation)
  strict private
    FElapsed: Single;            // 전체 경과(초)
    FFlicker: Single;            // 다음 재배치까지 남은 시간(초)
    FPts: TArray<TPointF>;       // 카드별 무작위 위치
    FAngles: TArray<Single>;     // 카드별 무작위 각도
    procedure RandomizeLayout;
  public
    constructor Create(const AHost: IAnimationHost);
    procedure Update(const ADeltaMs: Single); override;
    procedure Draw; override;
  end;

  /// <summary>딜 애니메이션에서 카드 한 장의 착지 정보(Board 가 좌표·각도·스케일을 계산해 채운다).</summary>
  TDealFly = record
    Target: TPointF;     // 착지 지점(중심)
    Card: THwatuCard;    // 바닥 카드의 앞면 표시용(손패는 미사용)
    IsFloor: Boolean;    // True=바닥, False=손패(뒷면)
    Reveal: Boolean;     // True면 바닥패가 앞면으로 착지(4인은 1장만 True)
    Pos: TSeatPos;       // 손패 대상 자리
    Angle: Single;       // 착지 각도(좌/우 자리는 90/270)
    Scale: Single;       // 카드 크기 배율
  end;

  /// <summary>
  ///   딜(패 돌리기) 연출. Board 가 계산한 착지 정보 배열을 받아, 뒷패 더미에서 한 장씩 각 목적지로
  ///   ease-out 비행시켜 순서대로 착지시킨다(공개 바닥패는 중간에 앞면으로 플립). 단계형 전체화면.
  /// </summary>
  TDealAnimation = class(TBoardAnimation)
  strict private
    FFlies: TArray<TDealFly>;
    FLanded: Integer;            // 착지 완료 장수
    FT: Single;                  // 현재 카드 비행 진행(0~1)
  public
    constructor Create(const AHost: IAnimationHost; const AFlies: TArray<TDealFly>);
    procedure Update(const ADeltaMs: Single); override;
    procedure Draw; override;
  end;

  /// <summary>
  ///   화면 흔들기 연출(값 제공형). 스스로 그리는 것은 없고 현재 좌우 오프셋(OffsetX)만 제공하며,
  ///   그 값을 CenterRegion·배너·나가리 도장 등이 참조해 함께 떨린다. 감쇠 사인파로 진폭이 0으로
  ///   수렴한다. 진행 중 다시 시작되면 Restart 로 처음부터 다시 흔든다.
  /// </summary>
  TShakeAnimation = class(TBoardAnimation)
  strict private
    FT: Single;                  // 진행도 0~1(1=정지)
    FAmp: Single;                // 진폭 배율(흔들기 1.0, 폭탄 등은 더 크게)
  public
    constructor Create(const AHost: IAnimationHost; const AAmplitude: Single);
    procedure Restart(const AAmplitude: Single);
    function OffsetX: Single;     // 현재 좌우 오프셋(px)
    procedure Update(const ADeltaMs: Single); override;
    procedure Draw; override;     // 그리는 것 없음(no-op)
  end;

implementation

{$REGION 'uses'}
uses
  System.Math,
  System.Math.Vectors,
  Gostop.Canvas.Helper,
  Gostop.Fonts,
  Gostop.Palette;
{$ENDREGION}

const
  // 나가리 연출 타이밍(진행도 FT 0~1 기준). 총 지속은 NAGARI_DURATION_MS(배속 미적용 기준).
  NAGARI_DURATION_MS = 1500.0;
  NAGARI_THROW_WINDOW = 0.34;   // 카드들이 던져지기 시작하는 시차 창(정규화) — 이 안에서 우르르 출발
  NAGARI_FLY_T = 0.26;          // 카드 한 장이 아바타→중앙으로 날아가는 소요(정규화)
  // 마지막 카드 도착 = THROW_WINDOW + FLY_T = 0.60. 그 뒤 도장을 찍는다.
  NAGARI_STAMP_IN_T = 0.62;     // '나가리' 도장이 나타나기 시작하는 진행도
  NAGARI_STAMP_SET_T = 0.82;    // 도장이 제 크기로 정착(쾅)하는 진행도 — 이때 흔들림·소리

  // 셔플 연출 타이밍(초 단위, 배속은 매니저가 델타에 반영).
  SHUFFLE_DURATION_SECONDS = 1.1;   // 셔플 연출 총 길이
  SHUFFLE_FLICKER_SECONDS = 0.14;   // 카드 다발 재배치 주기
  SHUFFLE_CARD_COUNT = 12;          // 흩어져 보일 카드 장수

  // 흔들기 연출.
  SHAKE_DURATION_MS = 700.0;        // 진동 지속 시간
  SHAKE_CYCLES = 4.0;               // 지속 시간 동안의 좌우 왕복 횟수
  SHAKE_AMP_RATIO = 0.34;           // 진폭 = 카드 폭 × 이 비율(High-DPI에서도 비율 유지)

{$REGION 'TBoardAnimation'}
constructor TBoardAnimation.Create(const AHost: IAnimationHost);
begin
  inherited Create;
  FHost := AHost;
  FDone := False;
end;
{$ENDREGION}

{$REGION 'TAnimationManager'}
constructor TAnimationManager.Create(const AHost: IAnimationHost);
begin
  inherited Create;
  FHost := AHost;
  FAnims := TObjectList<TBoardAnimation>.Create(True);   // OwnsObjects — 완료 시 해제
  FTimer := TTimer.Create(nil);
  FTimer.Interval := 16;   // ~60fps
  FTimer.Enabled := False;
  FTimer.OnTimer := TimerTick;
end;

destructor TAnimationManager.Destroy;
begin
  FTimer.Free;
  FAnims.Free;
  inherited;
end;

procedure TAnimationManager.Add(const AAnim: TBoardAnimation);
begin
  FAnims.Add(AAnim);
  FTimer.Enabled := True;
end;

procedure TAnimationManager.Clear;
begin
  FAnims.Clear;
  FTimer.Enabled := False;
end;

function TAnimationManager.Busy: Boolean;
begin
  Result := FAnims.Count > 0;
end;

procedure TAnimationManager.DrawAll;
begin
  for var I := 0 to FAnims.Count - 1 do
  begin
    FAnims[I].Draw;
  end;
end;

procedure TAnimationManager.TimerTick(Sender: TObject);
begin
  if FAnims.Count = 0 then
  begin
    FTimer.Enabled := False;
    Exit;
  end;

  // 배속을 여기서 한 번 곱해 전달하면 각 애니는 순수 진행만 신경 쓰면 된다
  var LDelta := FTimer.Interval * FHost.GetGameSpeed;
  for var I := FAnims.Count - 1 downto 0 do
  begin
    var LAnim := FAnims[I];
    LAnim.Update(LDelta);
    if LAnim.Done then
    begin
      var LCallback := LAnim.OnDone;
      FAnims.Delete(I);   // OwnsObjects → 애니 객체 해제
      if Assigned(LCallback) then
      begin
        LCallback();      // 정산창 진행 등 후속 흐름(해제된 애니를 참조하지 않는다)
      end;
    end;
  end;

  FHost.RequestRepaint;

  if FAnims.Count = 0 then
  begin
    FTimer.Enabled := False;
  end;
end;
{$ENDREGION}

{$REGION 'TNagariAnimation'}
constructor TNagariAnimation.Create(const AHost: IAnimationHost; const ACards: TArray<TNagariCard>);
begin
  inherited Create(AHost);
  FCards := ACards;
  FT := 0;
  FStamped := False;
end;

procedure TNagariAnimation.Update(const ADeltaMs: Single);
begin
  FT := FT + ADeltaMs / NAGARI_DURATION_MS;

  // 도장이 정착하는 순간: 화면을 흔들고 무승부 소리를 낸다(한 번만)
  if (not FStamped) and (FT >= NAGARI_STAMP_SET_T) then
  begin
    FStamped := True;
    FHost.BeginShakeEffect(1.4);
    FHost.PlaySound('draw');
  end;

  if FT >= 1 then
  begin
    FT := 1;
    FDone := True;
  end;
end;

// 먹은 패를 각 좌석 아바타(출발)에서 중앙 바닥(도착)으로 시차를 두고 날려 그린다.
// 아직 던질 차례가 안 된 카드(로컬 진행 <=0)는 그리지 않는다(원본 먹은패 더미가 그 자리에 있음).
procedure TNagariAnimation.DrawThrownCards;
begin
  var LCS := FHost.CardSize;
  for var I := 0 to High(FCards) do
  begin
    var LCard := FCards[I];
    var LP := (FT - LCard.Delay) / NAGARI_FLY_T;
    if LP <= 0 then
    begin
      Continue;
    end;

    if LP > 1 then
    begin
      LP := 1;
    end;

    var LEase := 1 - Sqr(1 - LP);   // ease-out(빠르게 날아가 부드럽게 안착)
    var LX := LCard.FromX + (LCard.ToX - LCard.FromX) * LEase;
    var LY := LCard.FromY + (LCard.ToY - LCard.FromY) * LEase;
    FHost.DrawCardRotated(LX, LY, LCS.Width, LCS.Height, LCard.Rot * LEase, LCard.AssetId, False);
  end;
end;

// 가운데 '나가리' 붉은 인주 도장. 큰 크기로 나타나 제 크기로 감속하며 정착한다.
procedure TNagariAnimation.DrawStamp;
begin
  if FT < NAGARI_STAMP_IN_T then
  begin
    Exit;
  end;

  var LS := (FT - NAGARI_STAMP_IN_T) / (NAGARI_STAMP_SET_T - NAGARI_STAMP_IN_T);
  if LS > 1 then
  begin
    LS := 1;
  end;

  var LScale := 1.0 + Sqr(1 - LS) * 1.1;   // 2.1배 → 1.0배로 감속
  var LAlpha := LS;                        // 등장하며 서서히 진해짐

  var LCanvas := FHost.GetCanvas;
  var LCen := FHost.CenterRegion;
  var LCx := (LCen.Left + LCen.Right) / 2 - FHost.ShakeOffsetX;   // 도장은 흔들림에 같이 떨지 않게 상쇄
  var LCy := (LCen.Top + LCen.Bottom) / 2;
  var LR0 := System.Math.Min(LCen.Width, LCen.Height) * 0.30;

  var LSaved := LCanvas.Matrix;
  var LMatrix := TMatrix.CreateTranslation(-LCx, -LCy) *
    TMatrix.CreateScaling(LScale, LScale) *
    TMatrix.CreateRotation(DegToRad(-8)) *
    TMatrix.CreateTranslation(LCx, LCy);
  LCanvas.SetMatrix(LMatrix * LSaved);
  try
    var LOuter := RectF(LCx - LR0, LCy - LR0, LCx + LR0, LCy + LR0);
    var LInner := RectF(LCx - LR0 * 0.80, LCy - LR0 * 0.80, LCx + LR0 * 0.80, LCy + LR0 * 0.80);
    var LFillAlpha := Round(LAlpha * $42);
    var LLineAlpha := Round(LAlpha * $FF);
    var LLineColor := TAlphaColor((Cardinal(LLineAlpha) shl 24) or TPalette.StampLineRgb);

    LCanvas.FillCircle(LOuter, TAlphaColor((Cardinal(LFillAlpha) shl 24) or TPalette.StampFillRgb));
    LCanvas.StrokeCircle(LOuter, LLineColor, System.Math.Max(3.0, LR0 * 0.06));
    LCanvas.StrokeCircle(LInner, LLineColor, System.Math.Max(2.0, LR0 * 0.03));

    LCanvas.Fill.Kind := TBrushKind.Solid;
    LCanvas.Fill.Color := TAlphaColor((Cardinal(LLineAlpha) shl 24) or TPalette.StampTextRgb);
    TGostopFonts.Apply(LCanvas, LR0 * 0.42, True);
    LCanvas.FillText(LOuter, '나가리', False, 1, [], TTextAlign.Center, TTextAlign.Center);
  finally
    LCanvas.SetMatrix(LSaved);
  end;
end;

procedure TNagariAnimation.Draw;
begin
  DrawThrownCards;
  DrawStamp;
end;
{$ENDREGION}

{$REGION 'TShuffleAnimation'}
constructor TShuffleAnimation.Create(const AHost: IAnimationHost);
begin
  inherited Create(AHost);
  FElapsed := 0;
  FFlicker := 0;
  RandomizeLayout;
end;

// 카드 다발이 뭉쳐 보이도록 좁은 반경 안에서 무작위 위치·각도로 재배치한다.
procedure TShuffleAnimation.RandomizeLayout;
begin
  var LCen := FHost.CenterRegion;
  var LCS := FHost.CardSize;
  var LMidX := (LCen.Left + LCen.Right) / 2;
  var LMidY := (LCen.Top + LCen.Bottom) / 2;
  var LSpreadX := LCS.Width * 0.55;
  var LSpreadY := LCS.Height * 0.45;
  SetLength(FPts, SHUFFLE_CARD_COUNT);
  SetLength(FAngles, SHUFFLE_CARD_COUNT);
  for var I := 0 to SHUFFLE_CARD_COUNT - 1 do
  begin
    FPts[I] := PointF(LMidX + (Random - 0.5) * LSpreadX, LMidY + (Random - 0.5) * LSpreadY);
    FAngles[I] := Random * 50 - 25;   // -25~+25도, 흐트러진 느낌
  end;
end;

procedure TShuffleAnimation.Update(const ADeltaMs: Single);
begin
  var LDt := ADeltaMs / 1000;   // 초 단위(매니저가 배속을 이미 반영)
  FElapsed := FElapsed + LDt;
  FFlicker := FFlicker + LDt;
  if FFlicker >= SHUFFLE_FLICKER_SECONDS then
  begin
    FFlicker := 0;
    RandomizeLayout;
    FHost.PlaySound('card_flip');
  end;

  if FElapsed >= SHUFFLE_DURATION_SECONDS then
  begin
    FDone := True;
  end;
end;

procedure TShuffleAnimation.Draw;
begin
  FHost.DrawPanels;   // 단계형 전체화면 — 배경 패널까지 스스로 그린다

  var LCS := FHost.CardSize;
  for var I := 0 to High(FPts) do
  begin
    FHost.DrawCardRotated(FPts[I].X, FPts[I].Y, LCS.Width * 0.6, LCS.Height * 0.6, FAngles[I], '', True);
  end;
end;
{$ENDREGION}

{$REGION 'TDealAnimation'}
constructor TDealAnimation.Create(const AHost: IAnimationHost; const AFlies: TArray<TDealFly>);
begin
  inherited Create(AHost);
  FFlies := AFlies;
  FLanded := 0;
  FT := 0;
end;

procedure TDealAnimation.Update(const ADeltaMs: Single);
begin
  // 원본: 틱(16ms)마다 진행 0.22×배속. 매니저 ADeltaMs=16×배속이므로 동일하게 환산.
  FT := FT + 0.22 * ADeltaMs / 16;
  if FT >= 1 then
  begin
    FT := 0;
    Inc(FLanded);
    FHost.PlaySound('card_place');
    if FLanded >= Length(FFlies) then
    begin
      FDone := True;
    end;
  end;
end;

procedure TDealAnimation.Draw;
begin
  FHost.DrawPanels;   // 딜 중에도 아바타·정보 패널 유지

  var LCS := FHost.CardSize;
  var LDeckPt := FHost.DealDeckPoint;

  // 뒷패 스택(뒷면 겹침)
  for var I := 2 downto 0 do
  begin
    FHost.DrawCardRotated(LDeckPt.X - I * 2, LDeckPt.Y - I * 2, LCS.Width * 0.8, LCS.Height * 0.8, 0, '', True);
  end;

  // 착지한 카드
  for var I := 0 to FLanded - 1 do
  begin
    var LF := FFlies[I];
    FHost.DrawCardRotated(LF.Target.X, LF.Target.Y, LCS.Width * LF.Scale, LCS.Height * LF.Scale, LF.Angle,
      LF.Card.AssetId, not (LF.IsFloor and LF.Reveal));
  end;

  // 비행 중 카드(뒷패 → 착지 지점, ease-out. 공개되는 바닥 카드만 중간에 앞면으로 플립)
  if FLanded <= High(FFlies) then
  begin
    var LF := FFlies[FLanded];
    var LE := 1 - Sqr(1 - FT);
    var LX := LDeckPt.X + (LF.Target.X - LDeckPt.X) * LE;
    var LY := LDeckPt.Y + (LF.Target.Y - LDeckPt.Y) * LE;
    var LBack := (not LF.IsFloor) or (not LF.Reveal) or (FT < 0.5);
    FHost.DrawCardRotated(LX, LY, LCS.Width * LF.Scale, LCS.Height * LF.Scale, LF.Angle * LE, LF.Card.AssetId, LBack);
  end;
end;
{$ENDREGION}

{$REGION 'TShakeAnimation'}
constructor TShakeAnimation.Create(const AHost: IAnimationHost; const AAmplitude: Single);
begin
  inherited Create(AHost);
  FAmp := AAmplitude;
  FT := 0;
end;

procedure TShakeAnimation.Restart(const AAmplitude: Single);
begin
  FAmp := AAmplitude;
  FT := 0;
  FDone := False;
end;

// 감쇠 사인파 — 왕복하며 진폭이 0으로 수렴한다.
function TShakeAnimation.OffsetX: Single;
begin
  if FT >= 1 then
  begin
    Exit(0);
  end;

  var LAmp := FHost.CardSize.Width * SHAKE_AMP_RATIO * FAmp * (1 - FT);
  Result := LAmp * Sin(FT * 2 * Pi * SHAKE_CYCLES);
end;

procedure TShakeAnimation.Update(const ADeltaMs: Single);
begin
  FT := FT + ADeltaMs / SHAKE_DURATION_MS;
  if FT >= 1 then
  begin
    FT := 1;   // 오프셋 0으로 복귀
    FDone := True;
  end;
end;

procedure TShakeAnimation.Draw;
begin
  // 그리는 것 없음 — OffsetX 값만 제공한다
end;
{$ENDREGION}

end.
