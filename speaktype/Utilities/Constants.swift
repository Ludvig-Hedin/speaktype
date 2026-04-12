//
//  Constants.swift
//  speaktype
//
//  Created by Karan Singh on 7/1/26.
//

import Foundation

enum Constants {
    // MARK: - App Information
    enum App {
        static let name = "SpeakType"
        static let bundleIdentifier = Bundle.main.bundleIdentifier ?? ""
        static let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        static let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
    
    // MARK: - UI Constants
    /// 4/8-pt rhythm: base unit4; cards and sheets use multiples for calmer grouping.
    enum UI {
        /// Default control rounding (buttons, chips). Prefer `Capsule()` for primary actions.
        static let cornerRadius: CGFloat = 12.0
        /// Large surfaces (cards, panels) — Apple-style continuous corners.
        static let cardCornerRadius: CGFloat = 18.0
        /// Sidebar rows and nested groups.
        static let sidebarItemCornerRadius: CGFloat = 12.0
        static let padding: CGFloat = 16.0
        static let smallPadding: CGFloat = 8.0
        static let largePadding: CGFloat = 24.0
    }
    
    // MARK: - Animation
    enum Animation {
        static let defaultDuration: Double = 0.3
        static let fastDuration: Double = 0.15
        static let slowDuration: Double = 0.5
    }
    
    // MARK: - Networking
    enum Network {
        static let timeoutInterval: TimeInterval = 30.0
        static let maxRetryCount = 3
    }
    
    // MARK: - Storage
    enum Storage {
        static let userDefaultsSuiteName = "com.speaktype.defaults"
    }
}

