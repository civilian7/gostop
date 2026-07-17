unit Gostop.Deck;

interface

{$REGION 'uses'}
uses
  System.SysUtils,
  System.Generics.Collections,
  Gostop.Cards;
{$ENDREGION}

type
  /// <summary>덱 구성 옵션.</summary>
  TDeckOptions = record
    /// <summary>보너스패(조커)를 덱에 포함할지 여부.</summary>
    IncludeBonus: Boolean;
    /// <summary>포함할 보너스패 장수(0~4). IncludeBonus가 False면 무시.</summary>
    BonusCount: Integer;

    /// <summary>표준 구성(48장, 보너스 없음) 옵션을 반환합니다.</summary>
    class function Standard: TDeckOptions; static;
    /// <summary>보너스패 포함 구성 옵션을 반환합니다.</summary>
    /// <param name="ACount">포함할 보너스패 장수(0~4). 기본 3(쌍피 2 · 3피 1).</param>
    class function WithBonus(const ACount: Integer = 3): TDeckOptions; static;
  end;

  /// <summary>덱이 비었을 때 카드를 뽑으려 하면 발생하는 예외.</summary>
  EHwatuDeckEmpty = class(EHwatuError);

  /// <summary>
  ///   화투 덱을 나타내는 클래스. 표준 48장(+선택적 보너스패)을 생성하고,
  ///   셔플·드로우 등 기본 덱 조작을 제공한다. 카드 순서에서 리스트의 끝이 '맨 위(다음에 뽑을 카드)'다.
  /// </summary>
  TDeck = class
  private
    FCards: TList<THwatuCard>;
    procedure DoShuffle(const ANextIndex: TFunc<Integer, Integer>);
  public
    /// <summary>표준 구성(48장)으로 덱을 생성합니다.</summary>
    constructor Create; overload;
    /// <summary>주어진 옵션으로 덱을 생성합니다.</summary>
    /// <param name="AOptions">덱 구성 옵션.</param>
    constructor Create(const AOptions: TDeckOptions); overload;
    destructor Destroy; override;

    /// <summary>옵션에 따라 덱을 다시 구성합니다(기존 카드는 모두 대체).</summary>
    /// <param name="AOptions">덱 구성 옵션.</param>
    procedure Build(const AOptions: TDeckOptions);
    /// <summary>시스템 난수로 카드를 섞습니다(비결정적).</summary>
    procedure Shuffle; overload;
    /// <summary>주어진 시드로 카드를 섞습니다(결정적·재현 가능).</summary>
    /// <param name="ASeed">난수 시드.</param>
    procedure Shuffle(const ASeed: Cardinal); overload;
    /// <summary>
    ///   OS 암호학적 난수(Windows <c>BCryptGenRandom</c>)로 카드를 섞습니다. 매 뽑기마다 새 엔트로피를 쓰고
    ///   rejection sampling으로 모듈로 편향을 제거해, LCG의 상태·시드 한계 없이 모든 순열이 등확률에 가깝습니다.
    ///   공정성이 중요한(온라인·경쟁) 셔플에 사용하세요.
    /// </summary>
    /// <exception cref="EHwatuError">난수 생성에 실패하면 발생.</exception>
    procedure ShuffleSecure;
    /// <summary>맨 위(리스트 끝) 카드를 한 장 뽑아 제거하고 반환합니다.</summary>
    /// <returns>뽑힌 카드.</returns>
    /// <exception cref="EHwatuDeckEmpty">덱이 비어 있으면 발생.</exception>
    function Draw: THwatuCard;
    /// <summary>맨 위에서 지정한 장수만큼 뽑아 제거하고 배열로 반환합니다.</summary>
    /// <param name="ACount">뽑을 장수.</param>
    /// <returns>뽑힌 카드 배열(뽑은 순서).</returns>
    /// <exception cref="EHwatuDeckEmpty">남은 카드보다 많이 뽑으려 하면 발생.</exception>
    function DrawMany(const ACount: Integer): TArray<THwatuCard>;
    /// <summary>덱이 비어 있으면 True를 반환합니다.</summary>
    function IsEmpty: Boolean;
    /// <summary>덱에 남은 카드 장수.</summary>
    function Count: Integer;

    /// <summary>덱의 카드 목록(읽기용). 끝이 맨 위.</summary>
    property Cards: TList<THwatuCard> read FCards;
  end;

implementation

const
  // 64비트 LCG(PCG류) 상수. 부호 없는 타입으로 명시해 부호 혼합 경고를 방지.
  LCG_MULTIPLIER: UInt64 = 6364136223846793005;
  LCG_INCREMENT: UInt64 = 1442695040888963407;

{$IFDEF MSWINDOWS}
const
  BCRYPT_USE_SYSTEM_PREFERRED_RNG = $00000002;

function BCryptGenRandom(hAlgorithm: Pointer; pbBuffer: PByte; cbBuffer: Cardinal;
  dwFlags: Cardinal): Integer; stdcall; external 'bcrypt.dll' name 'BCryptGenRandom';

// OS 암호학적 난수 32비트 1개
function SecureRandom32: Cardinal;
begin
  var LStatus := BCryptGenRandom(nil, @Result, SizeOf(Result), BCRYPT_USE_SYSTEM_PREFERRED_RNG);
  if LStatus <> 0 then
  begin
    raise EHwatuError.CreateFmt('BCryptGenRandom 실패 (NTSTATUS=0x%.8x)', [LStatus]);
  end;
end;

// [0, ABound) 균일 정수. rejection sampling으로 모듈로 편향 제거.
function SecureRandomBelow(const ABound: Cardinal): Cardinal;
begin
  if ABound <= 1 then
  begin
    Exit(0);
  end;

  var LRange: UInt64 := UInt64(1) shl 32;
  var LLimit: UInt64 := LRange - (LRange mod ABound);
  var LRaw: Cardinal;
  repeat
    LRaw := SecureRandom32;
  until LRaw < LLimit;

  Result := LRaw mod ABound;
end;
{$ENDIF}

{$REGION 'TDeckOptions'}
class function TDeckOptions.Standard: TDeckOptions;
begin
  Result.IncludeBonus := False;
  Result.BonusCount := 0;
end;

class function TDeckOptions.WithBonus(const ACount: Integer): TDeckOptions;
begin
  Result.IncludeBonus := True;
  Result.BonusCount := ACount;
end;
{$ENDREGION}

{$REGION 'TDeck'}
constructor TDeck.Create;
begin
  Create(TDeckOptions.Standard);
end;

constructor TDeck.Create(const AOptions: TDeckOptions);
begin
  inherited Create;
  FCards := TList<THwatuCard>.Create;
  Build(AOptions);
end;

destructor TDeck.Destroy;
begin
  FreeAndNil(FCards);
  inherited Destroy;
end;

procedure TDeck.Build(const AOptions: TDeckOptions);
begin
  FCards.Clear;
  FCards.AddRange(THwatuCatalog.Standard);

  if AOptions.IncludeBonus then
  begin
    var LBonus := THwatuCatalog.Bonus;
    var LCount := AOptions.BonusCount;
    if LCount > Length(LBonus) then
    begin
      LCount := Length(LBonus);
    end;

    for var I := 0 to LCount - 1 do
    begin
      FCards.Add(LBonus[I]);
    end;
  end;
end;

procedure TDeck.DoShuffle(const ANextIndex: TFunc<Integer, Integer>);
begin
  // Fisher–Yates: 뒤에서부터 앞쪽의 임의 위치와 교환
  for var I := FCards.Count - 1 downto 1 do
  begin
    var LJ := ANextIndex(I + 1);
    var LTemp := FCards[I];
    FCards[I] := FCards[LJ];
    FCards[LJ] := LTemp;
  end;
end;

procedure TDeck.Shuffle;
begin
  Randomize;
  DoShuffle(
    function(ABound: Integer): Integer
    begin
      Result := Random(ABound);
    end);
end;

procedure TDeck.Shuffle(const ASeed: Cardinal);
var
  LState: UInt64;
begin
  // 결정적 재현을 위해 RTL 전역 상태에 의존하지 않는 LCG 사용
  LState := ASeed;
  DoShuffle(
    function(ABound: Integer): Integer
    begin
      LState := LState * LCG_MULTIPLIER + LCG_INCREMENT;
      Result := Integer((LState shr 33) mod UInt64(ABound));
    end);
end;

procedure TDeck.ShuffleSecure;
begin
{$IFDEF MSWINDOWS}
  DoShuffle(
    function(ABound: Integer): Integer
    begin
      Result := Integer(SecureRandomBelow(Cardinal(ABound)));
    end);
{$ELSE}
  raise EHwatuError.Create('ShuffleSecure는 Windows(BCryptGenRandom)에서만 지원됩니다.');
{$ENDIF}
end;

function TDeck.Draw: THwatuCard;
begin
  if IsEmpty then
  begin
    raise EHwatuDeckEmpty.Create('덱이 비어 있어 카드를 뽑을 수 없습니다.');
  end;

  var LTopIndex := FCards.Count - 1;
  Result := FCards[LTopIndex];
  FCards.Delete(LTopIndex);
end;

function TDeck.DrawMany(const ACount: Integer): TArray<THwatuCard>;
begin
  if ACount > FCards.Count then
  begin
    raise EHwatuDeckEmpty.CreateFmt('덱에 %d장만 남아 %d장을 뽑을 수 없습니다.', [FCards.Count, ACount]);
  end;

  SetLength(Result, ACount);
  for var I := 0 to ACount - 1 do
  begin
    Result[I] := Draw;
  end;
end;

function TDeck.IsEmpty: Boolean;
begin
  Result := FCards.Count = 0;
end;

function TDeck.Count: Integer;
begin
  Result := FCards.Count;
end;
{$ENDREGION}

end.
