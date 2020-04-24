//
//  CameraSettings.swift
//  RTP iOS
//
//  Created by David Nadoba on 24.04.20.
//  Copyright © 2020 David Nadoba. All rights reserved.
//

import Foundation

final class CameraSettingsViewModel: ObservableObject {
    @Published var cameras: [Camera]
    @Published var formatsOfCamera: [Camera.ID: CameraFormats]
    @Published var selectedCamera: Camera.ID? = nil {
        didSet {
            if let dimmension = self.selectedDimension,
                let frameRate = preferedFrameRate ?? effectiveFrameRate,
                let formats = selectedCameraFormats {
                selectedFormat = formats.formatNearestTo(dimension: dimmension, frameRate: frameRate)
            }
        }
    }
    var selectedCameraFormats: CameraFormats? {
        selectedCamera.flatMap({ formatsOfCamera[$0] })
    }
    @Published var selectedFormat: CameraFormat? = nil
    
    var selectedDimension: CameraFormat.Dimension? {
        get {
            self.selectedFormat?.dimension ?? selectedCameraFormats?.defaultDimension
        }
        set {
            if let newDimension = newValue {
                self.selectedFormat = selectedCameraFormats?.bestFormatMatching(
                    dimension: newDimension,
                    pereferedFrameRate: effectiveFrameRate ?? 30
                )
            }
        }
    }
    @Published var preferedFrameRate: Double? {
        didSet {
            if let newFrameRate = preferedFrameRate {
                self.selectedFormat = selectedCameraFormats?.bestFormatMatching(
                    frameRate: newFrameRate,
                    preferedDimension: selectedDimension ?? selectedCameraFormats?.defaultDimension ?? CameraFormat.Dimension(width: 1920, height: 1080)
                )
            }
        }
    }
    var effectiveFrameRate: Double? {
        if let frameRate = preferedFrameRate, let format = selectedFormat {
            let clampedFrameRate = frameRate.clamped(to: format.frameRateRange)
            return clampedFrameRate
        } else {
            return self.selectedFormat?.defaultFrameRate ?? selectedCameraFormats?.defaultFrameRate
        }
    }
    init(
        cameras: [Camera],
        formatsOfCamera: [Camera.ID : CameraFormats],
        selectedCamera: Camera.ID? = nil,
        selectedCameraFormats: CameraFormats? = nil,
        selectedFormat: CameraFormat? = nil,
        preferedFrameRate: Double? = nil
    ) {
        self.cameras = cameras
        self.formatsOfCamera = formatsOfCamera
        self.selectedCamera = selectedCamera ?? defaultCamera
        self.selectedFormat = selectedFormat ?? self.selectedCameraFormats?.defaultForamt
        self.preferedFrameRate = preferedFrameRate
    }
}

extension CameraSettingsViewModel {
    var defaultCamera: Camera.ID? { cameras.first?.id }
}
