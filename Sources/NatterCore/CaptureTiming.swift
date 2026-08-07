import Foundation

public struct AdaptiveStopTimingEstimator: Sendable {
    private let sampleLimit: Int
    private var lastCallbackAt: TimeInterval?
    private var callbackIntervals: [TimeInterval] = []
    private var bufferDurations: [TimeInterval] = []

    public init(sampleLimit: Int = 8) {
        self.sampleLimit = max(1, sampleLimit)
    }

    public mutating func observe(
        callbackAt: TimeInterval,
        bufferDuration: TimeInterval
    ) {
        if let lastCallbackAt {
            append(callbackAt - lastCallbackAt, to: &callbackIntervals)
        }
        lastCallbackAt = callbackAt
        append(bufferDuration, to: &bufferDurations)
    }

    public var gracePeriod: TimeInterval {
        let cadence = max(callbackIntervals.max() ?? 0, bufferDurations.max() ?? 0)
        return min(max(cadence > 0 ? cadence + 0.008 : 0.05, 0.02), 0.08)
    }

    public mutating func reset() {
        lastCallbackAt = nil
        callbackIntervals = []
        bufferDurations = []
    }

    private func append(_ value: TimeInterval, to values: inout [TimeInterval]) {
        guard value.isFinite, value > 0, value < 1 else { return }
        values.append(value)
        if values.count > sampleLimit { values.removeFirst(values.count - sampleLimit) }
    }
}

public struct TimedPreRollBuffer<Element: Sendable>: Sendable {
    private struct Entry: Sendable {
        let element: Element
        let duration: TimeInterval
    }

    public let maximumDuration: TimeInterval
    private var entries: [Entry] = []
    public private(set) var duration: TimeInterval = 0

    public init(maximumDuration: TimeInterval) {
        self.maximumDuration = max(0, maximumDuration)
    }

    public mutating func append(_ element: Element, duration: TimeInterval) {
        guard duration.isFinite, duration > 0 else { return }
        entries.append(Entry(element: element, duration: duration))
        self.duration += duration
        while self.duration > maximumDuration, entries.count > 1 {
            self.duration -= entries.removeFirst().duration
        }
    }

    public mutating func drain() -> [Element] {
        let elements = entries.map(\.element)
        removeAll()
        return elements
    }

    public mutating func removeAll() {
        entries = []
        duration = 0
    }
}
