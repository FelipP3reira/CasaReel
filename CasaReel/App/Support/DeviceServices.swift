import Domain
import FeatureVideo
import UIKit

/// Warns before long renders when the battery is low and unplugged, or Low Power Mode is on.
struct DevicePowerStatus: PowerStatusProviding {
    @MainActor var shouldWarn: Bool {
        let device = UIDevice.current
        device.isBatteryMonitoringEnabled = true
        let lowAndUnplugged = device.batteryState == .unplugged && device.batteryLevel >= 0 && device.batteryLevel < 0.2
        return lowAndUnplugged || ProcessInfo.processInfo.isLowPowerModeEnabled
    }
}

/// Used only if SwiftData can't open even an in-memory store: the editor works, drafts just aren't kept.
struct NoDraftStore: VideoDraftStoring {
    func load() async -> VideoDraft? { nil }
    func save(_ draft: VideoDraft) async {}
    func delete() async {}
}
