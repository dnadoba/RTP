//
//  CameraSelection.swift
//  RTP iOS
//
//  Created by David Nadoba on 22.04.20.
//  Copyright © 2020 David Nadoba. All rights reserved.
//

import SwiftUI
import AVFoundation

struct CameraSettings: View {
    var cameras: [Camera]
    @State var selectedCamera: Camera.ID?
    var formats: [Camera.ID: CameraFormats]
    @State var selectedFormat: CameraFormat?
    @State var selectedFrameRate: Double?
    var body: some View {
        NavigationView {
            Form {
                Section {
                    CameraPicker(cameras: cameras, selectedCamera: $selectedCamera)
                }
                makeFormatPickerView()
            }.navigationBarTitle("Settings")
        }.navigationViewStyle(StackNavigationViewStyle())
    }
    private func makeFormatPickerView() -> AnyView {
        if let selectedCamera = self.selectedCamera,
            let formats = self.formats[selectedCamera] {
            return AnyView(makeFormatPickerView(formats: formats))
        } else {
            return AnyView(EmptyView())
        }
    }
    private func makeFormatPickerView(formats: CameraFormats) -> some View {
        CameraFormatPicker(
            formats: formats,
            selectedFormat: $selectedFormat,
            selectedFrameRate: $selectedFrameRate
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
//            selectedCamera: Self.cameras.first?.id,
//            formats: Self.formats,
//            selectedFormat: Self.cameras.first?.id.map({ Self.formats[ }))
//    }
//}


