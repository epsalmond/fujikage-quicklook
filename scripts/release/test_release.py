"""Release validation regressions; no keychain, network, or signing mutation."""

import copy
import tempfile
import unittest
from pathlib import Path

import release


class ReleaseValidationTests(unittest.TestCase):
    def setUp(self):
        self.info = {"CFBundleIdentifier": release.BUNDLE_ID,
                     "CFBundleShortVersionString": "1.0", "CFBundleVersion": "2"}
        self.signed = {"team": release.DEFAULT_TEAM,
                       "authorities": [f"Developer ID Application: Owner ({release.DEFAULT_TEAM})"],
                       "runtime": True,
                       "entitlements": {key: True for key in {release.SANDBOX} | release.HOST_PERMISSIONS}}

    def check(self, info=None, signed=None, channel="direct", archs=None, host=True, expected_id=None):
        release.validate_bundle(info or self.info, archs or ["arm64", "x86_64"], signed or self.signed,
                                expected_id=expected_id or release.BUNDLE_ID, expected_version=("1.0", "2"),
                                team=release.DEFAULT_TEAM, channel=channel, host=host)

    def test_valid_host(self):
        self.check()

    def test_missing_extension_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            app = Path(temp) / "FujikageQL.app"
            app.mkdir()
            with self.assertRaisesRegex(release.ReleaseError, "Missing required bundle: FujikageQLPreview"):
                release.bundle_paths(app)

    def test_extension_build_mismatch_rejected(self):
        info = dict(self.info, CFBundleVersion="3")
        with self.assertRaisesRegex(release.ReleaseError, "Version/build mismatch"):
            self.check(info=info)

    def test_development_signature_rejected_for_both_export_channels(self):
        signed = dict(self.signed, authorities=[f"Apple Development: Owner ({release.DEFAULT_TEAM})"])
        for channel in ("direct", "store"):
            with self.subTest(channel=channel), self.assertRaisesRegex(release.ReleaseError, "Wrong distribution signature"):
                self.check(signed=signed, channel=channel)
        self.check(signed=signed, channel="archive")

    def test_task_allow_rejected_even_in_archive(self):
        for key in ("get-task-allow", "com.apple.security.get-task-allow"):
            signed = copy.deepcopy(self.signed)
            signed["entitlements"][key] = True
            with self.subTest(key=key), self.assertRaisesRegex(release.ReleaseError, "get-task-allow"):
                self.check(signed=signed, channel="archive")

    def test_single_architecture_rejected(self):
        with self.assertRaisesRegex(release.ReleaseError, "Expected universal"):
            self.check(archs=["arm64"])

    def test_wrong_team_rejected(self):
        with self.assertRaisesRegex(release.ReleaseError, "Signing team mismatch"):
            self.check(signed=dict(self.signed, team="OTHERTEAM"))

    def test_extensions_must_not_receive_host_file_permissions(self):
        info = dict(self.info, CFBundleIdentifier=release.BUNDLE_ID + ".preview")
        with self.assertRaisesRegex(release.ReleaseError, "Unexpected entitlements"):
            self.check(info=info, expected_id=info["CFBundleIdentifier"], host=False)
        signed = copy.deepcopy(self.signed)
        signed["entitlements"] = {release.SANDBOX: True}
        self.check(info=info, signed=signed, expected_id=info["CFBundleIdentifier"], host=False)

    def test_runtime_required_for_release_export(self):
        with self.assertRaisesRegex(release.ReleaseError, "Hardened runtime missing"):
            self.check(signed=dict(self.signed, runtime=False))

    def test_export_options_are_local_and_preserve_version(self):
        profiles = {entry[1]: "profile-" + name for name, entry in release.TARGETS.items()}
        for channel in ("direct", "store"):
            options = release.export_options(channel, release.DEFAULT_TEAM, profiles)
            self.assertEqual(options["destination"], "export")
            self.assertIs(options["manageAppVersionAndBuildNumber"], False)
            self.assertEqual(options["signingStyle"], "manual")
        self.assertEqual(release.export_options("direct", release.DEFAULT_TEAM, {})["method"], "developer-id")
        self.assertEqual(release.export_options("store", release.DEFAULT_TEAM, profiles)["method"], "app-store-connect")

    def test_store_requires_all_three_profile_inputs(self):
        with self.assertRaisesRegex(release.ReleaseError, "host and both extensions"):
            release.export_options("store", release.DEFAULT_TEAM, {release.BUNDLE_ID: "only-host"})

    def test_duplicate_profile_input_rejected(self):
        with self.assertRaisesRegex(release.ReleaseError, "once"):
            release.profile_args(["id=one", "id=two"])


if __name__ == "__main__":
    unittest.main()
