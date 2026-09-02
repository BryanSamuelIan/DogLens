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
    private let sessionQueue = DispatchQueue(label: "com.doglens.macCameraSessionQueue")
    private let photoOutput = AVCapturePhotoOutput()
    private var currentInput: AVCaptureDeviceInput?
    private var isConfigured = false

    private var photoContinuation: CheckedContinuation<NSImage, Error>?

    override init() {
        super.init()
    }

    func setup() {
        checkPermissions()
    }

    func checkPermissions() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.authorizationStatus = status
            if status == .authorized {
                self.discoverDevices()
            } else if status == .notDetermined {
                AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                    DispatchQueue.main.async {
                        guard let self = self else { return }
                        self.authorizationStatus = granted ? .authorized : .denied
                        if granted {
                            self.discoverDevices()
                        }
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

        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self.session.beginConfiguration()
            if let currentInput = self.currentInput {
                self.session.removeInput(currentInput)
                self.currentInput = nil
            }

            if let newInput = try? AVCaptureDeviceInput(device: device),
               self.session.canAddInput(newInput) {
                self.session.addInput(newInput)
                self.currentInput = newInput
            }
            self.session.commitConfiguration()
        }
    }

    func startSession() {
        guard authorizationStatus == .authorized else { return }

        sessionQueue.async { [weak self] in
            guard let self = self else { return }

            if !self.isConfigured {
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
                self.isConfigured = true
            }

            if !self.session.isRunning {
                self.session.startRunning()
                let running = self.session.isRunning
                DispatchQueue.main.async {
                    self.isRunning = running
                }
            }
        }
    }

    func stopSession() {
        sessionQueue.async { [weak self] in
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
            sessionQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume(throwing: NSError(domain: "CameraError", code: -3, userInfo: [NSLocalizedDescriptionKey: "Camera manager deallocated"]))
                    return
                }
                self.photoContinuation = continuation
                let settings = AVCapturePhotoSettings()
                self.photoOutput.capturePhoto(with: settings, delegate: self)
            }
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

final class MacCameraPreviewNSView: NSView {
    private var previewLayer: AVCaptureVideoPreviewLayer?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
    }

    func setSession(_ session: AVCaptureSession) {
        if previewLayer == nil {
            let layer = AVCaptureVideoPreviewLayer(session: session)
            layer.videoGravity = .resizeAspectFill
            self.layer?.addSublayer(layer)
            self.previewLayer = layer
        } else {
            previewLayer?.session = session
        }
        previewLayer?.frame = bounds
    }

    override func layout() {
        super.layout()
        previewLayer?.frame = bounds
    }
}

struct MacCameraPreviewView: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> MacCameraPreviewNSView {
        let view = MacCameraPreviewNSView()
        view.setSession(session)
        return view
    }

    func updateNSView(_ nsView: MacCameraPreviewNSView, context: Context) {
        nsView.setSession(session)
    }
}
