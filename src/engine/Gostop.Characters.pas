unit Gostop.Characters;

interface

{$REGION 'uses'}
uses
  System.Math;
{$ENDREGION}

type
  /// <summary>
  ///   고스톱 캐릭터(아바타) 정본 데이터와 순수 조회 함수.
  ///   실제 데이터는 <c>assets\characters.json</c>에서 지연 로드한다(최초 조회 시 1회).
  ///   아바타 이미지 파일(<c>assets\avatars\avatar_NN.png</c>) 순서 = JSON 배열 순서 = 인덱스(0-기반).
  ///   페르소나·대사·이미지 프롬프트 등 상세는 <c>docs\characters.md</c> §4 참조(JSON의 원본 문서).
  /// </summary>
  TGostopCharacters = record
  public
    const
      /// <summary>능력치 축 수(수읽기/침착/배짱/욕심/운).</summary>
      STAT_COUNT = 5;
      /// <summary>능력치 축 인덱스.</summary>
      STAT_INSIGHT = 0;   // 수읽기
      STAT_COMPOSURE = 1; // 침착
      STAT_NERVE = 2;     // 배짱
      STAT_GREED = 3;     // 욕심
      STAT_LUCK = 4;      // 운

    /// <summary>등록된 캐릭터 수(JSON 로드 결과). 로드 실패 시 0.</summary>
    class function Count: Integer; static;
    /// <summary>인덱스의 닉네임을 반환합니다. 범위 밖이면 빈 문자열.</summary>
    class function NameOf(const AIndex: Integer): string; static;
    /// <summary>인덱스·축의 능력치(0~100)를 반환합니다. 범위 밖이면 평균 20.</summary>
    class function StatOf(const AIndex: Integer; const AStat: Integer): Integer; static;
    /// <summary>캐릭터 고유 AI 스킬 = (수읽기 + 침착) × 1.25 (0~100).</summary>
    class function DerivedSkill(const AIndex: Integer): Integer; static;
    /// <summary>캐릭터 고유 배짱(GoBias, 0~100): 능력치 배짱 ×2 + 10.</summary>
    class function NerveBias(const AIndex: Integer): Integer; static;
    /// <summary>캐릭터 고유 욕심(Greed, 0~100): 능력치 욕심 ×2 + 10.</summary>
    class function GreedBias(const AIndex: Integer): Integer; static;

    /// <summary>나이·직업 소개(예: "19세 · 재수생"). 범위 밖이면 빈 문자열.</summary>
    class function AgeJobOf(const AIndex: Integer): string; static;
    /// <summary>성격 소개 문장. 범위 밖이면 빈 문자열.</summary>
    class function PersonalityOf(const AIndex: Integer): string; static;
    /// <summary>고스톱 성향(플레이스타일) 소개 문장. 범위 밖이면 빈 문자열.</summary>
    class function PlaystyleOf(const AIndex: Integer): string; static;
    /// <summary>고 성향 별점(1~5). 범위 밖이거나 미상이면 0.</summary>
    class function GoStarsOf(const AIndex: Integer): Integer; static;
    /// <summary>추천 난이도 문자열(초급/중급/고급/최상). 범위 밖이면 빈 문자열.</summary>
    class function RecommendedDifficultyOf(const AIndex: Integer): string; static;
    /// <summary>대사 장수. 범위 밖이면 0.</summary>
    class function QuoteCount(const AIndex: Integer): Integer; static;
    /// <summary>인덱스 캐릭터의 AQuoteIndex번째 대사(0-기반). 범위 밖이면 빈 문자열.</summary>
    class function QuoteOf(const AIndex: Integer; const AQuoteIndex: Integer): string; static;
    /// <summary>이미지 생성 프롬프트(원본 참고용). 범위 밖이면 빈 문자열.</summary>
    class function ImagePromptOf(const AIndex: Integer): string; static;
    /// <summary>평상시 아바타 이미지의 <c>assets\avatars</c> 기준 상대 경로. 범위 밖이면 빈 문자열.</summary>
    class function NormalImageOf(const AIndex: Integer): string; static;
    /// <summary>환호(승리) 아바타 이미지의 <c>assets\avatars</c> 기준 상대 경로. 범위 밖이면 빈 문자열.</summary>
    class function CheerImageOf(const AIndex: Integer): string; static;
    /// <summary>슬픔(패배) 아바타 이미지의 <c>assets\avatars</c> 기준 상대 경로. 범위 밖이면 빈 문자열.</summary>
    class function SadImageOf(const AIndex: Integer): string; static;
    /// <summary>화남(패배·박 당함) 아바타 이미지의 <c>assets\avatars</c> 기준 상대 경로. 범위 밖이면 빈 문자열.</summary>
    class function AngryImageOf(const AIndex: Integer): string; static;
  end;

implementation

{$REGION 'uses'}
uses
  System.SysUtils,
  System.IOUtils,
  System.JSON,
  System.Generics.Collections,
  Gostop.Assets;
{$ENDREGION}

type
  TCharacterStats = array [0 .. TGostopCharacters.STAT_COUNT - 1] of Integer;

  TCharacterEntry = record
    Name: string;
    AgeJob: string;
    Personality: string;
    Playstyle: string;
    GoStars: Integer;
    RecommendedDifficulty: string;
    Stats: TCharacterStats;
    Quotes: TArray<string>;
    ImagePrompt: string;
    ImageNormal: string;
    ImageCheer: string;
    ImageSad: string;
    ImageAngry: string;
  end;

var
  GEntries: TArray<TCharacterEntry>;
  GLoaded: Boolean = False;

// JSON에서 캐릭터 배열을 읽어 GEntries를 채운다. 파일이 없거나 파싱 실패하면 빈 배열로 남는다(정상 동작 — 모든
// 조회 함수가 범위 밖 값에 대해 안전한 기본값을 반환하므로 게임은 계속 진행 가능).
procedure EnsureLoaded;
begin
  if GLoaded then
  begin
    Exit;
  end;

  GLoaded := True;   // 실패해도 재시도하지 않음(매 호출마다 파일 I/O 반복 방지)
  var LPath := THwatuAssets.CharactersJson;
  if (LPath = '') or (not TFile.Exists(LPath)) then
  begin
    Exit;
  end;

  try
    var LText := TFile.ReadAllText(LPath, TEncoding.UTF8);
    var LValue := TJSONObject.ParseJSONValue(LText);
    try
      if not (LValue is TJSONArray) then
      begin
        Exit;
      end;

      var LArr := TJSONArray(LValue);
      SetLength(GEntries, LArr.Count);
      for var I := 0 to LArr.Count - 1 do
      begin
        var LObj := LArr.Items[I] as TJSONObject;
        var LIdx := LObj.GetValue<Integer>('index', I);

        var LEntry: TCharacterEntry;
        LEntry.Name := LObj.GetValue<string>('name', '');
        LEntry.AgeJob := LObj.GetValue<string>('ageJob', '');
        LEntry.Personality := LObj.GetValue<string>('personality', '');
        LEntry.Playstyle := LObj.GetValue<string>('playstyle', '');
        LEntry.GoStars := LObj.GetValue<Integer>('goStars', 0);
        LEntry.RecommendedDifficulty := LObj.GetValue<string>('recommendedDifficulty', '');
        LEntry.ImagePrompt := LObj.GetValue<string>('imagePrompt', '');

        var LStatsObj: TJSONObject;
        if LObj.TryGetValue<TJSONObject>('stats', LStatsObj) then
        begin
          LEntry.Stats[TGostopCharacters.STAT_INSIGHT] := LStatsObj.GetValue<Integer>('insight', 20);
          LEntry.Stats[TGostopCharacters.STAT_COMPOSURE] := LStatsObj.GetValue<Integer>('composure', 20);
          LEntry.Stats[TGostopCharacters.STAT_NERVE] := LStatsObj.GetValue<Integer>('nerve', 20);
          LEntry.Stats[TGostopCharacters.STAT_GREED] := LStatsObj.GetValue<Integer>('greed', 20);
          LEntry.Stats[TGostopCharacters.STAT_LUCK] := LStatsObj.GetValue<Integer>('luck', 20);
        end;

        var LQuotesArr: TJSONArray;
        if LObj.TryGetValue<TJSONArray>('quotes', LQuotesArr) then
        begin
          SetLength(LEntry.Quotes, LQuotesArr.Count);
          for var Q := 0 to LQuotesArr.Count - 1 do
          begin
            LEntry.Quotes[Q] := LQuotesArr.Items[Q].Value;
          end;
        end;

        var LImagesObj: TJSONObject;
        if LObj.TryGetValue<TJSONObject>('images', LImagesObj) then
        begin
          LEntry.ImageNormal := LImagesObj.GetValue<string>('normal', '');
          LEntry.ImageCheer := LImagesObj.GetValue<string>('cheer', '');
          LEntry.ImageSad := LImagesObj.GetValue<string>('sad', '');
          LEntry.ImageAngry := LImagesObj.GetValue<string>('angry', '');
        end;

        if (LIdx >= 0) and (LIdx < Length(GEntries)) then
        begin
          GEntries[LIdx] := LEntry;
        end;
      end;
    finally
      LValue.Free;
    end;
  except
    // 손상된 JSON 등 — 빈 로스터로 안전 폴백(모든 조회 함수가 기본값 반환)
    SetLength(GEntries, 0);
  end;
end;

{$REGION 'TGostopCharacters'}
class function TGostopCharacters.Count: Integer;
begin
  EnsureLoaded;
  Result := Length(GEntries);
end;

class function TGostopCharacters.NameOf(const AIndex: Integer): string;
begin
  EnsureLoaded;
  if (AIndex >= 0) and (AIndex < Length(GEntries)) then
  begin
    Result := GEntries[AIndex].Name;
  end
  else
  begin
    Result := '';
  end;
end;

class function TGostopCharacters.StatOf(const AIndex: Integer; const AStat: Integer): Integer;
begin
  EnsureLoaded;
  if (AIndex >= 0) and (AIndex < Length(GEntries)) and (AStat >= 0) and (AStat <= STAT_COUNT - 1) then
  begin
    Result := GEntries[AIndex].Stats[AStat];
  end
  else
  begin
    Result := 20;
  end;
end;

class function TGostopCharacters.DerivedSkill(const AIndex: Integer): Integer;
begin
  Result := EnsureRange(Round((StatOf(AIndex, STAT_INSIGHT) + StatOf(AIndex, STAT_COMPOSURE)) * 1.25), 0, 100);
end;

class function TGostopCharacters.NerveBias(const AIndex: Integer): Integer;
begin
  Result := EnsureRange(StatOf(AIndex, STAT_NERVE) * 2 + 10, 0, 100);
end;

class function TGostopCharacters.GreedBias(const AIndex: Integer): Integer;
begin
  Result := EnsureRange(StatOf(AIndex, STAT_GREED) * 2 + 10, 0, 100);
end;

class function TGostopCharacters.AgeJobOf(const AIndex: Integer): string;
begin
  EnsureLoaded;
  if (AIndex >= 0) and (AIndex < Length(GEntries)) then
  begin
    Result := GEntries[AIndex].AgeJob;
  end
  else
  begin
    Result := '';
  end;
end;

class function TGostopCharacters.PersonalityOf(const AIndex: Integer): string;
begin
  EnsureLoaded;
  if (AIndex >= 0) and (AIndex < Length(GEntries)) then
  begin
    Result := GEntries[AIndex].Personality;
  end
  else
  begin
    Result := '';
  end;
end;

class function TGostopCharacters.PlaystyleOf(const AIndex: Integer): string;
begin
  EnsureLoaded;
  if (AIndex >= 0) and (AIndex < Length(GEntries)) then
  begin
    Result := GEntries[AIndex].Playstyle;
  end
  else
  begin
    Result := '';
  end;
end;

class function TGostopCharacters.GoStarsOf(const AIndex: Integer): Integer;
begin
  EnsureLoaded;
  if (AIndex >= 0) and (AIndex < Length(GEntries)) then
  begin
    Result := GEntries[AIndex].GoStars;
  end
  else
  begin
    Result := 0;
  end;
end;

class function TGostopCharacters.RecommendedDifficultyOf(const AIndex: Integer): string;
begin
  EnsureLoaded;
  if (AIndex >= 0) and (AIndex < Length(GEntries)) then
  begin
    Result := GEntries[AIndex].RecommendedDifficulty;
  end
  else
  begin
    Result := '';
  end;
end;

class function TGostopCharacters.QuoteCount(const AIndex: Integer): Integer;
begin
  EnsureLoaded;
  if (AIndex >= 0) and (AIndex < Length(GEntries)) then
  begin
    Result := Length(GEntries[AIndex].Quotes);
  end
  else
  begin
    Result := 0;
  end;
end;

class function TGostopCharacters.QuoteOf(const AIndex: Integer; const AQuoteIndex: Integer): string;
begin
  EnsureLoaded;
  if (AIndex >= 0) and (AIndex < Length(GEntries)) and
    (AQuoteIndex >= 0) and (AQuoteIndex < Length(GEntries[AIndex].Quotes)) then
  begin
    Result := GEntries[AIndex].Quotes[AQuoteIndex];
  end
  else
  begin
    Result := '';
  end;
end;

class function TGostopCharacters.ImagePromptOf(const AIndex: Integer): string;
begin
  EnsureLoaded;
  if (AIndex >= 0) and (AIndex < Length(GEntries)) then
  begin
    Result := GEntries[AIndex].ImagePrompt;
  end
  else
  begin
    Result := '';
  end;
end;

class function TGostopCharacters.NormalImageOf(const AIndex: Integer): string;
begin
  EnsureLoaded;
  if (AIndex >= 0) and (AIndex < Length(GEntries)) then
  begin
    Result := GEntries[AIndex].ImageNormal;
  end
  else
  begin
    Result := '';
  end;
end;

class function TGostopCharacters.CheerImageOf(const AIndex: Integer): string;
begin
  EnsureLoaded;
  if (AIndex >= 0) and (AIndex < Length(GEntries)) then
  begin
    Result := GEntries[AIndex].ImageCheer;
  end
  else
  begin
    Result := '';
  end;
end;

class function TGostopCharacters.SadImageOf(const AIndex: Integer): string;
begin
  EnsureLoaded;
  if (AIndex >= 0) and (AIndex < Length(GEntries)) then
  begin
    Result := GEntries[AIndex].ImageSad;
  end
  else
  begin
    Result := '';
  end;
end;

class function TGostopCharacters.AngryImageOf(const AIndex: Integer): string;
begin
  EnsureLoaded;
  if (AIndex >= 0) and (AIndex < Length(GEntries)) then
  begin
    Result := GEntries[AIndex].ImageAngry;
  end
  else
  begin
    Result := '';
  end;
end;
{$ENDREGION}

end.
