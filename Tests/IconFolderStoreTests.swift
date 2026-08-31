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
}
