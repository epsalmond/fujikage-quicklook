# Preparing releases

FujikageQL has two distribution paths: a Developer ID app in a notarized ZIP for GitHub downloads, and a signed installer package for App Store Connect. Both use the same universal macOS archive and preserve the version/build in `project.yml` (currently 1.0 / 2). `make release` remains a local development-signed build; it is not a distributable release.

The Python 3 standard-library helper below uses Xcode's archive/export flow. It never uploads to App Store Connect, changes a developer account, installs the app, creates a tag, or publishes to GitHub. It does not use `-allowProvisioningUpdates`; install the required certificates/private keys and profiles separately. Run from the repository root on macOS with Xcode and XcodeGen available.

## Local preparation

```sh
make release-script-test
make release-archive
python3 scripts/release/release.py verify --channel archive build/release/FujikageQL.xcarchive
```

The archive uses the existing Apple Development identity and a generic macOS destination with both `arm64` and `x86_64`. The verifier checks the host plus `FujikageQLPreview.appex` and `FujikageQLThumbnail.appex`: identical version/build and signing team, both architectures, valid signatures, App Sandbox, extension identifiers, host file/bookmark permissions, extension-specific entitlements, no debugger entitlement, and required app assets. Archive validation permits development signatures and says so explicitly.

The approved copyright owner is Eric Psalmond. `project.yml` supplies `Copyright © 2026 Eric Psalmond` to the app and extensions, so the ordinary archive command includes it. For a separately approved legal change, the archive command's optional `--copyright` argument overrides that default. Distribution export rejects archives with missing copyright metadata; rebuild older archives rather than modifying a signed bundle.

Use a new output path for every archive/export. The helper refuses to overwrite an existing output. Override the configured team with the global `--team TEAM_ID` argument before the subcommand; the identities and all three bundle identifiers/profiles must correspond to that team. Do not change version/build until the release owner confirms the intended version and, for the store, checks existing uploaded builds.

## GitHub download

```sh
python3 scripts/release/release.py preflight --channel direct
python3 scripts/release/release.py export --channel direct \
  --archive build/release/FujikageQL.xcarchive \
  --output build/release/direct
```

The preflight requires a valid Developer ID Application certificate with its private key. Apple Development and Apple Distribution cannot substitute for it. Export uses `method=developer-id`, `destination=export`, manual signing, and `manageAppVersionAndBuildNumber=false`. The exported app must carry a Developer ID signature and hardened runtime before it is accepted.

The following command submits to Apple's notarization service. Run it only when submission is authorized and an existing `notarytool` Keychain credential profile is configured. Pass the profile name, never a password or API-key contents. Creating that credential profile is a separate account task.

```sh
python3 scripts/release/release.py notarize build/release/direct/FujikageQL.app \
  --keychain-profile EXISTING_PROFILE_NAME \
  --output build/release/FujikageQL-1.0-2-macOS.zip
```

The helper ZIPs the exported app, waits for `notarytool --wait` to return `Accepted`, staples and validates the app, verifies signatures again, and assesses it with `spctl`. It then rebuilds the final ZIP from the stapled app, extracts it into a fresh temporary directory, repeats signature/ticket/assessment checks, and writes a `.zip.sha256` file. The submission ZIP is temporary; publish only the final ZIP and checksum after release authorization. Do not notarize an App Store package.

A test on a second Mac is still needed to confirm download/quarantine behavior, enabling the Quick Look extensions, previewing a real compressed RAF, and applying/removing icons on disposable copies. Universal binary verification is not physical Intel-Mac validation.

No updater is configured. A ZIP download is installed by moving the app to Applications; replace it there for future direct-download updates. The public repository [epsalmond/fujikage-quicklook](https://github.com/epsalmond/fujikage-quicklook) has been created. Publish release notes and verified assets there when completing the release. Public source visibility does not select a source license; none has been chosen here.

## Mac App Store

```sh
python3 scripts/release/release.py preflight --channel store

python3 scripts/release/release.py export --channel store \
  --archive build/release/FujikageQL.xcarchive \
  --output build/release/store
```

The local preflight requires Apple Distribution and Mac Installer Distribution identities with their private keys. The current app uses unrestricted sandbox/file/bookmark entitlements, so native Mac App Store distribution can omit provisioning profiles. Apple's [TN3125](https://developer.apple.com/documentation/technotes/tn3125-inside-code-signing-provisioning-profiles) explains that profiles become necessary for restricted entitlements; TestFlight always requires them. This helper prepares native App Store packages and does not support TestFlight export.

The helper resolves the valid installer identity to its SHA-1 selector because Xcode may not resolve the generic selector to its legacy `3rd Party Mac Developer Installer` name. `pkgutil` may describe this Apple-issued store certificate as `(Development)`; the verifier accepts that status only with the correct store installer leaf and team. Unsigned, expired, and untrusted package statuses are rejected. Apple's [packaging documentation](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution) identifies this legacy name as the Mac App Store distribution identity.

If profiles are needed or intentionally supplied, add `--profile BUNDLE_ID=INSTALLED_PROFILE_NAME_OR_UUID` to the export command for each affected executable: `com.epsalmond.fujikage.quicklook`, `.quicklook.preview`, and `.quicklook.thumbnail`. Xcode checks local profile availability during export. The verifier requires the corresponding embedded profile for every supplied mapping or restricted entitlement, validates any embedded profile even if none was supplied, and checks expiry, team/application identifier, entitlement authorization, and distribution type. A supplied name/UUID must match the embedded profile. New capabilities outside the helper's existing entitlement allowlist are rejected until reviewed.

Export uses `method=app-store-connect`, `destination=export`, manual signing, and `manageAppVersionAndBuildNumber=false`. The package must have a trusted store installer signature; its extracted app must pass store-signature, universal-binary, entitlement, and applicable provisioning checks. A checksum is written alongside the package.

The Mac App Store price is configured as free in 175 regions. App Store Connect record `6822129984`, App ID registration, signing setup, and required agreements are complete. Local package validation is not App Store Connect processing or App Review approval. Complete build processing, questionnaire entries, public support/privacy pages, contact details, screenshots, and the reviewer sample before submission. Use a real compressed RAF sample that may legally be supplied to reviewers; none is committed in this repository.

## Metadata and public pages

[app-store.md](app-store.md) contains the description, keywords, subtitle, reviewer instructions, intended public URLs, and unresolved questionnaire/account facts. [support.md](support.md) provides usage and GitHub issue contact; [privacy.md](privacy.md) describes local processing, settings/bookmarks, path-bearing diagnostics, and Finder metadata writes. Publish the pages to the approved public repository and verify their URLs before submission. An owner-approved public contact is still needed to meet Apple's stated Support URL contact requirements.

The source-supported App Privacy answer is **Data Not Collected**: RAF/JPEG processing, settings/bookmarks, and diagnostic logs stay on-device, and the app includes no analytics, built-in network client, or photo uploads. Apple’s [privacy definitions](https://developer.apple.com/app-store/app-privacy-details/) exclude solely on-device processing from collection. Apple’s [privacy-manifest documentation](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files) excludes native macOS from the required-reason API declaration requirement, so `UserDefaults` does not make a manifest mandatory for this submission. Data-collection disclosures apply on every platform. There are no declared third-party runtime dependencies; XcodeGen is a build tool.

The current in-app support link is `https://fujikage.io/#quicklook`; Quick Look content at that anchor has not been confirmed. The content pages do not modify that source URL. Screenshots and the App Review sample require an owner-approved real RAF before capture or sharing; the approved icon is retained.

## Release status: October 12, 2026

Distribution signing and App ID setup are complete. App Store Connect record `6822129984` exists, required agreements are complete, and the app is configured free in 175 regions. The public repository exists and Eric Psalmond’s copyright is recorded. Provisioning profiles remain optional for the current native App Store capabilities.

Remaining store work is build processing, submission assets, contact details, questionnaire entries, and publishing/verifying the support and privacy pages. The owner has been asked for an approved photo/local RAF path, public support email, and App Review telephone number; those answers are still pending. Source-established facts such as no accounts, analytics, app network client, or photo uploads do not need further owner confirmation.
