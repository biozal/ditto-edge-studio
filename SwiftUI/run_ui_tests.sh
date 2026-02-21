#!/bin/bash
#
# Script to run UI tests for Edge Debug Helper
# Usage: ./run_ui_tests.sh
#
# This script:
# 1. Builds the app
# 2. Runs all UI tests
# 3. Displays a summary of results
#

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "======================================"
echo "Edge Debug Helper - UI Test Runner"
echo "======================================"
echo ""

# Change to SwiftUI directory
cd "$(dirname "$0")"

PROJECT="Edge Debug Helper.xcodeproj"
SCHEME="Edge Studio"
DESTINATION="platform=macOS,arch=arm64"

# Optional: Clean derived data for fresh build (commented out to avoid package resolution issues)
# Uncomment if you need a truly clean build
# echo "🧹 Cleaning derived data..."
# rm -rf ~/Library/Developer/Xcode/DerivedData/*Edge*Debug*Helper*

# Build the app
echo ""
echo "🔨 Building app..."
if xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Debug -destination "$DESTINATION" build > /tmp/build_output.log 2>&1; then
    echo -e "${GREEN}✅ Build succeeded${NC}"
else
    echo -e "${RED}❌ Build failed${NC}"
    echo "See /tmp/build_output.log for details"
    tail -50 /tmp/build_output.log
    exit 1
fi

# Run UI tests
echo ""
echo "🧪 Running UI tests..."
echo ""

TEST_OUTPUT="/tmp/uitest_output_$(date +%Y%m%d_%H%M%S).log"

if xcodebuild test -project "$PROJECT" -scheme "$SCHEME" -destination "$DESTINATION" 2>&1 | tee "$TEST_OUTPUT"; then
    echo ""
    echo -e "${GREEN}✅ All tests passed${NC}"
else
    echo ""
    echo -e "${YELLOW}⚠️  Some tests failed or were skipped${NC}"
fi

# Display test summary
echo ""
echo "======================================"
echo "Test Summary"
echo "======================================"

# Extract UI test results
echo ""
echo "UI Tests:"
grep -E "^Test case.*Ditto_Edge_StudioUITests\.(test.*) (passed|failed|skipped)" "$TEST_OUTPUT" | while read -r line; do
    if echo "$line" | grep -q "passed"; then
        echo -e "${GREEN}  ✓${NC} $line"
    elif echo "$line" | grep -q "failed"; then
        echo -e "${RED}  ✗${NC} $line"
    else
        echo -e "${YELLOW}  ⊘${NC} $line"
    fi
done

# Count results
PASSED=$(grep -c "Ditto_Edge_StudioUITests.*passed" "$TEST_OUTPUT" || true)
FAILED=$(grep -c "Ditto_Edge_StudioUITests.*failed" "$TEST_OUTPUT" || true)
SKIPPED=$(grep -c "Ditto_Edge_StudioUITests.*skipped" "$TEST_OUTPUT" || true)

echo ""
echo "Results: ${GREEN}${PASSED} passed${NC}, ${RED}${FAILED} failed${NC}, ${YELLOW}${SKIPPED} skipped${NC}"
echo ""
echo "Full test output saved to: $TEST_OUTPUT"

# Exit with error if any tests failed
if [ "$FAILED" -gt 0 ]; then
    echo ""
    echo -e "${RED}❌ Tests failed! Fix the failures above before committing.${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}✅ All UI tests passed successfully!${NC}"
exit 0
