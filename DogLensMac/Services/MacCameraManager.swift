//
//  MacCameraManager.swift
//  DogLensMac
//

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
final class MacCameraManager: NSObject, AVCapturePhotoCaptureDelegate, AVCaptureFileOutputRecordingDelegate, AVCaptureVideoDataOutputSampleBufferDelegate {
    var availableDevices: [CameraDevice] = []
    var selectedDeviceID: String = ""
    var isRunning: Bool = false
    var isRecording: Bool = false
    var recordingDuration: TimeInterval = 0.0
    var authorizationStatus: AVAuthorizationStatus = .notDetermined

    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.doglens.macCameraSessionQueue")
    private let videoDataOutputQueue = DispatchQueue(label: "com.doglens.macVideoDataOutputQueue", qos: .userInitiated)
    
    private let photoOutput = AVCapturePhotoOutput()
    private let movieOutput = AVCaptureMovieFileOutput()
    private let videoDataOutput = AVCaptureVideoDataOutput()
    
    private var currentInput: AVCaptureDeviceInput?
    private var isConfigured = false
    
    private var recordingTimer: Timer?
    private var recordingStartDate: Date?
    private var recordingCompletion: ((Result<URL, Error>) -> Void)?
    private var photoContinuation: CheckedContinuation<NSImage, Error>?
    
    // Live Frame Streaming Callback
    var onSampleBufferReceived: ((CMSampleBuffer) -> Void)?

    override init() {
        super.init()
    }

    func setup() {
        checkPermissions()
    }

    func checkPermissions(autoStart: Bool = false) {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.authorizationStatus = status
            if status == .authorized {
                self.discoverDevices()
                if autoStart {
                    self.startSession()
                }
            } else if status == .notDetermined {
                AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                    DispatchQueue.main.async {
                        guard let self = self else { return }
                        self.authorizationStatus = granted ? .authorized : .denied
                        if granted {
                            self.discoverDevices()
                            if autoStart {
                                self.startSession()
                            }
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
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        if status != .authorized {
            checkPermissions(autoStart: true)
            return
        }

        self.authorizationStatus = .authorized
        if availableDevices.isEmpty {
            discoverDevices()
        }

        sessionQueue.async { [weak self] in
            guard let self = self else { return }

            if !self.isConfigured {
                self.session.beginConfiguration()
                self.session.sessionPreset = .high

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
                
                if self.session.canAddOutput(self.movieOutput) {
                    self.session.addOutput(self.movieOutput)
                }
                
                self.videoDataOutput.alwaysDiscardsLateVideoFrames = true
                self.videoDataOutput.videoSettings = [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
                ]
                self.videoDataOutput.setSampleBufferDelegate(self, queue: self.videoDataOutputQueue)
                
                if self.session.canAddOutput(self.videoDataOutput) {
                    self.session.addOutput(self.videoDataOutput)
                }

                self.session.commitConfiguration()
                self.isConfigured = true
            }

            if !self.session.isRunning {
                self.session.startRunning()
            }

            let running = self.session.isRunning
            DispatchQueue.main.async {
                self.isRunning = running
            }
        }
    }

    func stopSession() {
        if isRecording {
            stopRecordingVideo()
        }
        
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            if self.session.isRunning {
                self.session.stopRunning()
            }
            DispatchQueue.main.async {
                self.isRunning = false
            }
        }
    }

    // MARK: - Photo Capture
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

    // MARK: - Video Recording
    func startRecordingVideo(completion: @escaping (Result<URL, Error>) -> Void) {
        guard isRunning else {
            completion(.failure(NSError(domain: "CameraError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Camera session is not active"])))
            return
        }
        
        guard !isRecording else {
            completion(.failure(NSError(domain: "CameraError", code: -4, userInfo: [NSLocalizedDescriptionKey: "Recording is already in progress"])))
            return
        }

        self.recordingCompletion = completion
        
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("mac_webcam_rec_\(UUID().uuidString)")
            .appendingPathExtension("mp4")
            
        try? FileManager.default.removeItem(at: tempURL)

        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self.movieOutput.startRecording(to: tempURL, recordingDelegate: self)
            
            DispatchQueue.main.async {
                self.isRecording = true
                self.recordingStartDate = Date()
                self.recordingDuration = 0.0
                
                self.recordingTimer?.invalidate()
                self.recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                    guard let self = self, let start = self.recordingStartDate else { return }
                    self.recordingDuration = Date().timeIntervalSince(start)
                }
            }
        }
    }

    func stopRecordingVideo() {
        guard isRecording else { return }
        
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self.movieOutput.stopRecording()
        }
        
        DispatchQueue.main.async { [weak self] in
            self?.recordingTimer?.invalidate()
            self?.recordingTimer = nil
            self?.isRecording = false
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

    // MARK: - AVCaptureFileOutputRecordingDelegate
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.isRecording = false
            self.recordingTimer?.invalidate()
            self.recordingTimer = nil
            
            if let error = error {
                self.recordingCompletion?(.failure(error))
            } else {
                self.recordingCompletion?(.success(outputFileURL))
            }
            self.recordingCompletion = nil
        }
    }

    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        onSampleBufferReceived?(sampleBuffer)
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
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        previewLayer?.frame = bounds
        CATransaction.commit()
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        previewLayer?.frame = bounds
        CATransaction.commit()
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
