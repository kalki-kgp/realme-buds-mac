// What the app hands the widget: the last state it read from the buds, in the shared app group.

import Foundation

struct BatteryReading: Codable, Equatable {
    var percent: Int?
    var charging = false
}

struct BudsSnapshot: Codable, Equatable {
    var name: String
    var battery: [Bud: BatteryReading]
    var placement: [Bud: Placement]
    var noiseMode: NoiseMode?
    /// When the buds last answered.
    var updated: Date
    /// False when the buds are out of range or another device holds their control session.
    var live: Bool

    static let placeholder = BudsSnapshot(
        name: "realme Buds Air7",
        battery: [.left: .init(percent: 80), .right: .init(percent: 75), .enclosure: .init(percent: 40)],
        placement: [.left: .inEar, .right: .inEar],
        noiseMode: .anc(.smart), updated: .now, live: true)

    /// The lower of the two buds, which is the number that decides when you need to charge.
    var budsPercent: Int? {
        [Bud.left, .right].compactMap { battery[$0]?.percent }.min()
    }
}

enum SharedStore {
    static let defaultGroup = "group.dev.kalki.buds"
    private static let key = "snapshot.v1"

    /// AltStore re-signs free-account installs under new app group IDs and lists them in the
    /// app's Info.plist under ALTAppGroups. The widget runs from inside the app bundle, so it
    /// reads the host app's plist too. The first group the system actually grants us wins.
    static let groupID: String? = {
        var candidates: [String] = []
        let bundles = [Bundle.main, hostAppBundle].compactMap { $0 }
        for bundle in bundles {
            candidates += (bundle.object(forInfoDictionaryKey: "ALTAppGroups") as? [String]) ?? []
        }
        candidates.append(defaultGroup)
        return candidates.first { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) != nil }
    }()

    private static var hostAppBundle: Bundle? {
        let url = Bundle.main.bundleURL
        guard url.pathExtension == "appex" else { return nil }
        return Bundle(url: url.deletingLastPathComponent().deletingLastPathComponent())
    }

    private static var defaults: UserDefaults? { groupID.flatMap(UserDefaults.init(suiteName:)) }

    static func load() -> BudsSnapshot? {
        guard let data = defaults?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(BudsSnapshot.self, from: data)
    }

    static func save(_ snapshot: BudsSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults?.set(data, forKey: key)
    }
}
