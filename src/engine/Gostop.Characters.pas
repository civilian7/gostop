unit Gostop.Characters;

interface

{$REGION 'uses'}
uses
  System.Math;
{$ENDREGION}

type
  /// <summary>
  ///   고스톱 캐릭터(아바타) 정본 데이터와 순수 조회 함수.
  ///   아바타 이미지 파일(<c>assets\avatars\avatar_NN.png</c>) 순서 = 이 배열 순서 = 인덱스(0-기반).
  ///   능력치 상세는 <c>docs\characters.md</c> 참조.
  /// </summary>
  TGostopCharacters = record
  public
    const
      /// <summary>등록된 캐릭터 수.</summary>
      COUNT = 20;
      /// <summary>능력치 축 수(수읽기/침착/배짱/욕심/운).</summary>
      STAT_COUNT = 5;
      /// <summary>능력치 축 인덱스.</summary>
      STAT_INSIGHT = 0;   // 수읽기
      STAT_COMPOSURE = 1; // 침착
      STAT_NERVE = 2;     // 배짱
      STAT_GREED = 3;     // 욕심
      STAT_LUCK = 4;      // 운

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
  end;

implementation

{$REGION 'TGostopCharacters'}
const
  // 아바타(assets\avatars 순서)와 짝을 이루는 재미난 닉네임 풀
  AVATAR_NAMES: array [0 .. TGostopCharacters.COUNT - 1] of string = (
    '피주워요', '못먹어도고', '광팔이', '흔들신사', '동네타짜',
    '초단콜렉터', '고도리헌터', '쌍피장인', '뻑전문가', '화투도사',
    '쪽쪽이', '싹쓸이요정', '피박금지', '고고고', '국진할멈',
    '스톱은없다', '자뻑여왕', '점백의달인', '판쓸이할매', '옆집고수'
  );

  // 캐릭터 능력치(각 행 합계 100): [수읽기, 침착, 배짱, 욕심, 운]
  // 수읽기+침착 → AI 스킬(×1.25), 배짱 → GoBias, 욕심 → Greed, 운 → 판별 운 굴림 기반
  AVATAR_STATS: array [0 .. TGostopCharacters.COUNT - 1, 0 .. TGostopCharacters.STAT_COUNT - 1] of Integer = (
    (10, 15, 10, 25, 40),   // 피주워요
    (10, 10, 40, 30, 10),   // 못먹어도고
    (25, 25, 15, 25, 10),   // 광팔이
    (25, 20, 30, 15, 10),   // 흔들신사
    (35, 30, 15, 15, 5),    // 동네타짜
    (20, 25, 10, 35, 10),   // 초단콜렉터
    (25, 15, 25, 30, 5),    // 고도리헌터
    (25, 30, 15, 20, 10),   // 쌍피장인
    (10, 5, 25, 20, 40),    // 뻑전문가
    (40, 25, 15, 10, 10),   // 화투도사
    (10, 15, 20, 25, 30),   // 쪽쪽이
    (15, 10, 30, 30, 15),   // 싹쓸이요정
    (20, 30, 10, 10, 30),   // 피박금지
    (10, 10, 40, 25, 15),   // 고고고
    (30, 25, 10, 15, 20),   // 국진할멈
    (15, 15, 40, 25, 5),    // 스톱은없다
    (20, 15, 30, 25, 10),   // 자뻑여왕
    (40, 30, 10, 15, 5),    // 점백의달인
    (30, 20, 25, 20, 5),    // 판쓸이할매
    (35, 35, 10, 10, 10)    // 옆집고수
  );

class function TGostopCharacters.NameOf(const AIndex: Integer): string;
begin
  if (AIndex >= 0) and (AIndex <= High(AVATAR_NAMES)) then
  begin
    Result := AVATAR_NAMES[AIndex];
  end
  else
  begin
    Result := '';
  end;
end;

class function TGostopCharacters.StatOf(const AIndex: Integer; const AStat: Integer): Integer;
begin
  if (AIndex >= 0) and (AIndex <= High(AVATAR_STATS)) and (AStat >= 0) and (AStat <= STAT_COUNT - 1) then
  begin
    Result := AVATAR_STATS[AIndex, AStat];
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
{$ENDREGION}

end.
