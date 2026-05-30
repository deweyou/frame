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
            configureTextRecognitionRequest(request)

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
                    confidence: candidate.confidence,
                    tokens: makeRecognizedTextTokens(
                        in: candidate,
                        lineBounds: observation.boundingBox
                    )
                )
            }

            return makeRecognizedTextLayout(lines: lines)
        }.value
    }
}

func configureTextRecognitionRequest(
    _ request: VNRecognizeTextRequest,
    recognitionLanguages: [String] = SettingsStore.ocrRecognitionLanguages()
) {
    request.recognitionLevel = .accurate
    request.recognitionLanguages = OCRLanguageOption.validatedIdentifiers(recognitionLanguages)
    request.usesLanguageCorrection = true
}

func makeRecognizedTextLine(
    text: String,
    normalizedBounds: CGRect,
    confidence: Float?,
    tokens: [RecognizedTextToken] = []
) -> RecognizedTextLine {
    RecognizedTextLine(
        text: text,
        bounds: NormalizedImageRect(
            x: normalizedBounds.origin.x,
            y: normalizedBounds.origin.y,
            width: normalizedBounds.width,
            height: normalizedBounds.height
        ),
        confidence: confidence,
        tokens: tokens
    )
}

func makeRecognizedTextLayout(lines: [RecognizedTextLine]) -> RecognizedTextLayout {
    RecognizedTextLayout(lines: lines)
}

func makeRecognizedTextTokens(
    in recognizedText: VNRecognizedText,
    lineBounds: CGRect
) -> [RecognizedTextToken] {
    let fallbackBounds = NormalizedImageRect(
        x: lineBounds.origin.x,
        y: lineBounds.origin.y,
        width: lineBounds.width,
        height: lineBounds.height
    )

    return RecognizedTextCutLayout.tokenizerCandidates(in: recognizedText.string).map { candidate in
        let tokenBounds: NormalizedImageRect
        if let observation = try? recognizedText.boundingBox(for: candidate.range) {
            tokenBounds = NormalizedImageRect(
                x: observation.boundingBox.origin.x,
                y: observation.boundingBox.origin.y,
                width: observation.boundingBox.width,
                height: observation.boundingBox.height
            )
        } else {
            tokenBounds = fallbackBounds
        }

        return RecognizedTextToken(
            text: candidate.text,
            bounds: tokenBounds,
            needsLeadingSpace: candidate.needsLeadingSpace
        )
    }
}
