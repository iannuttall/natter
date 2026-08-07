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
            if canCancel, wordCount > 0 {
                Text("\(wordCount) words")
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
                    .contentTransition(.numericText())
                    .accessibilityLabel("\(wordCount) words dictated")
            }
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
            if canCancel, wordCount > 0 {
                Text("\(wordCount) words")
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
                    .contentTransition(.numericText())
                    .accessibilityLabel("\(wordCount) words dictated")
            }
            levelMeter
            Text(store.phase.label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private var wordCount: Int {
        store.liveTranscript.split(whereSeparator: \.isWhitespace).count
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
        LiveVoiceMeter(level: store.audioLevel, bands: store.audioBands, isActive: canCancel)
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
            "Tab: switch mode · tap \(store.selectedHotKey.label): stop · double-tap Left Option: cancel"
        case .recoverable:
            store.statusMessage ?? "The complete transcript is on your clipboard"
        case .failed:
            "Open Settings to fix this"
        default:
            store.statusMessage ?? "Finished locally"
        }
    }

}

/// Spectrum meter: each bar tracks a real log-spaced frequency band from the
/// capture path, so the display follows the shape of the sound rather than
/// pulsing every bar from one loudness value. Bars start flat and rise with
/// fast attack and slower release. Falls back to the overall level (uniform
/// pulse) only until the first spectrum frame arrives.
private struct LiveVoiceMeter: View {
    let level: Float
    let bands: [Float]
    let isActive: Bool
    @State private var bars = Array(repeating: CGFloat.zero, count: 7)

    private let releaseProfile: [CGFloat] = [0.62, 0.68, 0.72, 0.76, 0.7, 0.66, 0.6]
    private let heightProfile: [CGFloat] = [0.44, 0.64, 0.82, 1, 0.86, 0.68, 0.48]

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(bars.indices, id: \.self) { index in
                Capsule()
                    .fill(Theme.Colour.accent.opacity(0.3 + (0.7 * bars[index])))
                    .frame(width: 3, height: 3 + (bars[index].squareRoot() * 17))
            }
        }
        .frame(width: 39, height: 20)
        .onChange(of: targets, initial: true) { _, newTargets in
            guard isActive else {
                bars = Array(repeating: 0, count: bars.count)
                return
            }
            let nextBars = bars.indices.map { index in
                let target = newTargets[index]
                let previous = bars[index]
                guard target < previous else { return target }
                let release = releaseProfile[index]
                return (previous * release) + (target * (1 - release))
            }
            withAnimation(.interpolatingSpring(stiffness: 300, damping: 20)) {
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

    private var targets: [CGFloat] {
        let measured = CGFloat(min(1, max(0, level)))
        if bands.count == bars.count {
            return bands.indices.map { index in
                // Keep the real spectrum as subtle texture inside a stable
                // voice-shaped envelope. The centre remains tallest while the
                // outer bars still respond independently to the microphone.
                let band = CGFloat(min(1, max(0, bands[index])))
                let spectralTexture = (band - 0.5) * 0.06
                return min(1, measured * max(0, heightProfile[index] + spectralTexture))
            }
        }
        return heightProfile.map { min(1, measured * $0) }
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
        .help("Cancel dictation · double-tap Left Option")
        .accessibilityLabel("Cancel dictation")
    }
}
