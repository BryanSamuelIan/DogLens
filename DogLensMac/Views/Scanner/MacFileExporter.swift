//
//  MacFileExporter.swift
//  DogLensMac
//

import AppKit
import Photos
import UniformTypeIdentifiers

enum MacFileExporter {
    // MARK: - Save Image to File System
    static func saveImage(
        image: NSImage,
        defaultName: String,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        let savePanel = NSSavePanel()
        savePanel.title = "Save Image to File"
        savePanel.message = "Choose where to save the photo on your Mac"
        savePanel.prompt = "Save Image"
        savePanel.canCreateDirectories = true
        savePanel.showsTagField = false
        savePanel.nameFieldStringValue = defaultName
        savePanel.allowedContentTypes = [.jpeg, .png]

        if let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
            savePanel.directoryURL = downloadsURL
        }

        savePanel.begin { response in
            guard response == .OK, let url = savePanel.url else { return }

            let access = url.startAccessingSecurityScopedResource()
            defer {
                if access {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            guard let data = image.jpegData else {
                completion(.failure(NSError(domain: "ExportError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode image data"])))
                return
            }

            do {
                try data.write(to: url)
                completion(.success(url))
            } catch {
                completion(.failure(error))
            }
        }
    }

    // MARK: - Save Video to File System
    static func saveVideo(
        sourceURL: URL,
        defaultName: String,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        let savePanel = NSSavePanel()
        savePanel.title = "Save Video to File"
        savePanel.message = "Choose where to save the video on your Mac"
        savePanel.prompt = "Save Video"
        savePanel.canCreateDirectories = true
        savePanel.showsTagField = false
        savePanel.nameFieldStringValue = defaultName
        savePanel.allowedContentTypes = [.mpeg4Movie, .quickTimeMovie, .movie]

        if let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
            savePanel.directoryURL = downloadsURL
        }

        savePanel.begin { response in
            guard response == .OK, let destinationURL = savePanel.url else { return }

            let access = destinationURL.startAccessingSecurityScopedResource()
            defer {
                if access {
                    destinationURL.stopAccessingSecurityScopedResource()
                }
            }

            do {
                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    try FileManager.default.removeItem(at: destinationURL)
                }
                try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
                completion(.success(destinationURL))
            } catch {
                completion(.failure(error))
            }
        }
    }

    // MARK: - Save Image to Apple Photos Library
    static func saveImageToPhotos(
        image: NSImage,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        PHPhotoLibrary.requestAuthorization { status in
            DispatchQueue.main.async {
                guard status == .authorized || status == .limited else {
                    completion(.failure(NSError(domain: "PhotosError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Photo library access denied. Please allow access in System Settings."])))
                    return
                }

                guard let tiffData = image.tiffRepresentation,
                      let bitmap = NSBitmapImageRep(data: tiffData),
                      let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.9]) else {
                    completion(.failure(NSError(domain: "PhotosError", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to encode photo data."])))
                    return
                }

                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("temp_photo_\(UUID().uuidString).jpg")
                do {
                    try jpegData.write(to: tempURL)
                    PHPhotoLibrary.shared().performChanges({
                        PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: tempURL)
                    }) { success, error in
                        try? FileManager.default.removeItem(at: tempURL)
                        DispatchQueue.main.async {
                            if success {
                                completion(.success(()))
                            } else {
                                completion(.failure(error ?? NSError(domain: "PhotosError", code: -3, userInfo: [NSLocalizedDescriptionKey: "Unknown photo save error."])))
                            }
                        }
                    }
                } catch {
                    completion(.failure(error))
                }
            }
        }
    }

    // MARK: - Save Video to Apple Photos Library
    static func saveVideoToPhotos(
        videoURL: URL,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        PHPhotoLibrary.requestAuthorization { status in
            DispatchQueue.main.async {
                guard status == .authorized || status == .limited else {
                    completion(.failure(NSError(domain: "PhotosError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Photo library access denied. Please allow access in System Settings."])))
                    return
                }

                PHPhotoLibrary.shared().performChanges({
                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: videoURL)
                }) { success, error in
                    DispatchQueue.main.async {
                        if success {
                            completion(.success(()))
                        } else {
                            completion(.failure(error ?? NSError(domain: "PhotosError", code: -3, userInfo: [NSLocalizedDescriptionKey: "Unknown video save error."])))
                        }
                    }
                }
            }
        }
    }
}
