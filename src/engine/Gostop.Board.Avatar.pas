unit Gostop.Board.Avatar;

// 자기완결형 아바타 액터. 보드는 표정·말풍선을 "명령"만 하고(예: actor.HoldExpression / actor.ShowSpeech),
// 표정 전환→지정시간 대기→원복(또는 말풍선 표시→N초→사라짐)이라는 일련의 애니메이션은 액터가 스스로
// 수행한다. 타이머 생성·활성화·틱·종료·정리가 보드 여기저기 흩어지던 것을 없애고, 지연은 애니 매니저의
// 범용 TDelayAnimation(단일 타이머, OnDone 클로저)에 위임한다. 스레드를 쓰지 않아 UI 블로킹·AV 걱정이 없다.

interface

{$REGION 'uses'}
uses
  System.SysUtils,
  System.Types,
  FMX.Graphics,
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
  ///   한 좌석 아바타의 표정·말풍선 상태 머신. 보드는 표정 비트맵을 고를 때 Expression 을, 말풍선을 그릴 때
  ///   SpeechText 를 읽는다. HoldExpression/ShowSpeech 는 상태를 바꾸고 "N초 뒤 원복/지우기" 애니를 매니저에
  ///   등록한 뒤 즉시 반환한다 — 대기는 매니저 타이머가 경과시간으로 처리하므로 아무것도 멈추지 않는다.
  ///   좌석당 하나씩 존재하므로 여러 좌석이 동시에 화나거나 말풍선을 띄울 수 있다.
  /// </summary>
  TAvatarActor = class
  strict private
    FMgr: TAnimationManager;
    FExpression: TAvatarExpression;
    FHoldGen: Integer;     // 표정 홀드 세대. 새 홀드가 이전 홀드의 원복을 무효화(연속 유발 경합 방지)
    FSpeechText: string;
    FSpeechGen: Integer;   // 말풍선 세대. 위와 동일한 경합 방지
    // ADoneCallback 을 ASeconds 뒤 실행하는 지연 애니를 매니저에 등록(공용 헬퍼)
    procedure ScheduleDelay(const ASeconds: Single; const ADoneCallback: TProc);
  public
    constructor Create(const AMgr: TAnimationManager);
    /// <summary>표정을 즉시 AExpr 로 바꾸고 ASeconds 뒤 평상시로 되돌린다(대기는 논블로킹).</summary>
    procedure HoldExpression(const AExpr: TAvatarExpression; const ASeconds: Single);
    /// <summary>표정을 즉시 지정(자동 원복 없음 — 정산 환호/슬픔처럼 다음 상태까지 유지할 때).</summary>
    procedure SetExpression(const AExpr: TAvatarExpression);
    /// <summary>말풍선 텍스트를 띄우고 ASeconds 뒤 지운다(대기는 논블로킹).</summary>
    procedure ShowSpeech(const AText: string; const ASeconds: Single);
    /// <summary>표정·말풍선을 즉시 초기화하고 진행 중인 지연을 무효화(판 전환·정리용).</summary>
    procedure Reset;
    /// <summary>
    ///   현재 표정에 맞는 아바타 비트맵을 골라 그린다. 표정→비트맵 매핑을 액터가 소유한다(자기완결).
    ///   보드는 인덱스로 뽑은 후보 비트맵만 넘긴다(풀 소유는 보드 — 슬롯·피커·저장이 공유하므로).
    ///   화남 표정이고 화남 비트맵이 있으면 그것을, 없으면 평상시, 그것도 없으면 폴백을 쓴다.
    /// </summary>
    procedure Draw(const ACanvas: TCanvas; const ARect: TRectF;
      const ANormalBmp, AAngryBmp, AFallbackBmp: TBitmap);
    property Expression: TAvatarExpression read FExpression;
    property SpeechText: string read FSpeechText;
  end;

implementation

{$REGION 'TAvatarActor'}
constructor TAvatarActor.Create(const AMgr: TAnimationManager);
begin
  inherited Create;
  FMgr := AMgr;
  FExpression := aeNormal;
  FHoldGen := 0;
  FSpeechText := '';
  FSpeechGen := 0;
end;

procedure TAvatarActor.ScheduleDelay(const ASeconds: Single; const ADoneCallback: TProc);
begin
  var LAnim := TDelayAnimation.Create(ASeconds);
  LAnim.OnDone := ADoneCallback;   // "N초 뒤 무엇을 하기"를 클로저로 선언(개별 타이머 없이)
  FMgr.Add(LAnim);
end;

procedure TAvatarActor.HoldExpression(const AExpr: TAvatarExpression; const ASeconds: Single);
var
  LGen: Integer;   // 클로저가 캡처하므로 var 블록에 둔다
begin
  Inc(FHoldGen);
  FExpression := AExpr;
  LGen := FHoldGen;
  ScheduleDelay(ASeconds,
    procedure
    begin
      if LGen = FHoldGen then   // 더 새 홀드가 없을 때만 원복
      begin
        FExpression := aeNormal;
      end;
    end);
end;

procedure TAvatarActor.SetExpression(const AExpr: TAvatarExpression);
begin
  Inc(FHoldGen);   // 진행 중 홀드의 원복 무효화
  FExpression := AExpr;
end;

procedure TAvatarActor.ShowSpeech(const AText: string; const ASeconds: Single);
var
  LGen: Integer;   // 클로저가 캡처하므로 var 블록에 둔다
begin
  Inc(FSpeechGen);
  FSpeechText := AText;
  LGen := FSpeechGen;
  ScheduleDelay(ASeconds,
    procedure
    begin
      if LGen = FSpeechGen then   // 더 새 말풍선이 없을 때만 지움
      begin
        FSpeechText := '';
      end;
    end);
end;

procedure TAvatarActor.Reset;
begin
  Inc(FHoldGen);
  Inc(FSpeechGen);
  FExpression := aeNormal;
  FSpeechText := '';
end;

procedure TAvatarActor.Draw(const ACanvas: TCanvas; const ARect: TRectF;
  const ANormalBmp, AAngryBmp, AFallbackBmp: TBitmap);
begin
  var LBmp: TBitmap := nil;
  if (FExpression = aeAngry) and Assigned(AAngryBmp) then
  begin
    LBmp := AAngryBmp;
  end;

  if not Assigned(LBmp) then
  begin
    LBmp := ANormalBmp;
  end;

  if not Assigned(LBmp) then
  begin
    LBmp := AFallbackBmp;
  end;

  if Assigned(LBmp) then
  begin
    ACanvas.DrawBitmap(LBmp, RectF(0, 0, LBmp.Width, LBmp.Height), ARect, 1, False);
  end;
end;
{$ENDREGION}

end.
