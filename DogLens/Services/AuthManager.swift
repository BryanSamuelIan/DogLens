import Foundation
import SwiftUI
import AuthenticationServices
import CloudKit
import Combine

// MARK: - User Profile Model

struct UserProfile: Codable, Identifiable, Equatable {
    let id: String
    var fullName: String
    var email: String?
    var createdAt: Date
    
    var initials: String {
        let components = fullName.components(separatedBy: " ").filter { !$0.isEmpty }
        if components.count >= 2,
           let first = components.first?.first,
           let last = components.last?.first {
            return "\(first)\(last)".uppercased()
        } else if let first = fullName.first {
            return String(first).uppercased()
        }
        return "DL"
    }
}

// MARK: - Auth Manager

@MainActor
final class AuthManager: ObservableObject {
    static let shared = AuthManager()
    
    // Keys for persistence
    private let userProfileKey = "com.doglens.userProfile"
    private let isGuestKey = "com.doglens.isGuest"
    private let isAuthenticatedKey = "com.doglens.isAuthenticated"
    
    // Published state
    @Published var isAuthenticated: Bool = false
    @Published var isGuest: Bool = false
    @Published var currentUser: UserProfile?
    @Published var iCloudStatus: CKAccountStatus = .couldNotDetermine
    @Published var isLoading: Bool = false
    @Published var authErrorMessage: String?
    
    init() {
        loadSavedSession()
        Task {
            await checkiCloudStatus()
        }
    }
    
    // MARK: - Session Restoration
    
    private func loadSavedSession() {
        let isAuth = UserDefaults.standard.bool(forKey: isAuthenticatedKey)
        let guest = UserDefaults.standard.bool(forKey: isGuestKey)
        
        if isAuth, let data = UserDefaults.standard.data(forKey: userProfileKey),
           let profile = try? JSONDecoder().decode(UserProfile.self, from: data) {
            self.currentUser = profile
            self.isAuthenticated = true
            self.isGuest = false
        } else if guest {
            self.isGuest = true
            self.isAuthenticated = false
        }
    }
    
    // MARK: - Sign in with Apple Handler
    
    func handleAppleSignIn(result: Result<ASAuthorization, Error>) {
        isLoading = true
        authErrorMessage = nil
        
        switch result {
        case .success(let authorization):
            guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                authErrorMessage = "Invalid Apple ID credentials."
                isLoading = false
                return
            }
            
            let userId = appleIDCredential.user
            
            // Extract Name
            var name = "DogLens Explorer"
            if let givenName = appleIDCredential.fullName?.givenName,
               let familyName = appleIDCredential.fullName?.familyName {
                name = "\(givenName) \(familyName)"
            } else if let givenName = appleIDCredential.fullName?.givenName {
                name = givenName
            } else if let existing = currentUser?.fullName, !existing.isEmpty {
                name = existing
            }
            
            // Extract Email
            let email = appleIDCredential.email ?? currentUser?.email
            
            let profile = UserProfile(
                id: userId,
                fullName: name,
                email: email,
                createdAt: currentUser?.createdAt ?? Date()
            )
            
            saveSession(profile: profile)
            
            Task {
                await checkiCloudStatus()
                
                // If Apple Sign In didn't return a name (re-login), fetch from CloudKit
                if self.currentUser?.fullName == "DogLens Explorer" || self.currentUser?.fullName.isEmpty == true {
                    if let cloudName = await self.fetchCloudKitUserName() {
                        self.currentUser?.fullName = cloudName
                        if let updated = self.currentUser {
                            self.saveSession(profile: updated)
                        }
                    }
                }
                self.isLoading = false
            }
            
        case .failure(let error):
            if let asError = error as? ASAuthorizationError, asError.code == .canceled {
                // User cancelled, don't show error banner
                isLoading = false
                return
            }
            authErrorMessage = error.localizedDescription
            isLoading = false
        }
    }
    
    // MARK: - Guest Mode
    
    func continueAsGuest() {
        isGuest = true
        isAuthenticated = false
        currentUser = nil
        UserDefaults.standard.set(true, forKey: isGuestKey)
        UserDefaults.standard.set(false, forKey: isAuthenticatedKey)
        UserDefaults.standard.removeObject(forKey: userProfileKey)
    }
    
    // MARK: - Sign Out
    
    func signOut() {
        isAuthenticated = false
        isGuest = false
        currentUser = nil
        UserDefaults.standard.set(false, forKey: isAuthenticatedKey)
        UserDefaults.standard.set(false, forKey: isGuestKey)
        UserDefaults.standard.removeObject(forKey: userProfileKey)
    }
    
    // MARK: - Update Custom Name
    
    func updateUserName(_ newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        if var user = currentUser {
            user.fullName = trimmed
            saveSession(profile: user)
        } else {
            let newUser = UserProfile(
                id: UUID().uuidString,
                fullName: trimmed,
                email: nil,
                createdAt: Date()
            )
            saveSession(profile: newUser)
        }
    }
    
    // MARK: - Private Session Persistence
    
    private func saveSession(profile: UserProfile) {
        self.currentUser = profile
        self.isAuthenticated = true
        self.isGuest = false
        
        UserDefaults.standard.set(true, forKey: isAuthenticatedKey)
        UserDefaults.standard.set(false, forKey: isGuestKey)
        if let data = try? JSONEncoder().encode(profile) {
            UserDefaults.standard.set(data, forKey: userProfileKey)
        }
    }
    
    // MARK: - CloudKit User Discovery & Status
    
    func fetchCloudKitUserName() async -> String? {
        do {
            let container = CKContainer(identifier: "iCloud.DogLens")
            let userRecordID = try await container.userRecordID()
            let userIdentity = try await container.userIdentity(forUserRecordID: userRecordID)
            if let nameComponents = userIdentity?.nameComponents {
                let formatter = PersonNameComponentsFormatter()
                let formatted = formatter.string(from: nameComponents).trimmingCharacters(in: .whitespacesAndNewlines)
                if !formatted.isEmpty {
                    return formatted
                }
            }
        } catch {
            print("Could not discover user identity from CloudKit: \(error)")
        }
        return nil
    }
    func checkiCloudStatus() async {
        do {
            let container = CKContainer(identifier: "iCloud.DogLens")
            let status = try await container.accountStatus()
            self.iCloudStatus = status
            
            // Auto-resolve user name from CloudKit account if not customized
            if self.currentUser == nil || self.currentUser?.fullName == "DogLens Explorer" || self.currentUser?.fullName.isEmpty == true {
                if let cloudName = await self.fetchCloudKitUserName() {
                    if var existing = self.currentUser {
                        existing.fullName = cloudName
                        self.saveSession(profile: existing)
                    } else {
                        let user = UserProfile(
                            id: UUID().uuidString,
                            fullName: cloudName,
                            email: nil,
                            createdAt: Date()
                        )
                        self.saveSession(profile: user)
                    }
                }
            }
        } catch {
            self.iCloudStatus = .couldNotDetermine
        }
    }
}
