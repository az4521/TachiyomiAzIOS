//
//  String+Color.swift
//  Aidoku
//
//  Created by Skitty on 9/18/25.
//

import SwiftUI
import UIKit

enum AppAccentColor {
    static let defaultHex = "#54759E"

    static var storedHex: String {
        let value = UserDefaults.standard.string(forKey: "Appearance.accentColor") ?? defaultHex
        return uiColor(from: value) == nil ? defaultHex : value.uppercased()
    }

    static var uiColor: UIColor {
        uiColor(from: storedHex) ?? UIColor(
            red: 84 / 255,
            green: 117 / 255,
            blue: 158 / 255,
            alpha: 1
        )
    }

    @MainActor
    static func set(_ color: UIColor) {
        UserDefaults.standard.set(hexString(from: color), forKey: "Appearance.accentColor")
        apply(color)
    }

    @MainActor
    static func applyStoredColor() {
        apply(uiColor)
    }

    static func hexString(from color: UIColor) -> String {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return defaultHex
        }
        return String(
            format: "#%02X%02X%02X",
            Int(round(red * 255)),
            Int(round(green * 255)),
            Int(round(blue * 255))
        )
    }

    private static func uiColor(from value: String) -> UIColor? {
        var hex = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") {
            hex.removeFirst()
        }
        guard hex.count == 6, let rgb = Int(hex, radix: 16) else { return nil }
        return UIColor(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }

    @MainActor
    private static func apply(_ color: UIColor) {
        UIView.appearance().tintColor = color
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                window.tintColor = color
            }
        }
    }
}

extension String {
    func toColor() -> Color {
        switch lowercased() {
            case "black": return Color.black
            case "blue": return Color.blue
            case "gray", "grey": return Color.gray
            case "green": return Color.green
            case "orange": return Color.orange
            case "pink": return Color.pink
            case "purple": return Color.purple
            case "indigo": return Color.indigo
            case "red": return Color.red
            case "white": return Color.white
            case "yellow": return Color.yellow
            case "primary": return Color.primary
            case "secondary": return Color.secondary
            default:
                // parse hex code
                var hex = if hasPrefix("#") {
                    String(dropFirst())
                } else {
                    self
                }
                if hex.count == 3 {
                    let r = hex[hex.startIndex]
                    let g = hex[hex.index(hex.startIndex, offsetBy: 1)]
                    let b = hex[hex.index(hex.startIndex, offsetBy: 2)]
                    hex = "\(r)\(r)\(g)\(g)\(b)\(b)"
                }
                if hex.count == 6, let intCode = Int(hex, radix: 16) {
                    let red = Double((intCode >> 16) & 0xFF) / 255
                    let green = Double((intCode >> 8) & 0xFF) / 255
                    let blue = Double(intCode & 0xFF) / 255
                    return Color(red: red, green: green, blue: blue)
                } else if hex.count == 8, let intCode = Int(hex, radix: 16) {
                    let red = Double((intCode >> 24) & 0xFF) / 255
                    let green = Double((intCode >> 16) & 0xFF) / 255
                    let blue = Double((intCode >> 8) & 0xFF) / 255
                    let alpha = Double(intCode & 0xFF) / 255
                    return Color(red: red, green: green, blue: blue, opacity: alpha)
                }
                return Color.black
        }
    }
}
