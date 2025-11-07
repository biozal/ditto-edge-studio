# Makefile for Edge Debug Helper / Edge Studio
# Simplifies common development tasks

.PHONY: help test test-unit test-ui test-swiftui build-swiftui clean clean-swiftui

# Detect platform and architecture
UNAME_S := $(shell uname -s)
UNAME_M := $(shell uname -m)

# Set platform and architecture for xcodebuild
ifeq ($(UNAME_S),Darwin)
	PLATFORM := macOS
	ifeq ($(UNAME_M),arm64)
		ARCH := arm64
	else
		ARCH := x86_64
	endif
	DESTINATION := "platform=$(PLATFORM),arch=$(ARCH)"
else
	$(error This Makefile is designed for macOS. Detected platform: $(UNAME_S))
endif

# Default target
help:
	@echo "Edge Debug Helper / Edge Studio - Available Commands"
	@echo ""
	@echo "Platform: $(PLATFORM) ($(ARCH))"
	@echo ""
	@echo "Testing:"
	@echo "  make test              - Run unit tests"
	@echo "  make test-unit         - Run unit tests only"
	@echo "  make test-ui           - Run UI tests (requires proper code signing)"
	@echo "  make test-swiftui      - Run all SwiftUI tests (unit + UI)"
	@echo "  make test-syntax       - Validate Swift syntax without running tests"
	@echo ""
	@echo "Building:"
	@echo "  make build-swiftui     - Build SwiftUI app (Debug)"
	@echo ""
	@echo "Cleaning:"
	@echo "  make clean             - Clean all build artifacts"
	@echo "  make clean-swiftui     - Clean SwiftUI build artifacts"
	@echo ""

# Test targets
test: test-unit

test-unit:
	@echo "Running unit tests on $(PLATFORM) ($(ARCH))..."
	xcodebuild -project "SwiftUI/Edge Debug Helper.xcodeproj" \
		-scheme "Edge Studio" \
		-destination $(DESTINATION) \
		-only-testing:"Edge Debug HelperTests" \
		CODE_SIGN_IDENTITY="-" \
		CODE_SIGNING_REQUIRED=NO \
		CODE_SIGNING_ALLOWED=NO \
		TEST_HOST="" \
		BUNDLE_LOADER="" \
		test

test-ui:
	@echo "Running UI tests on $(PLATFORM) ($(ARCH))..."
	xcodebuild -project "SwiftUI/Edge Debug Helper.xcodeproj" \
		-scheme "Edge Studio" \
		-destination $(DESTINATION) \
		-only-testing:"Edge Debug HelperUITests" \
		CODE_SIGN_IDENTITY="-" \
		CODE_SIGNING_REQUIRED=NO \
		CODE_SIGNING_ALLOWED=NO \
		test

test-swiftui: test-unit test-ui
	@echo "All SwiftUI tests completed"

test-syntax:
	@echo "Validating Swift syntax..."
	@find "SwiftUI/Edge Debug Helper Tests" -name "*.swift" -exec echo "Checking {}" \; -exec xcrun swiftc -parse {} \;
	@echo "All Swift test files have valid syntax"

# Build targets
build-swiftui:
	@echo "Building SwiftUI app (Debug) for $(PLATFORM) ($(ARCH))..."
	xcodebuild -project "SwiftUI/Edge Debug Helper.xcodeproj" \
		-scheme "Edge Studio" \
		-configuration Debug \
		-destination $(DESTINATION) \
		build

# Clean targets
clean: clean-swiftui

clean-swiftui:
	@echo "Cleaning SwiftUI build artifacts..."
	xcodebuild -project "SwiftUI/Edge Debug Helper.xcodeproj" \
		-scheme "Edge Studio" \
		clean
	rm -rf ~/Library/Developer/Xcode/DerivedData/Edge_Debug_Helper-*
