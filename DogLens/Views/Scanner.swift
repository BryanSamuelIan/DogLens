import SwiftUI
import AVFoundation

// MARK: - Scan Dog Container (Photo | Video | Live tabs)

/// Full-screen container presented from Home.
/// Tab 0 (default) = Photo camera  |  Tab 1 = Video camera  |  Tab 2 = Live camera.
struct ScanDogContainerView: View {
    var onClose: () -> Void

    @State private var selectedTab: Int = 0
    
    // Photo flow
    @State private var capturedImage: UIImage?
    @State private var showImagePreview = false
    
    // Video flow
    @State private var recordedVideoURL: URL?
    @State private var showVideoPreview  = false
    
    // Live flow
    @StateObject private var liveViewModel = LiveScannerViewModel()

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                // ── Tab pages ─────────────────────────────────────────────
                TabView(selection: $selectedTab) {
                    // Photo tab
                    ScannerView(
                        isActive: selectedTab == 0,
                        onCapture: { image in
                            capturedImage   = image
                            showImagePreview = true
                        },
                        onClose: onClose
                    )
                    .tag(0)
                    .ignoresSafeArea()

                    // Video tab
                    VideoScannerView(
                        isActive: selectedTab == 1,
                        onRecordingFinished: { url in
                            recordedVideoURL  = url
                            showVideoPreview  = true
                        },
                        onClose: onClose
                    )
                    .tag(1)
                    .ignoresSafeArea()

                    // Live tab
                    LiveScannerView(
                        isActive: selectedTab == 2,
                        viewModel: liveViewModel,
                        onClose: onClose
                    )
                    .tag(2)
                    .ignoresSafeArea()
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .ignoresSafeArea()

                // ── Mode Picker overlay ───────────────────────────────────
                VStack(spacing: 0) {
                    Picker("Scan Mode", selection: $selectedTab) {
                        Label("Photo", systemImage: "camera.fill").tag(0)
                        Label("Video", systemImage: "video.fill").tag(1)
                        Label("Live", systemImage: "play.circle.fill").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 72)
                    .padding(.top, topSafeAreaInset() + 16)
                }
            }
            // ── Navigation destinations ───────────────────────────────────
            .navigationDestination(isPresented: $showImagePreview) {
                if let image = capturedImage {
                    ImagePreviewView(image: image)
                }
            }
            .navigationDestination(isPresented: $showVideoPreview) {
                if let url = recordedVideoURL {
                    VideoPreviewView(videoURL: url)
                }
            }
            .onChange(of: showVideoPreview) { _, isPresented in
                if !isPresented {
                    recordedVideoURL = nil
                }
            }
            .onChange(of: showImagePreview) { _, isPresented in
                if !isPresented {
                    capturedImage = nil
                }
            }
            .onChange(of: selectedTab) { _, newValue in
                // Clear any leftover live detection results when switching away from Live tab
                if newValue != 2 {
                    liveViewModel.clearResults()
                }
            }
        }
    }

    private func topSafeAreaInset() -> CGFloat {
        (UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.safeAreaInsets.top) ?? 44
    }
}
