//
//  MacVideoResultView.swift
//  DogLensMac
//

import SwiftUI
import AVKit
import SwiftData

struct MacVideoResultView: View {
    @ObservedObject var vm: MacVideoInferenceViewModel
    let allBreeds: [DogBreed]
    let onSaveToGallery: () -> Void
    let onSaveToFile: (Bool) -> Void
    let onSaveToPhotos: () -> Void
    let onScanAnother: () -> Void

    @State private var showOriginal = false
    @State private var player: AVPlayer?

    var body: some View {
        HStack(spacing: 0) {
            // Left Column: Video Player & Display Controls
            VStack(spacing: 16) {
                if vm.annotatedVideoURL != nil {
                    Picker("Display Mode", selection: $showOriginal) {
                        Text("Detected").tag(false)
                        Text("Original").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 240)
                    .tint(.orange)
                    .onChange(of: showOriginal) { _, original in
                        switchPlayer(showOriginal: original)
                    }
                }

                if let player = player {
                    VideoPlayer(player: player)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
                } else {
                    ProgressView("Loading Video…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                HStack {
                    Button {
                        player?.pause()
                        onScanAnother()
                    } label: {
                        Label("Scan Another Video", systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.orange)

                    Spacer()
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // Right Column: Summary & Save Actions
            VStack(alignment: .leading, spacing: 20) {
                // Header & Badges
                VStack(alignment: .leading, spacing: 8) {
                    let dogs = vm.trackedDogs
                    let count = dogs.isEmpty ? vm.allVideoDetections.count : dogs.count

                    HStack {
                        Text("\(count) Dog\(count == 1 ? "" : "s") Detected")
                            .font(.title2)
                            .fontWeight(.bold)

                        Spacer()

                        if vm.isNewBreed {
                            HStack(spacing: 4) {
                                Image(systemName: "sparkles")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                                Text("New Breed!")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.orange)
                                Image(systemName: "sparkles")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.orange.opacity(0.12), in: Capsule())
                        }
                    }

                    Text("Consolidated multi-object tracking across video frames")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Divider()

                // Tracked Dogs List
                ScrollView {
                    VStack(spacing: 10) {
                        if vm.trackedDogs.isEmpty && vm.allVideoDetections.isEmpty {
                            Text("No dog breeds detected in this video.")
                                .foregroundColor(.secondary)
                                .padding(.vertical, 20)
                        } else if !vm.trackedDogs.isEmpty {
                            ForEach(vm.trackedDogs) { dog in
                                trackedDogRow(dog: dog)
                            }
                        } else {
                            ForEach(Array(vm.allVideoDetections.keys.sorted()), id: \.self) { name in
                                let conf = vm.allVideoDetections[name] ?? 0.0
                                fallbackDetectionRow(name: name, confidence: conf)
                            }
                        }
                    }
                }
                .frame(maxHeight: .infinity)

                Divider()

                // Action Buttons
                VStack(spacing: 12) {
                    // New Breed Discovery Indicator above save button
                    if vm.isNewBreed {
                        HStack(spacing: 4) {
                            Image(systemName: "sparkles")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                            Text("New Breed Discovered!")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundStyle(.orange)
                            Image(systemName: "sparkles")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(0.15))
                        .clipShape(Capsule())
                        .frame(maxWidth: .infinity, alignment: .center)
                    }

                    // Save to Breed Gallery (Only if any confidence >= 0.70)
                    if vm.allVideoDetections.values.contains(where: { $0 >= 0.70 }) {
                        Button(action: onSaveToGallery) {
                            HStack(spacing: 8) {
                                if vm.isSavingToGallery {
                                    ProgressView()
                                        .controlSize(.small)
                                        .tint(.white)
                                    Text("Saving to Breed Gallery…")
                                        .fontWeight(.semibold)
                                } else {
                                    if vm.isNewBreed {
                                        Image(systemName: "star.fill")
                                    } else {
                                        Image(systemName: "square.grid.2x2.fill")
                                    }
                                    Text("Save Video to Breed Gallery")
                                        .fontWeight(.semibold)
                                }
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity, minHeight: 38)
                            .background(
                                vm.isNewBreed
                                ? LinearGradient(colors: [.orange, .pink], startPoint: .leading, endPoint: .trailing)
                                : LinearGradient(colors: [.orange, .orange], startPoint: .leading, endPoint: .trailing)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .shadow(color: vm.isNewBreed ? .orange.opacity(0.4) : .clear, radius: 6, x: 0, y: 3)
                        }
                        .buttonStyle(.plain)
                        .disabled(vm.isSavingToGallery)
                    }

                    // Save to Photos
                    Button(action: onSaveToPhotos) {
                        HStack(spacing: 8) {
                            if vm.isSavingToPhotos {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "photo.on.rectangle.angled")
                            }
                            Text("Save Video to Photos")
                                .fontWeight(.medium)
                        }
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background(Color(NSColor.controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(vm.isSavingToPhotos || vm.isSavingToGallery)

                    // Save to File System
                    Button {
                        onSaveToFile(showOriginal)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.down.doc")
                            Text("Save Video to File…")
                                .fontWeight(.medium)
                        }
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background(Color(NSColor.controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(vm.isSavingToGallery)
                }
            }
            .frame(width: 340)
            .padding(24)
        }
        .onAppear {
            vm.breeds = allBreeds
            setupPlayer()
        }
        .onChange(of: allBreeds) { _, newBreeds in
            vm.breeds = newBreeds
        }
        .onDisappear {
            player?.pause()
            player?.replaceCurrentItem(with: nil)
        }
    }

    private func trackedDogRow(dog: TrackedDogSummary) -> some View {
        let isHigh = dog.isHighConfidence
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(dog.displayName)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fontWeight(.bold)
                Text(dog.breedName)
                    .font(.subheadline)
                    .fontWeight(isHigh ? .bold : .medium)
            }
            Spacer()
            if dog.confidence > 0 {
                Text(String(format: "%.1f%%", dog.confidence * 100))
                    .font(.subheadline)
                    .fontWeight(isHigh ? .bold : .regular)
                    .foregroundColor(isHigh ? .orange : .secondary)
            }
        }
        .padding(12)
        .background(isHigh ? Color.orange.opacity(0.08) : Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isHigh ? Color.orange.opacity(0.4) : Color.primary.opacity(0.05), lineWidth: 1)
        )
    }

    private func fallbackDetectionRow(name: String, confidence: Double) -> some View {
        let isHigh = confidence >= 0.70
        return HStack {
            Text(name)
                .font(.subheadline)
                .fontWeight(isHigh ? .bold : .medium)
            Spacer()
            Text(String(format: "%.1f%%", confidence * 100))
                .font(.subheadline)
                .fontWeight(isHigh ? .bold : .regular)
                .foregroundColor(isHigh ? .orange : .secondary)
        }
        .padding(12)
        .background(isHigh ? Color.orange.opacity(0.08) : Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isHigh ? Color.orange.opacity(0.4) : Color.primary.opacity(0.05), lineWidth: 1)
        )
    }

    private func setupPlayer() {
        let targetURL = (showOriginal ? nil : vm.annotatedVideoURL) ?? vm.sourceURL
        let p = AVPlayer(url: targetURL)
        player = p
        p.play()
    }

    private func switchPlayer(showOriginal: Bool) {
        let targetURL = (showOriginal ? nil : vm.annotatedVideoURL) ?? vm.sourceURL
        player?.pause()
        let newPlayer = AVPlayer(url: targetURL)
        player = newPlayer
        newPlayer.play()
    }
}
