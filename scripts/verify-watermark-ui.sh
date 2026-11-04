#!/bin/bash
set -euo pipefail
watermark_probe_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$watermark_probe_root"
watermark_probe_output="${1:-build/watermark-ui-probe}"
mkdir -p "$watermark_probe_output"
swiftc -swift-version 6 -parse-as-library \
    LightCapture/Localization/LocalizationContext.swift \
    LightCapture/Localization/LocalizationConfiguration.swift \
    LightCapture/Localization/LocalizationStore.swift \
    LightCapture/Localization/L10n.swift \
    LightCapture/Localization/WatermarkL10n.swift \
    LightCapture/Watermark/WatermarkTemplate.swift \
    LightCapture/Watermark/WatermarkTemplateStore.swift \
    LightCapture/Watermark/WatermarkRenderer.swift \
    LightCapture/Watermark/WatermarkViews.swift \
    scripts/watermark-ui-probe.swift -o "$watermark_probe_output/watermark-ui-probe"
"$watermark_probe_output/watermark-ui-probe" > "$watermark_probe_output/result.json"
cat "$watermark_probe_output/result.json"
