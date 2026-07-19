unit Gostop.CardImages;

interface

{$REGION 'uses'}
uses
  System.SysUtils,
  System.Types,
  System.Classes,
  System.Generics.Collections,
  Winapi.Windows,
  FMX.Graphics,
  Gostop.Cards;
{$ENDREGION}

type
  /// <summary>
  ///   화투 카드 앞면·뒷면 이미지를 FMX <c>TBitmap</c>으로 로드해 캐싱하는 클래스.
  ///   이미지는 exe에 리소스(RCDATA)로 내장되어 있어 외부 파일에 의존하지 않는다
  ///   (리소스 이름 = 에셋 ID를 대문자로 바꾼 것, Gostop.rc 참고).
  ///   앞면은 에셋 ID, 뒷면은 색상 이름(red)으로 지연 로딩·재사용한다.
  ///   로드된 모든 비트맵의 수명은 이 캐시가 소유한다.
  /// </summary>
  TCardImageCache = class
  private
    FFronts: TObjectDictionary<string, TBitmap>;
    FBacks: TObjectDictionary<string, TBitmap>;
    FScaled: TObjectDictionary<string, TBitmap>;
    function LoadBitmap(const AResName: string): TBitmap;
    function ResizeStep(const ASource: TBitmap; const AWidth, AHeight: Integer): TBitmap;
    function HighQualityScale(const ASource: TBitmap; const AWidth, AHeight: Integer): TBitmap;
    function ScaledOf(const AKey: string; const ASource: TBitmap; const AWidth, AHeight: Integer): TBitmap;
  public
    constructor Create;
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
    /// <summary>
    ///   앞면을 지정한 픽셀 크기로 <b>고품질 축소</b>해 반환합니다(2배씩 단계적 축소로 앨리어싱 최소화).
    ///   같은 (ID·크기) 요청은 캐싱해 재사용한다. 원본보다 크게 요청하면 원본을 그대로 반환한다.
    /// </summary>
    /// <param name="AAssetId">카드 에셋 ID.</param>
    /// <param name="AWidth">목표 너비(디바이스 픽셀).</param>
    /// <param name="AHeight">목표 높이(디바이스 픽셀).</param>
    /// <returns>캐시가 소유하는 비트맵. 호출자는 Free하지 않는다.</returns>
    function ScaledFront(const AAssetId: string; const AWidth, AHeight: Integer): TBitmap;
    /// <summary>뒷면을 지정한 픽셀 크기로 고품질 축소해 반환합니다(<see cref="ScaledFront"/>와 동일 규칙).</summary>
    /// <param name="AName">뒷면 색상 이름.</param>
    /// <param name="AWidth">목표 너비(디바이스 픽셀).</param>
    /// <param name="AHeight">목표 높이(디바이스 픽셀).</param>
    function ScaledBack(const AName: string; const AWidth, AHeight: Integer): TBitmap;
    /// <summary>주어진 카드들의 앞면을 미리 로드합니다(첫 화면 지연 방지).</summary>
    /// <param name="ACards">미리 로드할 카드 배열.</param>
    procedure Preload(const ACards: array of THwatuCard);
    /// <summary>로드된 모든 비트맵을 비웁니다(메모리 해제).</summary>
    procedure Clear;

    /// <summary>현재 로드된 앞면 이미지 수.</summary>
    function LoadedFrontCount: Integer;
  end;

implementation

{$REGION 'TCardImageCache'}
constructor TCardImageCache.Create;
begin
  inherited Create;
  FFronts := TObjectDictionary<string, TBitmap>.Create([doOwnsValues]);
  FBacks := TObjectDictionary<string, TBitmap>.Create([doOwnsValues]);
  FScaled := TObjectDictionary<string, TBitmap>.Create([doOwnsValues]);
end;

destructor TCardImageCache.Destroy;
begin
  FreeAndNil(FScaled);
  FreeAndNil(FBacks);
  FreeAndNil(FFronts);
  inherited Destroy;
end;

function TCardImageCache.LoadBitmap(const AResName: string): TBitmap;
begin
  var LResName := UpperCase(AResName);
  if FindResource(HInstance, PChar(LResName), RT_RCDATA) = 0 then
  begin
    raise EHwatuError.CreateFmt('카드 이미지 리소스를 찾을 수 없습니다: %s', [LResName]);
  end;

  var LStream := TResourceStream.Create(HInstance, LResName, RT_RCDATA);
  try
    Result := TBitmap.Create;
    try
      Result.LoadFromStream(LStream);
    except
      on E: Exception do
      begin
        Result.Free;
        raise EHwatuError.CreateFmt('카드 이미지 로드 실패: %s (%s: %s)', [LResName, E.ClassName, E.Message]);
      end;
    end;
  finally
    LStream.Free;
  end;
end;

function TCardImageCache.Front(const AAssetId: string): TBitmap;
begin
  if not FFronts.TryGetValue(AAssetId, Result) then
  begin
    Result := LoadBitmap(AAssetId);
    FFronts.Add(AAssetId, Result);
  end;
end;

function TCardImageCache.Back(const AName: string): TBitmap;
begin
  var LKey := 'back_' + AName;
  if not FBacks.TryGetValue(LKey, Result) then
  begin
    Result := LoadBitmap(LKey);
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
  FScaled.Clear;
  FFronts.Clear;
  FBacks.Clear;
end;

function TCardImageCache.ResizeStep(const ASource: TBitmap; const AWidth, AHeight: Integer): TBitmap;
begin
  Result := TBitmap.Create(AWidth, AHeight);
  try
    Result.Clear(0);   // 투명 배경 유지
    if Result.Canvas.BeginScene then
    begin
      try
        Result.Canvas.DrawBitmap(ASource,
          RectF(0, 0, ASource.Width, ASource.Height),
          RectF(0, 0, AWidth, AHeight), 1, False);   // HighSpeed=False → 필터링(고품질)
      finally
        Result.Canvas.EndScene;
      end;
    end;
  except
    Result.Free;
    raise;
  end;
end;

function TCardImageCache.HighQualityScale(const ASource: TBitmap; const AWidth, AHeight: Integer): TBitmap;
begin
  var LWidth := AWidth;
  var LHeight := AHeight;
  if LWidth < 1 then
  begin
    LWidth := 1;
  end;

  if LHeight < 1 then
  begin
    LHeight := 1;
  end;

  // 원본이 목표보다 크지 않으면 단일 스텝으로 처리
  var LCurrent := ASource;
  var LOwned := False;
  // 목표의 2배보다 크면 절반씩 줄여 앨리어싱을 줄인다.
  while (LCurrent.Width >= LWidth * 2) and (LCurrent.Height >= LHeight * 2) do
  begin
    var LHalfW := LCurrent.Width div 2;
    var LHalfH := LCurrent.Height div 2;
    if (LHalfW < LWidth) or (LHalfH < LHeight) then
    begin
      Break;
    end;

    var LStep := ResizeStep(LCurrent, LHalfW, LHalfH);
    if LOwned then
    begin
      LCurrent.Free;
    end;

    LCurrent := LStep;
    LOwned := True;
  end;

  Result := ResizeStep(LCurrent, LWidth, LHeight);
  if LOwned then
  begin
    LCurrent.Free;
  end;
end;

function TCardImageCache.ScaledOf(const AKey: string; const ASource: TBitmap; const AWidth, AHeight: Integer): TBitmap;
const
  SCALED_CACHE_CAP = 240;   // 연속 리사이즈로 캐시가 무한정 커지는 것 방지
begin
  // 원본보다 크게(확대) 요청하면 원본을 그대로 사용(불필요한 업스케일 방지)
  if (AWidth >= ASource.Width) or (AHeight >= ASource.Height) then
  begin
    Exit(ASource);
  end;

  if not FScaled.TryGetValue(AKey, Result) then
  begin
    if FScaled.Count > SCALED_CACHE_CAP then
    begin
      FScaled.Clear;
    end;

    Result := HighQualityScale(ASource, AWidth, AHeight);
    FScaled.Add(AKey, Result);
  end;
end;

function TCardImageCache.ScaledFront(const AAssetId: string; const AWidth, AHeight: Integer): TBitmap;
begin
  if (AWidth <= 0) or (AHeight <= 0) then
  begin
    Exit(Front(AAssetId));
  end;

  Result := ScaledOf(Format('F:%s:%dx%d', [AAssetId, AWidth, AHeight]), Front(AAssetId), AWidth, AHeight);
end;

function TCardImageCache.ScaledBack(const AName: string; const AWidth, AHeight: Integer): TBitmap;
begin
  if (AWidth <= 0) or (AHeight <= 0) then
  begin
    Exit(Back(AName));
  end;

  Result := ScaledOf(Format('B:%s:%dx%d', [AName, AWidth, AHeight]), Back(AName), AWidth, AHeight);
end;

function TCardImageCache.LoadedFrontCount: Integer;
begin
  Result := FFronts.Count;
end;
{$ENDREGION}

end.
