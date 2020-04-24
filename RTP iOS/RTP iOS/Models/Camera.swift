//
//  Camera.swift
//  RTP iOS
//
//  Created by David Nadoba on 24.04.20.
//  Copyright © 2020 David Nadoba. All rights reserved.
//

import Foundation
struct Camera: Hashable, Identifiable {
    var id: String
    var localizedName: String
}

extension Camera: ExpressibleByStringLiteral {
    init(stringLiteral: String) {
        self.init(id: UUID().description, localizedName: stringLiteral)
    }
}
