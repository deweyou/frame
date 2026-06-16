import AVFoundation
import Foundation
import FrameCore

enum VideoEditingExportError: Equatable, Error {
    case unsupportedFormat
    case invalidRange
    case exportFailed(String)
}

@MainActor
protocol VideoEditingExporting {
    func export(sourceURL: URL, format: RecordingFormat, editingState: VideoEditingState) async throws -> URL
}

final class VideoEditingExporter: VideoEditingExporting {
    private let fileManager: FileManager
    private let temporaryDirectory: () -> URL

    init(
        fileManager: FileManager = .default,
        temporaryDirectory: @escaping () -> URL = {
            FileManager.default.temporaryDirectory
                .appendingPathComponent("FrameVideoEdits", isDirectory: true)
        }
    ) {
        self.fileManager = fileManager
        self.temporaryDirectory = temporaryDirectory
    }

    func export(
        sourceURL: URL,
        format: RecordingFormat,
        editingState: VideoEditingState
    ) async throws -> URL {
        guard format == .mp4 else {
            throw VideoEditingExportError.unsupportedFormat
        }
        guard editingState.selectedDuration >= VideoEditingState.minimumSelectedDuration else {
            throw VideoEditingExportError.invalidRange
        }

        let directory = temporaryDirectory()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let outputURL = directory.appendingPathComponent("Frame Edited-\(UUID().uuidString).mp4")
        if fileManager.fileExists(atPath: outputURL.path) {
            try fileManager.removeItem(at: outputURL)
        }

        let asset = AVURLAsset(url: sourceURL)
        let composition = AVMutableComposition()
        let sourceRange = CMTimeRange(
            start: CMTime(seconds: editingState.startTime, preferredTimescale: 600),
            duration: CMTime(seconds: editingState.selectedDuration, preferredTimescale: 600)
        )
        let scaledDuration = CMTime(seconds: editingState.outputDuration, preferredTimescale: 600)

        let sourceVideoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let sourceVideoTrack = sourceVideoTracks.first,
              let compositionVideoTrack = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
              ) else {
            throw VideoEditingExportError.exportFailed("MP4 没有可编辑的视频轨道。")
        }

        do {
            try compositionVideoTrack.insertTimeRange(sourceRange, of: sourceVideoTrack, at: .zero)
        } catch {
            throw VideoEditingExportError.exportFailed(error.localizedDescription)
        }

        compositionVideoTrack.preferredTransform = try await sourceVideoTrack.load(.preferredTransform)
        compositionVideoTrack.scaleTimeRange(
            CMTimeRange(start: .zero, duration: sourceRange.duration),
            toDuration: scaledDuration
        )

        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw VideoEditingExportError.exportFailed("无法创建 MP4 导出会话。")
        }
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true
        await runExport(exportSession)

        guard exportSession.status == .completed else {
            throw VideoEditingExportError.exportFailed(
                exportSession.error?.localizedDescription ?? "MP4 导出失败。"
            )
        }

        return outputURL
    }

    private func runExport(_ exportSession: AVAssetExportSession) async {
        await withCheckedContinuation { continuation in
            exportSession.exportAsynchronously {
                continuation.resume()
            }
        }
    }
}
