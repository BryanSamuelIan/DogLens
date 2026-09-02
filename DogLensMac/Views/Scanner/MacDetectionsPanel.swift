//
//  MacDetectionsPanel.swift
//  DogLensMac
//

import SwiftUI
import SwiftData

struct MacDetectionsPanel: View {
    let detections: [DetectionResult]
    let allBreeds: [DogBreed]
    let onSaveToGallery: () -> Void
    let onSaveToDevice: () -> Void

    private var hasEligibleDetection: Bool {
        detections.contains(where: { $0.confidence >= 0.7 })
    }

    private var isNewBreedDetected: Bool {
        detections.contains { result in
            result.confidence >= 0.7 && isNewBreed(name: result.label)
        }
    }

    private func isNewBreed(name: String) -> Bool {
        guard let breed = allBreeds.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
            return true
        }
        return breed.imageCount == 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerBar

            if detections.isEmpty {
                emptyState
            } else {
                resultsList
            }

            Spacer()
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var headerBar: some View {
        HStack {
            Image(systemName: "pawprint.fill")
                .foregroundColor(.orange)
            Text("Detection Results")
                .font(.headline)
            Spacer()
            Text("\(detections.count) dog\(detections.count == 1 ? "" : "s") detected")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.top, 20)
        .padding(.horizontal, 16)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "questionmark.circle")
                .font(.system(size: 40))
                .foregroundColor(.orange.opacity(0.6))
            Text("No dog breed recognized.")
                .font(.headline)
                .foregroundColor(.primary)
            Text("We couldn't find any dogs in this image. Make sure the dog is clearly visible and try again.")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(.horizontal, 16)
    }

    private var resultsList: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(detections) { item in
                    let isHigh = item.confidence >= 0.7
                    let isNew = isNewBreed(name: item.label)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(item.label)
                                .font(.headline)
                                .foregroundColor(.primary)
                            Spacer()
                            Text("\(Int(item.confidence * 100))%")
                                .font(.subheadline)
                                .fontWeight(isHigh ? .bold : .medium)
                                .foregroundColor(isHigh ? .orange : .secondary)
                        }

                        ProgressView(value: Double(item.confidence), total: 1.0)
                            .tint(isHigh ? .orange : .secondary)

                        if isHigh && isNew {
                            HStack(spacing: 4) {
                                Image(systemName: "sparkles")
                                    .font(.caption2)
                                Text("New Breed!")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                            }
                            .foregroundColor(.orange)
                            .padding(.top, 2)
                        }
                    }
                    .padding(12)
                    .background(isHigh ? Color.orange.opacity(0.08) : Color(NSColor.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(isHigh ? Color.orange.opacity(0.4) : Color.primary.opacity(0.06), lineWidth: isHigh ? 1.5 : 1)
                    )
                }

                Divider()
                    .padding(.vertical, 4)

                actionsArea
            }
            .padding(.horizontal, 16)
        }
    }

    private var actionsArea: some View {
        VStack(spacing: 10) {
            if hasEligibleDetection {
                if isNewBreedDetected {
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

                Button(action: onSaveToGallery) {
                    HStack(spacing: 6) {
                        if isNewBreedDetected {
                            Image(systemName: "star.fill")
                                .font(.subheadline)
                        } else {
                            Image(systemName: "plus.circle.fill")
                                .font(.subheadline)
                        }
                        Text("Save to Breed Gallery")
                            .font(.headline)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        isNewBreedDetected
                        ? LinearGradient(colors: [.orange, .pink], startPoint: .leading, endPoint: .trailing)
                        : LinearGradient(colors: [.orange, .orange], startPoint: .leading, endPoint: .trailing)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .shadow(
                        color: isNewBreedDetected ? .orange.opacity(0.5) : .clear,
                        radius: 8,
                        x: 0,
                        y: 4
                    )
                }
                .buttonStyle(.plain)
            }

            Button(action: onSaveToDevice) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.down.doc.fill")
                    Text("Save to Device…")
                        .font(.headline)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.blue)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }
}
