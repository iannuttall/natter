import AppKit
import SwiftUI

enum Theme {
    enum Colour {
        static let accent = Color.accentColor
        static let panel = Color(nsColor: .windowBackgroundColor)
        static let secondaryPanel = Color(nsColor: .controlBackgroundColor)
    }

    enum Space {
        static let compact: CGFloat = 8
        static let regular: CGFloat = 12
        static let section: CGFloat = 20
    }

    enum Radius {
        static let card: CGFloat = 12
    }
}
