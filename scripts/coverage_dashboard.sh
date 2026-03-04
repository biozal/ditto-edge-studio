#!/bin/bash

set -e

PROJECT_DIR="/Users/labeaaa/Developer/ditto-edge-studio"
cd "$PROJECT_DIR/SwiftUI"

# Check if coverage results exist
if [ ! -d "TestResults.xcresult" ]; then
    echo "❌ No coverage results found. Run generate_coverage_report.sh first."
    exit 1
fi

echo "📊 Coverage Dashboard"
echo "===================="
echo ""

# Generate text coverage report
xcrun xccov view --report TestResults.xcresult > coverage.txt

# Overall coverage
echo "Overall Coverage:"
echo "-----------------"
OVERALL_PCT=$(python3 -c "
import json
with open('coverage.json') as f:
    data = json.load(f)
    coverage = data['lineCoverage'] * 100
    print(f'{coverage:.2f}%')
")
echo "$OVERALL_PCT"
echo ""

# Per-file coverage
echo "SQLCipherService Coverage:"
echo "--------------------------"
grep -i "sqlcipher" coverage.txt | head -5 || echo "No SQLCipherService data found"
echo ""

echo "Test Files Coverage:"
echo "--------------------"
grep "Tests\.swift" coverage.txt | head -10 || echo "No test file data found"
echo ""
echo ""
echo "To view detailed coverage in Xcode:"
echo "1. Open TestResults.xcresult in Xcode"
echo "2. Navigate to Coverage tab"
