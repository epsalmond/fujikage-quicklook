import AppKit
import Foundation

enum FolderKind: String, Codable, Equatable, Sendable {
    case stamp
    case ignore
}

struct IconFolder: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var bookmark: Data
    var displayPath: String
    var fstype: String
    var kind: FolderKind
    var allowSidecars: Bool
    var lastNote: String

    init(
        id: UUID = UUID(),
        bookmark: Data,
        displayPath: String,
        fstype: String,
        kind: FolderKind = .stamp,
        allowSidecars: Bool = false,
        lastNote: String = ""
    ) {
        self.id = id
        self.bookmark = bookmark
        self.displayPath = displayPath
        self.fstype = fstype
        self.kind = kind
        self.allowSidecars = allowSidecars
        self.lastNote = lastNote
    }

    /// `kind`, `allowSidecars`, `lastNote` were added after the first release;
    /// older saved folders lack them.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        bookmark = try c.decode(Data.self, forKey: .bookmark)
        displayPath = try c.decode(String.self, forKey: .displayPath)
        fstype = try c.decode(String.self, forKey: .fstype)
        kind = try c.decodeIfPresent(FolderKind.self, forKey: .kind) ?? .stamp
        allowSidecars = try c.decodeIfPresent(Bool.self, forKey: .allowSidecars) ?? false
        lastNote = try c.decodeIfPresent(String.self, forKey: .lastNote) ?? ""
    }
}

private final class JobHandle: @unchecked Sendable {
    let id = UUID()
    private let lock = NSLock()
    private var cancelled = false
    var onProgress: (@Sendable (StampProgress) -> Void)?

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func report(_ progress: StampProgress) {
        onProgress?(progress)
    }
}

@MainActor
final class IconFolderStore: ObservableObject {
    @Published private(set) var folders: [IconFolder] = []
    @Published var status: String = ""
    @Published private(set) var busy = false
    @Published private(set) var progress: StampProgress?

    private let foldersKey = "iconFolders"
    private let denylistKey = "iconDenylist"
    private let defaults: UserDefaults
    private var job: JobHandle?
    private var runLoop: Task<Void, Never>?

    var denylist: [String] {
        folders.filter { $0.kind == .ignore }.map(\.displayPath)
    }

    var orderedFolders: [IconFolder] {
        let stamp = folders.filter { $0.kind == .stamp }
        let ignore = folders.filter { $0.kind == .ignore }
        var seen = Set<UUID>()
        var result: [IconFolder] = []
        for s in stamp {
            result.append(s)
            seen.insert(s.id)
            for ign in ignore where !seen.contains(ign.id) {
                if Self.isNested(ign.displayPath, under: s.displayPath) {
                    result.append(ign)
                    seen.insert(ign.id)
                }
            }
        }
        result.append(contentsOf: ignore.filter { !seen.contains($0.id) })
        return result
    }

    func isNestedIgnore(_ folder: IconFolder) -> Bool {
        folder.kind == .ignore && folders.contains {
            $0.kind == .stamp && Self.isNested(folder.displayPath, under: $0.displayPath)
        }
    }

    private static func isNested(_ child: String, under parent: String) -> Bool {
        IconStampPolicy.isDenied(URL(fileURLWithPath: child), prefixes: [parent])
            && (child as NSString).standardizingPath.caseInsensitiveCompare(
                (parent as NSString).standardizingPath
            ) != .orderedSame
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    func addFolder(kind: FolderKind = .stamp) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = kind == .ignore ? "Exclude" : "Add"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            _ = try add(url: url, kind: kind)
            status = kind == .ignore
                ? "Excluded \(url.lastPathComponent)."
                : "Added \(url.lastPathComponent). Choose Apply thumbnails when ready."
        } catch {
            status = error.localizedDescription
        }
    }

    @discardableResult
    func add(url: URL, kind: FolderKind = .stamp) throws -> IconFolder {
        let folderURL = url.standardizedFileURL
        let accessed = folderURL.startAccessingSecurityScopedResource()
        defer {
            if accessed { folderURL.stopAccessingSecurityScopedResource() }
        }
        let path = folderURL.path
        let existing = folders.first { $0.displayPath == path }
        let bookmark = try folderURL.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        let facts = VolumeFacts.inspect(folderURL)
        let note: String
        if kind == .ignore {
            note = existing?.kind == .ignore ? existing?.lastNote ?? "" : ""
        } else {
            switch facts.disposition {
            case .allow:
                note = facts.summary
            case .deny(let reason):
                note = "\(facts.summary). \(reason)"
            case .probeRequired:
                note = facts.summary
            }
        }
        folders.removeAll { $0.displayPath == path }
        let folder = IconFolder(
            bookmark: bookmark,
            displayPath: path,
            fstype: facts.fstype,
            kind: kind,
            allowSidecars: existing?.allowSidecars ?? false,
            lastNote: note
        )
        folders.append(folder)
        save()
        return folder
    }

    func handleDrop(_ urls: [URL], ignore: Bool = false) {
        let dropped = urls.filter { IconStampPolicy.isStampableFolder($0) }
        guard !dropped.isEmpty else { return }
        var added = 0
        for url in dropped {
            do {
                _ = try add(url: url, kind: ignore ? .ignore : .stamp)
                added += 1
            } catch {
                status = error.localizedDescription
                return
            }
        }
        let noun = added == 1 ? "folder" : "folders"
        status = ignore
            ? "Excluded \(added) \(noun)."
            : "Added \(added) \(noun). Choose Apply thumbnails when ready."
    }

    func clearStatus() {
        status = ""
    }

    func stop() {
        job?.cancel()
        runLoop?.cancel()
    }

    func remove(_ folder: IconFolder) {
        folders.removeAll { $0.id == folder.id }
        save()
    }

    func setAllowSidecars(_ folder: IconFolder, _ allow: Bool) {
        guard let i = folders.firstIndex(where: { $0.id == folder.id }) else { return }
        folders[i].allowSidecars = allow
        save()
    }

    func setKind(_ folder: IconFolder, _ kind: FolderKind) {
        guard let i = folders.firstIndex(where: { $0.id == folder.id }) else { return }
        folders[i].kind = kind
        if kind == .ignore { folders[i].lastNote = "" }
        save()
    }

    func stamp(_ folder: IconFolder) {
        guard folder.kind == .stamp else { return }
        replaceJob { await self.performStamp(folder) }
    }

    func clear(_ folder: IconFolder) {
        replaceJob { await self.performClear(folder) }
    }

    /// One job at a time. A new request cancels the running job and starts
    /// once it has wound down.
    private func replaceJob(_ body: @escaping @MainActor () async -> Void) {
        job?.cancel()
        runLoop?.cancel()
        let previous = runLoop
        runLoop = Task { @MainActor in
            await previous?.value
            guard !Task.isCancelled else { return }
            await body()
        }
    }

    private func performStamp(_ folder: IconFolder) async {
        await run(folder) { resolved, allow, denylist, handle in
            handle.report(.listing)
            let facts = VolumeFacts.inspect(resolved)
            if case .deny(let reason) = facts.disposition, !allow {
                throw IconStampError.denied(reason)
            }
            let files = IconStamper.rafFiles(
                in: resolved,
                denylist: denylist,
                isCancelled: { handle.isCancelled }
            )
            if handle.isCancelled { return StampReport(cancelled: true) }
            if files.isEmpty { throw IconStampError.noRAF }
            StampLog.notice(
                "stamp \(resolved.path) fstype=\(facts.fstype) local=\(facts.isLocal) files=\(files.count) sidecars=\(allow)"
            )
            if !allow, case .probeRequired = facts.disposition {
                try IconStamper.probeVolume(files)
            }
            return IconStamper.stamp(
                files: files,
                denylist: denylist,
                allowSidecars: allow,
                progress: { current, total, name in
                    handle.report(StampProgress(
                        listing: false,
                        current: current,
                        total: total,
                        filename: name
                    ))
                },
                isCancelled: { handle.isCancelled }
            )
        }
    }

    private func performClear(_ folder: IconFolder) async {
        await run(folder) { resolved, _, denylist, handle in
            handle.report(.listing)
            let files = IconStamper.rafFiles(
                in: resolved,
                denylist: denylist,
                isCancelled: { handle.isCancelled }
            )
            if handle.isCancelled { return StampReport(cancelled: true) }
            return IconStamper.clear(
                files: files,
                denylist: denylist,
                progress: { current, total, name in
                    handle.report(StampProgress(
                        listing: false,
                        current: current,
                        total: total,
                        filename: name
                    ))
                },
                isCancelled: { handle.isCancelled }
            )
        }
    }

    private func run(
        _ folder: IconFolder,
        work: @escaping @Sendable (URL, Bool, [String], JobHandle) throws -> StampReport
    ) async {
        let handle = JobHandle()
        let jobID = handle.id
        handle.onProgress = { [weak self] progress in
            Task { @MainActor in
                guard let self, self.job?.id == jobID else { return }
                self.progress = progress
            }
        }
        job = handle
        busy = true
        progress = .listing

        let denylist = self.denylist
        let allow = folder.allowSidecars
        var note = folder.lastNote
        do {
            let resolved = try resolveAndAccess(folder)
            defer { resolved.stopAccessingSecurityScopedResource() }
            StampLog.notice("access \(resolved.path)")
            let report = try await withCheckedThrowingContinuation { continuation in
                IconStamper.queue.async {
                    do {
                        continuation.resume(returning: try work(resolved, allow, denylist, handle))
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
            note = report.summary
            if !report.notes.isEmpty {
                note += " " + report.notes.prefix(3).joined(separator: " ")
            }
            status = note
            StampLog.notice("done \(folder.displayPath) \(note)")
        } catch {
            note = error.localizedDescription
            status = note
            StampLog.error("job \(folder.displayPath) \(error.stampDetail)")
        }
        if let i = folders.firstIndex(where: { $0.id == folder.id }) {
            folders[i].lastNote = note
            save()
        }
        if job?.id == jobID {
            busy = false
            progress = nil
            job = nil
        }
    }

    /// Start the security scope before refreshing a stale bookmark. Reinstall
    /// marks bookmarks stale; `bookmarkData` without access throws
    /// "The file couldn’t be opened."
    private func resolveAndAccess(_ folder: IconFolder) throws -> URL {
        var stale = false
        let url = try URL(
            resolvingBookmarkData: folder.bookmark,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        )
        let accessed = url.startAccessingSecurityScopedResource()
        guard accessed else {
            StampLog.error("startAccessing failed \(url.path)")
            throw IconStampError.denied("Could not open \(url.path). Drop the folder again.")
        }
        if stale, let i = folders.firstIndex(where: { $0.id == folder.id }) {
            do {
                folders[i].bookmark = try url.bookmarkData(
                    options: .withSecurityScope,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
                folders[i].displayPath = url.path
                StampLog.notice("refreshed stale bookmark \(url.path)")
            } catch {
                StampLog.error("bookmark refresh \(url.path) \(error.stampDetail)")
            }
        }
        return url
    }

    private func load() {
        if let data = defaults.data(forKey: foldersKey),
           let decoded = try? JSONDecoder().decode([IconFolder].self, from: data)
        {
            folders = decoded
        }
        let leftover = defaults.string(forKey: denylistKey) ?? ""
        if !leftover.isEmpty {
            for line in leftover.split(whereSeparator: \.isNewline) {
                let path = (String(line) as NSString).standardizingPath
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !path.isEmpty, !folders.contains(where: { $0.displayPath == path }) else { continue }
                folders.append(
                    IconFolder(bookmark: Data(), displayPath: path, fstype: "", kind: .ignore)
                )
            }
            defaults.removeObject(forKey: denylistKey)
            save()
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(folders) {
            defaults.set(data, forKey: foldersKey)
        }
    }
}
