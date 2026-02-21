# Test Coverage Scripts

This directory contains scripts for automated test coverage reporting and enforcement.

## Scripts

### `generate_coverage_report.sh`

Runs all unit tests with code coverage enabled and generates a coverage report.

**Usage:**
```bash
./scripts/generate_coverage_report.sh
```

**What it does:**
1. Runs all EdgeStudioUnitTests with coverage tracking
2. Generates JSON coverage report
3. Extracts overall coverage percentage
4. Checks against 50% threshold
5. Exits with error if below threshold

**Output:**
- `SwiftUI/TestResults.xcresult` - Full test results bundle
- `SwiftUI/coverage.json` - JSON coverage data
- Console output with pass/fail status

**Exit codes:**
- `0` - Tests passed and coverage ≥ 50%
- `1` - Tests failed or coverage < 50%

---

### `coverage_dashboard.sh`

Displays a detailed coverage dashboard with per-file statistics.

**Usage:**
```bash
./scripts/coverage_dashboard.sh
```

**Prerequisites:**
Must run `generate_coverage_report.sh` first to create coverage data.

**Output:**
- Overall coverage percentage
- SQLCipherService coverage details  
- Test file coverage
- Instructions to view in Xcode

---

## Current Coverage Status

**Target:** 50% minimum code coverage

**Current:** 15.96% (as of Phase 4 completion)

**Tested Components:**
- ✅ SQLCipherService: 62.19% coverage (500/804 lines)

**Next Priority for Testing:**
- DatabaseRepository
- HistoryRepository
- FavoritesRepository
- QueryService
- Other repositories and services

---

## Viewing Coverage in Xcode

1. Open `SwiftUI/TestResults.xcresult` in Xcode
2. Navigate to the **Coverage** tab
3. Browse per-file and per-function coverage
4. Click on files to see line-by-line coverage highlighting

---

## Pre-Push Hook (Optional)

A pre-push hook is available at `.git/hooks/pre-push` that runs coverage checks before every push.

**To enable:**
```bash
chmod +x .git/hooks/pre-push
```

**To disable:**
```bash
rm .git/hooks/pre-push
```

**Bypass once:**
```bash
git push --no-verify
```
