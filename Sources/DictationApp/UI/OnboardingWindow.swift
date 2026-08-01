import AppKit
import DictationCore
import SwiftUI

private struct OnboardingView: View {
    @Bindable var store: DictationStore
    @Bindable var modelManager: ModelManager
    @Bindable var permissions: PermissionController
    @Bindable var onboarding: OnboardingManager
    let dismiss: () -> Void

    @State private var practiceText = ""
    @FocusState private var practiceIsFocused: Bool

    private var snapshot: OnboardingSnapshot {
        onboarding.snapshot(modelManager: modelManager, permissions: permissions)
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 760, height: 560)
        .background(Theme.Colour.panel)
        .task {
            while !Task.isCancelled {
                permissions.refresh()
                modelManager.refresh()
                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    break
                }
            }
        }
        .onChange(of: snapshot.currentStep) { _, step in
            if step == .practice {
                store.select(.raw)
                Task { @MainActor in practiceIsFocused = true }
            }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(AppInfo.displayName, systemImage: "waveform")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Theme.Colour.accent)
                .padding(.bottom, 18)

            stepLabel(.welcome, title: "Welcome", symbol: "hand.wave")
            stepLabel(.speechModel, title: "Speech", symbol: "waveform.badge.mic")
            stepLabel(.permissions, title: "Permissions", symbol: "checkmark.shield")
            stepLabel(.practice, title: "Try it", symbol: "keyboard")
            stepLabel(.writingModel, title: "Writing tools", symbol: "text.badge.star")

            Spacer()
            Text("Local by design")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("No account or cloud inference")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(24)
        .frame(width: 190, alignment: .leading)
        .background(Theme.Colour.secondaryPanel)
    }

    @ViewBuilder
    private func stepLabel(
        _ step: OnboardingStep,
        title: String,
        symbol: String
    ) -> some View {
        let current = snapshot.currentStep
        let complete = stepIndex(step) < stepIndex(current)
        HStack(spacing: 10) {
            Image(systemName: complete ? "checkmark.circle.fill" : symbol)
                .foregroundStyle(current == step || complete
                    ? Theme.Colour.accent
                    : Color.secondary)
                .frame(width: 20)
            Text(title)
                .fontWeight(current == step ? .semibold : .regular)
                .foregroundStyle(current == step ? .primary : .secondary)
        }
        .padding(.vertical, 5)
    }

    private func stepIndex(_ step: OnboardingStep) -> Int {
        OnboardingStep.allCases.firstIndex(of: step) ?? 0
    }

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: 22) {
            switch snapshot.currentStep {
            case .welcome:
                welcome
            case .speechModel:
                speechModel
            case .permissions:
                permissionSetup
            case .practice:
                practice
            case .writingModel:
                writingModel
            case .ready:
                ready
            }
        }
        .padding(36)
    }

    private var welcome: some View {
        setupPage(
            title: "Dictation without the cloud",
            detail: "Speech, corrections and optional writing cleanup stay on this Mac. Models download once and live in Application Support.",
            symbol: "lock.laptopcomputer"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                feature("Fast live Raw dictation", symbol: "bolt.fill")
                feature("Agent, Clean, Email and Article modes", symbol: "slider.horizontal.3")
                feature("Private local history and dictionary", symbol: "externaldrive.fill")
            }
            Spacer()
            HStack {
                Spacer()
                Button("Continue") { onboarding.acceptWelcome() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
        }
    }

    private var speechModel: some View {
        setupPage(
            title: "Install live speech",
            detail: "Nemotron Streaming 560 ms powers every mode. It is required and downloads directly to this Mac.",
            symbol: "waveform.badge.mic"
        ) {
            modelCard(
                pack: .speech,
                licence: "NVIDIA Open Model License",
                licenceURL: URL(string: "https://www.nvidia.com/en-us/agreements/enterprise-software/nvidia-open-model-license/")!
            )
            Text("Licensed by NVIDIA Corporation under the NVIDIA Open Model License")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Spacer()
        }
    }

    private var permissionSetup: some View {
        setupPage(
            title: "Allow only what dictation needs",
            detail: "macOS controls these permissions. Dictation checks the real capabilities again whenever you return from System Settings.",
            symbol: "checkmark.shield"
        ) {
            VStack(spacing: 10) {
                ForEach(AppPermission.allCases) { permission in
                    permissionRow(permission)
                }
            }

            if AppPermission.allCases.contains(where: {
                permissions.wasRequested($0) && !permissions.isGranted($0)
            }) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Already enabled it?")
                        .fontWeight(.medium)
                    Text("Some macOS releases activate Input Monitoring only after the app restarts.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Restart Dictation") { AppRelauncher.relaunch() }
                }
                .padding(14)
                .background(Theme.Colour.secondaryPanel)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
            }

            Spacer()
        }
    }

    private var practice: some View {
        setupPage(
            title: "Try the shortcut",
            detail: "Click the field, double-tap " + store.selectedHotKey.label
                + ", say a short sentence, then tap it once to stop.",
            symbol: "keyboard"
        ) {
            TextEditor(text: $practiceText)
                .font(.system(.body, design: .rounded))
                .focused($practiceIsFocused)
                .scrollContentBackground(.hidden)
                .padding(12)
                .frame(height: 150)
                .background(Theme.Colour.secondaryPanel)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Radius.card)
                        .stroke(Theme.Colour.accent.opacity(0.45), lineWidth: 1)
                }
                .onChange(of: store.phase) { _, phase in
                    if phase == .idle,
                       practiceText.split(whereSeparator: \.isWhitespace).count >= 3 {
                        onboarding.completePractice()
                    }
                }
                .onAppear {
                    store.select(.raw)
                    Task { @MainActor in practiceIsFocused = true }
                }

            Text("The menu-bar icon turns into a recording indicator, and the overlay shows what the speech model hears.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private var writingModel: some View {
        setupPage(
            title: "Optional writing tools",
            detail: "Agent, Email and Article can use a local Qwen model after you stop speaking. Raw and Clean work without it.",
            symbol: "text.badge.star"
        ) {
            modelCard(
                pack: .writing,
                licence: "Apache License 2.0",
                licenceURL: URL(string: "https://huggingface.co/mlx-community/Qwen3.5-9B-MLX-4bit")!
            )
            Spacer()
            HStack {
                Button("Not now") { onboarding.deferWritingModel() }
                Spacer()
                if modelManager.writingInstalled {
                    Button("Continue") { onboarding.deferWritingModel() }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    private var ready: some View {
        setupPage(
            title: "Ready",
            detail: "Dictation is running in the menu bar. You can change modes, overlay style, app profiles and storage at any time.",
            symbol: "checkmark.circle.fill"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                feature(
                    "Double-tap " + store.selectedHotKey.label + " to start",
                    symbol: "record.circle"
                )
                feature("Tap once to stop", symbol: "stop.circle")
                feature("Press both right modifiers to cancel", symbol: "xmark.circle")
            }
            Spacer()
            HStack {
                Spacer()
                Button("Done") {
                    onboarding.complete()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
    }

    private func setupPage<Content: View>(
        title: String,
        detail: String,
        symbol: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(Theme.Colour.accent)
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.system(size: 28, weight: .semibold))
                Text(detail)
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            content()
        }
    }

    private func feature(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.system(size: 15, weight: .medium))
    }

    private func modelCard(pack: ModelPack, licence: String, licenceURL: URL) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(pack.label)
                        .font(.headline)
                    Text(pack.detail + " · " + pack.sizeLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                modelAction(pack)
            }
            Link(licence, destination: licenceURL)
                .font(.caption)
        }
        .padding(16)
        .background(Theme.Colour.secondaryPanel)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
    }

    @ViewBuilder
    private func modelAction(_ pack: ModelPack) -> some View {
        if modelManager.installing == pack {
            VStack(alignment: .trailing, spacing: 4) {
                ProgressView(value: modelManager.progress)
                    .frame(width: 130)
                Text(modelManager.status)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        } else if modelManager.isInstalled(pack) {
            Label("Installed", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        } else {
            Button("Download") { modelManager.install(pack) }
                .buttonStyle(.borderedProminent)
        }
    }

    private func permissionRow(_ permission: AppPermission) -> some View {
        HStack(spacing: 14) {
            Image(systemName: permissions.isGranted(permission)
                ? "checkmark.circle.fill"
                : "circle")
                .foregroundStyle(permissions.isGranted(permission) ? .green : .secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(permission.label)
                    .fontWeight(.medium)
                Text(permission.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if permissions.isGranted(permission) {
                Text("Allowed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if permissions.wasRequested(permission) {
                Button("Open Settings") { permissions.openSystemSettings(for: permission) }
            } else {
                Button("Allow") { permissions.request(permission) }
            }
        }
        .padding(14)
        .background(Theme.Colour.secondaryPanel)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
    }
}

@MainActor
private enum AppRelauncher {
    static func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(
            at: Bundle.main.bundleURL,
            configuration: configuration
        ) { _, error in
            guard error == nil else { return }
            Task { @MainActor in NSApp.terminate(nil) }
        }
    }
}

@MainActor
final class OnboardingWindow: NSObject, NSWindowDelegate {
    static let shared = OnboardingWindow()
    private var window: NSWindow?

    func show(
        store: DictationStore,
        modelManager: ModelManager,
        permissions: PermissionController,
        onboarding: OnboardingManager
    ) {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Set Up " + AppInfo.displayName
        window.isReleasedWhenClosed = false
        window.center()
        window.delegate = self
        window.contentView = NSHostingView(rootView: OnboardingView(
            store: store,
            modelManager: modelManager,
            permissions: permissions,
            onboarding: onboarding,
            dismiss: { [weak window] in window?.close() }
        ))
        self.window = window

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}
