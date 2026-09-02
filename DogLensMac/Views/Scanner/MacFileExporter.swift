//
//  MacFileExporter.swift
//  DogLensMac
//

import AppKit
import UniformTypeIdentifiers

enum MacFileExporter {
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
}
