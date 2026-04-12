//
//  View+Extensions.swift
//  speaktype
//
//  Created by Karan Singh on 7/1/26.
//

import AppKit
import SwiftUI

// MARK: - Pointer cursor (macOS)

/// Applies the pointing-hand cursor while the view is hovered and enabled.
struct ClickActionPointerCursorModifier: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false
    @State private var cursorPushed = false

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                isHovering = hovering
                reconcilePointerCursor()
            }
            .onChange(of: isEnabled) { _, _ in
                reconcilePointerCursor()
            }
    }

    /// Keeps `NSCursor` push/pop balanced when hover or enabled state changes (including disable-while-hovering).
    private func reconcilePointerCursor() {
        let wantsPointer = isHovering && isEnabled
        if wantsPointer && !cursorPushed {
            NSCursor.pointingHand.push()
            cursorPushed = true
        } else if !wantsPointer && cursorPushed {
            NSCursor.pop()
            cursorPushed = false
        }
    }
}

extension View {
    /// Tighter tracking + slightly denser line rhythm for UI copy (not marketing display).
    func stCompactUI() -> some View {
        self.kerning(-0.18)
            .lineSpacing(1)
    }

    /// Use on tappable controls (buttons, menus, links) for consistent macOS pointer feedback.
    func clickActionPointerCursor() -> some View {
        modifier(ClickActionPointerCursorModifier())
    }

    /// Applies a standard corner radius to the view
    func standardCornerRadius() -> some View {
        self.cornerRadius(Constants.UI.cornerRadius)
    }
    
    /// Applies standard padding to the view
    func standardPadding() -> some View {
        self.padding(Constants.UI.padding)
    }
    
    /// Conditionally applies a modifier
    @ViewBuilder
    func `if`<Transform: View>(_ condition: Bool, transform: (Self) -> Transform) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
    
    /// Applies a modifier conditionally with an else clause
    @ViewBuilder
    func `if`<TrueContent: View, FalseContent: View>(
        _ condition: Bool,
        if ifTransform: (Self) -> TrueContent,
        else elseTransform: (Self) -> FalseContent
    ) -> some View {
        if condition {
            ifTransform(self)
        } else {
            elseTransform(self)
        }
    }
}

