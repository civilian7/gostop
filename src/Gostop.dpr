program Gostop;

uses
  System.StartUpCopy,
  FMX.Forms,
  Gostop.Cards in 'engine\Gostop.Cards.pas',
  Gostop.Deck in 'engine\Gostop.Deck.pas',
  Gostop.Deal in 'engine\Gostop.Deal.pas',
  Gostop.Score in 'engine\Gostop.Score.pas',
  Gostop.Play in 'engine\Gostop.Play.pas',
  Gostop.Setup in 'engine\Gostop.Setup.pas',
  Gostop.AI in 'engine\Gostop.AI.pas',
  Gostop.Characters in 'engine\Gostop.Characters.pas',
  Gostop.Settings in 'engine\Gostop.Settings.pas',
  Gostop.Board.Layout in 'engine\Gostop.Board.Layout.pas',
  Gostop.Canvas.Helper in 'engine\Gostop.Canvas.Helper.pas',
  Gostop.Fonts in 'engine\Gostop.Fonts.pas',
  Gostop.FourPlayer in 'engine\Gostop.FourPlayer.pas',
  Gostop.Shodang in 'engine\Gostop.Shodang.pas',
  Gostop.Assets in 'engine\Gostop.Assets.pas',
  Gostop.Audio in 'engine\Gostop.Audio.pas',
  Gostop.CardImages in 'engine\Gostop.CardImages.pas',
  Gostop.SaveGame in 'engine\Gostop.SaveGame.pas',
  Gostop.Board.Settlement in 'engine\Gostop.Board.Settlement.pas',
  Gostop.Board.Animation in 'engine\Gostop.Board.Animation.pas',
  Gostop.Board.CardRender in 'engine\Gostop.Board.CardRender.pas',
  Gostop.Board.Widgets in 'engine\Gostop.Board.Widgets.pas',
  Gostop.Board.OverlayRender in 'engine\Gostop.Board.OverlayRender.pas',
  Gostop.Board in 'engine\Gostop.Board.pas',
  Main in 'Main.pas' {frmMain};

{$R *.res}

begin
  Application.Initialize;
  Application.CreateForm(TfrmMain, frmMain);
  Application.Run;
end.
