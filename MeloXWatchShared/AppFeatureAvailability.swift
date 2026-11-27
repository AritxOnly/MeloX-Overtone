import Foundation

enum AppFeatureAvailability {
    /// Personal builds include downloads. The App Store distribution family disables them.
    static let downloads: Bool = {
        #if DEBUG
            true
        #else
            guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
                return false
            }
            let distributionID = "top.aritxonly.overtone"
            return bundleIdentifier != distributionID && !bundleIdentifier.hasPrefix(distributionID + ".")
        #endif
    }()
}
