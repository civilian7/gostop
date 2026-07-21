unit Gostop.Dialog.ProgramInfo;

// 프로그램 정보 다이얼로그(버전·오픈소스 출처·저작권). TGostopDialog 분리의 파일럿 — 정적 텍스트 +
// 닫기 버튼만이라 입력 모델이 없고, 계약은 "띄우고 닫기"뿐이다. 보드에 있던 DrawProgramInfo 본문을
// 그대로 옮겨오되, 목함 프레임·팝인·버튼 히트테스트는 base 가 담당하므로 본문 그리기만 남는다.

interface

{$REGION 'uses'}
uses
  System.Classes,
  System.Types,
  FMX.Graphics,
  Gostop.Dialog;
{$ENDREGION}

type
  /// <summary>프로그램 정보 다이얼로그(정적 — 버전·오픈소스 출처·저작권 표시, 닫기만).</summary>
  TProgramInfoDialog = class(TGostopDialog)
  strict protected
    procedure DrawContent(const ACanvas: TCanvas; const APanel: TRectF); override;
  public
    constructor Create(AOwner: TComponent); override;
  end;

implementation

{$REGION 'uses'}
uses
  System.UITypes,
  FMX.Types,
  Gostop.Canvas.Helper,
  Gostop.Fonts,
  Gostop.Board.Widgets;
{$ENDREGION}

{$REGION 'TProgramInfoDialog'}
constructor TProgramInfoDialog.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  SetupDialog('프로그램 정보', 480, 360);
end;

procedure TProgramInfoDialog.DrawContent(const ACanvas: TCanvas; const APanel: TRectF);
begin
  var LY := APanel.Top + 66;

  ACanvas.DrawLabel(RectF(APanel.Left, LY, APanel.Right, LY + 28), '루미고스톱 v1.0.3', TAlphaColors.Gold, 18);
  LY := LY + 40;

  ACanvas.Fill.Kind := TBrushKind.Solid;
  ACanvas.Fill.Color := $FFE2C674;
  TGostopFonts.Apply(ACanvas, 14);
  ACanvas.FillText(RectF(APanel.Left + 28, LY, APanel.Right - 28, LY + 20), '오픈소스',
    False, 1, [], TTextAlign.Leading, TTextAlign.Center);
  LY := LY + 28;

  // 이름(위 줄) · 출처(아래 줄, 들여쓰기+옅은 색) 두 줄로 표시
  var LOsNames: TArray<string> := ['화투 카드 이미지', '효과음'];
  var LOsSources: TArray<string> := [
    'Wikimedia Commons "Category:Hwatu" (CC BY-SA 4.0)',
    'Kenney.nl Casino / Interface / Impact Audio (CC0)'
  ];

  for var I := 0 to High(LOsNames) do
  begin
    ACanvas.Fill.Kind := TBrushKind.Solid;
    ACanvas.Fill.Color := $FFEFEFE0;
    TGostopFonts.Apply(ACanvas, 12.5);
    ACanvas.FillText(RectF(APanel.Left + 28, LY, APanel.Right - 28, LY + 18), '- ' + LOsNames[I],
      False, 1, [], TTextAlign.Leading, TTextAlign.Leading);
    LY := LY + 20;

    ACanvas.Fill.Color := $FF8A968A;
    TGostopFonts.Apply(ACanvas, 11);
    ACanvas.FillText(RectF(APanel.Left + 42, LY, APanel.Right - 28, LY + 32), LOsSources[I],
      True, 1, [], TTextAlign.Leading, TTextAlign.Leading);
    LY := LY + 36;
  end;

  LY := LY + 8;
  ACanvas.DrawLabel(RectF(APanel.Left, LY, APanel.Right, LY + 20),
    '(c) 2024-2026 copyright in fullbit computing.', $FF8A968A, 12);

  AddButton(RectF(APanel.Left + APanel.Width / 2 - 70, APanel.Bottom - 54,
    APanel.Left + APanel.Width / 2 + 70, APanel.Bottom - 16), '닫기', dbkNeutral,
    procedure
    begin
      Dismiss;
    end);
end;
{$ENDREGION}

end.
