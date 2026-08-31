import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var iconStore: IconFolderStore
    @State private var preview: PreviewState?
    @State private var pendingClear: IconFolder?
    @State private var dropTargeted = false
    @State private var dropIgnore = false

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 20)
                .padding(.vertical, 14)

            ScrollView {
                VStack(spacing: 16) {
                    quickLookCard
                    if !iconStore.status.isEmpty {
                        statusBanner
                    }
                    folderSection
                }
                .padding(.horizontal, 20)
                .padding(.bottom, iconStore.busy ? 54 : 20)
            }
        }
        .frame(minWidth: 560, minHeight: 500, alignment: .top)
        .background(Theme.background)
        .background(WindowConfigurator())
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
        .overlay {
            if dropTargeted, !iconStore.busy {
                RoundedRectangle(cornerRadius: Theme.radiusMD)
                    .strokeBorder(dropIgnore ? Theme.muted : Theme.accent, lineWidth: 2)
                    .padding(8)
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .bottom) {
            if iconStore.busy {
                progressBar
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { _ in
            guard !iconStore.busy else { return false }
            let folders = FolderDrop.foldersFromDragPasteboard()
            guard !folders.isEmpty else { return false }
            iconStore.handleDrop(folders, ignore: FolderDrop.optionHeld)
            return true
        }
        .onChange(of: dropTargeted) { _, targeted in
            dropIgnore = targeted && FolderDrop.optionHeld
        }
        .onExitCommand {
            if iconStore.busy {
                iconStore.stop()
            }
        }
        .sheet(item: $preview) { item in
            PreviewSheet(state: item)
        }
        .alert(item: $pendingClear) { folder in
            Alert(
                title: Text("Remove applied thumbnails?"),
                message: Text(
                    "This removes only thumbnails FujikageQL applied inside \(Self.shortName(folder.displayPath)) and its subfolders."
                ),
                primaryButton: .destructive(Text("Remove thumbnails")) {
                    iconStore.clear(folder)
                },
                secondaryButton: .cancel()
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .openRAF)) { note in
            if let url = note.object as? URL {
                load(url)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            AppIconMark()
                .frame(width: 30, height: 30)
            Text("FujikageQL")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.foreground)
            Spacer(minLength: 8)
            Button {
                if let url = URL(string: "https://fujikage.io/#quicklook") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Image(systemName: "questionmark.circle")
            }
            .buttonStyle(IconToolButtonStyle())
            .help("FujikageQL help")
        }
    }

    private var quickLookCard: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "eye.fill")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 36, height: 36)
                .background(Theme.accent.opacity(0.13))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 7) {
                Text("Preview compressed Fujifilm RAF files")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.foreground)
                Text("Select a RAF file in Finder and press Space. FujikageQL shows the JPEG stored in the file without rewriting the RAF image data.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.foreground2)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Button("Choose a RAF…") { openRAF() }
                        .buttonStyle(.borderedProminent)
                    Text("If previews are missing, enable FujikageQL in System Settings › General › Login Items & Extensions.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface2)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusMD)
                .stroke(Theme.hairline, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMD))
    }

    private var statusBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(Theme.accent)
            Text(iconStore.status)
                .font(.system(size: 12))
                .foregroundStyle(Theme.foreground2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button {
                iconStore.clearStatus()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.muted)
            .help("Dismiss")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Theme.surface2.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSM))
    }

    private var folderSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Finder thumbnails")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.foreground)
                    Text("Optional. Apply thumbnails only when Finder's icon grid stays blank.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 12)
                Menu {
                    Button("Add folder…") { iconStore.addFolder() }
                    Button("Add excluded folder…") { iconStore.addFolder(kind: .ignore) }
                } label: {
                    Label("Add folder", systemImage: "plus")
                }
                .menuStyle(.button)
                .disabled(iconStore.busy)
            }

            if iconStore.folders.isEmpty {
                emptyDrop
            } else {
                VStack(spacing: 8) {
                    ForEach(iconStore.orderedFolders) { folder in
                        folderRow(folder)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyDrop: some View {
        VStack(spacing: 9) {
            Image(systemName: dropIgnore ? "folder.badge.minus" : "folder.badge.plus")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(dropTargeted ? (dropIgnore ? Theme.muted : Theme.accent) : Theme.muted)
            Text(dropIgnore ? "Drop to exclude this folder" : "No folders added")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.foreground2)
            Text("Drop a folder here or choose Add folder. Nothing changes until you apply thumbnails.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .frame(maxWidth: .infinity, minHeight: 150)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusMD)
                .strokeBorder(
                    dropTargeted ? Theme.accent : Theme.hairline2,
                    style: StrokeStyle(lineWidth: 1, dash: [6, 5])
                )
        )
    }

    private var progressBar: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
                .tint(Theme.accent)
            Text(iconStore.progress?.label ?? "…")
                .font(.system(size: Theme.caption, design: .monospaced))
                .foregroundStyle(Theme.foreground2)
                .lineLimit(1)
            Spacer(minLength: 8)
            Button {
                iconStore.stop()
            } label: {
                Image(systemName: "xmark")
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(IconToolButtonStyle())
            .help("Stop")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Theme.surface2)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Theme.hairline)
                .frame(height: 1)
        }
    }

    private func folderRow(_ folder: IconFolder) -> some View {
        let ignore = folder.kind == .ignore
        return HStack(spacing: 10) {
            if ignore {
                Image(systemName: "folder.badge.minus")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.muted)
                    .frame(width: 18)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(Self.shortName(folder.displayPath))
                    .font(.system(size: Theme.body, weight: .medium))
                    .foregroundStyle(ignore ? Theme.muted : Theme.foreground)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if !ignore, !folder.lastNote.isEmpty {
                    Text(folder.lastNote)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(2)
                        .truncationMode(.tail)
                }
            }
            Spacer(minLength: 8)
            if !ignore {
                Button("Apply thumbnails") { iconStore.stamp(folder) }
                    .buttonStyle(.borderedProminent)
                    .disabled(iconStore.busy)
            }
            Menu {
                if ignore {
                    Button("Include for thumbnails") { iconStore.setKind(folder, .stamp) }
                } else {
                    Button("Exclude this folder") { iconStore.setKind(folder, .ignore) }
                    Divider()
                    Toggle(
                        "Allow ._ metadata files",
                        isOn: Binding(
                            get: { folder.allowSidecars },
                            set: { iconStore.setAllowSidecars(folder, $0) }
                        )
                    )
                    Button("Remove applied thumbnails…") { pendingClear = folder }
                }
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting(
                        [URL(fileURLWithPath: folder.displayPath)]
                    )
                }
                Divider()
                Button("Remove from list", role: .destructive) { iconStore.remove(folder) }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.foreground2)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 28, height: 28)
            .disabled(iconStore.busy)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .padding(.leading, iconStore.isNestedIgnore(folder) ? 22 : 0)
        .background(Theme.surface2)
        .opacity(ignore ? 0.72 : 1)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusSM)
                .stroke(Theme.hairline, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSM))
    }

    private static func shortName(_ path: String) -> String {
        let url = URL(fileURLWithPath: path)
        let last = url.lastPathComponent
        let parent = url.deletingLastPathComponent().lastPathComponent
        if parent.isEmpty || parent == "/" { return last }
        return parent + "/" + last
    }

    private func openRAF() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        var types: [UTType] = []
        if let ours = UTType("com.epsalmond.fujikage.raf") {
            types.append(ours)
        }
        if let raf = UTType("com.fuji.raw-image") {
            types.append(raf)
        }
        if let ext = UTType(filenameExtension: "raf") {
            types.append(ext)
        }
        panel.allowedContentTypes = types.isEmpty ? [.data] : types
        guard panel.runModal() == .OK, let url = panel.url else { return }
        load(url)
    }

    private func load(_ url: URL) {
        do {
            let jpeg = try RAFEmbeddedJPEG.jpegData(from: url)
            guard let image = NSImage(data: jpeg) else {
                preview = nil
                iconStore.status = "\(url.lastPathComponent): The embedded preview could not be displayed."
                return
            }
            let size = RAFEmbeddedJPEG.displaySize(ofJPEG: jpeg)
            let megabytes = Double(jpeg.count) / 1_048_576
            let sizeText: String
            if let size {
                sizeText = "\(Int(size.width))×\(Int(size.height))  \(String(format: "%.1f", megabytes)) MB"
            } else {
                sizeText = String(format: "%.1f MB", megabytes)
            }
            iconStore.clearStatus()
            preview = PreviewState(name: url.lastPathComponent, image: image, summary: sizeText)
        } catch {
            preview = nil
            iconStore.status = "\(url.lastPathComponent): \(error.localizedDescription)"
        }
    }
}

private struct PreviewSheet: View {
    let state: PreviewState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 10) {
            Text(state.name)
                .font(.system(size: Theme.caption, design: .monospaced))
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
            Image(nsImage: state.image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 720, maxHeight: 420)
            Text(state.summary)
                .font(.system(size: Theme.micro, design: .monospaced))
                .foregroundStyle(Theme.muted)
        }
        .padding(16)
        .background(Theme.background)
        .preferredColorScheme(.dark)
        .onExitCommand { dismiss() }
    }
}

private struct PreviewState: Identifiable {
    let id = UUID()
    let name: String
    let image: NSImage
    let summary: String
}
