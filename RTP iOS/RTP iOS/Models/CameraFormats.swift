//
//  CameraForamts.swift
//  RTP iOS
//
//  Created by David Nadoba on 24.04.20.
//  Copyright © 2020 David Nadoba. All rights reserved.
//

import Foundation

extension Collection {
    func reduce(_ nextPartialResult: (Element, Element) throws -> Element) rethrows -> Element? {
        guard let first = self.first else { return nil }
        return try self.dropFirst().reduce(first, nextPartialResult)
    }
}

extension ClosedRange {
    func extended(by other: ClosedRange<Bound>) -> ClosedRange<Bound> {
        ClosedRange(uncheckedBounds: (
            lower: Swift.min(lowerBound, other.lowerBound),
            upper: Swift.max(upperBound, other.upperBound)
        ))
    }
}

struct CameraFormats {
    var formats: [CameraFormat]
    var dimensions: Set<CameraFormat.Dimension>
    var sortedDimensions: [CameraFormat.Dimension]
    var maxFrameRateRange: ClosedRange<Double>?
    init(formats: [CameraFormat]) {
        self.formats = formats
        dimensions = Set(formats.map(\.dimension))
        sortedDimensions = dimensions.sorted()
        maxFrameRateRange = formats.map(\.frameRateRange).reduce({ $0.extended(by: $1) })
    }
}

extension CameraFormats {
    var defaultDimension: CameraFormat.Dimension? {
        [
            CameraFormat.Dimension(width: 1920, height: 1080),
            CameraFormat.Dimension(width: 1280, height: 720),
            CameraFormat.Dimension(width: 640, height: 480),
        ].first(where: dimensions.contains(_:)) ?? dimensions.max()
    }
    var defaultFrameRate: Double? {
        maxFrameRateRange.flatMap(getDefaultFrameRate(_:))
    }
    var defaultForamt: CameraFormat? {
        guard let dimension = defaultDimension,
            let frameRate = defaultFrameRate else { return nil }
        return bestFormatMatching(dimension: dimension, pereferedFrameRate: frameRate)
    }
}

extension Sequence where Element == CameraFormat {
    func formatNearestTo(dimension: CameraFormat.Dimension, frameRate: Double) -> CameraFormat? {
        let grouped = self.grouped(by: { $0.dimension.distance(to: dimension) })
        let nearestDimensions = grouped.min(by: { $0.key < $1.key })
        let nearestDimension = nearestDimensions?.value
        let nearestFramerate = nearestDimension?.min(by: { lhs, rhs in
            let lhsFrameRateDistance = abs(lhs.frameRateRange.upperBound.distance(to: frameRate))
            let rhsFrameRateDistance = abs(rhs.frameRateRange.upperBound.distance(to: frameRate))

            guard lhsFrameRateDistance == rhsFrameRateDistance else {
                return lhsFrameRateDistance < rhsFrameRateDistance
            }
            return !CameraFormat.isLhsBetterThanRhs(lhs, rhs)
        })
        return nearestFramerate
    }
}

extension CameraFormats {
    func formatNearestTo(dimension: CameraFormat.Dimension, frameRate: Double) -> CameraFormat? {
        formats.formatNearestTo(dimension: dimension, frameRate: frameRate)
    }
    func bestFormatMatching(dimension: CameraFormat.Dimension, pereferedFrameRate: Double) -> CameraFormat? {
        let matchingFormats = formats.filter({ $0.dimension == dimension })
        return matchingFormats.min(by: { lhs, rhs in
            let lhsFrameRateDistance = abs(lhs.frameRateRange.upperBound.distance(to: pereferedFrameRate))
            let rhsFrameRateDistance = abs(rhs.frameRateRange.upperBound.distance(to: pereferedFrameRate))

            guard lhsFrameRateDistance == rhsFrameRateDistance else {
                return lhsFrameRateDistance < rhsFrameRateDistance
            }
            return !CameraFormat.isLhsBetterThanRhs(lhs, rhs)
        })
    }
    func bestFormatMatching(frameRate: Double, preferedDimension: CameraFormat.Dimension) -> CameraFormat? {
        let matchingFrameRate = formats.filter({ $0.frameRateRange.contains(frameRate) })
        let matchingDimension = matchingFrameRate.filter({ $0.dimension == preferedDimension })
        guard matchingDimension.isEmpty else {
            return matchingDimension.min(by: CameraFormat.isLhsBetterThanRhs(_:_:))
        }
        return matchingFrameRate.formatNearestTo(dimension: preferedDimension, frameRate: frameRate)
    }
}

struct CommonDimension: Hashable {
    static let allCases = [
        CommonDimension(name: "VGA", dimension: .init(width: 640, height: 480)),
        CommonDimension(name: "HD-Ready", dimension: .init(width: 1280, height: 720)),
        CommonDimension(name: "Full-HD", dimension: .init(width: 1920, height: 1080)),
        CommonDimension(name: "UHD", dimension: .init(width: 3840, height: 2160)),
    ]
    var name: String
    var dimension: CameraFormat.Dimension
}

extension CameraFormats {
    var selectedableCommonDimensions: [CommonDimension] {
        CommonDimension.allCases.filter({ self.dimensions.contains($0.dimension) })
    }
}
