//
//  CameraFormat.swift
//  RTP iOS
//
//  Created by David Nadoba on 24.04.20.
//  Copyright © 2020 David Nadoba. All rights reserved.
//

import Foundation
import AVFoundation

struct CameraFormat: Hashable, Codable {
    struct Dimension: Hashable, Codable {
        var width: Int
        var height: Int
    }
    var dimension: Dimension
    var frameRateRange: ClosedRange<Double>
    var maxZoom: Double
    var maxZoomWithoutUpscale: Double
    var isBinned: Bool
    var isMultiCamSupported: Bool
}

extension CameraFormat: Identifiable {
    var id: Self { self }
}

extension CameraFormat.Dimension: Comparable {
    static func < (lhs: CameraFormat.Dimension, rhs: CameraFormat.Dimension) -> Bool {
        if lhs.width == rhs.width {
            return lhs.height < rhs.height
        }
        return lhs.width < rhs.width
    }
}

extension CameraFormat.Dimension {
    var pixelCount: Int { width * height }
    func distance(to other: Self) -> Int {
        abs(pixelCount.distance(to: other.pixelCount))
    }
}

extension CameraFormat {
    static func isLhsBetterThanRhs(_ lhs: CameraFormat, _ rhs: CameraFormat) -> Bool {
        guard lhs.isBinned == rhs.isBinned else {
            return lhs.isBinned
        }
        guard lhs.isMultiCamSupported == rhs.isMultiCamSupported else {
            return lhs.isMultiCamSupported
        }
        guard lhs.frameRateRange.upperBound == rhs.frameRateRange.upperBound else {
            return lhs.frameRateRange.upperBound > rhs.frameRateRange.upperBound
        }
        guard lhs.maxZoomWithoutUpscale == rhs.maxZoomWithoutUpscale else {
            return lhs.maxZoomWithoutUpscale > rhs.maxZoomWithoutUpscale
        }
        guard lhs.maxZoom == rhs.maxZoom else {
            return lhs.maxZoom > rhs.maxZoom
        }
        return false
    }
}

func getSelecteableFrameRates(_ frameRateRange: ClosedRange<Double>) -> [Double] {
    [15, 30, 60, 120, 240].filter(frameRateRange.contains(_:))
}

func getDefaultFrameRate(_ frameRateRange: ClosedRange<Double>) -> Double? {
    [30, 60, 15, 120, 240].lazy.filter(frameRateRange.contains(_:)).first
}

extension CameraFormat {
    var selectableFrameRates: [Double] {
        getSelecteableFrameRates(frameRateRange)
    }
    var defaultFrameRate: Double? {
        getDefaultFrameRate(frameRateRange)
    }
}

extension CameraFormat.Dimension {
    init(_ dimensions: CMVideoDimensions) {
        self.init(
            width: Int(dimensions.width),
            height: Int(dimensions.height)
        )
    }
}

extension CameraFormat {
    init?(_ format: AVCaptureDevice.Format) {
        let description = format.formatDescription
        guard let frameRateMin = format.videoSupportedFrameRateRanges.map({ $0.minFrameRate }).min() else { return nil }
        guard let frameRateMax = format.videoSupportedFrameRateRanges.map({ $0.maxFrameRate }).max() else { return nil }
        self.init(
            dimension: Dimension(description.dimensions),
            frameRateRange: frameRateMin...frameRateMax,
            maxZoom: Double(format.videoMaxZoomFactor),
            maxZoomWithoutUpscale: Double(format.videoZoomFactorUpscaleThreshold),
            isBinned: format.isVideoBinned,
            isMultiCamSupported: format.isMultiCamSupported
        )
    }
}
