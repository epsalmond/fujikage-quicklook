# Mac App Store submission text

Prepared for FujikageQL 1.0, build 2. Signing and App ID setup are complete. App Store Connect record `6822129984` exists, the required agreements are complete, and free availability is configured in 175 regions. The public repository hosts the support and privacy documents below; no new hosting is required. Build processing, submission assets, contact details, and questionnaire entries remain to be completed.

The full app suite passed **54 tests with zero skips**, including the approved real RAF. The direct-download ZIP is notarized and independently approved. The Store 1.0 (2) package passed server validation and uploaded successfully with delivery ID `b968e84d-e25a-457d-ba2e-e2e71ecd0f55`; App Store Connect processing has not yet been verified. App Review approval remains pending.

## Metadata

| Field | Value |
| --- | --- |
| Name | FujikageQL |
| Subtitle | RAF previews in Quick Look |
| Primary language | English (U.S.) |
| Platform | macOS |
| Minimum macOS | 14.0 |
| Version / build | 1.0 / 2 |
| Bundle ID | `com.epsalmond.fujikage.quicklook` |
| App Store Connect Apple ID | `6822129984` |
| Primary category | Photo & Video |
| Secondary category | Leave unset |
| Price | Free |
| Copyright field | `2026 Eric Psalmond` |
| Support URL | `https://github.com/epsalmond/fujikage-quicklook/blob/main/docs/support.md` |
| Privacy Policy URL | `https://github.com/epsalmond/fujikage-quicklook/blob/main/docs/privacy.md` |
| Marketing URL | `https://github.com/epsalmond/fujikage-quicklook` |

The name and subtitle fit Apple’s 30-character limits. The App Store Connect category is **Photo & Video**; the native macOS bundle category in `project.yml` is separately named `public.app-category.photography`. The copyright field omits the symbol that App Store Connect adds. Verify the public URLs before entering them. [Apple’s app information reference](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information) describes these fields.

The owner has chosen [GitHub Issues](https://github.com/epsalmond/fujikage-quicklook/issues) for public support, bug reports, and feature requests. Use the published support-page URL above in App Store Connect; that page directs users to GitHub Issues.

## Description

Copy the following plain text into the Description field:

```text
Preview your Fujifilm RAF files directly in Finder with FujikageQL.

Select a RAF file and press Space to see the JPEG preview already stored inside it, including in compressed RAF files. FujikageQL reads that preview without decoding RAW sensor data or rewriting the RAF image data.

QUICK LOOK PREVIEWS
Use Finder’s Spacebar preview, or choose a RAF in the app to view its embedded JPEG.

OPTIONAL FINDER THUMBNAILS
If Finder’s icon grid stays blank, add a local folder and apply custom thumbnails to its RAF files. Exclude folders you want to leave alone, and remove thumbnails applied by FujikageQL when you no longer need them. Adding a folder alone does not change its files.

LOCAL PROCESSING
No account is required. FujikageQL processes files on your Mac and does not upload photos or include analytics.

Requires macOS 14 or later and a Fujifilm RAF with a readable embedded JPEG. This is a preview utility, not a RAW editor or converter. Finder thumbnail behavior varies by volume; applying thumbnails writes Finder metadata and may create ._ metadata files when you allow them.

If previews are missing, enable FujikageQL in System Settings > General > Login Items & Extensions.
```

## Keywords

```text
raf,raw,quicklook,finder,preview,thumbnail,photo,camera,compressed,jpeg
```

This ASCII list fits Apple’s 100-byte keyword limit and avoids repeating the app name or including another company’s name. The description is below 4,000 characters. [Apple’s platform version reference](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information) documents the limits.

## Promotional text

Optional:

```text
See the JPEG inside your Fujifilm RAF files in Quick Look. Add Finder thumbnails to selected local folders when you need them.
```

## App Review information

No sign-in or demo account is required. Enter the owner’s actual review contact name, email, and telephone number in App Store Connect. These private Apple review fields are separate from the public GitHub Issues support channel. The App Review telephone number remains pending owner input.

After attaching the approved compressed RAF sample, use these review notes:

```text
FujikageQL is a native macOS Quick Look utility for Fujifilm RAF files. It displays the JPEG embedded in the RAF; it does not decode RAW sensor data. No sign-in, camera connection, or subscription is required.

Use the compressed Fujifilm RAF sample attached to this submission. Save it to a local folder on an APFS volume, and keep an extra copy for the optional thumbnail test.

1. Open FujikageQL. If needed, enable its Quick Look extensions in System Settings > General > Login Items & Extensions (the exact extension controls vary by macOS version).
2. In Finder, select the sample RAF and press Space to see its embedded JPEG. In the app, Choose a RAF… displays the same preview independently of Finder’s extension selection.
3. To test optional custom Finder icons, add the folder containing the duplicate RAF. Adding the folder does not write to its files. Choose Apply thumbnails.
4. Open that folder’s menu and choose Remove applied thumbnails… to remove FujikageQL’s applied icon.

Thumbnail operations write Finder metadata and a FujikageQL marker, leaving RAF image data unchanged. Start on local APFS; network shares, removable filesystems, and File Provider folders have different metadata behavior. The Allow ._ metadata files option remains off for this test.
```

## Screenshots and reviewer sample

The owner has approved the real RAF photo for this release, and screenshot capture is in progress. The RAF and its private local path are kept outside the public repository. Prepare the reviewer attachment separately, checking identifying EXIF metadata before sharing the original file.

Capture the actual release app: a Finder Quick Look preview, the app’s embedded-JPEG preview, and the folder workflow on disposable local copies. Suggested captions are “Preview RAF files with Space,” “See the JPEG stored in your RAF,” and “Apply Finder thumbnails when you need them.” Preserve the approved app icon.

Apple’s current [Mac screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications) require 16:10 images at 1280 × 800, 1440 × 900, 2560 × 1600, or 2880 × 1800 pixels. Use one accepted size consistently and inspect every screenshot for private paths or unrelated desktop content. Screenshot completion and upload remain pending.

## Remaining submission items

- **App Privacy questionnaire:** enter **Data Not Collected**. Source inspection establishes local RAF/JPEG processing, local settings/bookmarks, local path-bearing diagnostics, no accounts, no analytics or built-in network client, and no photo uploads. Apple excludes processing solely on-device from collection, supporting this answer under [Apple’s privacy definitions](https://developer.apple.com/app-store/app-privacy-details/). The support/privacy pages describe external browser links and voluntary public issue reports separately.
- **Privacy-manifest scope:** Apple’s [privacy-manifest documentation](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files) requires declarations for required-reason APIs on iOS, iPadOS, tvOS, visionOS, and watchOS; native macOS is excluded from that requirement. This app’s `UserDefaults` usage therefore does not create a required-reason manifest prerequisite for submission. Data-collection disclosures apply on every platform; the inspected app collects no data and includes no third-party runtime SDKs.
- **Age rating and content rights:** complete the current questions in App Store Connect. The app displays user-selected local photos; do not infer a rating from camera-file support. Source inspection shows no ads, accounts, messaging, or in-app browsing. Confirm rights to all submitted screenshots, artwork, and the reviewer RAF.
- **Export compliance:** no custom cryptography or network client was found in the inspected source. Confirm the final binary and answer the current encryption questions; no legal declaration is made by this draft.
- **Accessibility claims:** no App Store accessibility claims are proposed without testing the release app against the relevant criteria.
- **Build and private review contact:** confirm App Store Connect has finished processing build 1.0 (2), then select it for submission. Supply the actual App Review contact telephone number; that owner input remains unanswered. Public support is through GitHub Issues. Signing, App ID registration, app record `6822129984`, agreements, and free availability in 175 regions are already complete.
- **Links:** use and verify the public URLs above before submission. The current in-app help button opens `https://fujikage.io/#quicklook`, which has no confirmed Quick Look section. These content changes do not modify that source URL or the built app.

See [releasing.md](releasing.md) for archive, export, and release validation.
