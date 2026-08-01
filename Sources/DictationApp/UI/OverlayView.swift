import DictationCore
import SwiftUI

struct OverlayView: View {
    @Bindable var store: DictationStore
    let onCancel: () -> Void

    var body: some View {
        switch store.overlayStyle {
        case .full:
            fullOverlay
        case .compact:
            compactOverlay
        case .hidden:
            EmptyView()
        }
    }

    private var fullOverlay: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            ScrollViewReader { proxy in
                ScrollView {
                    Text(transcript)
                        .font(.system(size: 16, weight: .regular, design: .rounded))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                    Color.clear
                        .frame(height: 1)
                        .id("transcript-bottom")
                }
                .onChange(of: store.liveTranscript) {
                    proxy.scrollTo("transcript-bottom", anchor: .bottom)
                }
            }

            HStack {
                Text(footerText)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
                if canCancel {
                    OverlayCancelButton(compact: false, action: onCancel)
                }
            }
        }
        .padding(16)
        .frame(width: 440, height: 166)
        .background(.ultraThickMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        }
    }

    private var compactOverlay: some View {
        HStack(spacing: 10) {
            levelMeter
            Text(store.selectedMode.label)
                .font(.system(size: 14, weight: .semibold))
            Text(store.phase.label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            if canCancel {
                OverlayCancelButton(compact: true, action: onCancel)
            }
        }
        .padding(.horizontal, 16)
        .frame(width: 250, height: 56)
        .background(.ultraThickMaterial)
        .clipShape(Capsule())
        .overlay { Capsule().stroke(.white.opacity(0.12), lineWidth: 1) }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform")
                .foregroundStyle(Theme.Colour.accent)
            VStack(alignment: .leading, spacing: 0) {
                Text(store.selectedMode.label)
                    .font(.system(size: 14, weight: .semibold))
                if let context = modeContext {
                    Text(context)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            levelMeter
            Text(store.phase.label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private var modeContext: String? {
        store.activeModeSource ?? store.activeApplicationName
    }

    private var canCancel: Bool {
        store.phase == .preparing || store.phase == .listening
    }

    private var transcript: String {
        if let statusMessage = store.statusMessage, store.liveTranscript.isEmpty {
            return statusMessage
        }
        return store.liveTranscript.isEmpty ? "Listening…" : store.liveTranscript
    }

    private var levelMeter: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(0..<5, id: \.self) { index in
                Capsule()
                    .fill(Theme.Colour.accent.opacity(barIsActive(index) ? 1 : 0.2))
                    .frame(width: 3, height: CGFloat(5 + (index % 3) * 4))
            }
        }
        .animation(.linear(duration: 0.08), value: store.audioLevel)
    }

    private var footerText: String {
        switch store.phase {
        case .preparing, .listening:
            "Tap \(store.selectedHotKey.label) to stop · both right modifiers cancel"
        case .recoverable:
            "The complete transcript is on your clipboard"
        case .failed:
            "Open Settings to fix this"
        default:
            store.statusMessage ?? "Finished locally"
        }
    }

    private func barIsActive(_ index: Int) -> Bool {
        store.audioLevel >= Float(index + 1) / 6
    }
}

private struct OverlayCancelButton: View {
    let compact: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                if !compact { Text("Cancel") }
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(isHovered ? .white : .red)
            .frame(minWidth: compact ? 24 : nil, minHeight: 22)
            .padding(.horizontal, compact ? 2 : 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? Color.red : Color.red.opacity(0.14))
            )
        }
        .buttonStyle(.plain)
        .help("Cancel dictation · press Right Option and Right Control together")
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) { isHovered = hovering }
        }
        .accessibilityLabel("Cancel dictation")
    }
}
