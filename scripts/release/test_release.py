"""Release validation regressions; no keychain, network, or signing mutation."""

import copy
import datetime
import plistlib
import tempfile
import unittest
from unittest.mock import patch
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

    def test_native_store_can_export_current_unrestricted_entitlements_without_profiles(self):
        options = release.export_options("store", release.DEFAULT_TEAM, {})
        self.assertNotIn("provisioningProfiles", options)
        with tempfile.TemporaryDirectory() as temp, patch.object(release, "validate_profile") as validate:
            release.validate_optional_profile(Path(temp) / "missing.provisionprofile", release.BUNDLE_ID,
                                              release.DEFAULT_TEAM, self.signed["entitlements"], "store")
            validate.assert_not_called()

    def test_store_preflight_resolves_legacy_installer_certificate_to_sha1(self):
        digest = "1234567890ABCDEF1234567890ABCDEF12345678"
        for name in ("3rd Party Mac Developer Installer", "Mac Installer Distribution"):
            output = f'  1) {digest} "{name}: Owner ({release.DEFAULT_TEAM})"\n'
            with self.subTest(name=name), patch.object(release, "require_identity"), patch.object(release, "run", return_value=output.encode()):
                options = release.preflight("store", release.DEFAULT_TEAM, {})
                self.assertEqual(options["installerSigningCertificate"], digest)

    def test_installer_selector_rejects_wrong_team_and_noninstaller_identities(self):
        digest = "1234567890ABCDEF1234567890ABCDEF12345678"
        for name, team in (("3rd Party Mac Developer Installer", "OTHERTEAM"),
                           ("Apple Distribution", release.DEFAULT_TEAM)):
            output = f'  1) {digest} "{name}: Owner ({team})"\n'
            with self.subTest(name=name, team=team), self.assertRaisesRegex(release.ReleaseError, "Missing Mac Installer"):
                release.installer_identity(output, release.DEFAULT_TEAM)

    def test_installer_selector_requires_valid_sha1_identity_line(self):
        output = f'  1) INVALID "3rd Party Mac Developer Installer: Owner ({release.DEFAULT_TEAM})"\n'
        with self.assertRaisesRegex(release.ReleaseError, "Missing Mac Installer"):
            release.installer_identity(output, release.DEFAULT_TEAM)

    def test_store_package_accepts_apple_issued_store_installer_status(self):
        output = ('Package "FujikageQL.pkg":\n'
                  '   Status: signed by a developer certificate issued by Apple (Development)\n'
                  '   Certificate Chain:\n'
                  f'    1. 3rd Party Mac Developer Installer: Owner ({release.DEFAULT_TEAM})\n'
                  '    2. Apple Worldwide Developer Relations Certification Authority\n'
                  '    3. Apple Root CA\n')
        release.validate_package_signature(output, release.DEFAULT_TEAM)
        for status in ("no signature", "signed by an untrusted certificate", "signed by a certificate that has since expired"):
            with self.subTest(status=status), self.assertRaisesRegex(release.ReleaseError, "not trusted"):
                release.validate_package_signature(output.replace("signed by a developer certificate issued by Apple (Development)", status), release.DEFAULT_TEAM)

    def test_store_package_requires_matching_installer_leaf(self):
        for leaf in (f"Apple Development: Owner ({release.DEFAULT_TEAM})",
                     "3rd Party Mac Developer Installer: Other (OTHERTEAM)"):
            output = ('   Status: signed by a developer certificate issued by Apple (Development)\n'
                      f'    1. {leaf}\n'
                      f'    2. 3rd Party Mac Developer Installer: Owner ({release.DEFAULT_TEAM})\n')
            with self.subTest(leaf=leaf), self.assertRaisesRegex(release.ReleaseError, "Wrong store installer"):
                release.validate_package_signature(output, release.DEFAULT_TEAM)

    def test_present_store_profile_is_always_validated(self):
        with tempfile.TemporaryDirectory() as temp, patch.object(release, "validate_profile") as validate:
            path = Path(temp) / "embedded.provisionprofile"
            path.touch()
            release.validate_optional_profile(path, release.BUNDLE_ID, release.DEFAULT_TEAM,
                                              self.signed["entitlements"], "store")
            validate.assert_called_once_with(path, release.BUNDLE_ID, release.DEFAULT_TEAM,
                                             self.signed["entitlements"], "store", None)

    def test_restricted_entitlement_requires_profile(self):
        with tempfile.TemporaryDirectory() as temp:
            entitlements = dict(self.signed["entitlements"], **{"keychain-access-groups": [release.DEFAULT_TEAM + "." + release.BUNDLE_ID]})
            with self.assertRaisesRegex(release.ReleaseError, "Missing profile for restricted"):
                release.validate_optional_profile(Path(temp) / "missing.provisionprofile", release.BUNDLE_ID,
                                                  release.DEFAULT_TEAM, entitlements, "store")

    def test_supplied_profile_must_be_embedded(self):
        with tempfile.TemporaryDirectory() as temp:
            with self.assertRaisesRegex(release.ReleaseError, "Missing profile"):
                release.validate_optional_profile(Path(temp) / "missing.provisionprofile", release.BUNDLE_ID,
                                                  release.DEFAULT_TEAM, self.signed["entitlements"], "store", "Supplied Profile")

    def test_unknown_profile_bundle_identifier_rejected(self):
        with self.assertRaisesRegex(release.ReleaseError, "Unknown provisioning-profile bundle"):
            release.export_options("store", release.DEFAULT_TEAM, {"com.example.unrelated": "Wrong App"})

    def test_profile_authorization_respects_prefix_wildcard(self):
        self.assertTrue(release.profile_value_matches("TEAM.app", "TEAM.*"))
        self.assertFalse(release.profile_value_matches("OTHER.app", "TEAM.*"))

    def test_valid_embedded_distribution_profile(self):
        claimed = {"keychain-access-groups": [release.DEFAULT_TEAM + "." + release.BUNDLE_ID]}
        profile = {"TeamIdentifier": [release.DEFAULT_TEAM], "Name": "Store Profile", "UUID": "profile-uuid",
                   "ExpirationDate": datetime.datetime.now() + datetime.timedelta(days=1),
                   "Entitlements": {"com.apple.application-identifier": release.DEFAULT_TEAM + "." + release.BUNDLE_ID,
                                    "keychain-access-groups": [release.DEFAULT_TEAM + ".*"]}}
        with patch.object(release, "run", return_value=plistlib.dumps(profile)):
            release.validate_profile(Path("embedded.provisionprofile"), release.BUNDLE_ID, release.DEFAULT_TEAM,
                                     claimed, "store", "profile-uuid")

    def test_embedded_profile_rejects_invalid_distribution_authorization(self):
        profile = {"TeamIdentifier": [release.DEFAULT_TEAM], "Name": "Store Profile", "UUID": "profile-uuid",
                   "ExpirationDate": datetime.datetime.now() + datetime.timedelta(days=1),
                   "Entitlements": {"com.apple.application-identifier": release.DEFAULT_TEAM + "." + release.BUNDLE_ID,
                                    "keychain-access-groups": [release.DEFAULT_TEAM + ".*"]}}
        cases = {
            "wrong team": {"TeamIdentifier": ["OTHER"]},
            "expired": {"ExpirationDate": datetime.datetime.now() - datetime.timedelta(days=1)},
            "devices": {"ProvisionedDevices": ["device-id"]},
            "developer id": {"ProvisionsAllDevices": True},
            "wrong app": {"Entitlements": dict(profile["Entitlements"], **{"com.apple.application-identifier": release.DEFAULT_TEAM + ".other"})},
            "debugger": {"Entitlements": dict(profile["Entitlements"], **{"com.apple.security.get-task-allow": True})},
            "unauthorized keychain": {"Entitlements": dict(profile["Entitlements"], **{"keychain-access-groups": ["OTHER.*"]})},
            "wrong selector": {"Name": "Other", "UUID": "other-uuid"},
        }
        claimed = {"keychain-access-groups": [release.DEFAULT_TEAM + "." + release.BUNDLE_ID]}
        for label, changes in cases.items():
            with self.subTest(label=label), patch.object(release, "run", return_value=plistlib.dumps(dict(profile, **changes))):
                with self.assertRaises(release.ReleaseError):
                    release.validate_profile(Path("embedded.provisionprofile"), release.BUNDLE_ID, release.DEFAULT_TEAM,
                                             claimed, "store", "profile-uuid")

    def test_duplicate_profile_input_rejected(self):
        with self.assertRaisesRegex(release.ReleaseError, "once"):
            release.profile_args(["id=one", "id=two"])


if __name__ == "__main__":
    unittest.main()
