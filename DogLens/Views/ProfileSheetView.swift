import SwiftUI
import CloudKit
import SwiftData

// MARK: - Profile & iCloud Dashboard Sheet

struct ProfileSheetView: View {
    @ObservedObject var authManager = AuthManager.shared
    @ObservedObject var cloudService = CloudKitService.shared
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var showLoginModal = false
    @State private var isManualSyncing = false
    @State private var showEditNameAlert = false
    @State private var newNameInput = ""
    
    var body: some View {
        NavigationStack {
            List {
                // ── User Account Header ───────────────────────────────────
                Section {
                    HStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [.orange, .orange.opacity(0.75)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 60, height: 60)
                            
                            if let profile = authManager.currentUser {
                                Text(profile.initials)
                                    .font(.title3)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                            } else {
                                Image(systemName: "person.fill")
                                    .font(.title2)
                                    .foregroundColor(.white)
                            }
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text(authManager.currentUser?.fullName ?? "Guest Explorer")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                
                                Button {
                                    newNameInput = authManager.currentUser?.fullName ?? ""
                                    showEditNameAlert = true
                                } label: {
                                    Image(systemName: "pencil.circle.fill")
                                        .font(.subheadline)
                                        .foregroundColor(.orange)
                                }
                                .buttonStyle(.plain)
                            }
                            
                            if let email = authManager.currentUser?.email {
                                Text(email)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            } else {
                                Text(authManager.isAuthenticated ? "Apple ID Connected" : "Local Session")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Spacer()
                    }
                    .padding(.vertical, 6)
                }
                
                // ── iCloud Sync Status ────────────────────────────────────
                Section(header: Text("iCloud Backup & Sync")) {
                    HStack {
                        Label("iCloud Status", systemImage: "icloud.fill")
                            .foregroundColor(.blue)
                        Spacer()
                        iCloudStatusBadge
                    }
                    
                    HStack {
                        Label("Cloud Gallery Items", systemImage: "photo.stack.fill")
                            .foregroundColor(.orange)
                        Spacer()
                        Text("\(cloudService.backedUpItemCount) item(s)")
                            .foregroundColor(.secondary)
                            .fontWeight(.medium)
                    }
                    
                    HStack {
                        Label("Sync State", systemImage: "arrow.triangle.2.circlepath")
                            .foregroundColor(.green)
                        Spacer()
                        Text(cloudService.syncState.displayText)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    // Manual Sync Trigger
                    Button(action: triggerManualSync) {
                        HStack {
                            Spacer()
                            if isManualSyncing {
                                ProgressView()
                                    .padding(.trailing, 4)
                            } else {
                                Image(systemName: "arrow.clockwise.icloud.fill")
                            }
                            Text(isManualSyncing ? "Syncing…" : "Sync Gallery to iCloud Now")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                        .foregroundColor(.white)
                        .padding(.vertical, 4)
                    }
                    .listRowBackground(Color.orange)
                    .disabled(isManualSyncing)
                }
                
                // ── Account Actions ───────────────────────────────────────
                Section {
                    if authManager.isAuthenticated {
                        Button(role: .destructive, action: {
                            authManager.signOut()
                            dismiss()
                        }) {
                            HStack {
                                Spacer()
                                Text("Sign Out")
                                    .fontWeight(.semibold)
                                Spacer()
                            }
                        }
                    } else {
                        Button(action: {
                            showLoginModal = true
                        }) {
                            HStack {
                                Image(systemName: "applelogo")
                                Text("Sign in with Apple")
                                    .fontWeight(.semibold)
                            }
                            .foregroundColor(.primary)
                        }
                    }
                }
                
                // ── App Info ──────────────────────────────────────────────
                Section {
                    HStack {
                        Text("DogLens Version")
                        Spacer()
                        Text("1.0 (Build with YOLO11 & CloudKit)")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Profile & iCloud")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showLoginModal) {
                LoginView(onLoginSuccess: {
                    showLoginModal = false
                })
            }
            .alert("Edit Profile Name", isPresented: $showEditNameAlert) {
                TextField("Your Name", text: $newNameInput)
                Button("Cancel", role: .cancel) {}
                Button("Save") {
                    authManager.updateUserName(newNameInput)
                }
            } message: {
                Text("Enter your display name for DogLens.")
            }
            .task {
                await authManager.checkiCloudStatus()
            }
        }
    }
    
    // MARK: - iCloud Status Badge View
    
    @ViewBuilder
    private var iCloudStatusBadge: some View {
        switch authManager.iCloudStatus {
        case .available:
            HStack(spacing: 4) {
                Circle().fill(Color.green).frame(width: 8, height: 8)
                Text("Connected").font(.caption).fontWeight(.medium).foregroundColor(.green)
            }
        case .noAccount:
            HStack(spacing: 4) {
                Circle().fill(Color.red).frame(width: 8, height: 8)
                Text("No Account").font(.caption).fontWeight(.medium).foregroundColor(.red)
            }
        case .restricted:
            HStack(spacing: 4) {
                Circle().fill(Color.orange).frame(width: 8, height: 8)
                Text("Restricted").font(.caption).fontWeight(.medium).foregroundColor(.orange)
            }
        case .couldNotDetermine, .temporarilyUnavailable:
            HStack(spacing: 4) {
                Circle().fill(Color.secondary).frame(width: 8, height: 8)
                Text("Checking…").font(.caption).foregroundColor(.secondary)
            }
        @unknown default:
            Text("Unknown").font(.caption).foregroundColor(.secondary)
        }
    }
    
    // MARK: - Trigger Manual Sync
    
    private func triggerManualSync() {
        isManualSyncing = true
        Task {
            await cloudService.syncWithLocalDatabase(modelContext: modelContext)
            await cloudService.refreshCloudItemCount()
            isManualSyncing = false
        }
    }
}

#Preview {
    ProfileSheetView()
}
