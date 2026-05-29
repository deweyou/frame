import AppKit
import FrameCore
import Vision

enum OCRServiceError: LocalizedError {
    case cgImageUnavailable
    case recognitionFailed(Error)

    var errorDescription: String? {
        switch self {
        case .cgImageUnavailable:
            "The screenshot image could not be prepared for text recognition."
        case let .recognitionFailed(error):
            error.localizedDescription
        }
    }
}

final class OCRService: Sendable {
    @MainActor
    func recognizeText(in screenshot: CapturedScreenshot) async throws -> RecognizedTextLayout {
        guard let cgImage = screenshot.image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw OCRServiceError.cgImageUnavailable
        }

        return try await recognizeText(in: cgImage)
    }

    nonisolated func recognizeText(in image: CGImage) async throws -> RecognizedTextLayout {
        try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try handler.perform([request])
            } catch {
                throw OCRServiceError.recognitionFailed(error)
            }

            let lines = (request.results ?? []).compactMap { observation -> RecognizedTextLine? in
                guard let candidate = observation.topCandidates(1).first else {
                    return nil
                }

                return makeRecognizedTextLine(
                    text: candidate.string,
                    normalizedBounds: observation.boundingBox,
                    confidence: candidate.confidence
                )
            }

            return makeRecognizedTextLayout(lines: lines)
        }.value
    }
}

func makeRecognizedTextLine(
    text: String,
    normalizedBounds: CGRect,
    confidence: Float?
) -> RecognizedTextLine {
    RecognizedTextLine(
        text: text,
        bounds: NormalizedImageRect(
            x: normalizedBounds.origin.x,
            y: normalizedBounds.origin.y,
            width: normalizedBounds.width,
            height: normalizedBounds.height
        ),
        confidence: confidence
    )
}

func makeRecognizedTextLayout(lines: [RecognizedTextLine]) -> RecognizedTextLayout {
    RecognizedTextLayout(lines: lines)
}
