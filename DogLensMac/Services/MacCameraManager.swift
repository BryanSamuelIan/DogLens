import Foundation
import AVFoundation
import AppKit
import SwiftUI

struct CameraDevice: Identifiable, Hashable {
    let id: String
    let name: String
    let device: AVCaptureDevice
}

@Observable
final class MacCameraManager: NSObject, AVCapturePhotoCaptureDelegate {
    var availableDevices: [CameraDevice] = []
    var selectedDeviceID: String = ""
    var isRunning: Bool = false
    var authorizationStatus: AVAuthorizationStatus = .notDetermined

    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private var currentInput: AVCaptureDeviceInput?

    private var photoContinuation: CheckedContinuation<NSImage, Error>?

    override init() {
        super.init()
        checkPermissions()
    }

    func checkPermissions() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        self.authorizationStatus = status
        if status == .authorized {
            discoverDevices()
            startSession()
        } else if status == .notDetermined {
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.authorizationStatus = granted ? .authorized : .denied
                    if granted {
                        self?.discoverDevices()
                        self?.startSession()
                    }
                }
            }
        }
    }

    func discoverDevices() {
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [
                .builtInWideAngleCamera,
                .external,
                .continuityCamera
            ],
            mediaType: .video,
            position: .unspecified
        )

        let devices = discoverySession.devices.map {
            CameraDevice(id: $0.uniqueID, name: $0.localizedName, device: $0)
        }

        self.availableDevices = devices
        if let first = devices.first, selectedDeviceID.isEmpty {
            self.selectedDeviceID = first.id
        }
    }

    func selectDevice(id: String) {
        guard let device = availableDevices.first(where: { $0.id == id })?.device else { return }
        self.selectedDeviceID = id

        session.beginConfiguration()
        if let currentInput = currentInput {
            session.removeInput(currentInput)
        }

        do {
            let newInput = try AVCaptureDeviceInput(device: device)
            if session.canAddInput(newInput) {
                session.addInput(newInput)
                self.currentInput = newInput
            }
        } catch {
            print("Failed to set camera device input: \(error)")
        }
        session.commitConfiguration()
    }

    func startSession() {
        guard authorizationStatus == .authorized else { return }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            if self.session.inputs.isEmpty {
                self.session.beginConfiguration()
                self.session.sessionPreset = .photo

                let targetDevice = self.availableDevices.first(where: { $0.id == self.selectedDeviceID })?.device
                    ?? AVCaptureDevice.default(for: .video)

                if let device = targetDevice,
                   let input = try? AVCaptureDeviceInput(device: device),
                   self.session.canAddInput(input) {
                    self.session.addInput(input)
                    self.currentInput = input
                }

                if self.session.canAddOutput(self.photoOutput) {
                    self.session.addOutput(self.photoOutput)
                }

                self.session.commitConfiguration()
            }

            if !self.session.isRunning {
                self.session.startRunning()
                DispatchQueue.main.async {
                    self.isRunning = true
                }
            }
        }
    }

    func stopSession() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            if self.session.isRunning {
                self.session.stopRunning()
                DispatchQueue.main.async {
                    self.isRunning = false
                }
            }
        }
    }

    func capturePhoto() async throws -> NSImage {
        guard isRunning else {
            throw NSError(domain: "CameraError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Camera session is not active"])
        }

        return try await withCheckedThrowingContinuation { continuation in
            self.photoContinuation = continuation
            let settings = AVCapturePhotoSettings()
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    // MARK: - AVCapturePhotoCaptureDelegate
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            photoContinuation?.resume(throwing: error)
            photoContinuation = nil
            return
        }

        guard let data = photo.fileDataRepresentation(),
              let image = NSImage(data: data) else {
            photoContinuation?.resume(throwing: NSError(domain: "CameraError", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to decode captured photo"]))
            photoContinuation = nil
            return
        }

        photoContinuation?.resume(returning: image)
        photoContinuation = nil
    }
}

// MARK: - AppKit Camera Preview View Representable for SwiftUI

struct MacCameraPreviewView: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        view.layer = previewLayer
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let previewLayer = nsView.layer as? AVCaptureVideoPreviewLayer {
            previewLayer.frame = nsView.bounds
        }
    }
}
