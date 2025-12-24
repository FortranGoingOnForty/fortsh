#!/bin/bash
# Batch fix MANUAL_REVIEW items across all auto-generated YAML files

cd "$(dirname "$0")/.." || exit 1

echo "====================================================="
echo "  Batch Fixing MANUAL_REVIEW Items"
echo "====================================================="
echo ""

FILES=(
    "posix_untested_auto.yaml"
    "posix_extended_auto.yaml"
    "posix_basic_auto.yaml"
    "posix_gaps_auto.yaml"
    "posix_advanced_auto.yaml"
    "posix_coverage_auto.yaml"
)

TOTAL_BEFORE=0
TOTAL_AFTER=0
TOTAL_FIXED=0

for file in "${FILES[@]}"; do
    filepath="test_specs/$file"

    if [ ! -f "$filepath" ]; then
        echo "⚠️  Skipping $file (not found)"
        continue
    fi

    echo "Processing: $file"
    echo "----------------------------------------"

    # Run the fixer with --use-shell for maximum auto-fixing
    .venv/bin/python utils/fix_manual_review.py "$filepath" --use-shell

    echo ""
done

echo "====================================================="
echo "  Batch Fix Complete!"
echo "====================================================="
echo ""
echo "Next: Run validation to measure improvement"
