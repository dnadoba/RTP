//
//  CameraFormatPicker.swift
//  RTP iOS
//
//  Created by David Nadoba on 22.04.20.
//  Copyright © 2020 David Nadoba. All rights reserved.
//

import SwiftUI
import AVFoundation
import RTPAVKit

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
}

extension CameraFormats {
    func bestFormatMatching(dimension: CameraFormat.Dimension, pereferedFrameRate: Double) -> CameraFormat? {
        let matchingFormats = formats.filter({ $0.dimension == dimension })
        return matchingFormats.min(by: { lhs, rhs in
            lhs.frameRateRange.upperBound.distance(to: pereferedFrameRate) < rhs.frameRateRange.upperBound.distance(to: pereferedFrameRate)
        })
    }
    func bestFormatMatching(frameRate: Double, preferedDimension: CameraFormat.Dimension) -> CameraFormat? {
        let matchingFrameRate = formats.filter({ $0.frameRateRange.contains(frameRate) })
        let matchingDimension = matchingFrameRate.filter({ $0.dimension == preferedDimension })
        guard matchingDimension.isEmpty else {
            return matchingDimension.min(by: CameraFormat.isLhsBetterThenRhs(_:rhs:))
        }
        return matchingFrameRate.min(by: { lhs, rhs in
            let lhsFrameRateDistance = lhs.frameRateRange.upperBound.distance(to: frameRate)
            let rhsFrameRateDistance = rhs.frameRateRange.upperBound.distance(to: frameRate)
            
            let lhsDimensionDistance = lhs.dimension.distance(to: preferedDimension)
            let rhsDimensionDistance = rhs.dimension.distance(to: preferedDimension)
            guard lhsDimensionDistance == rhsDimensionDistance else {
               return lhsDimensionDistance < rhsDimensionDistance
            }
            return lhsFrameRateDistance < rhsFrameRateDistance
        })
    }
}

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
        pixelCount.distance(to: other.pixelCount)
    }
}

extension CameraFormat {
    static func isLhsBetterThenRhs(_ lhs: CameraFormat, rhs: CameraFormat) -> Bool {
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

func with<T>(_ element: @autoclosure () -> T, transform: (inout T) -> ()) -> T {
    var initalElement = element()
    transform(&initalElement)
    return initalElement
}

extension LocalizedStringKey.StringInterpolation {
    public mutating func appendInterpolation<Number>(_ subject: Number, numberFormatter: Formatter? = nil) where Number : Numeric {
        appendInterpolation(subject as! NSNumber, formatter: numberFormatter)
    }
}

extension Binding {
    func map<NewValue>(
        get: @escaping (Value) -> NewValue,
        set: @escaping (NewValue) -> Value
    ) -> Binding<NewValue> {
        return Binding<NewValue>(
            get: { get(self.wrappedValue) },
            set: { self.wrappedValue = set($0) }
        )
    }
    func map(get: @escaping (Value) -> Value) -> Binding<Value> {
        map(get: get, set: { $0 })
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        max(min(self, range.upperBound), range.lowerBound)
    }
}

struct CameraFormatView: View {
    static let pixelForamtter = NumberFormatter()
    static let fpsForamtter = with(NumberFormatter()) {
        $0.minimumFractionDigits = 0
        $0.maximumFractionDigits = 2
    }
    static let zoomForamtter = with(NumberFormatter()) {
        $0.minimumFractionDigits = 0
        $0.maximumFractionDigits = 2
    }
    var format: CameraFormat
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("\(format.dimension.width, numberFormatter: Self.pixelForamtter)x\(format.dimension.height, numberFormatter: Self.pixelForamtter)").font(.headline)
                Spacer()
                Text("\(format.frameRateRange.lowerBound, numberFormatter: Self.fpsForamtter)-\(format.frameRateRange.upperBound, numberFormatter: Self.fpsForamtter) FPS")
                    .foregroundColor(.secondary)
            }
            Text("Max Zoom \(format.maxZoom, numberFormatter: Self.zoomForamtter)(upscales @\(format.maxZoomWithoutUpscale, numberFormatter: Self.zoomForamtter))")
            HStack {
                if format.isBinned {
                    Text("Binned")
                        .padding(2)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.green, lineWidth: 1)
                    )
                }
                if format.isMultiCamSupported {
                    Text("Supports Multicam")
                        .padding(2)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.orange, lineWidth: 1)
                    )
                }
            }
        }
    }
}

struct CameraFormatPicker: View {
    static let pixelForamtter = NumberFormatter()
    static let fpsForamtter = with(NumberFormatter()) {
        $0.minimumFractionDigits = 0
        $0.maximumFractionDigits = 2
    }
    static let zoomForamtter = with(NumberFormatter()) {
        $0.minimumFractionDigits = 0
        $0.maximumFractionDigits = 2
    }
    var formats: CameraFormats
    var matchingFormats: [CameraFormat] {
        return formats.formats.filter({
            $0.dimension == selectedFormat?.dimension &&
                selectedFrameRate.map($0.frameRateRange.contains(_:)) ?? true
        }).sorted(by: CameraFormat.isLhsBetterThenRhs(_:rhs:))
    }
    @Binding var selectedFormat: CameraFormat?
    var frameRates: [Double]? { formats.maxFrameRateRange.map(getSelecteableFrameRates(_:)) }
    @Binding var selectedFrameRate: Double?
    private var selecteFrameRateBinding: Binding<Double?> {
        Binding(get: {
            if let frameRate = self.selectedFrameRate, let format = self.selectedFormat {
                let clampedFrameRate = frameRate.clamped(to: format.frameRateRange)
                return clampedFrameRate
            } else {
                return self.selectedFormat?.defaultFrameRate ?? self.formats.defaultFrameRate
            }
        }) { (newFrameRate) in
            if let newFrameRate = newFrameRate {
                self.selectedFormat = self.formats.bestFormatMatching(
                    frameRate: newFrameRate,
                    preferedDimension: self.selectedResolution.wrappedValue ?? CameraFormat.Dimension(width: 1920, height: 1080)
                )
            }
            self.selectedFrameRate = newFrameRate
        }
    }
    private var selectedResolution: Binding<CameraFormat.Dimension?> {
        Binding(get: {
            self.selectedFormat?.dimension ?? self.formats.defaultDimension
        }, set: { newDimension in
            if let newDimension = newDimension {
                self.selectedFormat = self.formats.bestFormatMatching(
                    dimension: newDimension,
                    pereferedFrameRate: self.selecteFrameRateBinding.wrappedValue ?? 30
                )
            }
        })
    }
    var body: some View {
        Group {
            Section {
                Picker("Resolution", selection: selectedResolution) {
                    ForEach(formats.sortedDimensions, id: \.self) { dimension in
                        Text("\(dimension.width, numberFormatter: Self.pixelForamtter)x\(dimension.height, numberFormatter: Self.pixelForamtter)").font(.headline)
                            .tag(Optional.some(dimension))
                    }
                }
                if formats.maxFrameRateRange != nil {
                    Picker("Frame Rate", selection: selecteFrameRateBinding) {
                        ForEach(frameRates ?? [], id: \.self) { frameRate in
                            Text("\(frameRate, numberFormatter: Self.fpsForamtter)")
                                .tag(Optional.some(frameRate))
                        }
                    }.pickerStyle(SegmentedPickerStyle())
                }
            }
            
            Section(header: Text("Matching Formats")) {
                ForEach(matchingFormats) { format in
                    Button(action: { self.selectedFormat = format }) {
                        HStack {
                            CameraFormatView(format: format)
                            if format == self.selectedFormat {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
            Section(header: Text("All Formats")) {
                Picker(selection: $selectedFormat, label: EmptyView()) {
                    ForEach(formats.formats) { format in
                        CameraFormatView(format: format)
                            .tag(Optional.some(format))
                    }
                }
            }
        }
    }
}

struct CameraFormatPicker_Previews: PreviewProvider, View {
    static let formats = [
        CameraFormat(
            dimension: .init(width: 640, height: 480),
            frameRateRange: 1...60,
            maxZoom: 64,
            maxZoomWithoutUpscale: 2,
            isBinned: true,
            isMultiCamSupported: true
        ),
        CameraFormat(
            dimension: .init(width: 1280, height: 720),
            frameRateRange: 1...240,
            maxZoom: 64,
            maxZoomWithoutUpscale: 1,
            isBinned: true,
            isMultiCamSupported: true
        ),
        CameraFormat(
            dimension: .init(width: 1920, height: 1080),
            frameRateRange: 1...240,
            maxZoom: 64,
            maxZoomWithoutUpscale: 1,
            isBinned: true,
            isMultiCamSupported: true
        ),
    ]
    static var previews: some View {
        CameraFormatPicker_Previews(
            formats: Self.formats,
            selectedFormat: Self.formats.last,
            selectedFrameRate: Self.formats.last?.defaultFrameRate
        )
    }
    var formats: [CameraFormat]
    @State var selectedFormat: CameraFormat?
    @State var selectedFrameRate: Double?
    var body: some View {
        NavigationView {
            Form {
                CameraFormatPicker(
                    formats: CameraFormats(formats: Self.formats),
                    selectedFormat: $selectedFormat,
                    selectedFrameRate: $selectedFrameRate
                )
            }
        }
    }
}
