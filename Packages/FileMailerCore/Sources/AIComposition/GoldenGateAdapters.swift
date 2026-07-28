import FileMailerDomain
import Foundation

public enum GoldenGateFeatureStatus: Sendable, Equatable {
    case compiled

    public static var current: Self {
        .compiled
    }
}

@available(macOS 27.0, *)
public struct GoldenGateDraftGenerator: EmailDraftGenerating {
    private let onDevice = OnDeviceFoundationModelDraftGenerator()

    public init() {}

    public func streamDraft(
        request: DraftGenerationRequest
    ) -> AsyncThrowingStream<GeneratedDraftSnapshot, Error> {
        onDevice.streamDraft(request: request)
    }
}
