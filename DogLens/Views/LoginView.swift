import SwiftUI
import AuthenticationServices

// MARK: - HIG Apple Login View

struct LoginView: View {
    @ObservedObject var authManager = AuthManager.shared
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    
    var onLoginSuccess: (() -> Void)?
    
    var body: some View {
        ZStack {
            // Background subtle gradient
            LinearGradient(
                colors: [
                    Color.orange.opacity(0.12),
                    Color(.systemBackground),
                    Color.blue.opacity(0.06)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 28) {
                Spacer()
                
                // ── Hero App Icon & Title ─────────────────────────────────
                VStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [.orange, .orange.opacity(0.8)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 96, height: 96)
                            .shadow(color: .orange.opacity(0.35), radius: 16, x: 0, y: 8)
                        
                        Image(systemName: "viewfinder.circle.fill")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 54, height: 54)
                            .foregroundColor(.white)
                    }
                    
                    Text("Welcome to DogLens")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    
                    Text("Identify, track, and securely back up dog breeds to your private iCloud.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                
                // ── Feature Highlights (HIG Style) ────────────────────────
                VStack(alignment: .leading, spacing: 20) {
                    FeatureRow(
                        icon: "icloud.fill",
                        iconColor: .blue,
                        title: "iCloud Private Backup",
                        subtitle: "Your photos and videos are stored safely in your personal iCloud."
                    )
                    
                    FeatureRow(
                        icon: "pawprint.fill",
                        iconColor: .orange,
                        title: "52+ Breeds AI Detection",
                        subtitle: "Real-time recognition and tracking powered by YOLO11 & CoreML."
                    )
                    
                    FeatureRow(
                        icon: "arrow.triangle.2.circlepath",
                        iconColor: .green,
                        title: "Cross-Device Sync",
                        subtitle: "Access your unlocked dog breed gallery across all your Apple devices."
                    )
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 8)
                
                Spacer()
                
                // ── Sign In with Apple & Guest Options ────────────────────
                VStack(spacing: 16) {
                    // Sign In with Apple Button (Native HIG Component)
                    SignInWithAppleButton(
                        .signIn,
                        onRequest: { request in
                            request.requestedScopes = [.fullName, .email]
                        },
                        onCompletion: { result in
                            authManager.handleAppleSignIn(result: result)
                            if authManager.isAuthenticated {
                                onLoginSuccess?()
                            }
                        }
                    )
                    .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                    .frame(height: 52)
                    .cornerRadius(14)
                    .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 4)
                    
                    // Continue as Guest Option
                    Button(action: {
                        authManager.continueAsGuest()
                        onLoginSuccess?()
                    }) {
                        Text("Continue as Guest")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                            .padding(.vertical, 8)
                    }
                    
                    // Privacy Disclosure
                    Text("By continuing, your data is securely handled following Apple Privacy Guidelines.")
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            
            // Loading Overlay
            if authManager.isLoading {
                ZStack {
                    Color.black.opacity(0.35).ignoresSafeArea()
                    ProgressView("Signing in…")
                        .padding(24)
                        .background(.ultraThinMaterial)
                        .cornerRadius(16)
                }
            }
        }
        .alert("Authentication Note", isPresented: Binding(
            get: { authManager.authErrorMessage != nil },
            set: { if !$0 { authManager.authErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(authManager.authErrorMessage ?? "")
        }
    }
}

// MARK: - Feature Highlight Row

private struct FeatureRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(iconColor)
                .frame(width: 38, height: 38)
                .background(iconColor.opacity(0.12))
                .cornerRadius(10)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

#Preview {
    LoginView()
}
