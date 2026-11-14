/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import AppKit
import CoreImage
import CoreVideo
import VideoToolbox

/// Enlarges small cover art with Apple's on-device super-resolution model, for tracks
/// where no sharper copy of the cover exists online.
///
/// Only a fallback: the result is reconstructed detail, not the real cover. It returns
/// `nil` whenever the model is unavailable, so callers keep their existing image.
@available(macOS 26.0, *)
enum ArtworkUpscaler {
    /// Largest source side the image processor accepts.
    private static let maximumSourceSide = 1920
    /// Above this the cover is already sharp enough that upscaling gains little.
    private static let skipAboveSide = 1100

    static func upscale(_ image: NSImage, toward targetSide: Int, timeout: Duration) async -> NSImage? {
        await withTaskGroup(of: NSImage?.self) { group in
            group.addTask { await run(image, toward: targetSide) }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    private static func run(_ image: NSImage, toward targetSide: Int) async -> NSImage? {
        guard VTSuperResolutionScalerConfiguration.isSupported,
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return nil }

        let width = cgImage.width
        let height = cgImage.height
        let longestSide = max(width, height)
        guard longestSide <= maximumSourceSide, longestSide < skipAboveSide else { return nil }

        // Smallest supported factor that reaches the target, else the biggest available.
        let factors = VTSuperResolutionScalerConfiguration.supportedScaleFactors.sorted()
        guard let scaleFactor = factors.first(where: { longestSide * $0 >= targetSide }) ?? factors.last,
              scaleFactor > 1
        else { return nil }

        guard let configuration = VTSuperResolutionScalerConfiguration(
            frameWidth: width,
            frameHeight: height,
            scaleFactor: scaleFactor,
            inputType: .image,
            usePrecomputedFlow: false,
            qualityPrioritization: .normal,
            revision: VTSuperResolutionScalerConfiguration.defaultRevision
        ) else { return nil }

        // The model is a separate download. Start it for next time rather than make the
        // wallpaper wait for it.
        guard configuration.configurationModelStatus == .ready else {
            if configuration.configurationModelStatus == .downloadRequired {
                print("[ArtworkUpscaler] downloading super-resolution model")
                configuration.downloadConfigurationModel { error in
                    if let error {
                        print("[ArtworkUpscaler] model download failed: \(error.localizedDescription)")
                    }
                }
            }
            return nil
        }

        guard !Task.isCancelled else { return nil }

        let pixelFormat = configuration.supportedPixelFormats.contains(kCVPixelFormatType_32BGRA)
            ? kCVPixelFormatType_32BGRA
            : (configuration.supportedPixelFormats.first ?? kCVPixelFormatType_32BGRA)

        guard let sourceBuffer = makePixelBuffer(
                  width: width, height: height, format: pixelFormat,
                  attributes: configuration.sourcePixelBufferAttributes
              ),
              let destinationBuffer = makePixelBuffer(
                  width: width * scaleFactor, height: height * scaleFactor, format: pixelFormat,
                  attributes: configuration.destinationPixelBufferAttributes
              )
        else { return nil }

        let context = SharedCIContext.shared
        context.render(CIImage(cgImage: cgImage), to: sourceBuffer)

        guard let sourceFrame = VTFrameProcessorFrame(buffer: sourceBuffer, presentationTimeStamp: .zero),
              let destinationFrame = VTFrameProcessorFrame(buffer: destinationBuffer, presentationTimeStamp: .zero),
              let parameters = VTSuperResolutionScalerParameters(
                  sourceFrame: sourceFrame,
                  previousFrame: nil,
                  previousOutputFrame: nil,
                  opticalFlow: nil,
                  submissionMode: .random,
                  destinationFrame: destinationFrame
              )
        else { return nil }

        let processor = VTFrameProcessor()
        do {
            try processor.startSession(configuration: configuration)
            _ = try await processor.process(parameters: parameters)
            processor.endSession()
        } catch {
            print("[ArtworkUpscaler] processing failed: \(error.localizedDescription)")
            processor.endSession()
            return nil
        }

        let output = CIImage(cvPixelBuffer: destinationBuffer)
        guard let upscaled = context.createCGImage(output, from: output.extent) else { return nil }
        print("[ArtworkUpscaler] upscaled \(width)x\(height) -> \(upscaled.width)x\(upscaled.height)")
        return NSImage(cgImage: upscaled, size: NSSize(width: upscaled.width, height: upscaled.height))
    }

    private static func makePixelBuffer(
        width: Int,
        height: Int,
        format: OSType,
        attributes: [String: Any]
    ) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault, width, height, format, attributes as CFDictionary, &buffer
        )
        return status == kCVReturnSuccess ? buffer : nil
    }
}
