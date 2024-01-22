import Foundation

class Bouncer: NSObject {

    // This is the configuration CardVerify users should use
    static func configuration() -> ScanConfiguration {
        let configuration = ScanConfiguration()
        configuration.runOnOldDevices = true
        return configuration
    }

    // Call this method before scanning any cards
    static func configure(apiKey: String, useExperimentalScreenDetectionModel: Bool = false) {
		#if !os(visionOS)
        ScanBaseViewController.configure(apiKey: apiKey)
		#endif
    }

    static var useFlashFlow = false

    static func isCompatible() -> Bool {
		#if os(visionOS)
		return false
		#else
        return ScanBaseViewController.isCompatible(configuration: configuration())
		#endif
    }
}
