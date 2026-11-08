#!/usr/bin/env python3
"""Verify deployment settings and the actual minimum OS of both app slices."""

import argparse
import plistlib
import re
import subprocess
from pathlib import Path


def version(value):
    parts = tuple(int(part) for part in value.split("."))
    return parts + (0,) * (3 - len(parts))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--app", type=Path, required=True)
    parser.add_argument("--minimum", default="13.0")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    expected = version(args.minimum)

    def check(label, value):
        assert version(value) == expected, f"{label}: expected {args.minimum}, found {value}"

    settings = dict(re.findall(
        r'^\s*(macOS|MACOSX_DEPLOYMENT_TARGET):\s*"?([\d.]+)"?\s*$',
        (root / "project.yml").read_text(), re.MULTILINE,
    ))
    assert set(settings) == {"macOS", "MACOSX_DEPLOYMENT_TARGET"}, settings
    for key, value in settings.items():
        check(f"project.yml/{key}", value)
    source_info = plistlib.loads((root / "LightCapture/Resources/Info.plist").read_bytes())
    check("source Info.plist", source_info["LSMinimumSystemVersion"])
    info = plistlib.loads((args.app / "Contents/Info.plist").read_bytes())
    check("built Info.plist", info["LSMinimumSystemVersion"])

    binary = args.app / "Contents/MacOS" / info["CFBundleExecutable"]
    architectures = subprocess.check_output(["lipo", "-archs", str(binary)], text=True).split()
    assert set(architectures) == {"arm64", "x86_64"}, architectures
    for architecture in architectures:
        output = subprocess.check_output(
            ["xcrun", "vtool", "-arch", architecture, "-show-build", str(binary)], text=True,
        )
        minimum = re.search(r"^\s*minos\s+([\d.]+)\s*$", output, re.MULTILINE)
        assert minimum, f"No Mach-O minimum OS for {architecture}"
        check(f"Mach-O/{architecture}", minimum[1])

    print(f"Platform checks passed: macOS {args.minimum}+, arm64 and x86_64; source, Info.plist and Mach-O agree")


if __name__ == "__main__":
    main()
