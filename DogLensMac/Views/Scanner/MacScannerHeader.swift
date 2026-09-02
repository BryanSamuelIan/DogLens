//
//  MacScannerHeader.swift
//  DogLensMac
//

import SwiftUI

struct MacScannerHeader: View {
    @Binding var inputMode: InputMode
    @Bindable var cameraManager: MacCameraManager
    let onUploadFile: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Picker("Mode", selection: $inputMode) {
                ForEach(InputMode.allCases) { mode in
                    Label(mode.rawValue, systemImage: mode.icon).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 320)
            .tint(.orange)

            Button(action: onUploadFile) {
                Label("Upload from File…", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.bordered)

            Spacer()

            if inputMode == .webcam && !cameraManager.availableDevices.isEmpty {
                cameraDeviceMenu
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var cameraDeviceMenu: some View {
        Menu {
            ForEach(cameraManager.availableDevices) { dev in
                Button {
                    cameraManager.selectDevice(id: dev.id)
                } label: {
                    HStack {
                        Text(dev.name)
                        if dev.id == cameraManager.selectedDeviceID {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            let activeName = cameraManager.availableDevices.first(where: { $0.id == cameraManager.selectedDeviceID })?.name ?? "Select Camera"
            Label(activeName, systemImage: "video.fill")
        }
        .menuStyle(.borderedButton)
    }
}
