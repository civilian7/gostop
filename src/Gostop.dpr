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
  Gostop.FourPlayer in 'engine\Gostop.FourPlayer.pas',
  Gostop.Assets in 'engine\Gostop.Assets.pas',
  Gostop.Audio in 'engine\Gostop.Audio.pas',
  Gostop.CardImages in 'engine\Gostop.CardImages.pas',
  Gostop.Board in 'engine\Gostop.Board.pas',
  Main in 'Main.pas' {frmMain};

{$R *.res}

begin
  Application.Initialize;
  Application.CreateForm(TfrmMain, frmMain);
  Application.Run;
end.
