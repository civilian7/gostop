unit Gostop.Audio;

interface

{$REGION 'uses'}
uses
  System.SysUtils,
  System.Generics.Collections,
  Winapi.Windows,
  Winapi.MMSystem,
  Gostop.Play;
{$ENDREGION}

type
  /// <summary>
  ///   게임 효과음 재생 래퍼(싱글턴). <c>assets\audio</c>의 WAV(44.1kHz·16bit·스테레오)를 이름으로 재생한다.
  ///   백엔드는 <c>waveOut</c> 핸들 풀 — 여러 스트림을 동시에 열어 Windows 오디오 엔진이 믹싱하므로
  ///   효과음이 <b>동시에 겹쳐</b> 난다(폴리포니). 오디오 실패는 게임 진행에 영향을 주지 않는다.
  /// </summary>
  TGostopAudio = class
  strict private
    class var FInstance: TGostopAudio;
    class constructor Create;
    class destructor Destroy;
  private
    type
      TVoice = record
        Handle: HWAVEOUT;
        Hdr: TWaveHdr;   // lpData=nil = 미사용, WHDR_DONE = 재생 완료 → 재사용 가능
      end;
    const
      VOICE_COUNT = 8;   // 동시 발화 채널 수
  private
    FDir: string;
    FEnabled: Boolean;
    FMuted: Boolean;
    FVolume: Single;
    FVoices: array [0 .. VOICE_COUNT - 1] of TVoice;
    FVoiceCount: Integer;
    FNextVoice: Integer;
    FBuffers: TDictionary<string, TBytes>;   // 이름 → WAV data 청크(PCM) 캐시
    function OpenVoices: Boolean;
    procedure CloseVoices;
    function GetPcm(const AName: string): TBytes;
    procedure SetVolume(const AValue: Single);
  public
    /// <summary>오디오 폴더 탐색 + waveOut 채널을 열어 초기화합니다(실패 시 비활성).</summary>
    constructor Create;
    destructor Destroy; override;

    /// <summary>싱글턴 인스턴스를 반환합니다.</summary>
    class function Instance: TGostopAudio;

    /// <summary>이름(확장자 제외)으로 효과음을 재생합니다(빈 채널에 실어 동시 재생). 예: Play('card_place').</summary>
    procedure Play(const AName: string);
    /// <summary>엔진 이벤트 종류에 대응하는 효과음을 재생합니다(해당 없으면 무음).</summary>
    procedure PlayEvent(const AKind: TPlayEventKind);

    /// <summary>오디오 사용 가능 여부(폴더·디바이스). False면 모든 재생이 무음.</summary>
    property Enabled: Boolean read FEnabled write FEnabled;
    /// <summary>음소거 여부. True면 재생하지 않는다.</summary>
    property Muted: Boolean read FMuted write FMuted;
    /// <summary>전체 볼륨(0.0~1.0). 모든 채널에 즉시 적용된다.</summary>
    property Volume: Single read FVolume write SetVolume;
  end;

implementation

{$REGION 'uses'}
uses
  System.IOUtils,
  Gostop.Assets;
{$ENDREGION}

// WAV 바이트에서 'data' 청크(PCM)만 추출. 성공하면 True.
function ExtractWavData(const ARaw: TBytes; out AData: TBytes): Boolean;
begin
  Result := False;
  if Length(ARaw) < 44 then
  begin
    Exit;
  end;

  // 'RIFF' .... 'WAVE'
  if (ARaw[0] <> Ord('R')) or (ARaw[1] <> Ord('I')) or (ARaw[2] <> Ord('F')) or (ARaw[3] <> Ord('F')) then
  begin
    Exit;
  end;

  var LPos := 12;   // RIFF(4) + size(4) + WAVE(4)
  while LPos + 8 <= Length(ARaw) do
  begin
    var LIsData := (ARaw[LPos] = Ord('d')) and (ARaw[LPos + 1] = Ord('a')) and
      (ARaw[LPos + 2] = Ord('t')) and (ARaw[LPos + 3] = Ord('a'));
    var LSize := Cardinal(ARaw[LPos + 4]) or (Cardinal(ARaw[LPos + 5]) shl 8) or
      (Cardinal(ARaw[LPos + 6]) shl 16) or (Cardinal(ARaw[LPos + 7]) shl 24);
    var LBody := LPos + 8;

    if LIsData then
    begin
      var LN := Integer(LSize);
      if LBody + LN > Length(ARaw) then
      begin
        LN := Length(ARaw) - LBody;
      end;

      SetLength(AData, LN);
      if LN > 0 then
      begin
        Move(ARaw[LBody], AData[0], LN);
      end;

      Exit(True);
    end;

    // 손상 WAV 방어: 청크 크기가 비정상(음수·과대)이면 무한루프 대신 중단
    if (LSize > Cardinal(Length(ARaw))) or (Integer(LSize) < 0) then
    begin
      Break;
    end;

    LPos := LBody + Integer(LSize);
    if (LSize and 1) = 1 then
    begin
      Inc(LPos);   // 청크는 워드 정렬
    end;
  end;
end;

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
  FBuffers := TDictionary<string, TBytes>.Create;
  FDir := THwatuAssets.AudioDir;
  FMuted := False;
  FVolume := 1.0;
  FVoiceCount := 0;
  FNextVoice := 0;
  FEnabled := (FDir <> '') and TDirectory.Exists(FDir) and OpenVoices;
end;

procedure TGostopAudio.SetVolume(const AValue: Single);
begin
  FVolume := AValue;
  if FVolume < 0 then
  begin
    FVolume := 0;
  end;

  if FVolume > 1 then
  begin
    FVolume := 1;
  end;

  // 좌/우 동일 볼륨을 모든 채널에 적용
  var LW := Cardinal(Round(FVolume * $FFFF));
  var LVol := LW or (LW shl 16);
  for var I := 0 to FVoiceCount - 1 do
  begin
    if FVoices[I].Handle <> 0 then
    begin
      waveOutSetVolume(FVoices[I].Handle, LVol);
    end;
  end;
end;

destructor TGostopAudio.Destroy;
begin
  CloseVoices;
  FreeAndNil(FBuffers);
  inherited Destroy;
end;

function TGostopAudio.OpenVoices: Boolean;
begin
  var LFmt: TWaveFormatEx;
  FillChar(LFmt, SizeOf(LFmt), 0);
  LFmt.wFormatTag := WAVE_FORMAT_PCM;
  LFmt.nChannels := 2;
  LFmt.nSamplesPerSec := 44100;
  LFmt.wBitsPerSample := 16;
  LFmt.nBlockAlign := LFmt.nChannels * LFmt.wBitsPerSample div 8;
  LFmt.nAvgBytesPerSec := LFmt.nSamplesPerSec * LFmt.nBlockAlign;
  LFmt.cbSize := 0;

  FVoiceCount := 0;
  for var I := 0 to VOICE_COUNT - 1 do
  begin
    FillChar(FVoices[I], SizeOf(TVoice), 0);
    if waveOutOpen(@FVoices[I].Handle, WAVE_MAPPER, @LFmt, 0, 0, CALLBACK_NULL) = MMSYSERR_NOERROR then
    begin
      Inc(FVoiceCount);
    end
    else
    begin
      FVoices[I].Handle := 0;
      Break;   // 하나라도 실패하면 그만(연 것까지만 사용)
    end;
  end;

  Result := FVoiceCount > 0;
end;

procedure TGostopAudio.CloseVoices;
begin
  for var I := 0 to FVoiceCount - 1 do
  begin
    if FVoices[I].Handle <> 0 then
    begin
      waveOutReset(FVoices[I].Handle);
      if (FVoices[I].Hdr.dwFlags and WHDR_PREPARED) <> 0 then
      begin
        waveOutUnprepareHeader(FVoices[I].Handle, @FVoices[I].Hdr, SizeOf(TWaveHdr));
      end;

      waveOutClose(FVoices[I].Handle);
      FVoices[I].Handle := 0;
    end;
  end;

  FVoiceCount := 0;
end;

function TGostopAudio.GetPcm(const AName: string): TBytes;
begin
  if FBuffers.TryGetValue(AName, Result) then
  begin
    Exit;
  end;

  Result := nil;
  var LPath := TPath.Combine(FDir, AName + '.wav');
  if not TFile.Exists(LPath) then
  begin
    FBuffers.Add(AName, nil);   // 네거티브 캐시: 없는 파일을 매번 디스크 확인하지 않음
    Exit;
  end;

  try
    var LData: TBytes;
    if ExtractWavData(TFile.ReadAllBytes(LPath), LData) then
    begin
      FBuffers.Add(AName, LData);
      Result := LData;
    end
    else
    begin
      FBuffers.Add(AName, nil);   // 파싱 실패도 캐시
    end;
  except
    FBuffers.AddOrSetValue(AName, nil);
    Result := nil;
  end;
end;

procedure TGostopAudio.Play(const AName: string);
begin
  if (not FEnabled) or FMuted or (FVoiceCount = 0) then
  begin
    Exit;
  end;

  var LData := GetPcm(AName);
  if Length(LData) = 0 then
  begin
    Exit;
  end;

  // 라운드로빈: 완료 감지(WHDR_DONE)에 의존하지 않고 다음 채널을 끊고 재사용(절대 눌러붙지 않음).
  // 서로 다른 채널이라 Windows 오디오 엔진이 동시에 믹싱 → 폴리포니.
  var LIdx := FNextVoice;
  FNextVoice := (FNextVoice + 1) mod FVoiceCount;

  try
    waveOutReset(FVoices[LIdx].Handle);   // 이전 버퍼 중단
    if (FVoices[LIdx].Hdr.dwFlags and WHDR_PREPARED) <> 0 then
    begin
      waveOutUnprepareHeader(FVoices[LIdx].Handle, @FVoices[LIdx].Hdr, SizeOf(TWaveHdr));
    end;

    FillChar(FVoices[LIdx].Hdr, SizeOf(TWaveHdr), 0);
    FVoices[LIdx].Hdr.lpData := PAnsiChar(@LData[0]);   // 캐시가 소유(재생 동안 유효)
    FVoices[LIdx].Hdr.dwBufferLength := Length(LData);
    if waveOutPrepareHeader(FVoices[LIdx].Handle, @FVoices[LIdx].Hdr, SizeOf(TWaveHdr)) = MMSYSERR_NOERROR then
    begin
      waveOutWrite(FVoices[LIdx].Handle, @FVoices[LIdx].Hdr, SizeOf(TWaveHdr));
    end;
  except
    // 재생 실패는 무시(게임 진행 우선)
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
    pekBbeok, pekJabbeok, pekYeonbbeok, pekCheotbbeok, pekSambbeok:
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
    pekGo, pekReverseGo:
      begin
        Play('sfx_go');   // 역고 전용 음원은 아직 없어 고 소리를 함께 쓴다
      end;
    pekStop:
      begin
        Play('sfx_stop');
      end;
  end;
end;
{$ENDREGION}

end.
