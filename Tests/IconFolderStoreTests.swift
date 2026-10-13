import XCTest
@testable import FujikageQL

@MainActor
final class IconFolderStoreTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let suite = "fkql-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }

    func testDecodesFirstReleaseFoldersWithoutNewerKeys() throws {
        let json = """
        [{"id":"7B0B1E2A-3A4B-4C5D-8E6F-000000000001","bookmark":"","displayPath":"/Volumes/tank/raw","fstype":"smbfs"}]
        """
        let folders = try JSONDecoder().decode([IconFolder].self, from: Data(json.utf8))
        XCTAssertEqual(folders.count, 1)
        XCTAssertEqual(folders[0].kind, .stamp)
        XCTAssertFalse(folders[0].allowSidecars)
        XCTAssertEqual(folders[0].lastNote, "")
        XCTAssertEqual(folders[0].displayPath, "/Volumes/tank/raw")
    }

    func testRoundTripsThroughDefaults() throws {
        let defaults = makeDefaults()
        let folder = IconFolder(bookmark: Data([1, 2]), displayPath: "/a/b", fstype: "apfs", kind: .ignore, allowSidecars: true, lastNote: "n")
        defaults.set(try JSONEncoder().encode([folder]), forKey: "iconFolders")
        let store = IconFolderStore(defaults: defaults)
        XCTAssertEqual(store.folders, [folder])
    }

    func testMigratesLegacyDenylistIntoIgnoreFolders() {
        let defaults = makeDefaults()
        defaults.set("/Volumes/tank/raw/skip\n\n  /Users/eric/Pictures/old  \n", forKey: "iconDenylist")
        let store = IconFolderStore(defaults: defaults)
        XCTAssertEqual(store.folders.map(\.displayPath), ["/Volumes/tank/raw/skip", "/Users/eric/Pictures/old"])
        XCTAssertTrue(store.folders.allSatisfy { $0.kind == .ignore })
        XCTAssertEqual(store.denylist, ["/Volumes/tank/raw/skip", "/Users/eric/Pictures/old"])
        XCTAssertNil(defaults.string(forKey: "iconDenylist"), "legacy key removed after migration")
        XCTAssertNotNil(defaults.data(forKey: "iconFolders"), "migrated folders saved")
    }

    func testOrderedFoldersNestsIgnoresUnderTheirStampFolder() throws {
        let defaults = makeDefaults()
        let stampA = IconFolder(bookmark: Data(), displayPath: "/Volumes/tank/raw", fstype: "smbfs")
        let ignoreA = IconFolder(bookmark: Data(), displayPath: "/Volumes/tank/raw/2025", fstype: "", kind: .ignore)
        let stampB = IconFolder(bookmark: Data(), displayPath: "/Users/eric/Pictures", fstype: "apfs")
        let orphan = IconFolder(bookmark: Data(), displayPath: "/elsewhere", fstype: "", kind: .ignore)
        defaults.set(try JSONEncoder().encode([ignoreA, orphan, stampA, stampB]), forKey: "iconFolders")
        let store = IconFolderStore(defaults: defaults)

        XCTAssertEqual(store.orderedFolders.map(\.id), [stampA.id, ignoreA.id, stampB.id, orphan.id])
        XCTAssertTrue(store.isNestedIgnore(ignoreA))
        XCTAssertFalse(store.isNestedIgnore(orphan))
        XCTAssertFalse(store.isNestedIgnore(stampA))
    }

    func testSetKindToIgnoreClearsNoteAndRemovePersists() throws {
        let defaults = makeDefaults()
        let folder = IconFolder(bookmark: Data(), displayPath: "/a", fstype: "apfs", lastNote: "stamped 3.")
        defaults.set(try JSONEncoder().encode([folder]), forKey: "iconFolders")
        let store = IconFolderStore(defaults: defaults)

        store.setKind(folder, .ignore)
        XCTAssertEqual(store.folders[0].kind, .ignore)
        XCTAssertEqual(store.folders[0].lastNote, "")
        store.remove(folder)
        XCTAssertTrue(store.folders.isEmpty)
        XCTAssertTrue(IconFolderStore(defaults: defaults).folders.isEmpty)
    }

    func testHandleDropStagesFolderWithoutStartingWork() throws {
        let defaults = makeDefaults()
        let store = IconFolderStore(defaults: defaults)
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("fkql-drop-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }

        store.handleDrop([folder])

        XCTAssertEqual(store.folders.map(\.displayPath), [folder.path])
        XCTAssertFalse(store.busy)
        XCTAssertNil(store.progress)
        XCTAssertEqual(store.status, "Added 1 folder. Choose Apply thumbnails when ready.")
    }

    func testResolvedExclusionFollowsRenamedChildAndParent() async throws {
        for renameParent in [false, true] {
            let container = try makeTempDir("excluded-rename")
            let root = container.appendingPathComponent("photos", isDirectory: true)
            let excluded = root.appendingPathComponent("private", isDirectory: true)
            try FileManager.default.createDirectory(at: excluded, withIntermediateDirectories: true)
            _ = try writeRAF(in: root, name: "allowed.RAF")
            _ = try writeRAF(in: excluded, name: "excluded.RAF")
            let store = IconFolderStore(defaults: makeDefaults())
            try store.add(url: excluded, kind: .ignore)

            let movedRoot: URL
            let movedExcluded: URL
            if renameParent {
                movedRoot = container.appendingPathComponent("renamed-photos", isDirectory: true)
                try FileManager.default.moveItem(at: root, to: movedRoot)
                movedExcluded = movedRoot.appendingPathComponent("private", isDirectory: true)
            } else {
                movedRoot = root
                movedExcluded = root.appendingPathComponent("renamed-private", isDirectory: true)
                try FileManager.default.moveItem(at: excluded, to: movedExcluded)
            }

            let found = try await store.withResolvedDenylist { denylist in
                XCTAssertEqual(denylist, [movedExcluded.path])
                return IconStamper.rafFiles(in: movedRoot, denylist: denylist)
            }
            XCTAssertEqual(found.map(\.lastPathComponent), ["allowed.RAF"])
            XCTAssertEqual(store.folders[0].displayPath, movedExcluded.path)
        }
    }

    func testUnavailableExclusionStopsWorkAndReleasesEarlierScopes() async throws {
        let root = try makeTempDir("excluded-unavailable")
        let defaults = makeDefaults()
        let access = AccessRecord()
        let store = IconFolderStore(defaults: defaults, bookmarkAccess: access.io)
        try store.add(url: root, kind: .ignore)
        var saved = store.folders
        saved.append(IconFolder(bookmark: Data([0]), displayPath: "/missing", fstype: "", kind: .ignore))
        defaults.set(try JSONEncoder().encode(saved), forKey: "iconFolders")
        let reloaded = IconFolderStore(defaults: defaults, bookmarkAccess: access.io)
        var worked = false

        do {
            try await reloaded.withResolvedDenylist { _ in worked = true }
            XCTFail("unavailable exclusion must stop the job")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("excluded folder /missing"))
        }
        XCTAssertFalse(worked)
        XCTAssertEqual(access.started, [root.path])
        XCTAssertEqual(access.stopped, [root.path])
    }

    func testSecurityScopeFailureForExclusionStopsWork() async throws {
        let root = try makeTempDir("excluded-access")
        let store = IconFolderStore(
            defaults: makeDefaults(),
            bookmarkAccess: FolderBookmarkAccess(start: { _ in false }, stop: { _ in XCTFail("no scope to stop") })
        )
        try store.add(url: root, kind: .ignore)
        var worked = false
        do {
            try await store.withResolvedDenylist { _ in worked = true }
            XCTFail("denied exclusion must stop the job")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("excluded folder"))
        }
        XCTAssertFalse(worked)
    }

    func testDeletedExcludedFolderStopsWork() async throws {
        let root = try makeTempDir("excluded-deleted")
        let excluded = root.appendingPathComponent("private", isDirectory: true)
        try FileManager.default.createDirectory(at: excluded, withIntermediateDirectories: true)
        let store = IconFolderStore(defaults: makeDefaults())
        try store.add(url: excluded, kind: .ignore)
        try FileManager.default.removeItem(at: excluded)
        var worked = false
        do {
            try await store.withResolvedDenylist { _ in worked = true }
            XCTFail("missing exclusion must stop the job")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("excluded folder"))
        }
        XCTAssertFalse(worked)
    }

    func testExclusionScopesAreHeldThroughWorkAndReleasedOnFailure() async throws {
        let root = try makeTempDir("excluded-scopes")
        let access = AccessRecord()
        let store = IconFolderStore(defaults: makeDefaults(), bookmarkAccess: access.io)
        try store.add(url: root, kind: .ignore)
        let failure = NSError(domain: "test-work", code: 1)
        do {
            try await store.withResolvedDenylist { _ in
                XCTAssertEqual(access.started, [root.path])
                XCTAssertTrue(access.stopped.isEmpty)
                throw failure
            } as Void
            XCTFail("work failure must propagate")
        } catch {
            XCTAssertEqual(error as NSError, failure)
        }
        XCTAssertEqual(access.stopped, [root.path])
    }
}

private final class AccessRecord: @unchecked Sendable {
    private let lock = NSLock()
    private var starts: [String] = []
    private var stops: [String] = []

    var io: FolderBookmarkAccess {
        FolderBookmarkAccess(start: { url in
            self.lock.lock()
            defer { self.lock.unlock() }
            self.starts.append(url.path)
            return true
        }, stop: { url in
            self.lock.lock()
            defer { self.lock.unlock() }
            self.stops.append(url.path)
        })
    }

    var started: [String] {
        lock.lock()
        defer { lock.unlock() }
        return starts
    }

    var stopped: [String] {
        lock.lock()
        defer { lock.unlock() }
        return stops
    }
}
