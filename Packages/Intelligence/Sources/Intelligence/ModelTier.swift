import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Which model answers a request. Every prompt in the app goes through this package so the
/// tier can be swapped in Settings without touching views.
public enum ModelTier: String, Sendable, Codable, CaseIterable {
    /// Apple's on-device Foundation Model. Private, free, ~4k token context.
    case onDevice
    /// Apple's larger model on Private Cloud Compute. Requires Developer Program enrollment.
    case appleCloud
    /// Claude via ClaudeForFoundationModels. Billed; strongest reasoning.
    case claude
}

/// Why a tier is not usable right now, mirrored into the UI as the HIG asks.
public enum ModelUnavailability: Sendable, Equatable {
    case deviceNotEligible
    case appleIntelligenceNotEnabled
    case modelNotReady
    case notConfigured
    case unknown
}

public enum ModelAvailability {
    /// Availability of the on-device model. Always `.notConfigured` on platforms without FoundationModels,
    /// so callers must have a deterministic path (04 §1: "deterministic first, model second").
    public static func onDevice() -> Result<Void, ModelUnavailabilityError> {
        #if canImport(FoundationModels)
        switch SystemLanguageModel.default.availability {
        case .available:
            return .success(())
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible: return .failure(.init(reason: .deviceNotEligible))
            case .appleIntelligenceNotEnabled: return .failure(.init(reason: .appleIntelligenceNotEnabled))
            case .modelNotReady: return .failure(.init(reason: .modelNotReady))
            @unknown default: return .failure(.init(reason: .unknown))
            }
        }
        #else
        return .failure(.init(reason: .notConfigured))
        #endif
    }
}

public struct ModelUnavailabilityError: Error, Sendable, Equatable {
    public let reason: ModelUnavailability
    public init(reason: ModelUnavailability) { self.reason = reason }
}
