//
//  Camera.swift
//  RTP iOS
//
//  Created by David Nadoba on 24.04.20.
//  Copyright © 2020 David Nadoba. All rights reserved.
//

import Foundation
struct Camera: Hashable, Identifiable {
    enum Position {
        case front
        case back
        case unspecified
    }
    var id: String
    var localizedName: String
    var position: Position
}

extension Camera {
    init(testName: String, position: Position) {
        self.init(id: UUID().uuidString, localizedName: testName, position: position)
    }
}
