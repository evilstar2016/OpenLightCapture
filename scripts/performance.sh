#!/bin/bash
set -euo pipefail
probe_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$probe_root"
probe_output="${1:-build/performance-$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$probe_output"
swiftc -O -swift-version 6 -parse-as-library \
    LightCapture/Localization/LocalizationContext.swift \
    LightCapture/Localization/L10n.swift \
    LightCapture/Capture/CGImageCoordinates.swift \
    LightCapture/Annotation/AnnotationDocument.swift \
    LightCapture/Annotation/AnnotationRenderer.swift \
    LightCapture/Output/FilenamePolicy.swift \
    LightCapture/Output/AssetStore.swift \
    LightCapture/Output/ClipboardPublisher.swift \
    LightCapture/Output/OutputDeliveryService.swift \
    LightCapture/Stitching/OverlapMatcher.swift \
    LightCapture/Stitching/TileStore.swift \
    LightCapture/Stitching/LongCaptureEngine.swift \
    scripts/performance-probe.swift -o "$probe_output/performance-probe"
/usr/bin/time -l "$probe_output/performance-probe" "$probe_output" "${2:-standard}" \
    > "$probe_output/core-performance.log" 2> "$probe_output/resources.log"
cat "$probe_output/core-performance.log"
