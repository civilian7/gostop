unit Gostop.Audio;

interface

{$REGION 'uses'}
uses
  System.SysUtils,
  Gostop.Play;
{$ENDREGION}

type
  /// <summary>
  ///   게임 효과음 재생 래퍼(싱글턴). <c>assets\audio</c> 의 WAV를 이름으로 재생한다.
  ///   백엔드는 Windows <c>PlaySound</c>(단일 채널). 오디오 실패는 게임 진행에 영향을 주지 않는다.
  ///   폴리포니/볼륨/BGM이 필요하면 백엔드만 SCAudio 등으로 교체하면 된다.
  /// </summary>
  TGostopAudio = class
  strict private
    class var FInstance: TGostopAudio;
    class constructor Create;
    class destructor Destroy;
  private
    FDir: string;
    FEnabled: Boolean;
    FMuted: Boolean;
  public
    /// <summary>오디오 폴더를 탐색해 초기화합니다(폴더가 없으면 비활성).</summary>
    constructor Create;

    /// <summary>싱글턴 인스턴스를 반환합니다.</summary>
    class function Instance: TGostopAudio;

    /// <summary>이름(확장자 제외)으로 효과음을 재생합니다. 예: Play('card_place').</summary>
    /// <param name="AName">assets\audio 의 파일명(.wav 제외).</param>
    procedure Play(const AName: string);
    /// <summary>엔진 이벤트 종류에 대응하는 효과음을 재생합니다(해당 없으면 무음).</summary>
    /// <param name="AKind">플레이 이벤트 종류.</param>
    procedure PlayEvent(const AKind: TPlayEventKind);

    /// <summary>오디오 사용 가능 여부(폴더 존재 등). False면 모든 재생이 무음.</summary>
    property Enabled: Boolean read FEnabled write FEnabled;
    /// <summary>음소거 여부. True면 재생하지 않는다.</summary>
    property Muted: Boolean read FMuted write FMuted;
  end;

implementation

{$REGION 'uses'}
uses
  System.IOUtils,
  Winapi.Windows,
  Winapi.MMSystem,
  Gostop.Assets;
{$ENDREGION}

{$REGION 'TGostopAudio'}
class constructor TGostopAudio.Create;
begin
  FInstance := nil;
end;

class destructor TGostopAudio.Destroy;
begin
  FreeAndNil(FInstance);
end;

class function TGostopAudio.Instance: TGostopAudio;
begin
  if FInstance = nil then
  begin
    FInstance := TGostopAudio.Create;
  end;

  Result := FInstance;
end;

constructor TGostopAudio.Create;
begin
  inherited Create;
  FDir := THwatuAssets.AudioDir;
  FEnabled := (FDir <> '') and TDirectory.Exists(FDir);
  FMuted := False;
end;

procedure TGostopAudio.Play(const AName: string);
begin
  if (not FEnabled) or FMuted then
  begin
    Exit;
  end;

  var LPath := TPath.Combine(FDir, AName + '.wav');
  if not TFile.Exists(LPath) then
  begin
    Exit;
  end;

  try
    // 비동기·파일 재생. 파일 없으면 시스템 기본음도 안 냄. 단일 채널(새 재생이 이전을 중단).
    Winapi.MMSystem.PlaySound(PChar(LPath), 0, SND_ASYNC or SND_FILENAME or SND_NODEFAULT);
  except
    // 오디오 실패는 무시(게임 진행 우선)
  end;
end;

procedure TGostopAudio.PlayEvent(const AKind: TPlayEventKind);
begin
  case AKind of
    pekJjok:
      begin
        Play('sfx_jjok');
      end;
    pekTtadak:
      begin
        Play('sfx_ttadak');
      end;
    pekSseul:
      begin
        Play('sfx_sseul');
      end;
    pekBomb:
      begin
        Play('sfx_bomb');
      end;
    pekShake:
      begin
        Play('sfx_shake');
      end;
    pekBbeok, pekJabbeok, pekYeonbbeok, pekCheotbbeok:
      begin
        Play('sfx_bbeok');
      end;
    pekChongtong:
      begin
        Play('sfx_chongtong');
      end;
    pekPiSteal:
      begin
        Play('sfx_pi_steal');
      end;
    pekGo:
      begin
        Play('sfx_go');
      end;
    pekStop:
      begin
        Play('sfx_stop');
      end;
  end;
end;
{$ENDREGION}

end.
