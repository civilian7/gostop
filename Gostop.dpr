program Gostop;

uses
  System.StartUpCopy,
  FMX.Forms,
  Gostop.Cards in 'src\Gostop.Cards.pas',
  Gostop.Deck in 'src\Gostop.Deck.pas',
  Gostop.Deal in 'src\Gostop.Deal.pas',
  Gostop.Score in 'src\Gostop.Score.pas',
  Gostop.Play in 'src\Gostop.Play.pas',
  Gostop.Setup in 'src\Gostop.Setup.pas',
  Gostop.AI in 'src\Gostop.AI.pas',
  Gostop.FourPlayer in 'src\Gostop.FourPlayer.pas',
  Gostop.Assets in 'src\Gostop.Assets.pas',
  Gostop.Audio in 'src\Gostop.Audio.pas',
  Gostop.CardImages in 'src\Gostop.CardImages.pas',
  Gostop.Board in 'src\Gostop.Board.pas',
  Main in 'Main.pas' {frmMain};

{$R *.res}

begin
  Application.Initialize;
  Application.CreateForm(TfrmMain, frmMain);
  Application.Run;
end.
