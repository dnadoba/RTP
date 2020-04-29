//
//  CameraSelection.swift
//  RTP iOS
//
//  Created by David Nadoba on 22.04.20.
//  Copyright © 2020 David Nadoba. All rights reserved.
//

import SwiftUI
import AVFoundation

struct CameraSettingsViewModelWrapper: View {
    @ObservedObject var settings: CameraSettingsViewModel
    var dismiss: (() -> ())?
    var body: some View {
        CameraSettings(
            cameras: settings.cameras,
            formatsOfCamera: settings.formatsOfCamera,
            selectedCamera: $settings.selectedCameraId,
            selectedDimmension: $settings.selectedDimension,
            selectedFormat: $settings.selectedFormat,
            preferedFrameRate: $settings.preferedFrameRate,
            effectiveFrameRate: settings.effectiveFrameRate,
            onDismiss: dismiss
        )
    }
}

struct CameraSettings: View {
    var cameras: [Camera]
    var formatsOfCamera: [Camera.ID: CameraFormats]
    @Binding var selectedCamera: Camera.ID?
    @Binding var selectedDimmension: CameraFormat.Dimension?
    @Binding var selectedFormat: CameraFormat?
    @Binding var preferedFrameRate: Double?
    var effectiveFrameRate: Double?
    var onDismiss: (() -> ())?
    var body: some View {
        NavigationView {
            Form {
                Section {
                    CameraPicker(cameras: cameras, selectedCamera: $selectedCamera)
                }
                makeFormatPickerView()
            }.navigationBarTitle("Settings").navigationBarItems(trailing: Button(action: {
                self.onDismiss?()
            }, label: { Text("Close") }))
        }.navigationViewStyle(StackNavigationViewStyle())
    }
    private func makeFormatPickerView() -> AnyView {
        if let selectedCamera = self.selectedCamera,
            let formats = self.formatsOfCamera[selectedCamera] {
            return AnyView(makeFormatPickerView(formats: formats))
        } else {
            return AnyView(EmptyView())
        }
    }
    private func makeFormatPickerView(formats: CameraFormats) -> some View {
        CameraFormatPicker(
            formats: formats,
            selectedFormat: $selectedFormat,
            selectedDimension: $selectedDimmension,
            preferedFrameRate: $preferedFrameRate,
            effectiveFrameRate: effectiveFrameRate
        )
    }
}





//struct CameraSettings_Previews: PreviewProvider {
//    static let cameras: [Camera] = CameraPicker_Previews.cameras
//    static let formats: [Camera.ID: [CameraFormat]] = Dictionary(uniqueKeysWithValues:
//        zip(
//            Self.cameras.map(\.id),
//            (0...).lazy.map({ _ in CameraFormatPicker_Previews.formats })))
//    static var previews: some View {
//        CameraSettings(
//            cameras: Self.cameras,
//            selectedCameraId: Self.cameras.first?.id,
//            formats: Self.formats,
//            selectedFormat: Self.cameras.first?.id.map({ Self.formats[ }))
//    }
//}


