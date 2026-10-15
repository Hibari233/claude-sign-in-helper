import SwiftUI
import AppKit

/// Secondary screens, shown as sheets over the single sign-in screen.
enum HelperSheet: String, Identifiable {
    case backups, help
    var id: Self { self }
}
enum FlowStage { case welcome, ready, closeDesktop, existing, imported, verified, unconfirmed }

enum EngineResult {
    case inspection(Inspection), imported(SavedBackup), verified(Bool), backups([SavedBackup]), restored
}

/// Translates English text that arrives at runtime, such as the engine's error and progress messages.
/// The English text is the key in `Localizable.strings`, so the engine itself stays in English.
func localized(_ english: String) -> String {
    Bundle.main.localizedString(forKey: english, value: english, table: nil)
}

extension HelperFailure {
    /// macOS privacy protection blocked a read; Full Disk Access guidance applies.
    var needsDiskAccess: Bool { ["file_access", "database_access"].contains(code) }
}

final class HelperModel: ObservableObject {
    @Published var sheet: HelperSheet?
    @Published var stage: FlowStage = .welcome
    @Published var busy = false
    @Published var progress = ""
    @Published var problem: HelperFailure?
    @Published var desktopVersion = ""
    @Published var savedBackups: [SavedBackup] = []
    @Published var backupLoaded = false
    @Published var restoredNotice = false
    /// Set once Claude was opened from the helper after an import, so the flow moves on to verification.
    @Published var claudeOpened = false
    var preview = false

    func perform(_ label: String, operation: @escaping (SessionEngine) throws -> EngineResult) {
        guard !busy && !preview else { return }
        busy = true; progress = label; problem = nil
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let result = try operation(SessionEngine(paths: LocalPaths.discover()))
                DispatchQueue.main.async { self.accept(result); self.busy = false; self.progress = "" }
            } catch {
                let safe = readableFailure(error)
                DispatchQueue.main.async { self.problem = safe; self.busy = false; self.progress = "" }
            }
        }
    }
    func accept(_ result: EngineResult) {
        switch result {
        case .inspection(let inspection):
            desktopVersion = inspection.version; claudeOpened = false
            switch inspection.state { case .ready: stage = .ready; case .closeDesktop: stage = .closeDesktop; case .existingSession: stage = .existing }
        case .imported(let backup): savedBackups.insert(backup, at: 0); stage = .imported; claudeOpened = false
        case .verified(let observed): stage = observed ? .verified : .unconfirmed
        case .backups(let backups): savedBackups = backups; backupLoaded = true
        case .restored: restoredNotice = true; stage = .welcome; claudeOpened = false; refreshBackupsAfterRestore()
        }
    }
    func check() { perform("Checking this Mac…") { .inspection(try $0.inspect()) } }
    func transfer() {
        perform("Preparing the import…") { engine in
            .imported(try engine.repair { message in DispatchQueue.main.async { self.progress = message } })
        }
    }
    func verify() { perform("Checking Desktop’s sign-in…") { .verified(try $0.verify()) } }
    func loadBackups() { perform("Loading your private backups…") { .backups(try $0.backups()) } }
    func restore(_ backup: SavedBackup) { perform("Restoring the saved cookies…") { try $0.restore(backup.id); return .restored } }
    private func refreshBackupsAfterRestore() { DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { self.loadBackups() } }
    /// Backups has its own messages, so it starts clean and clears them when closed.
    /// Help leaves the sign-in screen's problem in place, since it explains how to fix it.
    func present(_ sheet: HelperSheet) {
        guard !(busy && sheet == .backups) else { return }
        if sheet == .backups { problem = nil; restoredNotice = false }
        self.sheet = sheet; lastSheet = sheet
        if sheet == .backups && !preview { loadBackups() }
    }
    func sheetDismissed() {
        if lastSheet == .backups { problem = nil; restoredNotice = false }
    }
    private var lastSheet: HelperSheet?
    func openClaude() {
        guard !preview else { return }
        do { NSWorkspace.shared.open(try LocalPaths.discover().app); claudeOpened = true; problem = nil }
        catch { problem = readableFailure(error) }
    }
    func openAccessSettings() {
        guard !preview, let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") else { return }
        NSWorkspace.shared.open(url)
    }
    func revealApp() { if !preview { NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL]) } }
    func revealBackups() {
        guard !preview else { return }
        do {
            let path = try LocalPaths.discover().backups
            if FileManager.default.fileExists(atPath: path.path) { NSWorkspace.shared.open(path) }
        } catch { problem = readableFailure(error) }
    }
    func openSupport() {
        if !preview, let url = URL(string: "https://support.claude.com/en/articles/13189465-log-in-to-your-claude-account") { NSWorkspace.shared.open(url) }
    }

    /// Demonstration states for `--render-preview`. They never touch real data.
    static func demonstration(_ scene: String) -> HelperModel {
        let model = HelperModel(); model.preview = true
        let version = "2.31226.1"
        switch scene {
        case "ready": model.stage = .ready; model.desktopVersion = version
        case "quit": model.stage = .closeDesktop; model.desktopVersion = version
        case "importing":
            model.stage = .ready; model.desktopVersion = version; model.busy = true; model.progress = "Waiting for macOS Keychain…"
        case "existing": model.stage = .existing; model.desktopVersion = version
        case "success": model.stage = .imported; model.desktopVersion = version
        case "opened": model.stage = .imported; model.desktopVersion = version; model.claudeOpened = true
        case "verified": model.stage = .verified; model.desktopVersion = version; model.claudeOpened = true
        case "unconfirmed": model.stage = .unconfirmed; model.desktopVersion = version; model.claudeOpened = true
        case "permission": model.problem = HelperFailure(code: "file_access", title: "macOS needs your permission", detail: "Safari protects its saved sign-in data. Open the access guide to allow this app to read it.")
        case "backups":
            model.sheet = .backups; model.backupLoaded = true
            model.savedBackups = [demonstrationBackup("20261012T120000Z", state: "committed"), demonstrationBackup("20261003T091500Z", state: "restored")]
        case "backups-empty": model.sheet = .backups; model.backupLoaded = true
        case "restored":
            model.sheet = .backups; model.backupLoaded = true; model.restoredNotice = true
            model.savedBackups = [demonstrationBackup("20261012T120000Z", state: "restored")]
        case "help": model.sheet = .help
        default: break
        }
        return model
    }
    private static func demonstrationBackup(_ stamp: String, state: String) -> SavedBackup {
        let manifest = BackupManifest(action: "import", state: state, createdUTC: stamp, profile: "PREVIEW", backupSHA256: "PREVIEW", logOffset: 0, importFingerprint: "PREVIEW", cookieNames: Format.names)
        return SavedBackup(id: stamp + "-abcdef12", manifest: manifest)
    }
}
