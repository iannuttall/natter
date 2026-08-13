import NatterCore
import SwiftUI

struct ModelPackAction: View {
    @Bindable var modelManager: ModelManager
    let pack: ModelPack
    var allowsRemoval = true
    var downloadTitle: String = "Download"
    var usesProminentButton = false

    @ViewBuilder
    var body: some View {
        if modelManager.removing == pack {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text("Removing…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else if modelManager.installing == pack {
            VStack(alignment: .trailing, spacing: usesProminentButton ? 6 : 4) {
                ProgressView(value: modelManager.progress)
                    .frame(width: usesProminentButton ? 130 : 110)
                Text(modelManager.status)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Button("Cancel") { modelManager.cancelInstallation() }
                    .controlSize(.small)
            }
        } else if modelManager.isInstalled(pack) {
            if allowsRemoval {
                HStack(spacing: 8) {
                    installedLabel
                        .font(.caption)
                    Button("Remove", role: .destructive) {
                        modelManager.remove(pack)
                    }
                    .controlSize(.small)
                }
            } else {
                installedLabel
            }
        } else {
            if usesProminentButton {
                installButton
                    .buttonStyle(.borderedProminent)
            } else {
                installButton
            }
        }
    }

    private var installButton: some View {
        Button(downloadTitle) {
            modelManager.install(pack)
        }
        .disabled(modelManager.installing != nil || modelManager.removing != nil)
    }

    private var installedLabel: some View {
        Label("Installed", systemImage: "checkmark.circle.fill")
            .foregroundStyle(.green)
    }
}
