import argparse
import importlib.util
import io
from pathlib import Path
import plistlib
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("runner", Path(__file__).parents[1] / "run_ui_tests.py")
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)


class UITestRunnerTests(unittest.TestCase):
    def report(self, **updates):
        return dict(result="Passed", passedTests=3, failedTests=0, skippedTests=0, expectedFailures=0) | updates

    def test_empty_or_skipped_mobile_runs_are_not_green(self):
        for report in (self.report(passedTests=0), self.report(skippedTests=1),
                       self.report(failedTests=1), self.report(result="Failed"), {}, self.report(expectedFailures=1)):
            self.assertFalse(runner.summary_passes(report))
        self.assertTrue(runner.summary_passes(self.report()))

    def test_legacy_skip_policy_still_requires_a_passing_test(self):
        self.assertTrue(runner.summary_passes(self.report(skippedTests=1), allow_skips=True))
        self.assertFalse(runner.summary_passes(self.report(passedTests=0, skippedTests=3), allow_skips=True))

    def test_build_failure_cannot_be_hidden_by_result_parsing(self):
        arguments = argparse.Namespace(plan="smoke", configuration=None, diagnostics="never")
        with tempfile.TemporaryDirectory() as directory, patch.object(runner.subprocess, "Popen") as spawn, \
                patch.object(runner.subprocess, "run") as parse, patch("sys.stdout", new_callable=io.StringIO):
            spawn.return_value.stdout = iter(["Build failed\n"])
            spawn.return_value.wait.return_value = 65
            self.assertEqual(runner.run_destination(arguments, "platform=iOS Simulator,id=test", Path(directory), {}), 65)
            parse.assert_not_called()

    def test_cloud_only_fixture_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "fixture.plist"
            path.write_bytes(plistlib.dumps({"databases": [{"mode": "development", "token": "fake"}]}))
            with self.assertRaises(ValueError):
                runner.workspace_fixture(path)

    def test_offline_fixture_forwards_only_required_fields(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "fixture.plist"
            path.write_bytes(plistlib.dumps({"databases": [{"mode": "smallPeerOnly", "databaseId": "test",
                                                          "token": "fake-license", "url": "https://unused.example",
                                                          "httpApiKey": "must-not-forward"}]}))
            payload = plistlib.loads(runner.base64.b64decode(runner.workspace_fixture(path)))
            self.assertEqual(payload, {"databaseId": "test", "developmentToken": "fake-license", "secretKey": ""})


if __name__ == "__main__":
    unittest.main()
