import AppKit
import SwiftUI

extension Notification.Name {
    static let openRAF = Notification.Name("FujikageQL.openRAF")
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var iconStore: IconFolderStore?
    private var pendingFolders: [URL] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .darkAqua)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        let folders = urls.filter { IconStampPolicy.isStampableFolder($0) }
        let files = urls.filter { !IconStampPolicy.isStampableFolder($0) }
        if !folders.isEmpty {
            if let iconStore {
                Task { @MainActor in
                    iconStore.handleDrop(folders)
                }
            } else {
                pendingFolders.append(contentsOf: folders)
            }
        }
        if let url = files.first {
            NotificationCenter.default.post(name: .openRAF, object: url)
        }
    }

    func takePendingFolders() -> [URL] {
        defer { pendingFolders.removeAll() }
        return pendingFolders
    }
}

@main
struct FujikageQLApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var iconStore = IconFolderStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(iconStore)
                .onAppear {
                    appDelegate.iconStore = iconStore
                    let pending = appDelegate.takePendingFolders()
                    if !pending.isEmpty {
                        iconStore.handleDrop(pending)
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 520, height: 400)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Add Folder…") {
                    iconStore.addFolder()
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
                Button("Stop") {
                    iconStore.stop()
                }
                .keyboardShortcut(".")
                .disabled(!iconStore.busy)
            }
        }
    }
}
