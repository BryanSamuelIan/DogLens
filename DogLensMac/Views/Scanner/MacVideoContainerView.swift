//
//  MacVideoContainerView.swift
//  DogLensMac
//

import SwiftUI
import SwiftData

struct MacVideoContainerView: View {
    @ObservedObject var vm: MacVideoInferenceViewModel
    let allBreeds: [DogBreed]
    let onSaveToGallery: () -> Void
    let onSaveToFile: (Bool) -> Void
    let onSaveToPhotos: () -> Void
    let onScanAnother: () -> Void

    var body: some View {
        Group {
            if vm.annotatedVideoURL != nil {
                MacVideoResultView(
                    vm: vm,
                    allBreeds: allBreeds,
                    onSaveToGallery: onSaveToGallery,
                    onSaveToFile: onSaveToFile,
                    onSaveToPhotos: onSaveToPhotos,
                    onScanAnother: onScanAnother
                )
            } else {
                MacVideoPreviewView(
                    vm: vm,
                    onScanAnother: onScanAnother
                )
            }
        }
    }
}
