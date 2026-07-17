unit Gostop.Settings;

interface

{$REGION 'uses'}
uses
  System.SysUtils,
  System.Math,
  System.IniFiles,
  Gostop.Cards,
  Gostop.Deck,
  Gostop.Score,
  Gostop.Play;
{$ENDREGION}

type
  /// <summary>
  ///   게임 룰·플레이어 설정 값(설정창에서 변경, gostop.ini에 저장). 순수 값 타입.
  ///   룰 옵션·덱 구성으로의 변환과 INI 입출력을 담당한다(UI 상태인 볼륨·배속·아바타는 제외).
  /// </summary>
  TGameConfig = record
  public
    Pibak: Boolean;          // 피박
    Gwangbak: Boolean;       // 광박
    Meongbak: Boolean;       // 멍박(열끗박)
    Gobak: Boolean;          // 고박(×2)
    Bonus: Boolean;          // 보너스패 3장 포함(끄면 순수 48장)
    MoneyPerPoint: Integer;  // 점당 금액
    SeedMoney: Integer;      // 시드머니
    AiSkill: Integer;        // 사람 자리 기본 AI 난이도(30/50/70/90)
    Nickname: string;        // 내 닉네임

    /// <summary>기본값으로 초기화합니다.</summary>
    procedure Reset;
    /// <summary>수동 편집 등으로 어긋난 값을 유효 범위로 보정합니다.</summary>
    procedure Validate;
    /// <summary>설정을 반영한 점수 옵션(피박·광박·고박 배수).</summary>
    function ToScore: TScoreOptions;
    /// <summary>설정을 반영한 룰셋.</summary>
    function ToRules: TRuleSet;
    /// <summary>설정을 반영한 덱 구성(보너스패 포함/순수 48장).</summary>
    function ToDeckOptions: TDeckOptions;
    /// <summary>INI의 [Rules]/[Player] 섹션에서 값을 읽습니다(기존 값을 기본값으로).</summary>
    procedure LoadFrom(const AIni: TIniFile);
    /// <summary>INI의 [Rules]/[Player] 섹션에 값을 씁니다.</summary>
    procedure SaveTo(const AIni: TIniFile);
  end;

implementation

{$REGION 'TGameConfig'}
procedure TGameConfig.Reset;
begin
  Pibak := True;
  Gwangbak := True;
  Meongbak := True;
  Gobak := True;
  Bonus := True;
  MoneyPerPoint := 100;
  SeedMoney := 30000;
  AiSkill := 70;
  Nickname := '나';
end;

procedure TGameConfig.Validate;
begin
  AiSkill := EnsureRange(AiSkill, 0, 100);
  if MoneyPerPoint <= 0 then
  begin
    MoneyPerPoint := 100;
  end;

  if SeedMoney <= 0 then
  begin
    SeedMoney := 30000;
  end;

  Nickname := Trim(Nickname);
  if Nickname = '' then
  begin
    Nickname := '나';
  end;
end;

function TGameConfig.ToScore: TScoreOptions;
begin
  Result := TScoreOptions.Default;
  Result.PibakEnabled := Pibak;
  Result.GwangbakEnabled := Gwangbak;
  Result.MeongbakEnabled := Meongbak;
  if Gobak then
  begin
    Result.GobakMultiplier := 2;
  end
  else
  begin
    Result.GobakMultiplier := 1;
  end;
end;

function TGameConfig.ToRules: TRuleSet;
begin
  Result := TRuleSet.Default;
  Result.Score := ToScore;
end;

function TGameConfig.ToDeckOptions: TDeckOptions;
begin
  if Bonus then
  begin
    Result := TDeckOptions.WithBonus(3);
  end
  else
  begin
    Result := TDeckOptions.Standard;
  end;
end;

procedure TGameConfig.LoadFrom(const AIni: TIniFile);
begin
  Pibak := AIni.ReadBool('Rules', 'Pibak', Pibak);
  Gwangbak := AIni.ReadBool('Rules', 'Gwangbak', Gwangbak);
  Meongbak := AIni.ReadBool('Rules', 'Meongbak', Meongbak);
  Gobak := AIni.ReadBool('Rules', 'Gobak', Gobak);
  Bonus := AIni.ReadBool('Rules', 'Bonus', Bonus);
  MoneyPerPoint := AIni.ReadInteger('Rules', 'MoneyPerPoint', MoneyPerPoint);
  SeedMoney := AIni.ReadInteger('Rules', 'SeedMoney', SeedMoney);
  AiSkill := AIni.ReadInteger('Rules', 'AiSkill', AiSkill);
  Nickname := AIni.ReadString('Player', 'Nickname', Nickname);
end;

procedure TGameConfig.SaveTo(const AIni: TIniFile);
begin
  AIni.WriteBool('Rules', 'Pibak', Pibak);
  AIni.WriteBool('Rules', 'Gwangbak', Gwangbak);
  AIni.WriteBool('Rules', 'Meongbak', Meongbak);
  AIni.WriteBool('Rules', 'Gobak', Gobak);
  AIni.WriteBool('Rules', 'Bonus', Bonus);
  AIni.WriteInteger('Rules', 'MoneyPerPoint', MoneyPerPoint);
  AIni.WriteInteger('Rules', 'SeedMoney', SeedMoney);
  AIni.WriteInteger('Rules', 'AiSkill', AiSkill);
  AIni.WriteString('Player', 'Nickname', Nickname);
end;
{$ENDREGION}

end.
