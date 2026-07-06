import CoreText
import Foundation

enum FontLoader {
    static func register() {
        let names = [
            "Silkscreen-Regular",
            "Silkscreen-Bold",
            "SpaceMono-Regular",
            "SpaceMono-Bold"
        ]
        for name in names {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else {
                print("[FontLoader] missing: \(name).ttf")
                continue
            }
            var error: Unmanaged<CFError>?
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
            if let err = error?.takeRetainedValue() {
                print("[FontLoader] \(name): \(err)")
            }
        }
    }
}
