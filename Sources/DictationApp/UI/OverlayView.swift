import DictationCore
import SwiftUI

struct OverlayView: View {
    @Bindable var store: DictationStore
    let onCycleMode: () -> Void
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
                        .font(.system(size: 16, weight: .regular))
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
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.separator.opacity(0.45), lineWidth: 1)
        }
    }

    private var compactOverlay: some View {
        HStack(spacing: 10) {
            levelMeter
            modeButton(font: .system(size: 14, weight: .semibold))
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
        .background(.regularMaterial)
        .clipShape(Capsule())
        .overlay { Capsule().stroke(.separator.opacity(0.45), lineWidth: 1) }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform")
                .foregroundStyle(Theme.Colour.accent)
            VStack(alignment: .leading, spacing: 0) {
                modeButton(font: .system(size: 14, weight: .semibold))
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
        LiveVoiceMeter(level: store.audioLevel, isActive: canCancel)
    }

    private func modeButton(font: Font) -> some View {
        Button(action: onCycleMode) {
            HStack(spacing: 3) {
                Text(store.selectedMode.label)
                    .font(font)
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
        .help("Switch mode · press Tab while listening")
        .accessibilityLabel("Switch from \(store.selectedMode.label) mode")
    }

    private var footerText: String {
        switch store.phase {
        case .preparing, .listening:
            "Tab: switch mode · tap \(store.selectedHotKey.label): stop · Right Option + Right Control: cancel"
        case .recoverable:
            store.statusMessage ?? "The complete transcript is on your clipboard"
        case .failed:
            "Open Settings to fix this"
        default:
            store.statusMessage ?? "Finished locally"
        }
    }

}

private struct LiveVoiceMeter: View {
    let level: Float
    let isActive: Bool
    @State private var bars = Array(repeating: CGFloat.zero, count: 7)

    private let heightProfile: [CGFloat] = [0.46, 0.72, 0.9, 1, 0.84, 0.64, 0.42]
    private let releaseProfile: [CGFloat] = [0.62, 0.68, 0.72, 0.76, 0.7, 0.66, 0.6]

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(bars.indices, id: \.self) { index in
                Capsule()
                    .fill(Theme.Colour.accent.opacity(0.3 + (0.7 * bars[index])))
                    .frame(width: 3, height: 3 + (bars[index].squareRoot() * 17))
            }
        }
        .frame(width: 39, height: 20)
        .onChange(of: level, initial: true) { _, newLevel in
            guard isActive else {
                bars = Array(repeating: 0, count: bars.count)
                return
            }
            let measured = CGFloat(min(1, max(0, newLevel)))
            let nextBars = bars.indices.map { index in
                let target = min(1, measured * heightProfile[index])
                let previous = bars[index]
                guard target < previous else { return target }
                let release = releaseProfile[index]
                return (previous * release) + (target * (1 - release))
            }
            withAnimation(.linear(duration: 0.06)) {
                bars = nextBars
            }
        }
        .onChange(of: isActive) { _, active in
            if !active { bars = Array(repeating: 0, count: bars.count) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Microphone level")
        .accessibilityValue("\(Int(min(1, max(0, level)) * 100)) percent")
    }
}

private struct OverlayCancelButton: View {
    let compact: Bool
    let action: () -> Void

    var body: some View {
        Button(role: .destructive, action: action) {
            HStack(spacing: 4) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                if !compact { Text("Cancel") }
            }
            .frame(minWidth: compact ? 22 : nil)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .tint(.red)
        .help("Cancel dictation · press Right Option and Right Control together")
        .accessibilityLabel("Cancel dictation")
    }
}
