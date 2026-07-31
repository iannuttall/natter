import AppKit
import SwiftUI

enum Theme {
    enum Colour {
        static let accent = Color(red: 0.18, green: 0.78, blue: 0.88)
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

