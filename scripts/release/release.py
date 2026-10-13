#!/usr/bin/env python3
"""Local archive/export preparation. Publishing and account mutation are separate."""

import argparse
import datetime
import hashlib
import json
import plistlib
import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_TEAM = "KA3Y4C7M3R"
BUNDLE_ID = "com.epsalmond.fujikage.quicklook"
TARGETS = {
    "FujikageQL": ("", BUNDLE_ID),
    "FujikageQLPreview": ("Contents/PlugIns/FujikageQLPreview.appex", BUNDLE_ID + ".preview"),
    "FujikageQLThumbnail": ("Contents/PlugIns/FujikageQLThumbnail.appex", BUNDLE_ID + ".thumbnail"),
}
SANDBOX = "com.apple.security.app-sandbox"
HOST_PERMISSIONS = {
    "com.apple.security.files.user-selected.read-write",
    "com.apple.security.files.bookmarks.app-scope",
}
SIGNING_KEYS = {
    "com.apple.developer.team-identifier",
    "com.apple.application-identifier",
    "application-identifier",
    "keychain-access-groups",
    "get-task-allow",
    "com.apple.security.get-task-allow",
}
RESTRICTED_KEYS = {"application-identifier", "com.apple.application-identifier", "keychain-access-groups"}


class ReleaseError(Exception):
    pass


def require(condition, message):
    if not condition:
        raise ReleaseError(message)


def run(command, capture=False):
    result = subprocess.run(command, cwd=ROOT, capture_output=capture)
    if result.returncode:
        # Tool output includes useful diagnostics, never credential values.
        if capture:
            sys.stderr.buffer.write(result.stdout + result.stderr)
        raise ReleaseError(f"{command[0]} failed (exit {result.returncode})")
    return result.stdout + result.stderr if capture else b""


def read_plist(path):
    require(path.is_file(), f"Missing plist: {path}")
    return plistlib.loads(path.read_bytes())


def signature(path):
    run(["codesign", "--verify", "--all-architectures", "--strict", str(path)], capture=True)
    details = run(["codesign", "-d", "--verbose=4", str(path)], capture=True).decode()
    entitlements_data = run(["codesign", "-d", "--entitlements", ":-", str(path)], capture=True)
    # codesign may append its status message on stderr after the XML.
    start = entitlements_data.find(b"<?xml")
    end = entitlements_data.find(b"</plist>", start)
    require(start >= 0 and end >= 0, f"Missing signed entitlements: {path}")
    entitlements = plistlib.loads(entitlements_data[start:end + len(b"</plist>")])
    team = re.search(r"^TeamIdentifier=(.+)$", details, re.M)
    authorities = re.findall(r"^Authority=(.+)$", details, re.M)
    return {"team": team.group(1) if team else None, "authorities": authorities,
            "runtime": bool(re.search(r"flags=.*\bruntime\b", details)),
            "entitlements": entitlements}


def validate_profile(path, bundle_id, team, entitlements, channel, expected_profile=None):
    profile = plistlib.loads(run(["security", "cms", "-D", "-i", str(path)], capture=True))
    require(team in profile.get("TeamIdentifier", []), f"Profile team mismatch: {path}")
    expiry = profile.get("ExpirationDate")
    require(isinstance(expiry, datetime.datetime) and expiry > datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None),
            f"Expired or missing profile expiry: {path}")
    ent = profile.get("Entitlements", {})
    app_id = ent.get("com.apple.application-identifier", ent.get("application-identifier"))
    require(app_id == f"{team}.{bundle_id}", f"Profile app identifier mismatch: {path}")
    require(not ent.get("get-task-allow") and not ent.get("com.apple.security.get-task-allow"),
            f"Development provisioning profile: {path}")
    require(not profile.get("ProvisionedDevices"), f"Device provisioning profile is not for distribution: {path}")
    if channel == "store":
        require(not profile.get("ProvisionsAllDevices"), f"Profile is not for App Store distribution: {path}")
    else:
        require(profile.get("ProvisionsAllDevices") is True, f"Profile is not for Developer ID distribution: {path}")
    if expected_profile:
        require(expected_profile in (profile.get("Name"), profile.get("UUID")),
                f"Embedded profile does not match supplied name/UUID: {path}")
    for key in RESTRICTED_KEYS & entitlements.keys():
        claimed = entitlements[key]
        allowed = ent.get(key)
        if isinstance(claimed, list):
            require(isinstance(allowed, list) and all(any(profile_value_matches(item, entry) for entry in allowed) for item in claimed),
                    f"Profile does not authorize {key}: {path}")
        else:
            require(profile_value_matches(claimed, allowed), f"Profile does not authorize {key}: {path}")


def profile_value_matches(claimed, allowed):
    if isinstance(claimed, str) and isinstance(allowed, str) and allowed.endswith("*"):
        return claimed.startswith(allowed[:-1])
    return claimed == allowed


def validate_optional_profile(path, bundle_id, team, entitlements, channel, expected_profile=None):
    required = bool(RESTRICTED_KEYS & entitlements.keys()) or bool(expected_profile)
    require(path.is_file() or not required, f"Missing profile for restricted entitlements or supplied profile: {bundle_id}")
    if path.is_file():
        validate_profile(path, bundle_id, team, entitlements, channel, expected_profile)


def validate_bundle(info, archs, signed, *, expected_id, expected_version, team, channel, host):
    """Pure checks used by the on-disk verifier and focused regression tests."""
    require(info.get("CFBundleIdentifier") == expected_id, f"Bundle identifier mismatch: {expected_id}")
    require((info.get("CFBundleShortVersionString"), info.get("CFBundleVersion")) == expected_version,
            f"Version/build mismatch: {expected_id}")
    require(set(archs) == {"arm64", "x86_64"}, f"Expected universal arm64 + x86_64: {expected_id}")
    require(signed["team"] == team, f"Signing team mismatch: {expected_id}")
    ent = signed["entitlements"]
    require(ent.get(SANDBOX) is True, f"Missing App Sandbox: {expected_id}")
    require(not ent.get("get-task-allow") and not ent.get("com.apple.security.get-task-allow"),
            f"get-task-allow is enabled: {expected_id}")
    allowed = {SANDBOX} | SIGNING_KEYS | (HOST_PERMISSIONS if host else set())
    require(not (set(ent) - allowed), f"Unexpected entitlements: {expected_id}: {sorted(set(ent) - allowed)}")
    if host:
        require(all(ent.get(key) is True for key in HOST_PERMISSIONS), f"Missing host file permissions: {expected_id}")
    for key in ("application-identifier", "com.apple.application-identifier"):
        if key in ent:
            require(ent[key] == f"{team}.{expected_id}", f"Signed application identifier mismatch: {expected_id}")
    if "com.apple.developer.team-identifier" in ent:
        require(ent["com.apple.developer.team-identifier"] == team, f"Entitlement team mismatch: {expected_id}")
    if "keychain-access-groups" in ent:
        require(ent["keychain-access-groups"] == [f"{team}.{expected_id}"], f"Unexpected keychain access groups: {expected_id}")
    if channel != "archive":
        authorities = signed["authorities"]
        require(authorities, f"Unsigned/ad-hoc release: {expected_id}")
        expected = ("Developer ID Application:",) if channel == "direct" else ("Apple Distribution:", "3rd Party Mac Developer Application:")
        require(authorities[0].startswith(expected), f"Wrong distribution signature: {expected_id}: {authorities[0]}")
        require(signed["runtime"], f"Hardened runtime missing: {expected_id}")


def bundle_paths(app):
    paths = [(name, app / relative, bundle_id) for name, (relative, bundle_id) in TARGETS.items()]
    for name, path, _ in paths:
        require(path.is_dir(), f"Missing required bundle: {name}: {path}")
    plugins = set((app / "Contents/PlugIns").glob("*.appex"))
    require(plugins == {paths[1][1], paths[2][1]}, "Unexpected embedded extension set")
    return paths


def verify_app(app, channel, team, expected_profiles=None):
    app = Path(app).resolve()
    paths = bundle_paths(app)
    host_info = read_plist(app / "Contents/Info.plist")
    version = (host_info.get("CFBundleShortVersionString"), host_info.get("CFBundleVersion"))
    require(all(isinstance(value, str) and value.strip() for value in version), "Missing host version/build")
    if channel != "archive":
        require(bool(host_info.get("NSHumanReadableCopyright", "").strip()), "Explicit copyright is required for distribution export")
    for resource in ("Assets.car", "AppIcon.icns"):
        require((app / "Contents/Resources" / resource).is_file(), f"Missing release resource: {resource}")
    report = []
    for name, path, bundle_id in paths:
        info = read_plist(path / "Contents/Info.plist")
        executable = path / "Contents/MacOS" / info.get("CFBundleExecutable", "")
        require(executable.is_file(), f"Missing executable: {name}")
        archs = run(["lipo", "-archs", str(executable)], capture=True).decode().split()
        signed = signature(path)
        validate_bundle(info, archs, signed, expected_id=bundle_id, expected_version=version,
                        team=team, channel=channel, host=name == "FujikageQL")
        if name != "FujikageQL":
            extension = info.get("NSExtension", {})
            expected_point = "com.apple.quicklook.preview" if name.endswith("Preview") else "com.apple.quicklook.thumbnail"
            require(extension.get("NSExtensionPointIdentifier") == expected_point, f"Wrong extension point: {name}")
        if channel != "archive":
            validate_optional_profile(path / "Contents/embedded.provisionprofile", bundle_id, team,
                                      signed["entitlements"], channel, (expected_profiles or {}).get(bundle_id))
        report.append({"bundle": name, "architectures": archs, "team": signed["team"], "authorities": signed["authorities"]})
    # Check nested code as well as each declared executable.
    run(["codesign", "--verify", "--all-architectures", "--deep", "--strict", str(app)], capture=True)
    print(json.dumps({"stage": channel, "app": str(app), "version": version[0], "build": version[1], "bundles": report}, indent=2))
    return version


def require_identity(prefix, team, policy="codesigning"):
    output = run(["security", "find-identity", "-v", "-p", policy], capture=True).decode()
    require(any(prefix in line and f"({team})" in line for line in output.splitlines()),
            f"Missing valid {prefix} identity with private key for team {team}; no development-signing fallback")


def export_options(channel, team, profiles):
    require(set(profiles) <= {entry[1] for entry in TARGETS.values()}, "Unknown provisioning-profile bundle identifier")
    options = {"method": "developer-id" if channel == "direct" else "app-store-connect",
               "destination": "export", "manageAppVersionAndBuildNumber": False,
               "teamID": team, "signingStyle": "manual",
               "signingCertificate": "Developer ID Application" if channel == "direct" else "Apple Distribution"}
    if channel == "store":
        options["installerSigningCertificate"] = "Mac Installer Distribution"
    if profiles:
        options["provisioningProfiles"] = profiles
    return options


def preflight(channel, team, profiles):
    options = export_options(channel, team, profiles)
    require_identity(options["signingCertificate"] + ":", team)
    if channel == "store":
        # Installer certificates use the older displayed name on many keychains.
        output = run(["security", "find-identity", "-v", "-p", "basic"], capture=True).decode()
        require(any(("3rd Party Mac Developer Installer:" in line or "Mac Installer Distribution:" in line)
                    and f"({team})" in line for line in output.splitlines()),
                f"Missing Mac Installer Distribution identity with private key for team {team}")
    print(f"Local {channel} signing preflight passed; profile availability is checked by Xcode during export.")
    return options


def verify_package(package, team, expected_profiles=None):
    output = run(["pkgutil", "--check-signature", str(package)], capture=True).decode()
    require(any(status in output for status in ("Status: signed by a certificate trusted by macOS", "Status: signed by a certificate trusted by Mac OS X")),
            "Store package signature is not trusted")
    require(any(("3rd Party Mac Developer Installer:" in line or "Mac Installer Distribution:" in line)
                and f"({team})" in line for line in output.splitlines()), "Wrong store installer signature/team")
    with tempfile.TemporaryDirectory(prefix="fujikageql-package-") as temp:
        expanded = Path(temp) / "expanded"
        run(["pkgutil", "--expand-full", str(package), str(expanded)], capture=True)
        apps = list(expanded.rglob("FujikageQL.app"))
        require(len(apps) == 1, "Expected exactly one FujikageQL.app inside store package")
        verify_app(apps[0], "store", team, expected_profiles)
    print(f"Verified App Store export package: {package}")


def checksum(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    path.with_name(path.name + ".sha256").write_text(f"{digest.hexdigest()}  {path.name}\n")


def profile_args(values):
    profiles = {}
    for value in values:
        key, separator, profile = value.partition("=")
        require(separator and profile and key not in profiles, "Use each --profile bundle-id=profile-name-or-UUID once")
        profiles[key] = profile
    return profiles


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--team", default=DEFAULT_TEAM)
    commands = parser.add_subparsers(dest="command", required=True)
    archive = commands.add_parser("archive", help="Build a local universal archive; development signing is permitted at this stage")
    archive.add_argument("--archive", type=Path, default=ROOT / "build/release/FujikageQL.xcarchive")
    archive.add_argument("--copyright", help="Owner-approved legal copyright text; required before distribution export")
    for command in ("preflight", "export"):
        sub = commands.add_parser(command)
        sub.add_argument("--channel", choices=("direct", "store"), required=True)
        sub.add_argument("--profile", action="append", default=[])
        if command == "export":
            sub.add_argument("--archive", type=Path, default=ROOT / "build/release/FujikageQL.xcarchive")
            sub.add_argument("--output", type=Path, required=True)
    verify = commands.add_parser("verify")
    verify.add_argument("--channel", choices=("archive", "direct", "store"), required=True)
    verify.add_argument("artifact", type=Path)
    notarize = commands.add_parser("notarize", help="Submit a direct export to Apple; requires separate authorization")
    notarize.add_argument("app", type=Path)
    notarize.add_argument("--keychain-profile", required=True, help="Existing notarytool credential profile name; never a password")
    notarize.add_argument("--output", type=Path, required=True, help="Final stapled release ZIP")
    args = parser.parse_args()
    if args.command == "archive":
        if args.copyright is not None:
            require(args.copyright.strip(), "Copyright text cannot be blank")
        require(not args.archive.exists(), f"Archive output already exists: {args.archive}")
        run(["xcodegen", "generate"])
        copyright_settings = [f"INFOPLIST_KEY_NSHumanReadableCopyright={args.copyright}"] if args.copyright else []
        run(["xcodebuild", "-project", "FujikageQL.xcodeproj", "-scheme", "FujikageQL", "-configuration", "Release",
             "-destination", "generic/platform=macOS", "-archivePath", str(args.archive.resolve()),
             "-derivedDataPath", str(ROOT / "build/release/DerivedData"),
             "ARCHS=arm64 x86_64", "ONLY_ACTIVE_ARCH=NO", f"DEVELOPMENT_TEAM={args.team}",
             "CODE_SIGN_IDENTITY=Apple Development", "CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO",
             *copyright_settings, "archive"])
        verify_app(args.archive / "Products/Applications/FujikageQL.app", "archive", args.team)
        print("Archive preparation passed. This development-signed archive is not a public release.")
    elif args.command in ("preflight", "export"):
        options = preflight(args.channel, args.team, profile_args(args.profile))
        if args.command == "export":
            archived_app = args.archive / "Products/Applications/FujikageQL.app"
            verify_app(archived_app, "archive", args.team)
            require(bool(read_plist(archived_app / "Contents/Info.plist").get("NSHumanReadableCopyright", "").strip()),
                    "Rebuild the archive with --copyright containing owner-approved legal text before distribution export")
            require(not args.output.exists(), f"Export output already exists: {args.output}")
            args.output.mkdir(parents=True)
            options_path = args.output / "ExportOptions.plist"
            options_path.write_bytes(plistlib.dumps(options))
            run(["xcodebuild", "-exportArchive", "-archivePath", str(args.archive.resolve()),
                 "-exportPath", str(args.output.resolve()), "-exportOptionsPlist", str(options_path.resolve())])
            profiles = profile_args(args.profile)
            if args.channel == "direct":
                verify_app(args.output / "FujikageQL.app", "direct", args.team, profiles)
                print("Developer ID export verified; notarization and stapling still required before public release.")
            else:
                packages = list(args.output.glob("*.pkg"))
                require(len(packages) == 1, "Expected exactly one App Store export package")
                verify_package(packages[0], args.team, profiles)
                checksum(packages[0])
    elif args.command == "verify":
        if args.artifact.suffix == ".pkg":
            require(args.channel == "store", "Only store package verification is supported")
            verify_package(args.artifact.resolve(), args.team)
        else:
            app = args.artifact / "Products/Applications/FujikageQL.app" if args.artifact.suffix == ".xcarchive" else args.artifact
            verify_app(app, args.channel, args.team)
    else:
        app = args.app.resolve()
        verify_app(app, "direct", args.team)
        require(args.output.suffix == ".zip" and not args.output.exists(), "Use a new .zip output path")
        args.output.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix="fujikageql-notary-") as temp:
            submitted = Path(temp) / "submission.zip"
            run(["ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", str(app), str(submitted)])
            result = json.loads(run(["xcrun", "notarytool", "submit", str(submitted), "--keychain-profile",
                                     args.keychain_profile, "--wait", "--output-format", "json"], capture=True))
            require(result.get("status") == "Accepted", f"Notarization was not accepted: {result.get('status')}; submission ID: {result.get('id')}")
            print(f"Notarization accepted: {result.get('id')}")
        run(["xcrun", "stapler", "staple", str(app)])
        run(["xcrun", "stapler", "validate", str(app)])
        verify_app(app, "direct", args.team)
        run(["spctl", "--assess", "--type", "execute", "--verbose=2", str(app)], capture=True)
        run(["ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", str(app), str(args.output.resolve())])
        with tempfile.TemporaryDirectory(prefix="fujikageql-final-zip-") as temp:
            run(["ditto", "-x", "-k", str(args.output.resolve()), temp])
            extracted = Path(temp) / "FujikageQL.app"
            verify_app(extracted, "direct", args.team)
            run(["xcrun", "stapler", "validate", str(extracted)])
            run(["spctl", "--assess", "--type", "execute", "--verbose=2", str(extracted)], capture=True)
        checksum(args.output)
        print(f"Stapled direct-release ZIP and SHA-256: {args.output}")


if __name__ == "__main__":
    try:
        main()
    except (ReleaseError, OSError, ValueError, plistlib.InvalidFileException) as error:
        sys.exit(f"Release preparation failed: {error}")
