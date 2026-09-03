//
//  MacScannerInputMode.swift
//  DogLensMac
//

import SwiftUI

enum ScannerMode: String, CaseIterable, Identifiable {
    case photo = "Photo"
    case video = "Video"
    case live = "Live Camera"

    var id: String { self.rawValue }

    var icon: String {
        switch self {
        case .photo: return "camera.fill"
        case .video: return "video.fill"
        case .live: return "sparkles.tv.fill"
        }
    }
}

enum MediaInputSource: String, CaseIterable, Identifiable {
    case camera = "Webcam"
    case file = "Upload / Drop"

    var id: String { self.rawValue }

    var icon: String {
        switch self {
        case .camera: return "camera.viewfinder"
        case .file: return "square.and.arrow.down"
        }
    }
}
