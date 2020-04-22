//
//  CameraPicker.swift
//  RTP iOS
//
//  Created by David Nadoba on 22.04.20.
//  Copyright © 2020 David Nadoba. All rights reserved.
//

import SwiftUI

struct Camera: Hashable, Identifiable {
    var id: String
    var localizedName: String
}

extension Camera: ExpressibleByStringLiteral {
    init(stringLiteral: String) {
        self.init(id: UUID().description, localizedName: stringLiteral)
    }
}

struct CameraPicker: View {
    var cameras: [Camera]
    @Binding var selectedCamera: Camera.ID?
    var body: some View {
        Picker("Camera", selection: $selectedCamera) {
            ForEach(cameras) { camera in
                Text(camera.localizedName)
                    .tag(Optional.some(camera.id))
            }
        }
    }
}

struct CameraPicker_Previews: PreviewProvider, View {
    static let cameras: [Camera] = [
        "Back Camera",
        "Back Telephoto Camera",
        "Back Dual Camera",
        "Front Camera",
    ]
    static var previews: some View {
        CameraPicker_Previews(cameras: Self.cameras, selectedCamera: Self.cameras.first?.id)
    }
    
    var cameras: [Camera]
    @State var selectedCamera: Camera.ID?
    var body: some View {
        CameraPicker(cameras: cameras, selectedCamera: $selectedCamera)
    }
}
