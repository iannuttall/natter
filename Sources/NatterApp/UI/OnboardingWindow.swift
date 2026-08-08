import AppKit
import NatterCore
import SwiftUI

private struct OnboardingView: View {
    @Bindable var store: DictationStore
    @Bindable var modelManager: ModelManager
    @Bindable var permissions: PermissionController
    @Bindable var onboarding: OnboardingManager
    let dismiss: () -> Void

    @State private var practiceText = ""
    @State private var practiceBaselineWordCount = 0
    @State private var practiceWasStarted = false
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
            title: "Natter your thoughts",
            detail: "Speak naturally and Natter will clean it up for you. Speech, corrections and optional writing cleanup stay on this Mac.",
            symbol: "lock.laptopcomputer"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                feature("Fast local Raw dictation", symbol: "bolt.fill")
                feature("Editable Fast, Refine and Rewrite modes", symbol: "slider.horizontal.3")
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
            detail: "Parakeet Unified 0.6B powers every mode. It is required and downloads directly to this Mac.",
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
            title: "Set up macOS permissions",
            detail: "Natter will take you through each permission and verify that it actually works before continuing.",
            symbol: "checkmark.shield"
        ) {
            permissionProgress

            if let permission = nextRequiredPermission {
                guidedPermissionCard(permission)
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
                    switch phase {
                    case .listening:
                        practiceBaselineWordCount = practiceText
                            .split(whereSeparator: \.isWhitespace).count
                        practiceWasStarted = true
                    case .idle where practiceWasStarted:
                        let currentWordCount = practiceText
                            .split(whereSeparator: \.isWhitespace).count
                        if currentWordCount >= practiceBaselineWordCount + 3 {
                            onboarding.completePractice()
                        }
                        practiceWasStarted = false
                    case .recoverable, .failed:
                        practiceWasStarted = false
                    default:
                        break
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
            title: "Optional writing models",
            detail: "Refine modes use the smaller local model for guarded formatting. Rewrite modes use the larger model for restructuring. Fast modes use neither.",
            symbol: "text.badge.star"
        ) {
            modelCard(
                pack: .agentWriting,
                licence: "Apache License 2.0",
                licenceURL: URL(string: "https://huggingface.co/mlx-community/Qwen3.5-4B-MLX-4bit")!
            )
            modelCard(
                pack: .writing,
                licence: "Apache License 2.0",
                licenceURL: URL(string: "https://huggingface.co/mlx-community/Qwen3.5-9B-MLX-4bit")!
            )
            Spacer()
            HStack {
                Button("Not now") { onboarding.deferWritingModel() }
                Spacer()
                if modelManager.agentWritingInstalled || modelManager.writingInstalled {
                    Button("Continue") { onboarding.deferWritingModel() }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    private var ready: some View {
        setupPage(
            title: "Ready",
            detail: "\(AppInfo.displayName) is running in the menu bar. You can change modes, overlay style, app profiles and storage at any time.",
            symbol: "checkmark.circle.fill"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                feature(
                    "Double-tap " + store.selectedHotKey.label + " to start",
                    symbol: "record.circle"
                )
                feature("Tap once to stop", symbol: "stop.circle")
                feature(
                    "Press Command-Shift-M while listening to switch mode",
                    symbol: "arrow.triangle.2.circlepath"
                )
                feature("Double-tap Left Option to cancel", symbol: "xmark.circle")
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
            if pack == .speech {
                Link(
                    "NVIDIA Trustworthy AI terms",
                    destination: URL(string: "https://www.nvidia.com/en-us/agreements/trustworthy-ai/terms/")!
                )
                .font(.caption)
                Text("Choosing Agree & Download confirms that you accept these model terms.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(16)
        .background(Theme.Colour.secondaryPanel)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
    }

    @ViewBuilder
    private func modelAction(_ pack: ModelPack) -> some View {
        if modelManager.installing == pack {
            VStack(alignment: .trailing, spacing: 6) {
                ProgressView(value: modelManager.progress)
                    .frame(width: 130)
                Text(modelManager.status)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Button("Cancel") { modelManager.cancelInstallation() }
                    .controlSize(.small)
            }
        } else if modelManager.isInstalled(pack) {
            Label("Installed", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        } else {
            Button(pack == .speech ? "Agree & Download" : "Download") {
                modelManager.install(pack)
            }
                .buttonStyle(.borderedProminent)
        }
    }

    private var nextRequiredPermission: AppPermission? {
        AppPermission.allCases.first { !permissions.isGranted($0) }
    }

    private var grantedPermissionCount: Int {
        AppPermission.allCases.count(where: permissions.isGranted)
    }

    private var permissionProgress: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(grantedPermissionCount) of \(AppPermission.allCases.count) allowed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                ForEach(AppPermission.allCases) { permission in
                    Image(systemName: permissions.isGranted(permission)
                        ? "checkmark.circle.fill"
                        : "circle")
                        .foregroundStyle(permissions.isGranted(permission) ? .green : .secondary)
                        .accessibilityLabel(
                            "\(permission.label): "
                                + (permissions.isGranted(permission) ? "allowed" : "waiting")
                        )
                }
            }
            ProgressView(
                value: Double(grantedPermissionCount),
                total: Double(AppPermission.allCases.count)
            )
        }
    }

    private func guidedPermissionCard(_ permission: AppPermission) -> some View {
        let index = AppPermission.allCases.firstIndex(of: permission) ?? 0
        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: permission.symbol)
                    .font(.system(size: 26))
                    .frame(width: 34)
                    .foregroundStyle(Theme.Colour.accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Step \(index + 1): \(permission.label)")
                        .font(.headline)
                    Text(permission.detail)
                        .foregroundStyle(.secondary)
                }
            }

            Text(permission.onboardingExplanation)
                .fixedSize(horizontal: false, vertical: true)

            Label(permission.settingsPath, systemImage: "gear")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            permissionActions(permission)
        }
        .padding(18)
        .background(Theme.Colour.secondaryPanel)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
    }

    @ViewBuilder
    private func permissionActions(_ permission: AppPermission) -> some View {
        if permissions.requiresRelaunch(permission) {
            VStack(alignment: .leading, spacing: 10) {
                Label("Restart required", systemImage: "arrow.clockwise")
                    .fontWeight(.medium)
                Text(relaunchExplanation(for: permission))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Open Settings Again") {
                        permissions.openSystemSettings(for: permission)
                    }
                    Spacer()
                    Button("Restart Natter") { AppRelauncher.relaunch() }
                        .buttonStyle(.borderedProminent)
                }
            }
        } else if permissions.wasRequested(permission) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Natter still cannot verify this permission. Make sure its switch is on in System Settings, then return here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Check Again") { permissions.refresh() }
                    Spacer()
                    Button("Open Settings") {
                        permissions.openSystemSettings(for: permission)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        } else {
            HStack {
                Text("macOS will ask you to approve this next.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Allow \(permission.label)") {
                    permissions.request(permission)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private func relaunchExplanation(for permission: AppPermission) -> String {
        if permission == .accessibility,
           permissions.accessibilityControlGranted,
           !permissions.keyboardEventPostingGranted {
            return "macOS has enabled Accessibility, but Natter must restart before it can type into other apps."
        }
        return "After enabling this macOS permission, Natter must restart before it can verify and use it."
    }
}

@MainActor
enum AppRelauncher {
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
