import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var iconStore: IconFolderStore
    @State private var preview: PreviewState?
    @State private var dropTargeted = false
    @State private var dropIgnore = false

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.top, 10)
                .padding(.horizontal, 14)
                .padding(.bottom, 10)

            folderArea
                .padding(.horizontal, 14)
                .padding(.bottom, iconStore.busy ? 8 : 14)
        }
        .frame(minWidth: 480, minHeight: 340, alignment: .top)
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
        .onReceive(NotificationCenter.default.publisher(for: .openRAF)) { note in
            if let url = note.object as? URL {
                load(url)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button {
                if let url = URL(string: "https://fujikage.io/#quicklook") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                AppIconMark()
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("fujikage.io")
            Text("FujikageQL")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.foreground)
            Spacer(minLength: 8)
            Button {
                iconStore.addFolder()
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(IconToolButtonStyle())
            .help("Add folder")
            .disabled(iconStore.busy)
            Menu {
                Button("Open RAF") { openRAF() }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.foreground2)
                    .frame(width: 28, height: 28)
                    .background(Theme.surface2)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Theme.hairline, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 28, height: 28)
        }
    }

    private var folderArea: some View {
        Group {
            if iconStore.folders.isEmpty {
                emptyDrop
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(iconStore.orderedFolders) { folder in
                            folderRow(folder)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyDrop: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.radiusMD)
                .strokeBorder(
                    dropTargeted ? Theme.accent : Theme.hairline2,
                    style: StrokeStyle(lineWidth: 1, dash: [6, 5])
                )
            Image(systemName: dropIgnore ? "folder.badge.minus" : "folder.badge.plus")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(dropTargeted ? (dropIgnore ? Theme.muted : Theme.accent) : Theme.muted)
        }
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
                        .font(.system(size: Theme.micro, design: .monospaced))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            Spacer(minLength: 8)
            if !ignore {
                Button("Stamp") { iconStore.stamp(folder) }
                    .buttonStyle(AccentButtonStyle())
                    .disabled(iconStore.busy)
            }
            Menu {
                if ignore {
                    Button("Stamp") { iconStore.setKind(folder, .stamp) }
                } else {
                    Button("Ignore") { iconStore.setKind(folder, .ignore) }
                    Toggle(
                        "._ sidecars",
                        isOn: Binding(
                            get: { folder.allowSidecars },
                            set: { iconStore.setAllowSidecars(folder, $0) }
                        )
                    )
                    Button("Clear") { iconStore.clear(folder) }
                }
                Button("Reveal") {
                    NSWorkspace.shared.activateFileViewerSelecting(
                        [URL(fileURLWithPath: folder.displayPath)]
                    )
                }
                Divider()
                Button("Remove", role: .destructive) { iconStore.remove(folder) }
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
            guard let image = NSImage(data: jpeg) else { return }
            let size = RAFEmbeddedJPEG.displaySize(ofJPEG: jpeg)
            let megabytes = Double(jpeg.count) / 1_048_576
            let sizeText: String
            if let size {
                sizeText = "\(Int(size.width))×\(Int(size.height))  \(String(format: "%.1f", megabytes)) MB"
            } else {
                sizeText = String(format: "%.1f MB", megabytes)
            }
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


