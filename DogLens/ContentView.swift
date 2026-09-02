//
//  ContentView.swift
//  DogLens
//
//  Created by Bryan Samuel on 21/08/26.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var authManager = AuthManager.shared
    @StateObject private var cloudService = CloudKitService.shared
    
    var body: some View {
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
        .environmentObject(authManager)
        .environmentObject(cloudService)
        .task {
            await authManager.checkiCloudStatus()
            await cloudService.syncWithLocalDatabase(modelContext: modelContext)
            await cloudService.refreshCloudItemCount()
        }
    }
}

#Preview {
    ContentView()
}
