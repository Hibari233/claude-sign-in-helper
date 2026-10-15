import SwiftUI

struct HelperRootView: View {
    static let size = CGSize(width: 440, height: 480)
    @ObservedObject var model: HelperModel
    @State private var confirmImport = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 28) // Clears the transparent title bar.
            SignInView(model: model) { confirmImport = true }
            Spacer(minLength: 16)
            HStack(spacing: 2) {
                Button("Backups") { model.present(.backups) }.disabled(model.busy)
                Text(verbatim: "·").foregroundStyle(Palette.text3).accessibilityHidden(true)
                Button("How it works") { model.present(.help) }
            }
            .buttonStyle(LinkButtonStyle())
            .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.canvas)
        .foregroundStyle(Palette.text)
        .tint(Palette.accent)
        .ignoresSafeArea()
        .sheet(item: $model.sheet, onDismiss: model.sheetDismissed) { sheet in
            HelperSheetView(sheet: sheet, model: model)
        }
        .alert(ConfirmCopy.importSignIn.title, isPresented: $confirmImport) {
            Button(ConfirmCopy.importSignIn.action) { model.transfer() }.keyboardShortcut(.defaultAction)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(ConfirmCopy.importSignIn.message)
        }
    }
}

struct HelperSheetView: View {
    let sheet: HelperSheet
    @ObservedObject var model: HelperModel
    var body: some View {
        switch sheet {
        case .backups: BackupsSheet(model: model)
        case .help: HelpSheet(model: model)
        }
    }
}

/// Wording for the two confirmations, shared by the app's alerts and the preview renderer.
struct ConfirmCopy {
    let title: String
    let message: String
    let action: String

    static let importSignIn = ConfirmCopy(
        title: String(localized: "Import your Safari sign-in?"),
        message: String(localized: "A private backup is saved first, so you can undo this. If macOS asks about “Claude Safe Storage,” choose Allow, and type your password only in that macOS dialog. Keep Claude Desktop closed until it finishes."),
        action: String(localized: "Import"))
    static let restoreBackup = ConfirmCopy(
        title: String(localized: "Undo this import?"),
        message: String(localized: "Quit Claude Desktop first. Only the imported Claude cookies are replaced, and nothing changes if Desktop has a newer sign-in. This doesn’t sign out server sessions."),
        action: String(localized: "Restore"))

    static func demonstration(_ scene: String) -> ConfirmCopy? {
        switch scene {
        case "confirm-import": return importSignIn
        case "confirm-restore": return restoreBackup
        default: return nil
        }
    }
}
