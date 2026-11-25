#if DEBUG
    import AppKit

    /// Dev-only screenshot helper. Launch with `-uiPreviewScrollStep 500` and the main page
    /// scrolls down by that many points every 1.5 s (first step after 4 s), so an external
    /// `screencapture -l <window>` loop can capture a long page without accessibility access.
    enum DebugScreenshotScroller {
        static func startIfRequested() {
            let step = UserDefaults.standard.double(forKey: "uiPreviewScrollStep")
            guard step > 0 else { return }
            var offset: CGFloat = 0
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { _ in
                    MainActor.assumeIsolated {
                        guard let scrollView = largestScrollView() else { return }
                        offset += step
                        scrollView.documentView?.scroll(NSPoint(x: 0, y: offset))
                    }
                }
            }
        }

        private static func largestScrollView() -> NSScrollView? {
            guard let root = NSApp.windows.first(where: { $0.isVisible && $0.frame.width > 600 })?.contentView
            else { return nil }
            var best: NSScrollView?
            func walk(_ view: NSView) {
                if let s = view as? NSScrollView,
                    s.frame.width * s.frame.height > (best.map { $0.frame.width * $0.frame.height } ?? 0)
                {
                    best = s
                }
                view.subviews.forEach(walk)
            }
            walk(root)
            return best
        }
    }
#endif
