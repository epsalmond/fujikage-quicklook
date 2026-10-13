# FujikageQL privacy

Applies to FujikageQL 1.0 for macOS. Updated October 12, 2026.

FujikageQL is developed by Eric Psalmond.

FujikageQL processes Fujifilm RAF files on your Mac. It reads the JPEG preview embedded in a RAF to display a preview or make a thumbnail. It does not decode the RAW sensor data or upload your photos to the developer. The app has no analytics, advertising, account system, or built-in network client.

## Local settings and diagnostics

The app saves selected folders, excluded folders, their paths, security-scoped bookmarks, the “Allow ._ metadata files” setting, and recent operation notes in local app settings. Bookmarks let the sandboxed app access folders you selected in later sessions. “Remove from list” removes that saved folder entry; it does not delete the folder or remove applied thumbnails.

The host app writes local diagnostic messages to macOS logging and to:

```text
~/Library/Containers/com.epsalmond.fujikage.quicklook/Data/Library/Logs/stamp.log
```

These messages can include file names, full folder paths, filesystem details, operation results, and errors. The thumbnail extension also writes file paths and errors to macOS logging, visible in Console under the subsystem `com.epsalmond.fujikage.quicklook`. Logs do not contain the photo itself. FujikageQL does not automatically send these logs to the developer. The text log is replaced after it exceeds approximately 512 KB; macOS controls retention of its own logs.

## Changes to selected files

Previewing a RAF does not write to it. “Apply thumbnails” writes a custom Finder icon using Finder metadata and a resource fork, stored as extended attributes where supported, plus the `com.epsalmond.fujikage.stamp` marker. On some volumes this metadata can be stored in an AppleDouble `._` file beside the RAF. The “Allow ._ metadata files” option controls whether the app permits those files on volumes it would otherwise skip or probe.

Applying or removing thumbnails does not rewrite the RAF image data. For a file without owner-write permission, the app may temporarily add that permission to write metadata, then restore the original mode. “Remove applied thumbnails” uses the FujikageQL marker to identify applied icons and any sidecar it created. Metadata attached to a photo can travel with it when you copy or share the file.

## Files and websites outside the app

Files you select on a network share or in a cloud-managed folder are accessed through macOS. Your storage service may transfer or synchronize those files and their metadata under its own policies.

Clicking the help button opens a website in your browser. Visiting support pages or submitting an issue involves the website or GitHub; information you choose to submit there is separate from the app’s local processing. [GitHub issues](https://github.com/epsalmond/fujikage-quicklook/issues) are public, so review photos, paths, and logs before posting them.

For questions about this policy, use the [FujikageQL support page](support.md).
