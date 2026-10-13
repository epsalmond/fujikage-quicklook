# FujikageQL support

FujikageQL brings Quick Look previews to Fujifilm `.raf` files, including compressed RAF files. It displays the JPEG stored in the file, rather than decoding RAW sensor data. It requires macOS 14 or later; support depends on a readable embedded JPEG, not a promise of compatibility with every camera or RAW format.

For help, bug reports, and feature requests, use [GitHub Issues](https://github.com/epsalmond/fujikage-quicklook/issues). Search existing issues first, then open an issue if you need help with something not already covered.

## Install a GitHub download

Download the ZIP from [GitHub Releases](https://github.com/epsalmond/fujikage-quicklook/releases), unzip it in Finder, and drag **FujikageQL.app** into **Applications**. Open FujikageQL once from Applications before trying a RAF preview. For updates, quit FujikageQL and replace the installed app.

## Preview a RAF

1. Open FujikageQL after installing it.
2. If Finder previews are missing, enable FujikageQL in **System Settings → General → Login Items & Extensions**. The extension controls may be in a separate **Extensions** section on your macOS version.
3. Select a RAF in Finder and press **Space**. You can also choose **Choose a RAF…** in FujikageQL to check its embedded JPEG directly.

An unreadable or missing embedded JPEG produces an error. FujikageQL is a preview tool; it does not develop, edit, or convert RAW sensor data.

## Optional Finder thumbnails

Try Quick Look and Finder first. If Finder’s icon grid remains blank on a local APFS or HFS+ volume:

1. Drag a folder into FujikageQL or choose **Add folder**. Adding it does not change its files.
2. Use **Add excluded folder…**, Option-drag a folder, or **Exclude this folder** to omit folders from thumbnail operations.
3. Choose **Apply thumbnails** for the folder. This processes RAF files in it and its subfolders, respecting exclusions. Start with a small folder of duplicate files.
4. To undo applied icons, open the folder’s menu, choose **Remove applied thumbnails…**, and confirm. **Remove from list** only forgets the folder selection.

Applying thumbnails writes Finder metadata, a resource fork, and the FujikageQL marker. It does not rewrite the RAF image data. Existing custom icons are skipped. Removal uses the marker to identify FujikageQL icons and any `._` sidecar it created.

## Network and removable volumes

Use Finder without applying custom thumbnails first on network shares. Finder can request the thumbnail extension on NFS; applying custom icons there normally creates AppleDouble `._` files. FujikageQL skips NFS, FAT/exFAT, and detected File Provider folders unless **Allow ._ metadata files** is enabled. The app probes SMB and other uncertain volumes before applying thumbnails when that option is off. SMB thumbnail behavior has not been verified across servers. Read-only volumes cannot accept metadata writes.

The metadata-file option permits sidecars; it cannot make every filesystem or cloud provider preserve icons. Network files must remain reachable, and cloud files may need downloading by their provider.

## Troubleshooting and GitHub support

If a saved folder becomes unavailable, remove it from the list and add it again. If an excluded folder cannot be opened, restore access or remove and re-add that exclusion before retrying. When reporting a preview problem, include the camera model, RAF compression mode if known, macOS version, app version, error text, and whether **Choose a RAF…** works. For thumbnail problems, also include the volume type and metadata-file setting.

Local thumbnail-operation diagnostics are at:

```text
~/Library/Containers/com.epsalmond.fujikage.quicklook/Data/Library/Logs/stamp.log
```

The thumbnail extension also logs to macOS Console under `com.epsalmond.fujikage.quicklook`. Logs can contain full file paths.

[GitHub Issues](https://github.com/epsalmond/fujikage-quicklook/issues) is the support channel for FujikageQL. Issues are public; review photos and logs for private information before attaching them. See the [privacy page](privacy.md) for details on local settings, logs, and file metadata.
