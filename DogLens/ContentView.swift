//
//  ContentView.swift
//  DogLens
//
//  Created by Bryan Samuel on 21/08/26.
//

import SwiftUI

struct ContentView: View {
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
        .tint(.orange) // Theme color
    }
}

#Preview {
    ContentView()
}
