#!/usr/bin/env bash
# =============================================================================
#  clean.sh  --  remove all build artifacts
# =============================================================================
set -euo pipefail

DIR="$(dirname "$(readlink -f "$0")")"
cd "$DIR"

echo "Cleaning PysProject build artifacts..."

for item in model3d.msh mesh results test_outputs; do
    if [ -e "$item" ]; then
        size=$(du -sh "$item" | cut -f1)
        rm -rf "$item"
        echo "  removed  $item  ($size)"
    fi
done

# also remove __pycache__
find . -type d -name __pycache__ -not -path './elmer262/*' -exec rm -rf {} + 2>/dev/null || true
find . -type f -name '*.pyc'   -not -path './elmer262/*' -delete 2>/dev/null || true

total=$(du -sh --exclude=elmer262 . | cut -f1)
echo
echo "  project size (excluding ./elmer262/):  $total"