import Foundation

public struct RecoveryRecord: Codable, Equatable, Sendable {
    public let createdAt: Date
    public let transcript: String
    public let deliveredPrefix: String
    public let targetBundleIdentifier: String?
    public let reason: String

    public init(
        createdAt: Date = Date(),
        transcript: String,
        deliveredPrefix: String,
        targetBundleIdentifier: String?,
        reason: String
    ) {
        self.createdAt = createdAt
        self.transcript = transcript
        self.deliveredPrefix = deliveredPrefix
        self.targetBundleIdentifier = targetBundleIdentifier
        self.reason = reason
    }
}
