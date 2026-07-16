unit Gostop.CardImages;

interface

{$REGION 'uses'}
uses
  System.SysUtils,
  System.IOUtils,
  System.Generics.Collections,
  FMX.Graphics,
  Gostop.Cards;
{$ENDREGION}

type
  /// <summary>
  ///   화투 카드 앞면·뒷면 PNG 이미지를 FMX <c>TBitmap</c>으로 로드해 캐싱하는 클래스.
  ///   앞면은 에셋 ID, 뒷면은 색상 이름(red/blue/green/purple/black)으로 지연 로딩·재사용한다.
  ///   로드된 모든 비트맵의 수명은 이 캐시가 소유한다.
  /// </summary>
  TCardImageCache = class
  private
    FPngDir: string;
    FFronts: TObjectDictionary<string, TBitmap>;
    FBacks: TObjectDictionary<string, TBitmap>;
    function LoadBitmap(const AFileName: string): TBitmap;
  public
    /// <summary>PNG 폴더 경로를 지정해 캐시를 생성합니다.</summary>
    /// <param name="APngDir">카드 PNG가 들어 있는 폴더(예: assets\hwatu\png).</param>
    constructor Create(const APngDir: string);
    destructor Destroy; override;

    /// <summary>에셋 ID에 해당하는 앞면 비트맵을 반환합니다(없으면 로드 후 캐싱).</summary>
    /// <param name="AAssetId">카드 에셋 ID(예: 'november_hikari').</param>
    /// <returns>캐시가 소유하는 비트맵. 호출자는 Free하지 않는다.</returns>
    /// <exception cref="EHwatuError">이미지 파일을 찾거나 로드하지 못하면 발생.</exception>
    function Front(const AAssetId: string): TBitmap;
    /// <summary>뒷면 비트맵을 반환합니다(없으면 로드 후 캐싱).</summary>
    /// <param name="AName">뒷면 색상 이름. 기본 'red'. 파일은 back_&lt;name&gt;.png.</param>
    /// <returns>캐시가 소유하는 비트맵. 호출자는 Free하지 않는다.</returns>
    /// <exception cref="EHwatuError">이미지 파일을 찾거나 로드하지 못하면 발생.</exception>
    function Back(const AName: string = 'red'): TBitmap;
    /// <summary>주어진 카드들의 앞면을 미리 로드합니다(첫 화면 지연 방지).</summary>
    /// <param name="ACards">미리 로드할 카드 배열.</param>
    procedure Preload(const ACards: array of THwatuCard);
    /// <summary>로드된 모든 비트맵을 비웁니다(메모리 해제).</summary>
    procedure Clear;

    /// <summary>현재 로드된 앞면 이미지 수.</summary>
    function LoadedFrontCount: Integer;
    /// <summary>PNG 폴더 경로.</summary>
    property PngDir: string read FPngDir;
  end;

implementation

{$REGION 'TCardImageCache'}
constructor TCardImageCache.Create(const APngDir: string);
begin
  inherited Create;
  FPngDir := APngDir;
  FFronts := TObjectDictionary<string, TBitmap>.Create([doOwnsValues]);
  FBacks := TObjectDictionary<string, TBitmap>.Create([doOwnsValues]);
end;

destructor TCardImageCache.Destroy;
begin
  FreeAndNil(FBacks);
  FreeAndNil(FFronts);
  inherited Destroy;
end;

function TCardImageCache.LoadBitmap(const AFileName: string): TBitmap;
begin
  if not TFile.Exists(AFileName) then
  begin
    raise EHwatuError.CreateFmt('카드 이미지 파일을 찾을 수 없습니다: %s', [AFileName]);
  end;

  Result := TBitmap.Create;
  try
    Result.LoadFromFile(AFileName);
  except
    on E: Exception do
    begin
      Result.Free;
      raise EHwatuError.CreateFmt('카드 이미지 로드 실패: %s (%s: %s)', [AFileName, E.ClassName, E.Message]);
    end;
  end;
end;

function TCardImageCache.Front(const AAssetId: string): TBitmap;
begin
  if not FFronts.TryGetValue(AAssetId, Result) then
  begin
    Result := LoadBitmap(TPath.Combine(FPngDir, AAssetId + '.png'));
    FFronts.Add(AAssetId, Result);
  end;
end;

function TCardImageCache.Back(const AName: string): TBitmap;
begin
  var LKey := 'back_' + AName;
  if not FBacks.TryGetValue(LKey, Result) then
  begin
    Result := LoadBitmap(TPath.Combine(FPngDir, LKey + '.png'));
    FBacks.Add(LKey, Result);
  end;
end;

procedure TCardImageCache.Preload(const ACards: array of THwatuCard);
begin
  for var I := Low(ACards) to High(ACards) do
  begin
    Front(ACards[I].AssetId);
  end;
end;

procedure TCardImageCache.Clear;
begin
  FFronts.Clear;
  FBacks.Clear;
end;

function TCardImageCache.LoadedFrontCount: Integer;
begin
  Result := FFronts.Count;
end;
{$ENDREGION}

end.
