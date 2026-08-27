import SwiftUI
import PhotosUI

struct HomeView: View {
    @StateObject private var vm = HomeViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                // ── App Logo ──────────────────────────────────────────────
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
                    // ── Scan Dog (Photo + Video) ──────────────────────────
                    Button(action: vm.requestCameraPermission) {
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

                    // ── Upload Photo ──────────────────────────────────────
                    Button(action: vm.requestPhotoPermission) {
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

                    // ── Upload Video ──────────────────────────────────────
                    Button(action: vm.requestVideoPermission) {
                        HStack {
                            if vm.isLoadingVideo {
                                ProgressView().tint(.purple)
                            } else {
                                Image(systemName: "video.badge.plus")
                            }
                            Text("Upload Video")
                        }
                        .font(.headline)
                        .foregroundColor(.purple)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.purple.opacity(0.1))
                        .cornerRadius(16)
                    }
                    .disabled(vm.isLoadingVideo)
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 40)
            }
            .padding(.top, 60)

            // ── Photo picker ──────────────────────────────────────────────
            .photosPicker(isPresented: $vm.showPhotoPicker,
                          selection: $vm.selectedPhotoItem,
                          matching: .images)
            .onChange(of: vm.selectedPhotoItem) { _, _ in
                Task { await vm.loadSelectedPhoto() }
            }

            // ── Video picker ──────────────────────────────────────────────
            .photosPicker(isPresented: $vm.showVideoPicker,
                          selection: $vm.selectedVideoItem,
                          matching: .videos)
            .onChange(of: vm.selectedVideoItem) { _, _ in
                Task { await vm.loadSelectedVideo() }
            }

            // ── Navigation: Photo upload → ImagePreviewView ───────────────
            .navigationDestination(isPresented: $vm.showPreview) {
                if let image = vm.selectedImage {
                    ImagePreviewView(image: image)
                }
            }

            // ── Navigation: Video upload → VideoPreviewView ───────────────
            .navigationDestination(isPresented: $vm.showVideoPreview) {
                if let url = vm.selectedVideoURL {
                    VideoPreviewView(videoURL: url)
                }
            }

            // ── Scan Dog: fullScreenCover with Photo/Video tabs ───────────
            .fullScreenCover(isPresented: $vm.showCamera) {
                ScanDogContainerView(onClose: { vm.showCamera = false })
            }

            // ── Permission alert ──────────────────────────────────────────
            .alert("Permission Denied", isPresented: $vm.showPermissionAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(vm.permissionMessage)
            }
        }
    }
}

#Preview {
    HomeView()
}
