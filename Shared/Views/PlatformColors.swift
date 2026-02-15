import SwiftUI

#if os(macOS)
import AppKit
typealias PlatformColor = NSColor
#else
import UIKit
typealias PlatformColor = UIColor
#endif

extension Color {
    static var platformControlBackground: Color {
        #if os(macOS)
        Color(NSColor.controlBackgroundColor)
        #else
        Color(UIColor.secondarySystemBackground)
        #endif
    }

    static var platformTextBackground: Color {
        #if os(macOS)
        Color(NSColor.textBackgroundColor)
        #else
        Color(UIColor.systemBackground)
        #endif
    }

    static var platformSeparator: Color {
        #if os(macOS)
        Color(NSColor.separatorColor)
        #else
        Color(UIColor.separator)
        #endif
    }

    static var platformWindowBackground: Color {
        #if os(macOS)
        Color(NSColor.windowBackgroundColor)
        #else
        Color(UIColor.systemBackground)
        #endif
    }
}
