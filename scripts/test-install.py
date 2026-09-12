#!/usr/bin/env python3
"""Exercise installer failures in temporary directories, without quitting apps.

System copy/move utilities operate only on test fixtures. Code signing and app
termination are substituted so failure branches can be tested deterministically.
"""
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import unittest

SCRIPTS = Path(__file__).resolve().parent
APP = "Joy-Con Vibe Remote.app"
LEGACY = "JoyCon Vibe Remote.app"
IDENTIFIER = "com.aqxp.JoyConVibeRemote"

MOCK_TOOL = '''#!/usr/bin/env python3
import os, pathlib, subprocess, sys
name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
if name == "quit-app":
    sys.exit(1 if os.environ.get("TEST_QUIT_FAIL") else 0)
if name == "codesign":
    target = pathlib.Path(args[-1])
    if os.environ.get("TEST_FINAL_VERIFY_FAIL") and target.parent.resolve() == pathlib.Path(os.environ["TEST_ROOT"]).resolve():
        sys.exit(1)
    sys.exit(0)
if name == "ditto" and os.environ.get("TEST_COPY_FAIL"):
    sys.exit(1)
if name == "mv" and os.environ.get("TEST_SWAP_FAIL"):
    source = pathlib.Path(args[0])
    if source.name.endswith(".app") and source.parent.name.startswith(".joycon-vibe-remote-install."):
        sys.exit(1)
real = {"mv": "/bin/mv", "ditto": "/usr/bin/ditto"}[name]
sys.exit(subprocess.run([real, *args]).returncode)
'''


@unittest.skipUnless(sys.platform == "darwin", "macOS installer")
class InstallerTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="joycon-installer-test-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.destination = self.root / "Applications with spaces"
        self.destination.mkdir()
        self.source = self.root / "build" / APP
        self.make_bundle(self.source, "new")
        self.tools = self.root / "tools"
        self.tools.mkdir()
        for name in ["quit-app", "codesign", "ditto", "mv"]:
            tool = self.tools / name
            tool.write_text(MOCK_TOOL)
            tool.chmod(0o755)
        self.environment = dict(os.environ, PATH=f"{self.tools}:{os.environ['PATH']}",
                                TEST_ROOT=str(self.destination))
        self.developer = self.root / "Custom Xcode.app/Contents/Developer"
        xcodebuild = self.developer / "usr/bin/xcodebuild"
        xcodebuild.parent.mkdir(parents=True)
        xcodebuild.write_text("#!/bin/sh\nexit 0\n")
        xcodebuild.chmod(0o755)
        self.environment["DEVELOPER_DIR"] = str(self.developer)

    def make_bundle(self, path, marker, identifier=IDENTIFIER):
        (path / "Contents").mkdir(parents=True)
        (path / "Contents" / "Info.plist").write_bytes(
            plistlib.dumps({"CFBundleIdentifier": identifier}))
        (path / "version.txt").write_text(marker)

    def install(self, **faults):
        return subprocess.run(
            ["/bin/zsh", str(SCRIPTS / "install-app.sh"), str(self.source),
             str(self.destination), str(self.tools / "quit-app")],
            env=dict(self.environment, **faults), text=True, capture_output=True)

    def assert_originals(self):
        self.assertEqual((self.destination / APP / "version.txt").read_text(), "current")
        self.assertEqual((self.destination / LEGACY / "version.txt").read_text(), "legacy")

    def existing_apps(self):
        self.make_bundle(self.destination / APP, "current")
        self.make_bundle(self.destination / LEGACY, "legacy")

    def test_first_install_in_user_directory_with_spaces(self):
        result = self.install()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.destination / APP / "version.txt").read_text(), "new")
        self.assertEqual(list(self.destination.glob(".joycon-*")), [])

    def test_upgrade_preserves_both_previous_versions(self):
        self.existing_apps()
        result = self.install()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((self.destination / LEGACY).exists())
        backups = list(self.destination.glob(".joycon-vibe-remote-install.*"))
        self.assertEqual(len(backups), 1)
        self.assertEqual((backups[0] / "previous-current/version.txt").read_text(), "current")
        self.assertEqual((backups[0] / "previous-legacy/version.txt").read_text(), "legacy")

    def test_copy_failure_leaves_previous_apps_untouched(self):
        self.existing_apps()
        self.assertNotEqual(self.install(TEST_COPY_FAIL="1").returncode, 0)
        self.assert_originals()

    def test_quit_refusal_leaves_previous_apps_untouched(self):
        self.existing_apps()
        self.assertNotEqual(self.install(TEST_QUIT_FAIL="1").returncode, 0)
        self.assert_originals()

    def test_failed_swap_restores_both_versions(self):
        self.existing_apps()
        self.assertNotEqual(self.install(TEST_SWAP_FAIL="1").returncode, 0)
        self.assert_originals()

    def test_final_verification_failure_restores_both_versions(self):
        self.existing_apps()
        self.assertNotEqual(self.install(TEST_FINAL_VERIFY_FAIL="1").returncode, 0)
        self.assert_originals()

    def test_final_failure_on_first_install_leaves_no_broken_app(self):
        self.assertNotEqual(self.install(TEST_FINAL_VERIFY_FAIL="1").returncode, 0)
        self.assertFalse((self.destination / APP).exists())

    def test_unrelated_app_is_not_replaced(self):
        self.make_bundle(self.destination / APP, "unrelated", "org.example.other")
        self.assertNotEqual(self.install().returncode, 0)
        self.assertEqual((self.destination / APP / "version.txt").read_text(), "unrelated")

    def test_symlink_is_not_followed_or_removed(self):
        (self.destination / APP).symlink_to(self.source, target_is_directory=True)
        self.assertNotEqual(self.install().returncode, 0)
        self.assertTrue((self.destination / APP).is_symlink())
        self.assertEqual((self.source / "version.txt").read_text(), "new")

    def test_old_toolchain_fails_before_building(self):
        xcrun = self.tools / "xcrun"
        xcrun.write_text('#!/bin/sh\nif [ "$1 $2" = "swift --version" ]; then\n'
                         'echo "Apple Swift version 5.10"\nelse\nexit 99\nfi\n')
        xcrun.chmod(0o755)
        result = subprocess.run(["/bin/zsh", str(SCRIPTS / "build-app.sh")],
                                env=self.environment, text=True, capture_output=True)
        self.assertEqual(result.returncode, 1)
        self.assertIn("Swift 6+ is required", result.stderr)

    def test_missing_explicit_xcode_reports_actionable_error(self):
        result = subprocess.run(["/bin/zsh", str(SCRIPTS / "build-app.sh")],
                                env=dict(self.environment, DEVELOPER_DIR=str(self.root / "missing")),
                                text=True, capture_output=True)
        self.assertEqual(result.returncode, 1)
        self.assertIn("Full Xcode 16+ is required", result.stderr)

    def test_custom_xcode_selection_is_preserved(self):
        xcrun = self.tools / "xcrun"
        xcrun.write_text('#!/bin/sh\nif [ "$1 $2" = "swift --version" ]; then\n'
                         'echo "Apple Swift version 6.0"\nelse\n'
                         'echo "selected=$DEVELOPER_DIR" >&2\nexit 97\nfi\n')
        xcrun.chmod(0o755)
        result = subprocess.run(["/bin/zsh", str(SCRIPTS / "build-app.sh")],
                                env=self.environment, text=True, capture_output=True)
        self.assertEqual(result.returncode, 97)
        self.assertIn(f"selected={self.developer}", result.stderr)


if __name__ == "__main__":
    unittest.main(verbosity=2)
