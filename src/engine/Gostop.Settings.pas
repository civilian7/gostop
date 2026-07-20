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
    ReverseGo: Boolean;      // 역고(따따블 ×4)
    Bonus: Boolean;          // 보너스패 3장 포함(끄면 순수 48장)
    Speech: Boolean;         // 참가자 말풍선 표시(기본 켬)
    MoneyPerPoint: Integer;  // 점당 금액(사용자 설정 불가 — AiSkill로 자동 결정, SyncMoneyPerPoint 참조)
    SeedMoney: Integer;      // 시드머니(사용자 설정 불가 — 시스템 고정값)
    AiSkill: Integer;        // 게임 레벨(30/50/70/100 — 병아리/선수/타짜/신의손)
    Nickname: string;        // 내 닉네임
    KillCount: Integer;      // 오링 카운트(내가 상대를 파산시킨 누적 횟수, 매치 리셋과 무관하게 영구 유지)
    RefillCount: Integer;    // 리필 횟수(내가 오링되어 시드머니를 재지급받은 누적 횟수, 매치 리셋과 무관하게 영구 유지)

    /// <summary>기본값으로 초기화합니다.</summary>
    procedure Reset;
    /// <summary>수동 편집 등으로 어긋난 값을 유효 범위로 보정합니다.</summary>
    procedure Validate;
    /// <summary>AiSkill(게임 레벨)에 따라 점당 금액을 자동으로 맞춥니다.</summary>
    procedure SyncMoneyPerPoint;
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
  ReverseGo := True;
  Bonus := True;
  Speech := True;
  SeedMoney := 1000000;   // 시스템 고정 시드머니(100만원)
  AiSkill := 70;
  SyncMoneyPerPoint;
  Nickname := '나';
  KillCount := 0;
  RefillCount := 0;
end;

procedure TGameConfig.Validate;
begin
  AiSkill := EnsureRange(AiSkill, 0, 100);
  SyncMoneyPerPoint;   // 점당 금액은 항상 AiSkill에서 유도(수동 편집 무력화)

  if SeedMoney <= 0 then
  begin
    SeedMoney := 1000000;
  end;

  Nickname := Trim(Nickname);
  if Nickname = '' then
  begin
    Nickname := '나';
  end;

  if KillCount < 0 then
  begin
    KillCount := 0;
  end;

  if RefillCount < 0 then
  begin
    RefillCount := 0;
  end;
end;

procedure TGameConfig.SyncMoneyPerPoint;
begin
  case AiSkill of
    30:
      begin
        MoneyPerPoint := 50;
      end;
    50:
      begin
        MoneyPerPoint := 100;
      end;
    70:
      begin
        MoneyPerPoint := 500;
      end;
  else
    begin
      MoneyPerPoint := 1000;   // 100(신의손) 포함
    end;
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

  Result.ReverseGoEnabled := ReverseGo;
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
  ReverseGo := AIni.ReadBool('Rules', 'ReverseGo', ReverseGo);
  Bonus := AIni.ReadBool('Rules', 'Bonus', Bonus);
  Speech := AIni.ReadBool('Rules', 'Speech', Speech);
  // MoneyPerPoint(AiSkill로 자동 유도)·SeedMoney(시스템 고정값)는 사용자 설정이 아니므로
  // INI에서 읽지 않는다(과거 저장된 값이 남아있어도 무시 — Reset의 기본값을 그대로 유지)
  AiSkill := AIni.ReadInteger('Rules', 'AiSkill', AiSkill);
  Nickname := AIni.ReadString('Player', 'Nickname', Nickname);
  KillCount := AIni.ReadInteger('Player', 'KillCount', KillCount);
  RefillCount := AIni.ReadInteger('Player', 'RefillCount', RefillCount);
end;

procedure TGameConfig.SaveTo(const AIni: TIniFile);
begin
  AIni.WriteBool('Rules', 'Pibak', Pibak);
  AIni.WriteBool('Rules', 'Gwangbak', Gwangbak);
  AIni.WriteBool('Rules', 'Meongbak', Meongbak);
  AIni.WriteBool('Rules', 'Gobak', Gobak);
  AIni.WriteBool('Rules', 'ReverseGo', ReverseGo);
  AIni.WriteBool('Rules', 'Bonus', Bonus);
  AIni.WriteBool('Rules', 'Speech', Speech);
  AIni.WriteInteger('Rules', 'AiSkill', AiSkill);
  AIni.WriteString('Player', 'Nickname', Nickname);
  AIni.WriteInteger('Player', 'KillCount', KillCount);
  AIni.WriteInteger('Player', 'RefillCount', RefillCount);
end;
{$ENDREGION}

end.
