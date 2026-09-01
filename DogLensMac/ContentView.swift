import SwiftUI
import SwiftData

enum MacNavigationTab: String, Hashable, CaseIterable {
    case scanner = "Scan & Detect"
    case gallery = "Breed Gallery"

    var icon: String {
        switch self {
        case .scanner: return "camera.viewfinder"
        case .gallery: return "square.grid.2x2.fill"
        }
    }
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var selectedTab: MacNavigationTab = .scanner
    @State private var cloudKitService = MacCloudKitService.shared

    var body: some View {
        NavigationSplitView {
            List(MacNavigationTab.allCases, id: \.self, selection: $selectedTab) { tab in
                Label(tab.rawValue, systemImage: tab.icon)
                    .tag(tab)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
            .safeAreaInset(edge: .bottom) {
                // iCloud Status Indicator
                HStack(spacing: 8) {
                    Image(systemName: cloudKitService.isAvailable ? "checkmark.icloud.fill" : "exclamationmark.icloud.fill")
                        .foregroundColor(cloudKitService.isAvailable ? .blue : .orange)

                    Text(cloudKitService.isAvailable ? "iCloud Connected" : "iCloud Offline")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()
                }
                .padding(12)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
            }
        } detail: {
            Group {
                switch selectedTab {
                case .scanner:
                    MacScannerView()
                case .gallery:
                    MacBreedGalleryView()
                }
            }
            .frame(minWidth: 750, minHeight: 550)
        }
        .task {
            cloudKitService.checkAccountStatus()
            // Initial background iCloud sync on startup
            await cloudKitService.syncFromCloud(modelContext: modelContext)
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [DogBreed.self, BreedImage.self], inMemory: true)
}
