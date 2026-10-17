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

    /// Decided Oct 17, 2026 (04 §5.1): heavy reasoning goes to Apple's cloud model unless the cook
    /// picks Claude in Profile → Intelligence. Extraction and classification always stay on device.
    public static let defaultHeavyReasoning: ModelTier = .appleCloud
    public static let defaultExtraction: ModelTier = .onDevice
}

/// What a prompt is for; decides which tier answers it (02 §4.3).
public enum ModelTask: String, Sendable, Codable, CaseIterable {
    /// Structuring OCR text, parsing ingredients, classifying a recipe, short summaries.
    case extraction
    /// Menu conversation, pairing notes, balance commentary.
    case heavyReasoning
}

public enum ModelRouting {
    /// The tier for a task given the cook's preferred heavy-reasoning tier. On-device never
    /// escalates; a preference for on-device only is honored for heavy reasoning too.
    public static func tier(for task: ModelTask, preferredHeavyReasoning: ModelTier = ModelTier.defaultHeavyReasoning) -> ModelTier {
        switch task {
        case .extraction: return ModelTier.defaultExtraction
        case .heavyReasoning: return preferredHeavyReasoning
        }
    }
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
