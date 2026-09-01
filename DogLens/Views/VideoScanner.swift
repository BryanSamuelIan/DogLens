import SwiftUI
import AVFoundation

// MARK: - SwiftUI Representable
// Full UIKit controller lives in VideoCameraViewController.swift

struct VideoScannerView: UIViewControllerRepresentable {
    var isActive: Bool
    var onRecordingFinished: (URL) -> Void
    var onClose: () -> Void

    func makeUIViewController(context: Context) -> VideoCameraViewController {
        let vc = VideoCameraViewController()
        vc.onRecordingFinished = onRecordingFinished
        vc.onClose = onClose
        vc.setActive(isActive)
        return vc
    }

    func updateUIViewController(_ uiViewController: VideoCameraViewController, context: Context) {
        uiViewController.onRecordingFinished = onRecordingFinished
        uiViewController.onClose = onClose
        uiViewController.setActive(isActive)
    }
}
