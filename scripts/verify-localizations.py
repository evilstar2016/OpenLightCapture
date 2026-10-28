#!/usr/bin/env python3
"""Check source translations and, optionally, the compiled macOS app resources."""

import argparse
import json
import plistlib
import re
import subprocess
from pathlib import Path


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--app", type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    resources = root / "LightCapture/Resources"
    config = json.loads((resources / "LocalizationConfig.json").read_text())
    languages = [item["identifier"] for item in config["languages"]]
    assert len(languages) == len(set(languages)), "Duplicate language identifiers"
    assert config["fallbackLanguage"] in languages
    assert config["defaultSelection"] in ["system", *languages]
    catalog = json.loads((resources / "Localizable.xcstrings").read_text())
    assert catalog["sourceLanguage"] == config["fallbackLanguage"]
    specifiers = re.compile(r"%(?:(\d+)\$)?(lld|ld|d|@)|%#@(\w+)@")

    def signature(localization):
        result = []
        for position, kind, substitution in specifiers.findall(localization["stringUnit"]["value"]):
            if substitution:
                data = localization["substitutions"][substitution]
                result.append((str(data["argNum"]), data["formatSpecifier"]))
                forms = data["variations"]["plural"]
                assert "other" in forms
                for form in forms.values():
                    assert form["stringUnit"]["state"] == "translated"
                    assert form["stringUnit"]["value"]
            else:
                result.append((position, kind))
        return sorted(result)

    for key, entry in catalog["strings"].items():
        translated = entry["localizations"]
        assert set(translated) == set(languages), f"Incomplete language set: {key}"
        expected = signature(translated[config["fallbackLanguage"]])
        for language in languages:
            unit = translated[language]["stringUnit"]
            assert unit["state"] == "translated" and unit["value"], (key, language)
            assert signature(translated[language]) == expected, f"Parameter mismatch: {key}/{language}"

    keys = set()
    for path in (root / "LightCapture").rglob("*.swift"):
        keys.update(re.findall(r'\.\s*(?:string|format)\("([^"\n]+)"', path.read_text()))
    assert keys == set(catalog["strings"]), f"Code/catalog mismatch: {keys ^ set(catalog['strings'])}"
    info_catalog = json.loads((resources / "InfoPlist.xcstrings").read_text())
    display_names = info_catalog["strings"]["CFBundleDisplayName"]["localizations"]
    assert set(display_names) == set(languages)
    assert all(item["stringUnit"]["value"] == "OpenLightCapture" for item in display_names.values())

    if args.app:
        compiled = args.app / "Contents/Resources"
        info = plistlib.loads((args.app / "Contents/Info.plist").read_bytes())
        assert info["CFBundleDevelopmentRegion"] == config["fallbackLanguage"]
        assert info["CFBundleIdentifier"] == "io.github.evilstar2016.openlightcapture"
        assert info["CFBundleExecutable"] == "OpenLightCapture"
        assert info["CFBundleName"] == "OpenLightCapture"
        assert args.app.name == "OpenLightCapture.app"
        assert json.loads((compiled / "LocalizationConfig.json").read_text()) == config
        for language in languages:
            folder = compiled / f"{language}.lproj"
            assert (folder / "Localizable.strings").is_file(), f"Missing {language} strings"
            assert (folder / "Localizable.stringsdict").is_file(), f"Missing {language} plurals"
            info_strings = folder / "InfoPlist.strings"
            assert info_strings.is_file(), f"Missing {language} display name"
            display_name = json.loads(subprocess.check_output([
                "plutil", "-convert", "json", "-o", "-", str(info_strings)
            ]))
            assert display_name["CFBundleDisplayName"] == "OpenLightCapture"
        assert not (compiled / "zh-Hant.lproj").exists(), "Traditional Chinese is outside this release"

    print(f"Localization checks passed: {len(catalog['strings'])} keys, {', '.join(languages)}")


if __name__ == "__main__":
    main()
