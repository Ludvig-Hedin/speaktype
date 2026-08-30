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
    /// One honored radius + spacing rhythm. Route every corner/gap through these —
    /// no inline literals (they had drifted to 6/10/14/22/24/26 across the app).
    enum UI {
        // Radius scale — three steps only.
        /// Nested chips, inline panels, small pills.
        static let radiusSmall: CGFloat = 8.0
        /// Controls: buttons, menus, rows, permission items.
        static let radiusControl: CGFloat = 10.0
        /// Large surfaces: cards, panels, sheets — continuous corners.
        static let radiusCard: CGFloat = 16.0

        /// Legacy aliases (kept so existing call sites compile) — map onto the scale above.
        static let cornerRadius: CGFloat = radiusControl
        static let cardCornerRadius: CGFloat = radiusCard
        static let sidebarItemCornerRadius: CGFloat = radiusControl

        // Spacing scale — strict 4/8 grid.
        static let space1: CGFloat = 4.0
        static let space2: CGFloat = 8.0
        static let space3: CGFloat = 12.0
        static let space4: CGFloat = 16.0
        static let space5: CGFloat = 20.0
        static let space6: CGFloat = 24.0

        /// Standard rhythm: page edge 24, card interior 20, inter-card gap 16, intra-section rows 12.
        static let pagePadding: CGFloat = space6
        static let cardPadding: CGFloat = space5
        static let sectionGap: CGFloat = space4
        static let rowGap: CGFloat = space3

        // Legacy padding aliases.
        static let padding: CGFloat = space4
        static let smallPadding: CGFloat = space2
        static let largePadding: CGFloat = space6
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

