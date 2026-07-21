unit Gostop.Board.Avatar;

// 자기완결형 아바타 액터. 보드는 표정을 "명령"만 하고(예: actor.Provoke), 표정 전환→지정시간
// 대기→원복이라는 일련의 애니메이션은 액터가 스스로 수행한다. 타이머 생성·활성화·틱·종료·정리가
// 보드 여기저기 흩어지던 것을 없애고, 한 애니의 라이프사이클을 애니 매니저(단일 타이머)에 위임한다.
// 스레드를 쓰지 않으므로 UI 블로킹·객체수명 AV 걱정이 없다.

interface

{$REGION 'uses'}
uses
  Gostop.Board.Animation;
{$ENDREGION}

type
  /// <summary>아바타 표정. 평상시 외 표정은 지정시간 뒤 자동으로 평상시로 돌아간다(HoldExpression).</summary>
  TAvatarExpression = (
    aeNormal,   // 평상시
    aeCheer,    // 환호(승리)
    aeSad,      // 슬픔(패배)
    aeAngry     // 화남(피 뺏김·박)
  );

  /// <summary>
  ///   한 좌석 아바타의 표정 상태 머신. 보드가 표정 비트맵을 고를 때 이 Expression 을 읽는다.
  ///   HoldExpression 은 "표정을 바꾸고 N초 뒤 평상시로 되돌리는" 애니를 매니저에 등록하고 즉시 반환한다
  ///   — 대기는 매니저 타이머가 경과시간으로 처리하므로 아무것도 멈추지 않는다.
  /// </summary>
  TAvatarActor = class
  strict private
    FMgr: TAnimationManager;
    FExpression: TAvatarExpression;
    FHoldGen: Integer;   // 홀드 세대. 새 홀드가 이전 홀드의 원복을 무효화(연속 유발 경합 방지)
  public
    constructor Create(const AMgr: TAnimationManager);
    /// <summary>표정을 즉시 AExpr 로 바꾸고 ASeconds 뒤 평상시로 되돌린다(대기는 논블로킹).</summary>
    procedure HoldExpression(const AExpr: TAvatarExpression; const ASeconds: Single);
    /// <summary>표정을 즉시 지정(자동 원복 없음 — 정산 환호/슬픔처럼 다음 상태까지 유지할 때).</summary>
    procedure SetExpression(const AExpr: TAvatarExpression);
    /// <summary>평상시로 되돌리고 진행 중인 홀드를 무효화(판 전환·정리용).</summary>
    procedure Reset;
    /// <summary>홀드 애니가 완료 시 호출 — 자기가 등록한 세대일 때만 원복(더 새 홀드가 있으면 무시).</summary>
    procedure RestoreIfCurrent(const AGen: Integer);
    property Expression: TAvatarExpression read FExpression;
  end;

implementation

type
  // 표정을 지정시간 유지한 뒤 액터를 평상시로 되돌리는 애니(그리는 것 없음, 시간만 잰다).
  TExpressionHoldAnimation = class(TBoardAnimation)
  strict private
    FActor: TAvatarActor;
    FGen: Integer;
    FRemainMs: Single;
  public
    constructor Create(const AActor: TAvatarActor; const AGen: Integer; const ASeconds: Single);
    procedure Update(const ADeltaMs: Single); override;
    procedure Draw; override;
  end;

{$REGION 'TExpressionHoldAnimation'}
constructor TExpressionHoldAnimation.Create(const AActor: TAvatarActor; const AGen: Integer; const ASeconds: Single);
begin
  inherited Create(nil);   // 호스트 불필요(Draw 없음)
  FActor := AActor;
  FGen := AGen;
  FRemainMs := ASeconds * 1000;
end;

procedure TExpressionHoldAnimation.Update(const ADeltaMs: Single);
begin
  FRemainMs := FRemainMs - ADeltaMs;
  if FRemainMs <= 0 then
  begin
    FActor.RestoreIfCurrent(FGen);
    FDone := True;
  end;
end;

procedure TExpressionHoldAnimation.Draw;
begin
  // 그리는 것 없음 — 시간만 잰다
end;
{$ENDREGION}

{$REGION 'TAvatarActor'}
constructor TAvatarActor.Create(const AMgr: TAnimationManager);
begin
  inherited Create;
  FMgr := AMgr;
  FExpression := aeNormal;
  FHoldGen := 0;
end;

procedure TAvatarActor.HoldExpression(const AExpr: TAvatarExpression; const ASeconds: Single);
begin
  Inc(FHoldGen);
  FExpression := AExpr;
  FMgr.Add(TExpressionHoldAnimation.Create(Self, FHoldGen, ASeconds));
end;

procedure TAvatarActor.SetExpression(const AExpr: TAvatarExpression);
begin
  Inc(FHoldGen);   // 진행 중 홀드의 원복 무효화
  FExpression := AExpr;
end;

procedure TAvatarActor.Reset;
begin
  Inc(FHoldGen);
  FExpression := aeNormal;
end;

procedure TAvatarActor.RestoreIfCurrent(const AGen: Integer);
begin
  if AGen = FHoldGen then
  begin
    FExpression := aeNormal;
  end;
end;
{$ENDREGION}

end.
