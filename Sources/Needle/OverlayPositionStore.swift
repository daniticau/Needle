import AppKit
import Foundation

enum OverlayPositionStore {
    private static let originXKey = "Needle.overlayOriginX"
    private static let originYKey = "Needle.overlayOriginY"
    private static let widthKey = "Needle.overlayWidth"
    private static let heightKey = "Needle.overlayHeight"

    static func save(origin: NSPoint) {
        UserDefaults.standard.set(origin.x, forKey: originXKey)
        UserDefaults.standard.set(origin.y, forKey: originYKey)
    }

    static func save(size: NSSize) {
        let clampedSize = OverlaySizeRules.clamped(size)
        UserDefaults.standard.set(clampedSize.width, forKey: widthKey)
        UserDefaults.standard.set(clampedSize.height, forKey: heightKey)
    }

    static func savedOrigin() -> NSPoint? {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: originXKey) != nil,
              defaults.object(forKey: originYKey) != nil else {
            return nil
        }

        return NSPoint(
            x: defaults.double(forKey: originXKey),
            y: defaults.double(forKey: originYKey)
        )
    }

    static func savedSize() -> NSSize? {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: widthKey) != nil,
              defaults.object(forKey: heightKey) != nil else {
            return nil
        }

        return OverlaySizeRules.clamped(
            NSSize(
                width: defaults.double(forKey: widthKey),
                height: defaults.double(forKey: heightKey)
            )
        )
    }
}
