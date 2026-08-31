//
//  ContentView.swift
//  DogLens
//
//  Created by Bryan Samuel on 21/08/26.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var authManager = AuthManager.shared
    @StateObject private var cloudService = CloudKitService.shared
    
    var body: some View {
        Group {
            if authManager.isAuthenticated || authManager.isGuest {
                TabView {
                    HomeView()
                        .tabItem {
                            Label("Home", systemImage: "house")
                        }
                    
                    BreedGalleryView()
                        .tabItem {
                            Label("Gallery", systemImage: "photo.on.rectangle")
                        }
                }
                .tint(.orange)
            } else {
                LoginView()
            }
        }
        .environmentObject(authManager)
        .environmentObject(cloudService)
    }
}

#Preview {
    ContentView()
}
