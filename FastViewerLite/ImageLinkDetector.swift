//
//  ImageLinkDetector.swift
//  FastViewer Lite
//

import AppKit
import Vision

struct DetectedImageLink: Equatable {
    let url: URL
    /// Vision-normalized coordinates with the origin at the lower-left corner.
    let normalizedBounds: CGRect
}

/// Finds web links in an image using only the on-device Vision and Foundation APIs.
///
/// Requests run one at a time at utility priority so OCR never competes with image
/// navigation for the main thread or the user-initiated decode queue.
final class ImageLinkDetector {
    static let shared = ImageLinkDetector()

    private let operationQueue: OperationQueue

    private init() {
        operationQueue = OperationQueue()
        operationQueue.name = "com.fastviewer.imageLinkDetection"
        operationQueue.qualityOfService = .utility
        operationQueue.maxConcurrentOperationCount = 1
    }

    @discardableResult
    func detectLinks(
        in image: CGImage,
        completion: @escaping ([DetectedImageLink]) -> Void
    ) -> Operation {
        let operation = BlockOperation()
        operation.addExecutionBlock { [weak operation] in
            guard let operation, !operation.isCancelled else { return }

            let links = autoreleasepool {
                Self.performDetection(in: image, shouldCancel: { operation.isCancelled })
            }

            guard !operation.isCancelled else { return }
            DispatchQueue.main.async {
                guard !operation.isCancelled else { return }
                completion(links)
            }
        }
        operationQueue.addOperation(operation)
        return operation
    }

    static func links(
        in text: String,
        normalizedTextBounds: CGRect,
        boundsForRange: (Range<String.Index>) -> CGRect?
    ) -> [DetectedImageLink] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return []
        }

        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        return detector.matches(in: text, options: [], range: fullRange).compactMap { match in
            guard let url = match.url,
                  let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https",
                  let stringRange = Range(match.range, in: text) else {
                return nil
            }

            return DetectedImageLink(
                url: url,
                normalizedBounds: boundsForRange(stringRange) ?? normalizedTextBounds
            )
        }
    }

    private static func performDetection(
        in sourceImage: CGImage,
        shouldCancel: @escaping () -> Bool
    ) -> [DetectedImageLink] {
        guard !shouldCancel(),
              let analysisImage = downsampledImage(sourceImage, maximumDimension: 1_600),
              !shouldCancel() else {
            return []
        }

        guard let fastObservations = recognizeText(
            in: analysisImage,
            level: .fast,
            shouldCancel: shouldCancel
        ) else {
            return []
        }

        let fastLinks = links(in: fastObservations, shouldCancel: shouldCancel)
        guard fastLinks.isEmpty,
              !shouldCancel(),
              fastObservations.contains(where: observationMayContainURL) else {
            return shouldCancel() ? [] : fastLinks
        }

        // The fast recognizer can confuse URL slashes with I/l in small browser
        // text (for example, "https:Il"). Use the accurate on-device recognizer
        // only for URL-looking text that the inexpensive pass couldn't parse.
        guard let accurateObservations = recognizeText(
            in: analysisImage,
            level: .accurate,
            shouldCancel: shouldCancel
        ) else {
            return []
        }
        return links(in: accurateObservations, shouldCancel: shouldCancel)
    }

    private static func recognizeText(
        in image: CGImage,
        level: VNRequestTextRecognitionLevel,
        shouldCancel: @escaping () -> Bool
    ) -> [VNRecognizedTextObservation]? {
        guard !shouldCancel() else { return nil }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = level
        request.usesLanguageCorrection = false
        request.minimumTextHeight = 0.008

        do {
            try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        } catch {
            return nil
        }
        return shouldCancel() ? nil : request.results
    }

    private static func links(
        in observations: [VNRecognizedTextObservation],
        shouldCancel: () -> Bool
    ) -> [DetectedImageLink] {
        var detectedLinks: [DetectedImageLink] = []
        for observation in observations {
            guard !shouldCancel(),
                  let candidate = observation.topCandidates(1).first else {
                break
            }

            detectedLinks.append(contentsOf: links(
                in: candidate.string,
                normalizedTextBounds: observation.boundingBox,
                boundsForRange: { range in
                    (try? candidate.boundingBox(for: range))?.boundingBox
                }
            ))
        }
        return shouldCancel() ? [] : detectedLinks
    }

    static func textMayContainURL(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        return lowercased.contains("http") || lowercased.contains("www.")
    }

    private static func observationMayContainURL(_ observation: VNRecognizedTextObservation) -> Bool {
        observation.topCandidates(3).contains { textMayContainURL($0.string) }
    }

    private static func downsampledImage(
        _ image: CGImage,
        maximumDimension: Int
    ) -> CGImage? {
        let longestSide = max(image.width, image.height)
        guard longestSide > maximumDimension else {
            return image
        }

        let scale = CGFloat(maximumDimension) / CGFloat(longestSide)
        let width = max(1, Int((CGFloat(image.width) * scale).rounded()))
        let height = max(1, Int((CGFloat(image.height) * scale).rounded()))
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}
