import SwiftUI

struct BackupsSheet: View {
    @ObservedObject var model: HelperModel
    @State private var candidate: SavedBackup?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Backups").font(.serif(22)).accessibilityAddTraits(.isHeader)
            Text("A backup is saved before every import. Restore one to undo it.")
                .font(.ui(12.5)).foregroundStyle(Palette.text3).fixedSize(horizontal: false, vertical: true).padding(.top, 4)
            status
            list.padding(.top, 14)
            Text("Quit Claude Desktop before restoring. Only the imported Claude cookies are replaced, and server sessions aren’t signed out.")
                .font(.ui(11.5)).foregroundStyle(Palette.text3).lineSpacing(1).fixedSize(horizontal: false, vertical: true).padding(.top, 12)
            HStack {
                Button("Show in Finder") { model.revealBackups() }.buttonStyle(LinkButtonStyle()).padding(.leading, -6)
                    .disabled(model.savedBackups.isEmpty || model.busy)
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(OutlineButtonStyle()).keyboardShortcut(.cancelAction)
            }
            .padding(.top, 18)
        }
        .padding(24).frame(width: 400)
        .background(Palette.canvas)
        .foregroundStyle(Palette.text)
        .alert(ConfirmCopy.restoreBackup.title, isPresented: Binding(get: { candidate != nil }, set: { if !$0 { candidate = nil } }),
               presenting: candidate) { backup in
            Button(ConfirmCopy.restoreBackup.action) { model.restore(backup) }.keyboardShortcut(.defaultAction)
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text(ConfirmCopy.restoreBackup.message)
        }
    }

    @ViewBuilder private var status: some View {
        if model.busy {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(localized(model.progress)).font(.ui(12)).foregroundStyle(Palette.text3)
            }
            .padding(.top, 12)
        } else if model.restoredNotice {
            Label("Import undone. The original cookies were restored.", systemImage: "checkmark.circle.fill")
                .font(.ui(12, weight: .medium)).foregroundStyle(Palette.success).padding(.top, 12)
        } else if let problem = model.problem {
            Label { (Text(localized(problem.title)).fontWeight(.semibold) + Text(verbatim: " ") + Text(localized(problem.detail))).fixedSize(horizontal: false, vertical: true) } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
            }
            .font(.ui(12)).foregroundStyle(Palette.warning).padding(.top, 12)
        }
    }

    @ViewBuilder private var list: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        if model.savedBackups.isEmpty {
            Text(model.backupLoaded ? String(localized: "No backups yet.") : String(localized: "Your backups will appear here."))
                .font(.ui(12.5)).foregroundStyle(Palette.text3)
                .frame(maxWidth: .infinity).frame(height: 64)
                .background(shape.fill(Palette.surface)).overlay(shape.strokeBorder(Palette.border))
        } else {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(model.savedBackups.enumerated()), id: \.element.id) { index, backup in
                        if index > 0 { Hairline() }
                        row(backup)
                    }
                }
            }
            .frame(height: min(CGFloat(model.savedBackups.count) * 56, 224))
            .background(shape.fill(Palette.surface)).overlay(shape.strokeBorder(Palette.border))
            .clipShape(shape)
        }
    }

    private func row(_ backup: SavedBackup) -> some View {
        let restored = backup.manifest.state == "restored"
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(backup.date.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? String(localized: "Saved import"))
                    .font(.ui(13, weight: .medium)).foregroundStyle(restored ? Palette.text3 : Palette.text)
                Text(restored ? String(localized: "Restored") : String(localized: "Before an import")).font(.ui(11.5)).foregroundStyle(Palette.text3)
            }
            Spacer(minLength: 8)
            if !restored {
                Button("Restore…") { candidate = backup }.buttonStyle(OutlineButtonStyle(height: 26))
                    .disabled(!backup.canRestore || model.busy)
            }
        }
        .padding(.horizontal, 14).frame(height: 55)
        .accessibilityElement(children: .contain)
    }
}
