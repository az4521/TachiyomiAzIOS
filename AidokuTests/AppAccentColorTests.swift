@testable import Aidoku
import Testing
import UIKit

struct AppAccentColorTests {
    @Test @MainActor
    func convertsSRGBColorsToPersistentHex() {
        let color = UIColor(
            red: 17.0 / 255,
            green: 34.0 / 255,
            blue: 51.0 / 255,
            alpha: 1
        )
        #expect(AppAccentColor.hexString(from: color) == "#112233")
    }

    @Test @MainActor
    func convertsDisplayP3ColorsWithoutFallingBackToDefault() {
        let color = UIColor(
            displayP3Red: 0.9,
            green: 0.2,
            blue: 0.4,
            alpha: 1
        )
        #expect(
            AppAccentColor.hexString(from: color)
                != AppAccentColor.defaultHex
        )
    }
}
