import Foundation
import AppKit

/// Hotkey options for triggering SpeakType recording
enum HotkeyOption: String, Codable, CaseIterable, Identifiable {
    // MARK: - Modifier-only keys (use flagsChanged events)
    case fn = "fn"
    case rightCommand = "rightCommand"
    case leftCommand = "leftCommand"
    case rightControl = "rightControl"
    case leftControl = "leftControl"
    case rightOption = "rightOption"
    case leftOption = "leftOption"
    case capsLock = "capsLock"
    case leftShift = "leftShift"
    case rightShift = "rightShift"

    // MARK: - Function keys (use keyDown/keyUp events)
    case f13 = "f13"
    case f14 = "f14"
    case f15 = "f15"
    case f16 = "f16"
    case f17 = "f17"
    case f18 = "f18"
    case f19 = "f19"

    // MARK: - Custom combo (modifier + key, stored separately)
    case custom = "custom"

    var id: String { rawValue }

    /// Display name with appropriate symbols
    var displayName: String {
        switch self {
        case .fn:           return "Fn / 🌐"
        case .rightCommand: return "Right ⌘"
        case .leftCommand:  return "Left ⌘"
        case .rightControl: return "Right ⌃"
        case .leftControl:  return "Left ⌃"
        case .rightOption:  return "Right ⌥"
        case .leftOption:   return "Left ⌥"
        case .capsLock:     return "Caps Lock"
        case .leftShift:    return "Left ⇧"
        case .rightShift:   return "Right ⇧"
        case .f13:          return "F13"
        case .f14:          return "F14"
        case .f15:          return "F15"
        case .f16:          return "F16"
        case .f17:          return "F17"
        case .f18:          return "F18"
        case .f19:          return "F19"
        case .custom:       return "Custom…"
        }
    }

    /// macOS virtual keycode for this key
    var keyCode: UInt16 {
        switch self {
        case .fn:           return 63   // kVK_Function
        case .rightCommand: return 54   // kVK_RightCommand
        case .leftCommand:  return 55   // kVK_Command
        case .rightControl: return 62   // kVK_RightControl
        case .leftControl:  return 59   // kVK_Control
        case .rightOption:  return 61   // kVK_RightOption
        case .leftOption:   return 58   // kVK_Option
        case .capsLock:     return 57   // kVK_CapsLock
        case .leftShift:    return 56   // kVK_Shift
        case .rightShift:   return 60   // kVK_RightShift
        case .f13:          return 105  // kVK_F13
        case .f14:          return 107  // kVK_F14
        case .f15:          return 113  // kVK_F15
        case .f16:          return 106  // kVK_F16
        case .f17:          return 64   // kVK_F17
        case .f18:          return 79   // kVK_F18
        case .f19:          return 80   // kVK_F19
        case .custom:       return 0    // Determined at runtime from UserDefaults
        }
    }

    /// Modifier flag checked in flagsChanged events (not applicable to F-keys or custom)
    var modifierFlag: NSEvent.ModifierFlags {
        switch self {
        case .fn:
            return .function
        case .rightCommand, .leftCommand:
            return .command
        case .rightControl, .leftControl:
            return .control
        case .rightOption, .leftOption:
            return .option
        case .capsLock:
            return .capsLock
        case .leftShift, .rightShift:
            return .shift
        case .f13, .f14, .f15, .f16, .f17, .f18, .f19, .custom:
            // These are handled via keyDown/keyUp, not flagsChanged
            return .init(rawValue: 0)
        }
    }

    /// Whether this hotkey fires on keyDown/keyUp (true) rather than flagsChanged (false)
    var usesKeyDownEvents: Bool {
        switch self {
        case .f13, .f14, .f15, .f16, .f17, .f18, .f19, .custom:
            return true
        default:
            return false
        }
    }

    /// Default hotkey option
    static var `default`: HotkeyOption { .fn }
}

// MARK: - SwiftUI Binding support

import SwiftUI

extension HotkeyOption {
    static func binding(forKey key: String, default defaultValue: HotkeyOption = .default) -> Binding<HotkeyOption> {
        Binding(
            get: {
                guard let rawValue = UserDefaults.standard.string(forKey: key),
                      let option = HotkeyOption(rawValue: rawValue) else {
                    return defaultValue
                }
                return option
            },
            set: { newValue in
                UserDefaults.standard.set(newValue.rawValue, forKey: key)
            }
        )
    }
}
