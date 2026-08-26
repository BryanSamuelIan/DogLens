// HomeViewModel.swift
import SwiftUI
import PhotosUI
import AVFoundation
import Photos
import Combine

@MainActor
final class HomeViewModel: ObservableObject {
    @Published var showCamera = false
    @Published var showPhotoPicker = false
    @Published var selectedPhotoItem: PhotosPickerItem?
    @Published var selectedImage: UIImage?
    @Published var showPreview = false
    @Published var showPermissionAlert = false
    @Published var permissionMessage = ""

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

    func handleCameraCapture(_ image: UIImage?) {
        guard let image else { return }
        selectedImage = image
        showPreview = true
    }

    func loadSelectedPhoto() async {
        guard let item = selectedPhotoItem else { return }
        if let data = try? await item.loadTransferable(type: Data.self),
           let image = UIImage(data: data) {
            selectedImage = image
            showPreview = true
            selectedPhotoItem = nil
        }
    }
}
