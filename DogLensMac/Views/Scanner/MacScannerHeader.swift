//
//  MacScannerHeader.swift
//  DogLensMac
//

import SwiftUI

struct MacScannerHeader: View {
    @Binding var scannerMode: ScannerMode
    @Binding var inputSource: MediaInputSource
    @Bindable var cameraManager: MacCameraManager
    let onUploadFile: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            // Main Scanner Mode Picker (Photo / Video / Live)
            Picker("Mode", selection: $scannerMode) {
                ForEach(ScannerMode.allCases) { mode in
                    Label(mode.rawValue, systemImage: mode.icon).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 330)
            .tint(.orange)

            // Sub-source selector (Webcam / File) when not in Live mode
            if scannerMode != .live {
                Picker("Input", selection: $inputSource) {
                    ForEach(MediaInputSource.allCases) { src in
                        Label(src.rawValue, systemImage: src.icon).tag(src)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
                .tint(.orange)

                Button(action: onUploadFile) {
                    Label(
                        scannerMode == .video ? "Upload Video…" : "Upload Photo…",
                        systemImage: "square.and.arrow.up"
                    )
                }
                .buttonStyle(.bordered)
            } else {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                    Text("Real-time YOLO Active")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.ultraThinMaterial, in: Capsule())
            }

            Spacer()

            // Camera selector menu if camera is used
            if (scannerMode == .live || inputSource == .camera) && !cameraManager.availableDevices.isEmpty {
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
