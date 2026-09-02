//
//  MacScannerInputMode.swift
//  DogLensMac
//

import SwiftUI

enum InputMode: String, CaseIterable, Identifiable {
    case webcam = "Live Camera"
    case fileDrop = "Upload / Drop Image"

    var id: String { self.rawValue }

    var icon: String {
        switch self {
        case .webcam: return "camera.fill"
        case .fileDrop: return "photo.on.rectangle.angled"
        }
    }
}
