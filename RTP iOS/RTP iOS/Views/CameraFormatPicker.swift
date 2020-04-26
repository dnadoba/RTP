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
                (preferedFrameRate ?? effectiveFrameRate).map($0.frameRateRange.contains(_:)) ?? true
        }).sorted(by: CameraFormat.isLhsBetterThanRhs(_:_:))
    }
    @Binding var selectedFormat: CameraFormat?
    @Binding var selectedDimension: CameraFormat.Dimension?
    var frameRates: [Double]? { formats.maxFrameRateRange.map(getSelecteableFrameRates(_:)) }
    @Binding var preferedFrameRate: Double?
    var effectiveFrameRate: Double?
    var frameRateBinding: Binding<Double?> {
        $preferedFrameRate.map(get: { _ in self.effectiveFrameRate })
    }
    var body: some View {
        Group {
            Section {
                Picker("Resolution", selection: $selectedDimension) {
                    ForEach(formats.sortedDimensions, id: \.self) { dimension in
                        Text("\(dimension.width, numberFormatter: Self.pixelForamtter)x\(dimension.height, numberFormatter: Self.pixelForamtter)").font(.headline)
                            .tag(Optional.some(dimension))
                    }
                }
                Picker("Resolution", selection: $selectedDimension) {
                    ForEach(formats.selectedableCommonDimensions, id: \.self) { commonDimension in
                        Text("\(commonDimension.name)")
                            .tag(Optional.some(commonDimension.dimension))
                    }
                }.pickerStyle(SegmentedPickerStyle())
                if formats.maxFrameRateRange != nil {
                    Picker("Frame Rate", selection: frameRateBinding) {
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
            selectedDimension: Self.formats.last?.dimension,
            selectedFrameRate: Self.formats.last?.defaultFrameRate,
            effectiveFrameRate: Self.formats.last?.defaultFrameRate
        )
    }
    var formats: [CameraFormat]
    @State var selectedFormat: CameraFormat?
    @State var selectedDimension: CameraFormat.Dimension?
    @State var selectedFrameRate: Double?
    var effectiveFrameRate: Double?
    var body: some View {
        NavigationView {
            Form {
                CameraFormatPicker(
                    formats: CameraFormats(formats: Self.formats),
                    selectedFormat: $selectedFormat,
                    selectedDimension: $selectedDimension,
                    preferedFrameRate: $selectedFrameRate,
                    effectiveFrameRate: effectiveFrameRate
                )
            }
        }
    }
}
