unit Gostop.Dialog.Settings;

// 새게임(설정) 다이얼로그. 인원수(2/3/4)·AI 난이도(4)·내 아바타를 큰 카드로 고르고 [취소]/[다음].
// 카드는 표준 버튼이 아니라 커스텀 렌더(TSelectCardRender) + 커스텀 히트영역이라, DrawContent 에서
// 카드를 그리고(호버는 base 의 IsHot) MouseDown 오버라이드로 카드 클릭을 처리한다([취소]/[다음]은
// base 버튼). 현재 선택값(인원수·난이도·아바타)은 보드가 소유하므로 TFunc 접근자로 매 프레임 읽어
// 선택 카드를 강조한다. 아바타 '변경'은 보드가 별도로 그리는 아바타 피커를 열도록 콜백만 보낸다(그때
// 이 다이얼로그는 숨었다가 선택 후 다시 뜨므로 피커와 z-order 가 겹치지 않는다).

interface

{$REGION 'uses'}
uses
  System.SysUtils,
  System.Types,
  System.UITypes,
  System.Classes,
  System.Generics.Collections,
  FMX.Graphics,
  Gostop.Dialog;
{$ENDREGION}

type
  /// <summary>설정 다이얼로그에 주입하는 모델(라벨·값·풀은 보드 소유를 참조, 현재값은 라이브 접근자).</summary>
  TSettingsModel = record
    ModeLabels: TArray<string>;         // 인원수 별칭(맞고/삼파전/광팔어유), 인덱스 0..2 = 2/3/4인
    SkillLabels: TArray<string>;        // 난이도 별칭(병아리/선수/타짜/신의손)
    SkillValues: TArray<Integer>;       // 난이도 스킬값(30/50/70/100)
    AvatarPool: TObjectList<TBitmap>;   // 아바타 풀(참조)
    SkillPool: TObjectList<TBitmap>;    // 난이도 카드 아바타 풀(참조)
    CurCount: TFunc<Integer>;           // 현재 인원수(라이브)
    CurSkill: TFunc<Integer>;           // 현재 난이도 스킬값(라이브)
    CurAvatarIdx: TFunc<Integer>;       // 현재 내 아바타 인덱스(라이브)
    OnCount: TProc<Integer>;            // 인원수 선택
    OnSkill: TProc<Integer>;            // 난이도 선택(스킬값)
    OnAvatarClick: TProc;               // 아바타 카드 클릭(보드가 피커 오픈)
    OnCancel: TProc;                    // 취소(타이틀로)
    OnNext: TProc;                      // 다음(대전 설정으로)
  end;

  /// <summary>새게임(설정) 다이얼로그.</summary>
  TSettingsDialog = class(TGostopDialog)
  strict private
    FModel: TSettingsModel;
    FCountRects: array [0 .. 2] of TRectF;
    FSkillRects: array [0 .. 3] of TRectF;
    FAvatarRect: TRectF;
    FBtnCancel: TDialogButton;
    FBtnNext: TDialogButton;
  strict protected
    function  PanelHeight: Single; override;
    procedure BuildButtons; override;
    procedure DrawContent(const ACanvas: TCanvas; const APanel: TRectF); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Single); override;
  public
    procedure Present(const AModel: TSettingsModel);
  end;

implementation

{$REGION 'uses'}
uses
  System.Math,
  Gostop.Canvas.Helper,
  Gostop.Board.CardRender,
  Gostop.Board.Widgets;
{$ENDREGION}

const
  CARD_ROW_H = 106.0;
  CARD_GAP = 12.0;
  CARD_AREA_MAX_W = 440.0;
  AV_CARD_SZ = 130.0;   // 정사각형 아바타 카드(원본 128x128 비율 유지)

{$REGION 'TSettingsDialog'}
function TSettingsDialog.PanelHeight: Single;
begin
  // 인원수·난이도 카드 2행 + 정사각형 아바타 카드 1행 + 제목·버튼
  Result := 56 + 2 * CARD_ROW_H + AV_CARD_SZ + CARD_GAP * 2 + 72;
end;

procedure TSettingsDialog.Present(const AModel: TSettingsModel);
begin
  FModel := AModel;
  SetupDialog('새게임', 480.0, PanelHeight);
  Popup;
end;

procedure TSettingsDialog.BuildButtons;
begin
  FBtnCancel := AddButton('취소', dbkNeutral,
    procedure
    begin
      if Assigned(FModel.OnCancel) then
      begin
        FModel.OnCancel();
      end;
    end);

  FBtnNext := AddButton('다음', dbkPrimary,
    procedure
    begin
      if Assigned(FModel.OnNext) then
      begin
        FModel.OnNext();
      end;
    end);
end;

procedure TSettingsDialog.DrawContent(const ACanvas: TCanvas; const APanel: TRectF);
begin
  var LCardAreaW := Min(APanel.Width - 40, CARD_AREA_MAX_W);
  var LCardAreaL := (APanel.Left + APanel.Right) / 2 - LCardAreaW / 2;
  var LCardY := APanel.Top + 56;

  // 인원수 카드(3) — 인원수만큼 아바타를 겹쳐 표시
  var LSeg3Gap := CARD_GAP;
  var LSeg3W := (LCardAreaW - LSeg3Gap * 2) / 3;
  for var LSeg := 0 to 2 do
  begin
    var LSegCount := LSeg + 2;
    var LSegRect := RectF(LCardAreaL + LSeg * (LSeg3W + LSeg3Gap), LCardY,
      LCardAreaL + LSeg * (LSeg3W + LSeg3Gap) + LSeg3W, LCardY + CARD_ROW_H);
    FCountRects[LSeg] := LSegRect;

    var LStackAv: TArray<TBitmap>;
    SetLength(LStackAv, LSegCount);
    if Assigned(FModel.AvatarPool) and (FModel.AvatarPool.Count > 0) then
    begin
      for var K := 0 to LSegCount - 1 do
      begin
        LStackAv[K] := FModel.AvatarPool[K mod FModel.AvatarPool.Count];
      end;
    end;

    TSelectCardRender.AvatarStack(ACanvas, LSegRect, LStackAv, FModel.ModeLabels[LSeg],
      LSegCount = FModel.CurCount(), IsHot(LSegRect), IsPressed(LSegRect));
  end;

  // 난이도 카드(4)
  LCardY := LCardY + CARD_ROW_H + CARD_GAP;
  var LSeg4Gap := CARD_GAP * 0.75;
  var LSeg4W := (LCardAreaW - LSeg4Gap * 3) / 4;
  for var LSeg := 0 to 3 do
  begin
    var LSegRect := RectF(LCardAreaL + LSeg * (LSeg4W + LSeg4Gap), LCardY,
      LCardAreaL + LSeg * (LSeg4W + LSeg4Gap) + LSeg4W, LCardY + CARD_ROW_H);
    FSkillRects[LSeg] := LSegRect;

    var LSkillBmp: TBitmap := nil;
    if Assigned(FModel.SkillPool) and (LSeg < FModel.SkillPool.Count) then
    begin
      LSkillBmp := FModel.SkillPool[LSeg];
    end;

    TSelectCardRender.Avatar(ACanvas, LSegRect, LSkillBmp, FModel.SkillLabels[LSeg],
      FModel.SkillValues[LSeg] = FModel.CurSkill(), IsHot(LSegRect), IsPressed(LSegRect));
  end;

  // 아바타 카드(정사각형, 클릭 → 피커). 현재 내 아바타를 크게, 캡션 '변경', 선택 스타일 강조
  var LAvY := LCardY + CARD_ROW_H + CARD_GAP;
  var LAvL := (APanel.Left + APanel.Right) / 2 - AV_CARD_SZ / 2;
  FAvatarRect := RectF(LAvL, LAvY, LAvL + AV_CARD_SZ, LAvY + AV_CARD_SZ);

  var LMyAvBmp: TBitmap := nil;
  var LAvIdx := FModel.CurAvatarIdx();
  if Assigned(FModel.AvatarPool) and (LAvIdx >= 0) and (LAvIdx < FModel.AvatarPool.Count) then
  begin
    LMyAvBmp := FModel.AvatarPool[LAvIdx];
  end;

  TSelectCardRender.Avatar(ACanvas, FAvatarRect, LMyAvBmp, '변경', True, IsHot(FAvatarRect), IsPressed(FAvatarRect));

  // [취소]/[다음] 위치 갱신(패널 하단 중앙)
  var LCX := (APanel.Left + APanel.Right) / 2;
  FBtnCancel.Rect := RectF(LCX - 150, APanel.Bottom - 56, LCX - 10, APanel.Bottom - 16);
  FBtnNext.Rect := RectF(LCX + 10, APanel.Bottom - 56, LCX + 150, APanel.Bottom - 16);
end;

procedure TSettingsDialog.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Single);
begin
  inherited;   // 마우스 추적 + [취소]/[다음] 버튼 처리
  var LPt := PointF(X, Y);

  for var LSeg := 0 to 2 do
  begin
    if FCountRects[LSeg].Contains(LPt) then
    begin
      if Assigned(FModel.OnCount) then
      begin
        FModel.OnCount(LSeg + 2);
      end;

      Repaint;
      Exit;
    end;
  end;

  for var LSeg := 0 to 3 do
  begin
    if FSkillRects[LSeg].Contains(LPt) then
    begin
      if Assigned(FModel.OnSkill) then
      begin
        FModel.OnSkill(FModel.SkillValues[LSeg]);
      end;

      Repaint;
      Exit;
    end;
  end;

  if FAvatarRect.Contains(LPt) then
  begin
    if Assigned(FModel.OnAvatarClick) then
    begin
      FModel.OnAvatarClick();
    end;
  end;
end;
{$ENDREGION}

end.
