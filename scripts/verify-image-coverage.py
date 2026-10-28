#!/usr/bin/env python3
"""Compare every full-width output row to explicitly positioned reference PNGs.

The manifest supplies native-pixel crop coordinates and source Y offsets. There
is no alignment search, scaling, stitching, or source image modification. An
embedded reference ICC profile is converted to sRGB before comparison; any
allowed quantization tolerance is explicit and reported, never inferred.
"""
import argparse
import hashlib
import io
import json
from pathlib import Path

from PIL import Image, ImageChops, ImageCms


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load_image(path):
    with Image.open(path) as original:
        if original.format != "PNG":
            raise ValueError(f"Not a PNG: {path}")
        profile = original.info.get("icc_profile")
        if profile:
            image = ImageCms.profileToProfile(
                original, ImageCms.ImageCmsProfile(io.BytesIO(profile)),
                ImageCms.createProfile("sRGB"), renderingIntent=0, outputMode="RGBA",
            )
        elif "srgb" in original.info:
            image = original.convert("RGBA")
        else:
            raise ValueError(f"PNG has no explicit ICC or sRGB color space: {path}")
        return image, {
            "file": str(path.resolve()), "sha256": digest(path),
            "size": list(original.size),
            "color_conversion": "embedded ICC to sRGB" if profile else "already sRGB",
            "icc_sha256": hashlib.sha256(profile).hexdigest() if profile else None,
        }


def gaps(coverage):
    result = []
    start = None
    for index, covered in enumerate(coverage + [True]):
        if not covered and start is None:
            start = index
        elif covered and start is not None:
            result.append([start, index])
            start = None
    return result


def check(manifest_path):
    manifest = json.loads(manifest_path.read_text())
    root = manifest_path.parent
    target, metadata = load_image(root / manifest["target"])
    if list(target.size) != manifest["expected_size"]:
        raise ValueError("Output dimensions do not match the declared expected_size")
    tolerance = manifest.get("channel_tolerance", 0)
    if type(tolerance) is not int or not 0 <= tolerance <= 1:
        raise ValueError("channel_tolerance must be explicitly 0 or 1")
    coverage = [False] * target.height
    checks = []
    for entry in manifest["references"]:
        reference, reference_metadata = load_image(root / entry["file"])
        x, y, width, height = entry["crop"]
        source_y = entry["source_y"]
        if any(type(value) is not int for value in (x, y, width, height, source_y)):
            raise ValueError("Coordinates must be integer native pixels")
        if min(x, y, source_y) < 0 or width != target.width or height <= 0:
            raise ValueError("Each comparison must cover the full output width")
        if x + width > reference.width or y + height > reference.height or source_y + height > target.height:
            raise ValueError("Comparison rectangle lies outside an image")
        expected = reference.crop((x, y, x + width, y + height))
        actual = target.crop((0, source_y, width, source_y + height))
        difference = ImageChops.difference(expected, actual)
        channels = difference.split()
        maximum = channels[0]
        for channel in channels[1:]:
            maximum = ImageChops.lighter(maximum, channel)
        histogram = maximum.histogram()
        unequal = sum(histogram[1:])
        beyond_tolerance = sum(histogram[tolerance + 1:])
        mask = maximum.point(lambda value: 255 if value > tolerance else 0)
        checks.append({
            **reference_metadata, "source_y": source_y, "crop": entry["crop"],
            "pixels_checked": width * height, "unequal_pixels": unequal,
            "pixels_beyond_tolerance": beyond_tolerance,
            "maximum_channel_difference": max(value for value, count in enumerate(histogram) if count),
            "difference_bbox_in_crop": mask.getbbox(), "passed": beyond_tolerance == 0,
        })
        coverage[source_y:source_y + height] = [True] * height
    uncovered = gaps(coverage)
    return {
        "scope": "Every full-width output row compared with declared independent reference crops; no alignment or resampling.",
        "provenance": manifest.get("provenance"), "target": metadata,
        "channel_tolerance": tolerance,
        "total_output_pixels": target.width * target.height,
        "covered_output_rows": sum(coverage), "uncovered_row_ranges_end_exclusive": uncovered,
        "references": checks,
        "passed": bool(checks) and not uncovered and all(item["passed"] for item in checks),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifest", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    result = check(args.manifest)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"passed": result["passed"], "covered_output_rows": result["covered_output_rows"],
                      "uncovered_rows": result["uncovered_row_ranges_end_exclusive"],
                      "failed_references": [item["file"] for item in result["references"] if not item["passed"]]}, ensure_ascii=False))
    return 0 if result["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
