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

An archive without approved copyright text can be used for preparation, but distribution export requires a new archive with the approved legal text:

```sh
python3 scripts/release/release.py archive \
  --archive build/release/FujikageQL-ready.xcarchive \
  --copyright 'OWNER-APPROVED LEGAL COPYRIGHT TEXT'
```

Use a new output path for every archive/export. The helper refuses to overwrite an existing output. Override the configured team with the global `--team TEAM_ID` argument before the subcommand; the identities and all three bundle identifiers/profiles must correspond to that team. Do not change version/build until the release owner confirms the intended version and, for the store, checks existing uploaded builds.

## GitHub download

```sh
python3 scripts/release/release.py preflight --channel direct
python3 scripts/release/release.py export --channel direct \
  --archive build/release/FujikageQL-ready.xcarchive \
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

No updater is configured. A ZIP download is installed by moving the app to Applications; replace it there for future direct-download updates. GitHub repository ownership/name, public source visibility, license, release tag, release notes, and final download URL remain owner decisions. A public binary release does not resolve source licensing.

## Mac App Store

```sh
python3 scripts/release/release.py preflight --channel store

python3 scripts/release/release.py export --channel store \
  --archive build/release/FujikageQL-ready.xcarchive \
  --output build/release/store
```

The local preflight requires Apple Distribution and Mac Installer Distribution identities with their private keys. The current app uses unrestricted sandbox/file/bookmark entitlements, so native Mac App Store distribution can omit provisioning profiles. Apple's [TN3125](https://developer.apple.com/documentation/technotes/tn3125-inside-code-signing-provisioning-profiles) explains that profiles become necessary for restricted entitlements; TestFlight always requires them. This helper prepares native App Store packages and does not support TestFlight export.

If profiles are needed or intentionally supplied, add `--profile BUNDLE_ID=INSTALLED_PROFILE_NAME_OR_UUID` to the export command for each affected executable: `com.epsalmond.fujikage.quicklook`, `.quicklook.preview`, and `.quicklook.thumbnail`. Xcode checks local profile availability during export. The verifier requires the corresponding embedded profile for every supplied mapping or restricted entitlement, validates any embedded profile even if none was supplied, and checks expiry, team/application identifier, entitlement authorization, and distribution type. A supplied name/UUID must match the embedded profile. New capabilities outside the helper's existing entitlement allowlist are rejected until reviewed.

Export uses `method=app-store-connect`, `destination=export`, manual signing, and `manageAppVersionAndBuildNumber=false`. The package must have a trusted store installer signature; its extracted app must pass store-signature, universal-binary, entitlement, and applicable provisioning checks. A checksum is written alongside the package.

Upload with the owner's chosen Apple-supported tool only after authorization. Local package validation is not App Store Connect validation or App Review approval. The App Store Connect app record, bundle-ID registration, team agreements, price/availability, approved copyright, privacy answers/URL, support URL, screenshots, age rating, and reviewer sample are unresolved. Use a real compressed RAF sample that may legally be supplied to reviewers; none is committed in this repository.

## Metadata and privacy draft

Suggested description, subject to owner review:

> Preview compressed Fujifilm RAF files in Quick Look and Finder. FujikageQL displays the full-size JPEG embedded in each RAF; it does not decode RAW sensor data. Optionally apply Finder icons to RAF files in selected folders. Requires macOS 14 or later.

Suggested privacy disclosure prose, to review against the final binary and privacy form:

> FujikageQL processes selected files locally. It saves folder selections, exclusions, and security-scoped bookmarks in local app settings. Local diagnostic logs include file names and paths. Applying thumbnails writes Finder metadata and extended attributes; depending on the volume and your metadata-file setting, this can also create AppleDouble `._` files. RAF image data is not rewritten. The source currently includes no networking or analytics client; opening the support link opens a website in your browser.

Do not present this draft as an approved App Store privacy answer. No privacy manifest is added speculatively: inspect the final binary's required-reason API usage and SDKs against Apple's current submission requirements before upload. `UserDefaults` usage requires that inventory. There are no declared third-party runtime dependencies; XcodeGen is a build tool.

The current in-app support link is `https://fujikage.io/#quicklook`; the homepage responds, but Quick Look support content at that anchor has not been confirmed. A `/privacy` page exists, but its applicability/content needs owner review. Approved screenshots should use a real RAF and the actual app; existing icon artwork is retained, with prior design decisions tracked separately.

Review notes should explain how to enable FujikageQL in System Settings → General → Login Items & Extensions, preview the supplied compressed RAF with Finder Spacebar or “Choose a RAF…”, and test Apply/Remove thumbnails on a small duplicate RAF folder on local APFS. Avoid broad network-volume promises: NFS, SMB, removable filesystems, and File Provider have different behavior described in the README.

## Current local limitations

The local identity inventory during preparation contained Apple Development and Apple Distribution; no Developer ID Application or Mac Installer Distribution identity was present. No App Store Connect record, legal copyright, or release account inputs were confirmed. No distribution profiles were confirmed; they are optional for the current native App Store capabilities. The archive can therefore be prepared and verified, while direct export needs a Developer ID Application identity and store export needs a Mac Installer Distribution identity; both need approved copyright text. No upload, notarization submission, publication, installation, tag, or push was performed by this preparation work.
