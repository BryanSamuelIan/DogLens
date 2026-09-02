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
                Label {
                    Text(tab.rawValue)
                        .fontWeight(.medium)
                } icon: {
                    Image(systemName: tab.icon)
                        .foregroundColor(tab == selectedTab ? .orange : .secondary)
                }
                .tag(tab)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
            .safeAreaInset(edge: .bottom) {
                // iCloud Status Indicator
                HStack(spacing: 8) {
                    Image(systemName: cloudKitService.isAvailable ? "checkmark.icloud.fill" : "exclamationmark.icloud.fill")
                        .foregroundColor(cloudKitService.isAvailable ? .orange : .secondary)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(cloudKitService.isAvailable ? "iCloud Synced" : "iCloud Offline")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)

                        if cloudKitService.isAvailable && cloudKitService.backedUpItemCount > 0 {
                            Text("\(cloudKitService.backedUpItemCount) items backed up")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()

                    if cloudKitService.isAvailable {
                        Button {
                            Task {
                                await cloudKitService.syncFromCloud(modelContext: modelContext)
                            }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .help("Sync with iCloud now")
                    }
                }
                .padding(12)
                .background(.ultraThinMaterial)
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
        .tint(.orange)
        .task {
            seedBreedsIfNeeded()
            await cloudKitService.checkAccountStatus()
            if cloudKitService.isAvailable {
                await cloudKitService.syncFromCloud(modelContext: modelContext)
            }
        }
    }

    private func seedBreedsIfNeeded() {
        do {
            let descriptor = FetchDescriptor<DogBreed>()
            let existingBreeds = try modelContext.fetch(descriptor)
            let existingNames = Set(existingBreeds.map { $0.name.lowercased() })
            var didInsert = false
            for name in DogBreed.predefinedBreeds {
                if !existingNames.contains(name.lowercased()) {
                    modelContext.insert(DogBreed(name: name))
                    didInsert = true
                }
            }
            if didInsert {
                try modelContext.save()
            }
        } catch {
            print("Failed to seed predefined breeds on Mac: \(error)")
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [DogBreed.self, BreedImage.self], inMemory: true)
}
