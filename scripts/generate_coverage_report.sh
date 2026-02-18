#!/bin/bash

set -e

PROJECT_DIR="/Users/labeaaa/Developer/ditto-edge-studio"
cd "$PROJECT_DIR/SwiftUI"

echo "🧪 Running tests with coverage..."

# Run tests with code coverage enabled
xcodebuild test \
    -project "Edge Debug Helper.xcodeproj" \
    -scheme "Edge Studio" \
    -destination "platform=macOS,arch=arm64" \
    -enableCodeCoverage YES \
    -resultBundlePath "TestResults.xcresult" \
    -only-testing:EdgeStudioUnitTests

echo ""
echo "📊 Generating coverage report..."

# Generate JSON coverage report
xcrun xccov view --report --json TestResults.xcresult > coverage.json

# Extract coverage percentage
COVERAGE=$(python3 -c "
import json, sys
try:
    with open('coverage.json') as f:
        data = json.load(f)
        coverage = data['lineCoverage'] * 100
        print(f'{coverage:.2f}')
except Exception as e:
    print('0.00', file=sys.stderr)
    sys.exit(1)
")

echo ""
echo "================================"
echo "Coverage: $COVERAGE%"
echo "================================"
echo ""

# Check threshold
THRESHOLD=50
if (( $(echo "$COVERAGE < $THRESHOLD" | bc -l) )); then
    echo "❌ Coverage $COVERAGE% is below threshold $THRESHOLD%"
    exit 1
else
    echo "✅ Coverage $COVERAGE% meets threshold $THRESHOLD%"
fi
