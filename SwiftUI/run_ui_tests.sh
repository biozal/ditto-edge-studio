#!/bin/bash
# Run from any directory. See --help for plans and explicit destinations.
set -euo pipefail
exec python3 "$(dirname "$0")/../scripts/run_ui_tests.py" "$@"
