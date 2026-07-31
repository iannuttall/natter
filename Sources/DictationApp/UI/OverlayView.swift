import DictationCore
import SwiftUI

struct OverlayView: View {
    @Bindable var store: DictationStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "waveform")
                    .foregroundStyle(Theme.Colour.accent)
                Text(store.selectedMode.label)
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                levelMeter
                Text(store.phase.label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }

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

            Text(footerText)
                .font(.caption)
                .foregroundStyle(.tertiary)
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
            "Tap \(store.selectedHotKey.label) to stop"
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
