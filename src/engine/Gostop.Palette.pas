unit Gostop.Palette;

// 게임 전역 색상 팔레트. 여기저기 하드코딩되던 색상 매직넘버($AARRGGBB 리터럴)를 의미 있는 이름으로
// 한 곳에 모은다 — 어느 컴포넌트에도 속하지 않는 공유 자산(팔레트)이므로 공통 유닛에 둔다.
// record 네임스페이스로 접근(TPalette.Gold)해 이름 충돌을 피한다.

interface

{$REGION 'uses'}
uses
  System.UITypes;
{$ENDREGION}

type
  /// <summary>게임 전역 색상. 값은 $AARRGGBB(알파·빨강·녹색·파랑).</summary>
  TPalette = record
  public const
    // 금색 계열 — 강조·선택·강조 텍스트
    Gold        = TAlphaColor($FFFFD54A);   // 강조·선택 테두리
    GoldHover   = TAlphaColor($90FFD54A);   // 호버 금 테두리(반투명)
    GoldText    = TAlphaColor($FFFFE082);   // 금색 텍스트(값 버튼 등)
    GoldDeep    = TAlphaColor($FFB8860B);   // 짙은 금(accent 버튼)
    BannerText  = TAlphaColor($FFFFE14A);   // 특수상황 배너 금 텍스트

    // 다이얼로그 버튼
    BtnPrimary      = TAlphaColor($FF2E7D32);   // 긍정/확인/선택 녹색
    BtnDanger       = TAlphaColor($FF8E2430);   // 취소/부정 빨강
    BtnNeutral      = TAlphaColor($FF37474F);   // 기본 회청
    BtnDisabledFill = TAlphaColor($60333A33);   // 비활성 채움
    BtnDisabledText = TAlphaColor($806E786E);   // 비활성 텍스트

    // 패널·셸·토글
    PanelDark   = TAlphaColor($FF2F4436);   // 비선택 카드 셸·값 버튼 채움
    ToggleOff   = TAlphaColor($FF44504A);   // 토글 오프 트랙

    // 테두리(반투명 흰)
    BorderSoft  = TAlphaColor($50FFFFFF);   // 기본 테두리
    BorderMild  = TAlphaColor($60FFFFFF);   // 살짝 진한 테두리
    BorderFaint = TAlphaColor($30FFFFFF);   // 약한 테두리

    // 선택형 카드 라벨 스크림
    CardLabelSel  = TAlphaColor($B0B8860B);   // 선택 카드 하단 라벨 배경(반투명 금갈)
    CardLabelNorm = TAlphaColor($A0182018);   // 비선택 카드 라벨 배경
    CaptionDim    = TAlphaColor($FFCBD6C8);   // 스택 카드 캡션(연회녹)

    // 말풍선
    BubbleFill   = TAlphaColor($F0F5EEDD);   // 말풍선 배경
    BubbleBorder = TAlphaColor($FF8A7048);   // 말풍선 테두리
    BubbleText   = TAlphaColor($FF3A2A18);   // 말풍선 글자

    // 배너·오버레이·배지
    BannerFill = TAlphaColor($B0201008);   // 특수상황 배너 배경
    OverlayDim = TAlphaColor($A0000000);   // 일시정지 딤
    BadgeFill  = TAlphaColor($99787878);   // 획득 장수 배지 배경
    BadgeText  = TAlphaColor($FFFFF4D0);   // 배지 숫자(크림)

    // 나가리 도장(붉은 인주). 알파는 등장하며 동적으로 바뀌므로 RGB만($00RRGGBB), 사용처에서 알파 OR.
    StampFillRgb = TAlphaColor($00C81E1E);   // 도장 원판 채움
    StampLineRgb = TAlphaColor($00B01414);   // 도장 테두리
    StampTextRgb = TAlphaColor($00D42020);   // '나가리' 글자
  end;

implementation

end.
