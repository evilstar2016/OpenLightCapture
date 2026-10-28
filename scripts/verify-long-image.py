#!/usr/bin/env python3
"""Check an exported PNG's dimensions and ordered ROW labels with Tesseract.

This reads the actual output. It does not create, repair, or align image pixels,
and OCR continuity alone does not establish full pixel identity or GUI provenance.
"""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import re
import struct
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("image", type=Path)
    parser.add_argument("--first-row", type=int, default=1)
    parser.add_argument("--last-row", type=int, default=80)
    parser.add_argument("--expected-width", type=int)
    parser.add_argument("--expected-height", type=int)
    parser.add_argument("--ocr-region", type=int, nargs=4, metavar=("X", "Y", "WIDTH", "HEIGHT"),
                        help="OCR an explicit label region in native pixels; requires Pillow and leaves the source unchanged")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if not 1 <= args.first_row <= args.last_row <= 999:
        parser.error("row range must be within 1..999")

    with args.image.open("rb") as image:
        header = image.read(24)
        if len(header) != 24 or header[:8] != b"\x89PNG\r\n\x1a\n" or header[12:16] != b"IHDR":
            parser.error("input must be an exported PNG")
        width, height = struct.unpack(">II", header[16:24])
        image.seek(0)
        digest = hashlib.sha256()
        for chunk in iter(lambda: image.read(1024 * 1024), b""):
            digest.update(chunk)

    with tempfile.TemporaryDirectory(prefix="cut-paste-image-ocr-") as folder:
        ocr_image = args.image
        if args.ocr_region:
            x, y, region_width, region_height = args.ocr_region
            if min(x, y) < 0 or min(region_width, region_height) < 1 or x + region_width > width or y + region_height > height:
                parser.error("OCR region must be a non-empty rectangle within the original PNG")
            try:
                from PIL import Image
            except ImportError:
                parser.error("--ocr-region requires Pillow in the selected Python environment")
            ocr_image = Path(folder) / "labels.png"
            with Image.open(args.image) as original:
                original.crop((x, y, x + region_width, y + region_height)).save(ocr_image)
        ocr = subprocess.run(
            ["tesseract", str(ocr_image), "stdout", "--psm", "6", "-l", "eng"],
            capture_output=True, text=True, check=True, timeout=120,
        )
    rows = [int(value) for value in re.findall(r"^\s*ROW\s+(\d{1,3})\b", ocr.stdout, re.MULTILINE)]
    expected = list(range(args.first_row, args.last_row + 1))
    counts = Counter(rows)
    geometry_matches = (
        (args.expected_width is None or args.expected_width == width)
        and (args.expected_height is None or args.expected_height == height)
    )
    result = {
        "scope": "PNG metadata and strict OCR row order only; not full pixel identity or end-to-end acceptance.",
        "source_image": str(args.image.resolve()),
        "sha256": digest.hexdigest(),
        "width": width,
        "height": height,
        "expected_width": args.expected_width,
        "expected_height": args.expected_height,
        "ocr_region": args.ocr_region,
        "geometry_matches": geometry_matches,
        "expected_rows": expected,
        "recognized_rows": rows,
        "missing_rows": sorted(set(expected) - set(rows)),
        "duplicate_rows": sorted(value for value, count in counts.items() if count > 1),
        "unexpected_rows": sorted(set(rows) - set(expected)),
        "row_order_matches": rows == expected,
        "passed": geometry_matches and rows == expected,
    }
    args.output.mkdir(parents=True, exist_ok=True)
    (args.output / "ocr.txt").write_text(ocr.stdout)
    (args.output / "ocr-stderr.txt").write_text(ocr.stderr)
    serialized = json.dumps(result, ensure_ascii=False, indent=2) + "\n"
    (args.output / "check.json").write_text(serialized)
    print(serialized)
    return 0 if result["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
