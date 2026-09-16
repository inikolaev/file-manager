#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift scripts/generate-icon.swift Assets
iconutil -c icns Assets/Commander.iconset -o Assets/Commander.icns
