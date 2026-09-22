#!/usr/bin/env python3
"""Run UI plans; fail on build failures, empty runs, and unexpected mobile skips."""
import argparse
import base64
import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile

PLANS = {"macos": "Edge Studio", "smoke": "Edge Studio Mobile Smoke",
         "regression": "Edge Studio Mobile Regression", "accessibility": "Edge Studio Mobile Accessibility"}


def workspace_fixture(path):
    """Forward one offline identity, never cloud URLs or HTTP API credentials."""
    with open(path, "rb") as stream:
        source = plistlib.load(stream)
    candidates = [item for item in source.get("databases", []) if str(item.get("mode", "")).lower()
                  in {"smallpeeronly", "smallpeersonly", "sharedkey", "offlineplayground", "offline"}]
    if len(candidates) != 1:
        raise ValueError("Fixture must contain exactly one offline database")
    item = candidates[0]
    payload = {"databaseId": item.get("databaseId") or item.get("appId"),
               "developmentToken": item.get("developmentToken") or item.get("token") or item.get("authToken"),
               "secretKey": item.get("secretKey", "")}
    if not all(isinstance(payload[key], str) and payload[key].strip() for key in ("databaseId", "developmentToken")):
        raise ValueError("Offline database ID and license are required")
    return base64.b64encode(plistlib.dumps(payload)).decode("ascii")


def summary_passes(summary, allow_skips=False):
    counts = [summary.get(key) for key in ("passedTests", "failedTests", "skippedTests", "expectedFailures")]
    if any(type(value) is not int or value < 0 for value in counts):
        return False
    passed, failed, skipped, expected = counts
    return (summary.get("result") == "Passed" and passed > 0 and failed == 0 and expected == 0
            and (allow_skips or skipped == 0))


def run_destination(arguments, destination, output, environment):
    project = Path(__file__).resolve().parents[1] / "SwiftUI/Edge Debug Helper.xcodeproj"
    result = output / "results.xcresult"
    command = ["xcodebuild", "test", "-project", str(project), "-scheme", "Edge Studio",
               "-testPlan", PLANS[arguments.plan], "-destination", destination,
               "-only-testing:EdgeStudioUITests", "-parallel-testing-enabled", "NO",
               "-resultBundlePath", str(result), "-collect-test-diagnostics", arguments.diagnostics]
    if arguments.configuration:
        command.extend(["-only-test-configuration", arguments.configuration])
    print(f"Running {PLANS[arguments.plan]} on {destination}\nArtifacts: {output}", flush=True)
    # No shell/tee pipeline: preserve xcodebuild's actual exit status.
    with (output / "xcodebuild.log").open("w") as log:
        process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                   text=True, env=environment)
        for line in process.stdout:
            log.write(line)
            log.flush()
            sys.stdout.write(line)
            sys.stdout.flush()
        status = process.wait()
    if status:
        print(f"xcodebuild failed (exit {status}); see {output / 'xcodebuild.log'}", file=sys.stderr)
        return status
    report = subprocess.run(["xcrun", "xcresulttool", "get", "test-results", "summary", "--path", str(result)],
                            capture_output=True, text=True, check=True)
    (output / "summary.json").write_text(report.stdout)
    summary = json.loads(report.stdout)
    print("Results: " + ", ".join(f"{key}={summary.get(key, 'missing')}" for key in
                                  ("passedTests", "failedTests", "skippedTests", "expectedFailures")))
    if not summary_passes(summary, allow_skips=arguments.plan == "macos"):
        print("UI gate failed: required tests must execute and pass without unexpected skips.", file=sys.stderr)
        return 1
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--plan", choices=PLANS, default="macos")
    parser.add_argument("--destination", action="append", help="Repeat for a device matrix; prefer platform=iOS Simulator,id=UUID")
    parser.add_argument("--fixture", type=Path, help="Untracked testDatabaseConfig.plist with one offline database; required for regression")
    parser.add_argument("--configuration", help="Only this named test-plan configuration")
    parser.add_argument("--diagnostics", choices=["on-failure", "never"], default="on-failure",
                        help="Verbose simulator diagnostics; 'never' keeps test screenshots/results but avoids sysdiagnose collection")
    parser.add_argument("--output-dir", type=Path, help="Artifact parent directory; each invocation creates a unique child")
    arguments = parser.parse_args()
    if arguments.plan != "macos" and not arguments.destination:
        parser.error("Mobile plans require --destination 'platform=iOS Simulator,id=<UUID>'")
    destinations = arguments.destination or ["platform=macOS,arch=arm64"]
    if arguments.plan != "macos" and any("platform=iOS" not in value for value in destinations):
        parser.error("Mobile plans require iOS device/simulator destinations")
    environment = os.environ.copy()
    if arguments.plan == "regression":
        if not arguments.fixture:
            parser.error("Regression requires --fixture; smoke and accessibility require no credentials")
        # Xcode forwards TEST_RUNNER_ variables to the test runner without that prefix.
        environment["TEST_RUNNER_EDGE_UI_TEST_FIXTURE_BASE64"] = workspace_fixture(arguments.fixture)
    if arguments.output_dir:
        arguments.output_dir.mkdir(parents=True, exist_ok=True)
    root = Path(tempfile.mkdtemp(prefix=f"edge-ui-{arguments.plan}-", dir=arguments.output_dir))
    statuses = []
    for index, destination in enumerate(destinations, start=1):
        output = root / str(index)
        output.mkdir()
        statuses.append(run_destination(arguments, destination, output, environment))
    return next((status for status in statuses if status), 0)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, subprocess.CalledProcessError):
        # Exceptions may contain credential-bearing payloads; don't echo them.
        print("Cannot load fixture, run Xcode, or read results. Check artifact logs and --help.", file=sys.stderr)
        sys.exit(1)
