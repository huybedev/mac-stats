import Foundation

enum FanPlatform {
    static let unsupportedMessage = "Fan Control requires macOS 14 or later and an Apple M4 Mac."

    static func supports(brand: String) -> Bool {
        brand == "Apple M4" || brand.hasPrefix("Apple M4 ")
    }

    static var isSupported: Bool {
        #if arch(arm64)
        guard #available(macOS 14.0, *) else { return false }
        var size = 0
        guard sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0) == 0, size > 0 else { return false }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname("machdep.cpu.brand_string", &bytes, &size, nil, 0) == 0 else { return false }
        return supports(brand: String(cString: bytes))
        #else
        return false
        #endif
    }
}
