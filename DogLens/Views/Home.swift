import SwiftUI
import PhotosUI
import AVFoundation
import Photos

struct HomeView: View {
    @State private var showCamera = false
    @State private var showPhotoPicker = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var showPreview = false
    
    @State private var showPermissionAlert = false
    @State private var permissionMessage = ""
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                // App Logo Placeholder
                Image(systemName: "viewfinder.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 120, height: 120)
                    .foregroundStyle(.orange, .blue.opacity(0.8))
                
                VStack(spacing: 8) {
                    Text("DogLens")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    
                    Text("Identify dog breeds instantly using CoreML.")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                
                Spacer()
                
                VStack(spacing: 16) {
                    Button(action: {
                        requestCameraPermission()
                    }) {
                        HStack {
                            Image(systemName: "camera.fill")
                            Text("Scan Dog")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.orange)
                        .cornerRadius(16)
                    }
                    
                    Button(action: {
                        requestPhotoPermission()
                    }) {
                        HStack {
                            Image(systemName: "photo.on.rectangle.angled")
                            Text("Upload Photo")
                        }
                        .font(.headline)
                        .foregroundColor(.blue)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(16)
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 40)
            }
            .padding(.top, 60)
            .photosPicker(isPresented: $showPhotoPicker, selection: $selectedPhotoItem, matching: .images)
            .onChange(of: selectedPhotoItem) { _, newItem in
                Task {
                    if let data = try? await newItem?.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        selectedImage = image
                        showPreview = true
                        selectedPhotoItem = nil
                    }
                }
            }
            .navigationDestination(isPresented: $showPreview) {
                if let image = selectedImage {
                    ImagePreviewView(image: image)
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                ScannerView { image in
                    if let image = image {
                        selectedImage = image
                        showPreview = true
                    }
                }
            }
            .alert("Permission Denied", isPresented: $showPermissionAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(permissionMessage)
            }
        }
    }
    
    private func requestCameraPermission() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .authorized {
            showCamera = true
        } else if status == .notDetermined {
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        self.showCamera = true
                    } else {
                        self.permissionMessage = "Camera access is required to scan dogs. Please enable it in Settings."
                        self.showPermissionAlert = true
                    }
                }
            }
        } else {
            self.permissionMessage = "Camera access is required to scan dogs. Please enable it in Settings."
            self.showPermissionAlert = true
        }
    }
    
    private func requestPhotoPermission() {
        let status = PHPhotoLibrary.authorizationStatus()
        if status == .authorized || status == .limited {
            showPhotoPicker = true
        } else if status == .notDetermined {
            PHPhotoLibrary.requestAuthorization { newStatus in
                DispatchQueue.main.async {
                    if newStatus == .authorized || newStatus == .limited {
                        self.showPhotoPicker = true
                    } else {
                        self.permissionMessage = "Photo Library access is required to upload photos. Please enable it in Settings."
                        self.showPermissionAlert = true
                    }
                }
            }
        } else {
            self.permissionMessage = "Photo Library access is required to upload photos. Please enable it in Settings."
            self.showPermissionAlert = true
        }
    }
}

#Preview {
    HomeView()
}
