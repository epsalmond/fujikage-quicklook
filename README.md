# FujikageQL

macOS Quick Look host for Fujifilm `.raf`. Spacebar preview reads the JPEG Fuji already stored in the file. It does not decode the sensor payload. It does not rewrite the RAF data fork.

Apple's Quick Look handles uncompressed RAF and fails on compressed RAF. This is a native Mac app. Fujikage on Mac is Designed for iPad, so that binary cannot host Quick Look extensions.

## Preview

The extractor range-reads the 92-byte header plus the JPEG. It does not pull the rest of the file.

Header layout matches exiftool `Image::ExifTool::FujiFilm::RAFHeader` in `FujiFilm.pm` and dcraw `parse_fuji`: magic `FUJIFILMCCD-RAW` at byte 0, JPEG offset `u32-BE` at `0x54`, length at `0x58`.

The preview extension claims Apple's `com.fuji.raw-image` and an exported `com.epsalmond.fujikage.raf` (conforms to `public.data`). It does not replace Apple's type.

A thumbnail extension ships in the same bundle and range-reads the same JPEG. QuickLookThumbnailing calls it when Finder asks.

## Finder icons

Stamp local APFS and HFS+ if the icon grid stays empty. Finder icon view on those volumes still uses Apple's RAW thumbnailer for `com.fuji.raw-image` and does not ask FujikageQL. Stamp writes `com.apple.FinderInfo` plus an icns resource fork as extended attributes. Already-stamped files are skipped. RAF bytes do not change.

Do not stamp network shares. On NFS, Finder asks the thumbnail extension and icons fill in with no xattrs. A stamp there would write `._` AppleDouble files. The host skips NFS unless ⋯ → ._ sidecars is on. macOS NFS writes `._` files, not ZFS attributes. SMB with vfs_fruit is the ZFS path.

The thumbnailer only runs on a Mac with FujikageQL enabled. Stamped icons travel with the file.

SMB is untested for the thumbnailer. Try without stamping first. The host probes one SMB file before writing. FAT, exFAT, and File Provider skip unless sidecars are on.

Drop a folder on the window, or press +. Option-drop, or ⋯ → Ignore, adds a skip folder. Nested ignores sit under the stamp folder they exclude. Stamp walks the tree and skips those prefixes.

Stamp also writes a `com.epsalmond.fujikage.stamp` xattr as provenance. ⋯ → Clear only removes icons that carry it, and only deletes a `._` sidecar the marker says we created. Icons set by Finder or another tool stay.

AirDrop often lands files mode `0444`. Stamp adds owner-write for the attribute write, then restores the original mode.

## Build

macOS 14 or later. Xcode with an Apple Development identity. [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

Signing team is `KA3Y4C7M3R`. Bundle id is `com.epsalmond.fujikage.quicklook`. If that is not your team, set `TEAM` and the bundle ids in `Makefile` and `project.yml` before building. The pluginkit ids in the Makefile must match.

```
make test
make install
```

`make test` and `make install` are arm64. `make install` builds Release, copies `~/Applications/FujikageQL.app`, registers the extensions with pluginkit, and opens the app.

`make reset-ql` reloads Quick Look and Finder.

If spacebar preview is missing: System Settings → General → Login Items & Extensions, enable FujikageQL.

## Check

```
make test
qlmanage -p /path/to/file.RAF
```

Stamp failures are in `~/Library/Containers/com.epsalmond.fujikage.quicklook/Data/Library/Logs/stamp.log`. ⋯ → Open RAF extracts the same JPEG the preview extension uses.

`FUJIKAGE_TEST_RAF=/path/to/DSCF0001.RAF make test` also runs the real-camera-file test; without it that test skips.

XcodeGen reads `project.yml`. Swift 6, warnings as errors. JPEG parse is `Sources/RAFJPEG`. Preview and thumbnail extensions are `Sources/Preview` and `Sources/Thumbnail`. The drop-target host and stamper are `Sources/Host`. Tests are in `Tests/`.
