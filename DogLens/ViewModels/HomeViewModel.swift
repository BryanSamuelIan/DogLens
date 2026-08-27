// HomeViewModel.swift
import SwiftUI
import PhotosUI
import AVFoundation
import Photos
import Combine
import UniformTypeIdentifiers

// MARK: - Video Transferable

struct VideoFileTransferable: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in
            // Copy to a stable temp path so the URL remains valid
            let fileName = received.file.lastPathComponent
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent("upload_\(UUID().uuidString)_\(fileName)")
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.copyItem(at: received.file, to: dest)
            return VideoFileTransferable(url: dest)
        }
    }
}

// MARK: - Home View Model

@MainActor
final class HomeViewModel: ObservableObject {
    // ── Camera / Scanner ──────────────────────────────────────────────
    @Published var showCamera         = false

    // ── Photo Upload ──────────────────────────────────────────────────
    @Published var showPhotoPicker    = false
    @Published var selectedPhotoItem: PhotosPickerItem?
    @Published var selectedImage: UIImage?
    @Published var showPreview        = false

    // ── Video Upload ──────────────────────────────────────────────────
    @Published var showVideoPicker    = false
    @Published var selectedVideoItem: PhotosPickerItem?
    @Published var selectedVideoURL: URL?
    @Published var showVideoPreview   = false
    @Published var isLoadingVideo     = false

    // ── Permissions ───────────────────────────────────────────────────
    @Published var showPermissionAlert = false
    @Published var permissionMessage   = ""

    // MARK: - Camera

    func requestCameraPermission() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            showCamera = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.showCamera = true
                    } else {
                        self?.permissionMessage = "Camera access is required to scan dogs. Please enable it in Settings."
                        self?.showPermissionAlert = true
                    }
                }
            }
        default:
            permissionMessage = "Camera access is required to scan dogs. Please enable it in Settings."
            showPermissionAlert = true
        }
    }

    // MARK: - Photo Upload

    func requestPhotoPermission() {
        let status = PHPhotoLibrary.authorizationStatus()
        switch status {
        case .authorized, .limited:
            showPhotoPicker = true
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization { [weak self] newStatus in
                DispatchQueue.main.async {
                    if newStatus == .authorized || newStatus == .limited {
                        self?.showPhotoPicker = true
                    } else {
                        self?.permissionMessage = "Photo Library access is required to upload photos. Please enable it in Settings."
                        self?.showPermissionAlert = true
                    }
                }
            }
        default:
            permissionMessage = "Photo Library access is required to upload photos. Please enable it in Settings."
            showPermissionAlert = true
        }
    }

    func loadSelectedPhoto() async {
        guard let item = selectedPhotoItem else { return }
        if let data = try? await item.loadTransferable(type: Data.self),
           let image = UIImage(data: data) {
            selectedImage     = image
            showPreview       = true
            selectedPhotoItem = nil
        }
    }

    // MARK: - Video Upload

    func requestVideoPermission() {
        let status = PHPhotoLibrary.authorizationStatus()
        switch status {
        case .authorized, .limited:
            showVideoPicker = true
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization { [weak self] newStatus in
                DispatchQueue.main.async {
                    if newStatus == .authorized || newStatus == .limited {
                        self?.showVideoPicker = true
                    } else {
                        self?.permissionMessage = "Photo Library access is required to upload videos. Please enable it in Settings."
                        self?.showPermissionAlert = true
                    }
                }
            }
        default:
            permissionMessage = "Photo Library access is required to upload videos. Please enable it in Settings."
            showPermissionAlert = true
        }
    }

    func loadSelectedVideo() async {
        guard let item = selectedVideoItem else { return }
        isLoadingVideo = true
        defer { isLoadingVideo = false }

        do {
            if let transferable = try await item.loadTransferable(type: VideoFileTransferable.self) {
                selectedVideoURL  = transferable.url
                showVideoPreview  = true
                selectedVideoItem = nil
            }
        } catch {
            permissionMessage  = "Failed to load video: \(error.localizedDescription)"
            showPermissionAlert = true
            selectedVideoItem   = nil
        }
    }

    // MARK: - State Reset Helpers

    func resetPhotoState() {
        selectedPhotoItem = nil
        selectedImage = nil
        showPreview = false
    }

    func resetVideoState() {
        selectedVideoItem = nil
        selectedVideoURL = nil
        showVideoPreview = false
        isLoadingVideo = false
    }
}
