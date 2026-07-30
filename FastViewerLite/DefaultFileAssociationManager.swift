//
//  DefaultFileAssociationManager.swift
//  FastViewer
//
//  Created by Alexander Deplov on 18.12.25.
//

import AppKit
import UniformTypeIdentifiers

/// Manages explicit, user-initiated changes to the default apps for supported images.
final class DefaultFileAssociationManager {

    enum State {
        case available
        case managedByFastViewer
        case alreadyDefault
    }

    struct AssociationError: LocalizedError {
        let operation: String
        let formats: [String]

        var errorDescription: String? {
            "\(operation) failed for: \(formats.joined(separator: ", "))."
        }
    }

    static let shared = DefaultFileAssociationManager()

    private struct ImageType {
        let identifier: String
        let displayName: String

        var type: UTType? {
            UTType(identifier)
        }
    }

    private let imageTypes = [
        ImageType(identifier: "public.jpeg", displayName: "JPEG"),
        ImageType(identifier: "public.png", displayName: "PNG"),
        ImageType(identifier: "org.webmproject.webp", displayName: "WebP"),
        ImageType(identifier: "public.avif", displayName: "AVIF"),
        ImageType(identifier: "public.heic", displayName: "HEIC"),
        ImageType(identifier: "public.heif", displayName: "HEIF")
    ]

    private let previousHandlersKey = "PreviousDefaultImageHandlers"
    private let previewBundleIdentifier = "com.apple.Preview"
    private let workspace: NSWorkspace

    private var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "com.aleksandr.deplov.FastViewerLite"
    }

    private var previousHandlers: [String: String] {
        get {
            UserDefaults.standard.dictionary(forKey: previousHandlersKey) as? [String: String] ?? [:]
        }
        set {
            if newValue.isEmpty {
                UserDefaults.standard.removeObject(forKey: previousHandlersKey)
            } else {
                UserDefaults.standard.set(newValue, forKey: previousHandlersKey)
            }
        }
    }

    private init(workspace: NSWorkspace = .shared) {
        self.workspace = workspace
    }

    var state: State {
        if !previousHandlers.isEmpty {
            return .managedByFastViewer
        }
        return isDefaultHandlerForAllTypes() ? .alreadyDefault : .available
    }

    func isDefaultHandlerForAllTypes() -> Bool {
        imageTypes.allSatisfy { imageType in
            guard let type = imageType.type,
                  let appURL = workspace.urlForApplication(toOpen: type) else {
                return false
            }
            return Bundle(url: appURL)?.bundleIdentifier == bundleIdentifier
        }
    }

    /// Captures the current handlers, then makes FastViewer the default.
    /// Nothing is changed unless this method is called explicitly by the user.
    func setAsDefaultHandler(completion: @escaping (Result<Void, Error>) -> Void) {
        var snapshot: [String: String] = [:]
        var unavailableFormats: [String] = []

        for imageType in imageTypes {
            guard let type = imageType.type,
                  let appURL = workspace.urlForApplication(toOpen: type),
                  let handlerBundleIdentifier = Bundle(url: appURL)?.bundleIdentifier else {
                unavailableFormats.append(imageType.displayName)
                continue
            }
            snapshot[imageType.identifier] = handlerBundleIdentifier
        }

        guard unavailableFormats.isEmpty else {
            completion(.failure(AssociationError(
                operation: "Could not determine the current default app",
                formats: unavailableFormats
            )))
            return
        }

        setFastViewer(
            at: 0,
            changedTypes: [],
            snapshot: snapshot,
            completion: completion
        )
    }

    /// Restores the app that handled each image type before FastViewer.
    func restorePreviousHandlers(completion: @escaping (Result<Void, Error>) -> Void) {
        let snapshot = previousHandlers
        guard !snapshot.isEmpty else {
            completion(.success(()))
            return
        }

        restore(
            types: imageTypes,
            at: 0,
            snapshot: snapshot,
            failedFormats: []
        ) { [weak self] failedFormats in
            guard let self else { return }
            if failedFormats.isEmpty {
                self.previousHandlers = [:]
                completion(.success(()))
            } else {
                completion(.failure(AssociationError(
                    operation: "Could not restore the previous default app",
                    formats: failedFormats
                )))
            }
        }
    }

    /// Uses Preview when FastViewer is already the default but no previous
    /// handlers were captured (for example, when the user changed them in Finder).
    func restoreDefaultHandlers(completion: @escaping (Result<Void, Error>) -> Void) {
        guard workspace.urlForApplication(
            withBundleIdentifier: previewBundleIdentifier
        ) != nil else {
            completion(.failure(AssociationError(
                operation: "Could not find the default image app",
                formats: imageTypes.map(\.displayName)
            )))
            return
        }

        let snapshot = Dictionary(
            uniqueKeysWithValues: imageTypes.map {
                ($0.identifier, previewBundleIdentifier)
            }
        )

        restore(
            types: imageTypes,
            at: 0,
            snapshot: snapshot,
            failedFormats: []
        ) { failedFormats in
            if failedFormats.isEmpty {
                completion(.success(()))
            } else {
                completion(.failure(AssociationError(
                    operation: "Could not restore the default image app",
                    formats: failedFormats
                )))
            }
        }
    }

    private func setFastViewer(
        at index: Int,
        changedTypes: [ImageType],
        snapshot: [String: String],
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard index < imageTypes.count else {
            previousHandlers = snapshot
            completion(.success(()))
            return
        }

        let imageType = imageTypes[index]
        guard let type = imageType.type else {
            rollback(changedTypes: changedTypes, snapshot: snapshot) {
                completion(.failure(AssociationError(
                    operation: "Could not set FastViewer as the default app",
                    formats: [imageType.displayName]
                )))
            }
            return
        }

        workspace.setDefaultApplication(
            at: Bundle.main.bundleURL,
            toOpen: type
        ) { [weak self] error in
            guard let self else { return }
            if error != nil {
                self.rollback(changedTypes: changedTypes, snapshot: snapshot) {
                    completion(.failure(AssociationError(
                        operation: "Could not set FastViewer as the default app",
                        formats: [imageType.displayName]
                    )))
                }
            } else {
                self.setFastViewer(
                    at: index + 1,
                    changedTypes: changedTypes + [imageType],
                    snapshot: snapshot,
                    completion: completion
                )
            }
        }
    }

    private func rollback(
        changedTypes: [ImageType],
        snapshot: [String: String],
        completion: @escaping () -> Void
    ) {
        restore(
            types: changedTypes,
            at: 0,
            snapshot: snapshot,
            failedFormats: []
        ) { _ in
            completion()
        }
    }

    private func restore(
        types: [ImageType],
        at index: Int,
        snapshot: [String: String],
        failedFormats: [String],
        completion: @escaping ([String]) -> Void
    ) {
        guard index < types.count else {
            completion(failedFormats)
            return
        }

        let imageType = types[index]
        guard let type = imageType.type,
              let previousBundleIdentifier = snapshot[imageType.identifier],
              let appURL = workspace.urlForApplication(withBundleIdentifier: previousBundleIdentifier) else {
            restore(
                types: types,
                at: index + 1,
                snapshot: snapshot,
                failedFormats: failedFormats + [imageType.displayName],
                completion: completion
            )
            return
        }

        workspace.setDefaultApplication(at: appURL, toOpen: type) { [weak self] error in
            guard let self else { return }
            self.restore(
                types: types,
                at: index + 1,
                snapshot: snapshot,
                failedFormats: error == nil
                    ? failedFormats
                    : failedFormats + [imageType.displayName],
                completion: completion
            )
        }
    }
}
