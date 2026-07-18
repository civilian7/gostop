"""
아바타 이미지 배경 제거 도구(rembg 신경망 매팅).

두 가지 모드:
  single  - 단일 이미지 1장 처리(정사각 아니면 중앙 크롭 후 배경 제거)
  sheet   - 여러 인물이 격자로 배열된 시트 1장을 N명으로 잘라 일괄 처리

자세한 설명은 docs/avatar-image-pipeline.md 참조.

사용 예:
  # 단일 파일(이미 인물 사진 한 장)
  python scripts/avatar_bg_remove.py single input.png output.png
  python scripts/avatar_bg_remove.py single input.png output.png --size 256

  # 격자 시트(5열×4행 = 20명) → assets/avatars/에 avatar_01.png..avatar_20.png
  python scripts/avatar_bg_remove.py sheet sheet_normal.png assets/avatars "avatar_{:02d}.png"

  # 격자 시트 → assets/avatars/states/에 환호 상태
  python scripts/avatar_bg_remove.py sheet sheet_cheer.png assets/avatars/states "avatar_{:02d}_cheer.png"
"""

import argparse
import os

from PIL import Image
from rembg import new_session, remove

DEFAULT_SIZE = 128
DEFAULT_COLS = 5
DEFAULT_ROWS = 4
DEFAULT_TOP_FRAC = 0.15  # 셀 안에서 정사각 크롭을 시작할 세로 위치(비율). 기존 원형
                          # 크롭 아바타와 픽셀이 거의 일치하도록 역산해서 찾은 값(sheet 모드용).


def crop_center_square(im: Image.Image) -> Image.Image:
    """이미지가 정사각이 아니면 중앙 기준으로 짧은 변에 맞춰 정사각 크롭."""
    w, h = im.size
    if w == h:
        return im

    side = min(w, h)
    left = (w - side) // 2
    top = (h - side) // 2
    return im.crop((left, top, left + side, top + side))


def crop_grid_cell(im: Image.Image, cellw: float, cellh: float, row: int, col: int,
                    top_frac: float) -> Image.Image:
    """격자 셀 (row, col)에서 셀 너비와 같은 변의 정사각형을 잘라낸다."""
    x0 = col * cellw
    y0 = row * cellh + top_frac * (cellh - cellw)
    return im.crop((int(round(x0)), int(round(y0)),
                     int(round(x0 + cellw)), int(round(y0 + cellw))))


def process_single(in_path: str, out_path: str, size: int, session) -> None:
    im = Image.open(in_path).convert("RGB")
    im = crop_center_square(im)
    matted = remove(im, session=session)
    matted = matted.resize((size, size), Image.LANCZOS)
    os.makedirs(os.path.dirname(out_path) or ".", exist_ok=True)
    matted.save(out_path)
    print(f"saved {out_path} ({size}x{size})")


def process_sheet(sheet_path: str, out_dir: str, out_pattern: str, cols: int, rows: int,
                   top_frac: float, size: int, session) -> None:
    sheet = Image.open(sheet_path).convert("RGB")
    w, h = sheet.size
    cellw, cellh = w / cols, h / rows

    os.makedirs(out_dir, exist_ok=True)
    count = cols * rows
    for idx in range(1, count + 1):
        row, col = (idx - 1) // cols, (idx - 1) % cols
        crop = crop_grid_cell(sheet, cellw, cellh, row, col, top_frac)
        matted = remove(crop, session=session)
        matted = matted.resize((size, size), Image.LANCZOS)
        out_path = os.path.join(out_dir, out_pattern.format(idx))
        matted.save(out_path)

    print(f"saved {count} images to {out_dir}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="mode", required=True)

    p_single = sub.add_parser("single", help="이미지 1장 처리")
    p_single.add_argument("input", help="입력 이미지 경로")
    p_single.add_argument("output", help="출력 PNG 경로")
    p_single.add_argument("--size", type=int, default=DEFAULT_SIZE, help=f"출력 정사각 크기(기본 {DEFAULT_SIZE})")

    p_sheet = sub.add_parser("sheet", help="격자 시트 1장을 여러 명으로 잘라 일괄 처리")
    p_sheet.add_argument("input", help="시트 이미지 경로")
    p_sheet.add_argument("out_dir", help="출력 폴더")
    p_sheet.add_argument("pattern", help='출력 파일명 패턴(예: "avatar_{:02d}.png")')
    p_sheet.add_argument("--cols", type=int, default=DEFAULT_COLS, help=f"격자 열 수(기본 {DEFAULT_COLS})")
    p_sheet.add_argument("--rows", type=int, default=DEFAULT_ROWS, help=f"격자 행 수(기본 {DEFAULT_ROWS})")
    p_sheet.add_argument("--top-frac", type=float, default=DEFAULT_TOP_FRAC,
                          help=f"셀 안 정사각 크롭 시작 위치 비율(기본 {DEFAULT_TOP_FRAC})")
    p_sheet.add_argument("--size", type=int, default=DEFAULT_SIZE, help=f"출력 정사각 크기(기본 {DEFAULT_SIZE})")

    args = parser.parse_args()
    session = new_session("u2net")

    if args.mode == "single":
        process_single(args.input, args.output, args.size, session)
    else:
        process_sheet(args.input, args.out_dir, args.pattern, args.cols, args.rows,
                       args.top_frac, args.size, session)


if __name__ == "__main__":
    main()
