import FileMailerDomain
import Foundation

public enum GenerationApplicationResult: Sendable, Equatable {
    case applied
    case suggestion(GeneratedDraftSnapshot)
}

public struct DraftRevisionPolicy: Sendable {
    public init() {}

    public func apply(
        _ generated: GeneratedDraftSnapshot,
        generationStartedAt revision: UInt64,
        to draft: inout ComposeDraft
    ) -> GenerationApplicationResult {
        guard draft.userRevision == revision else {
            draft.generationState = .suggestionAvailable
            return .suggestion(generated)
        }
        draft.subject = generated.subject
        draft.body = generated.body
        draft.generationState = generated.isFinal ? .generated : .generating
        return .applied
    }
}
