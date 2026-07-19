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
    /// <summary>SVG 카드 이미지 폴더(<c>assets\hwatu\svg</c>) 경로를 반환합니다. 못 찾으면 빈 문자열.</summary>
    /// <param name="ARoot">에셋 루트. 빈 문자열이면 <see cref="FindRoot"/>로 자동 탐색.</param>
    class function SvgDir(const ARoot: string = ''): string; static;
    /// <summary>오디오 효과음 폴더(<c>assets\audio</c>) 경로를 반환합니다. 못 찾으면 빈 문자열.</summary>
    /// <param name="ARoot">에셋 루트(<c>assets\hwatu</c>). 빈 문자열이면 <see cref="FindRoot"/>로 자동 탐색.</param>
    class function AudioDir(const ARoot: string = ''): string; static;
    /// <summary>아바타 이미지 폴더(<c>assets\avatars</c>) 경로를 반환합니다. 못 찾으면 빈 문자열.</summary>
    /// <param name="ARoot">에셋 루트(<c>assets\hwatu</c>). 빈 문자열이면 <see cref="FindRoot"/>로 자동 탐색.</param>
    class function AvatarDir(const ARoot: string = ''): string; static;
    /// <summary>캐릭터 정본 데이터 파일(<c>assets\avatars\characters.json</c>) 경로를 반환합니다. 못 찾으면 빈 문자열.</summary>
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

  // 루트 디렉터리에 닿을 때까지 상위로 올라가며 assets\avatars 탐색(반환값은 관례상 hwatu 경로
  // 이름을 유지 — 화투패 이미지는 이제 리소스로 내장되어 assets\hwatu 폴더 자체가 배포판에 없으므로,
  // 그 폴더를 앵커로 쓰면 실제 배포 환경에서 탐색이 실패한다. avatars는 여전히 파일로 배포되므로
  // 이걸 앵커로 삼는다).
  while LDir <> '' do
  begin
    var LAssetsDir := TPath.Combine(LDir, 'assets');
    if TDirectory.Exists(TPath.Combine(LAssetsDir, 'avatars')) then
    begin
      Result := TPath.Combine(LAssetsDir, 'hwatu');
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

  // LRoot = <...>\assets\hwatu → 아바타 캐릭터 데이터라 assets\avatars 폴더에 함께 둔다
  Result := TPath.Combine(TPath.Combine(TDirectory.GetParent(LRoot), 'avatars'), 'characters.json');
end;
{$ENDREGION}

end.
