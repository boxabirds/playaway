import PlayawayCore
import Foundation

/// The Sparkle keys the app carries in its Info.plist, as read (nothing is interpreted here).
struct UpdateConfiguration {
    let feedURL: String
    let publicEDKey: String
    let automaticChecksEnabled: Bool?

    static let feedURLKey = "SUFeedURL"
    static let publicKeyKey = "SUPublicEDKey"
    static let automaticChecksKey = "SUEnableAutomaticChecks"

    /// Reads the Sparkle keys from the app's own Info.plist. A missing key reads as an empty string.
    static func fromBundle(_ bundle: Bundle = .main) -> UpdateConfiguration {
        from(info: bundle.infoDictionary ?? [:])
    }

    /// A non-boolean value for the automatic-checks key reads as `nil` (not enabled).
    static func from(info: [String: Any]) -> UpdateConfiguration {
        UpdateConfiguration(
            feedURL: info[feedURLKey] as? String ?? "",
            publicEDKey: info[publicKeyKey] as? String ?? "",
            automaticChecksEnabled: info[automaticChecksKey] as? Bool)
    }
}

/// One case per way the configuration can be wrong.
enum ConfigIssue: Equatable, CustomStringConvertible {
    case feedURLMissing
    case feedURLNotHTTPS
    case feedURLUnparsable
    case feedURLPlaceholder
    case publicKeyMissing
    case publicKeyNotBase64
    case publicKeyTooShort
    case publicKeyPlaceholder
    case publicKeyIsCutawayKey
    case automaticChecksNotEnabled

    var description: String {
        switch self {
        case .feedURLMissing: return "SUFeedURL is missing or empty"
        case .feedURLNotHTTPS: return "SUFeedURL must use https"
        case .feedURLUnparsable: return "SUFeedURL is not a valid URL"
        case .feedURLPlaceholder: return "SUFeedURL still holds a placeholder value"
        case .publicKeyMissing: return "SUPublicEDKey is missing or empty"
        case .publicKeyNotBase64: return "SUPublicEDKey is not valid base64"
        case .publicKeyTooShort: return "SUPublicEDKey is too short to be an EdDSA public key"
        case .publicKeyPlaceholder: return "SUPublicEDKey still holds a placeholder value"
        case .publicKeyIsCutawayKey: return "SUPublicEDKey is the key of another product; update keys must not be shared"
        case .automaticChecksNotEnabled: return "SUEnableAutomaticChecks is missing, false or not a boolean"
        }
    }
}

enum UpdateConfigurationRules {
    static let https = "https"
    /// A public key of this length or shorter is rejected (11 characters pass the length rule).
    static let minimumPublicKeyLength = 10
    static let placeholderMarker = "PLACEHOLDER"
    /// The reference product's public key. Keys are per product, so this value is a deny-list entry only.
    static let rejectedForeignPublicKey = "rqIy/mx4aHQfqlexNM0vv6B+tHhHrCJy2sijyrmn450="
}

@MainActor
func containsPlaceholder(_ value: String) -> Bool {
    value.range(of: UpdateConfigurationRules.placeholderMarker, options: .caseInsensitive) != nil
}

/// Every problem with the configuration, in a stable order. Empty means the configuration is usable.
@MainActor
func validate(_ configuration: UpdateConfiguration) -> [ConfigIssue] {
    var issues: [ConfigIssue] = []

    let feed = configuration.feedURL.trimmingCharacters(in: .whitespacesAndNewlines)
    if feed.isEmpty {
        issues.append(.feedURLMissing)
    } else {
        if let components = URLComponents(string: feed), let scheme = components.scheme,
           components.host?.isEmpty == false {
            if scheme.lowercased() != UpdateConfigurationRules.https { issues.append(.feedURLNotHTTPS) }
        } else {
            issues.append(.feedURLUnparsable)
        }
        if containsPlaceholder(feed) { issues.append(.feedURLPlaceholder) }
    }

    let key = configuration.publicEDKey.trimmingCharacters(in: .whitespacesAndNewlines)
    if key.isEmpty {
        issues.append(.publicKeyMissing)
    } else {
        if Data(base64Encoded: key) == nil { issues.append(.publicKeyNotBase64) }
        if key.count <= UpdateConfigurationRules.minimumPublicKeyLength { issues.append(.publicKeyTooShort) }
        if containsPlaceholder(key) { issues.append(.publicKeyPlaceholder) }
        if key == UpdateConfigurationRules.rejectedForeignPublicKey { issues.append(.publicKeyIsCutawayKey) }
    }

    if configuration.automaticChecksEnabled != true { issues.append(.automaticChecksNotEnabled) }
    return issues
}

/// The test-only feed override. It exists in debug builds only: in a release build the environment variable
/// name is not even compiled in, so the plist feed URL is always the one used.
enum FeedURLOverride {
    static let isDebugBuild: Bool = {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }()

    static func resolve(environment: [String: String] = ProcessInfo.processInfo.environment,
                        debugBuild: Bool = isDebugBuild) -> String? {
        guard debugBuild else { return nil }
        #if DEBUG
        guard let value = environment["LOCALPLAYER_TEST_FEED_URL"], !value.isEmpty, URL(string: value) != nil else { return nil }
        return value
        #else
        return nil
        #endif
    }
}
