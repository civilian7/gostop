unit Gostop.Assets;

interface

{$REGION 'uses'}
uses
  System.SysUtils,
  System.IOUtils;
{$ENDREGION}

type
  /// <summary>
  ///   화투 이미지 에셋 폴더의 위치를 찾아 주는 정적 헬퍼.
  ///   실행 파일 경로에서 위로 올라가며 <c>assets\hwatu</c> 폴더를 탐색한다.
  /// </summary>
  THwatuAssets = record
  public
    /// <summary>
    ///   시작 폴더에서 상위로 올라가며 <c>assets\hwatu</c> 폴더를 찾아 그 전체 경로를 반환합니다.
    ///   찾지 못하면 빈 문자열을 반환합니다.
    /// </summary>
    /// <param name="AStartDir">탐색 시작 폴더. 빈 문자열이면 실행 파일 폴더에서 시작.</param>
    class function FindRoot(const AStartDir: string = ''): string; static;
    /// <summary>PNG 카드 이미지 폴더(<c>assets\hwatu\png</c>) 경로를 반환합니다. 못 찾으면 빈 문자열.</summary>
    /// <param name="ARoot">에셋 루트. 빈 문자열이면 <see cref="FindRoot"/>로 자동 탐색.</param>
    class function PngDir(const ARoot: string = ''): string; static;
    /// <summary>SVG 카드 이미지 폴더(<c>assets\hwatu\svg</c>) 경로를 반환합니다. 못 찾으면 빈 문자열.</summary>
    /// <param name="ARoot">에셋 루트. 빈 문자열이면 <see cref="FindRoot"/>로 자동 탐색.</param>
    class function SvgDir(const ARoot: string = ''): string; static;
    /// <summary>오디오 효과음 폴더(<c>assets\audio</c>) 경로를 반환합니다. 못 찾으면 빈 문자열.</summary>
    /// <param name="ARoot">에셋 루트(<c>assets\hwatu</c>). 빈 문자열이면 <see cref="FindRoot"/>로 자동 탐색.</param>
    class function AudioDir(const ARoot: string = ''): string; static;
    /// <summary>아바타 이미지 폴더(<c>assets\avatars</c>) 경로를 반환합니다. 못 찾으면 빈 문자열.</summary>
    /// <param name="ARoot">에셋 루트(<c>assets\hwatu</c>). 빈 문자열이면 <see cref="FindRoot"/>로 자동 탐색.</param>
    class function AvatarDir(const ARoot: string = ''): string; static;
    /// <summary>캐릭터 정본 데이터 파일(<c>assets\characters.json</c>) 경로를 반환합니다. 못 찾으면 빈 문자열.</summary>
    /// <param name="ARoot">에셋 루트(<c>assets\hwatu</c>). 빈 문자열이면 <see cref="FindRoot"/>로 자동 탐색.</param>
    class function CharactersJson(const ARoot: string = ''): string; static;
  end;

implementation

{$REGION 'THwatuAssets'}
class function THwatuAssets.FindRoot(const AStartDir: string): string;
begin
  var LDir := AStartDir;
  if LDir = '' then
  begin
    LDir := TPath.GetDirectoryName(ParamStr(0));
  end;

  LDir := TPath.GetFullPath(LDir);

  // 루트 디렉터리에 닿을 때까지 상위로 올라가며 assets\hwatu 탐색
  while LDir <> '' do
  begin
    var LCandidate := TPath.Combine(TPath.Combine(LDir, 'assets'), 'hwatu');
    if TDirectory.Exists(LCandidate) then
    begin
      Result := LCandidate;
      Exit;
    end;

    var LParent := TDirectory.GetParent(LDir);
    if (LParent = '') or SameText(LParent, LDir) then
    begin
      Break;
    end;

    LDir := LParent;
  end;

  Result := '';
end;

class function THwatuAssets.PngDir(const ARoot: string): string;
begin
  var LRoot := ARoot;
  if LRoot = '' then
  begin
    LRoot := FindRoot;
  end;

  if LRoot = '' then
  begin
    Result := '';
    Exit;
  end;

  Result := TPath.Combine(LRoot, 'png');
end;

class function THwatuAssets.SvgDir(const ARoot: string): string;
begin
  var LRoot := ARoot;
  if LRoot = '' then
  begin
    LRoot := FindRoot;
  end;

  if LRoot = '' then
  begin
    Result := '';
    Exit;
  end;

  Result := TPath.Combine(LRoot, 'svg');
end;

class function THwatuAssets.AudioDir(const ARoot: string): string;
begin
  var LRoot := ARoot;
  if LRoot = '' then
  begin
    LRoot := FindRoot;
  end;

  if LRoot = '' then
  begin
    Result := '';
    Exit;
  end;

  // LRoot = <...>\assets\hwatu → 형제 폴더 <...>\assets\audio
  Result := TPath.Combine(TDirectory.GetParent(LRoot), 'audio');
end;

class function THwatuAssets.AvatarDir(const ARoot: string): string;
begin
  var LRoot := ARoot;
  if LRoot = '' then
  begin
    LRoot := FindRoot;
  end;

  if LRoot = '' then
  begin
    Result := '';
    Exit;
  end;

  // LRoot = <...>\assets\hwatu → 형제 폴더 <...>\assets\avatars
  Result := TPath.Combine(TDirectory.GetParent(LRoot), 'avatars');
end;

class function THwatuAssets.CharactersJson(const ARoot: string): string;
begin
  var LRoot := ARoot;
  if LRoot = '' then
  begin
    LRoot := FindRoot;
  end;

  if LRoot = '' then
  begin
    Result := '';
    Exit;
  end;

  // LRoot = <...>\assets\hwatu → 상위 assets 폴더의 characters.json
  Result := TPath.Combine(TDirectory.GetParent(LRoot), 'characters.json');
end;
{$ENDREGION}

end.
