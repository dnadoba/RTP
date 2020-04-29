//
//  CameraSelectionViewController.swift
//  RTP iOS
//
//  Created by David Nadoba on 22.04.20.
//  Copyright © 2020 David Nadoba. All rights reserved.
//

import SwiftUI

import AVFoundation
extension AVCaptureDevice.Position: Comparable {
    public static func < (lhs: AVCaptureDevice.Position, rhs: AVCaptureDevice.Position) -> Bool {
        lhs.order < rhs.order
    }
    var order: Int {
        switch self {
        case .back: return 1
        case .front: return 2
        case .unspecified: return 3
        @unknown default: return 4
        }
    }
}

extension AVCaptureDevice.Format {
    static func isLhsBetterThenRhs(_ lhs: AVCaptureDevice.Format, _ rhs: AVCaptureDevice.Format) -> Bool {
        guard lhs.isVideoBinned == rhs.isVideoBinned else {
            return lhs.isVideoBinned
        }
        guard lhs.isMultiCamSupported == rhs.isMultiCamSupported else {
            return lhs.isMultiCamSupported
        }
        if let lhsMaxFrameRate = lhs.videoSupportedFrameRateRanges.map({ $0.maxFrameRate }).max(),
            let rhsMaxFrameRate = rhs.videoSupportedFrameRateRanges.map({ $0.maxFrameRate }).max(),
            lhsMaxFrameRate != rhsMaxFrameRate {
            return lhsMaxFrameRate > rhsMaxFrameRate
        }
        guard lhs.videoZoomFactorUpscaleThreshold == rhs.videoZoomFactorUpscaleThreshold else {
            return lhs.videoZoomFactorUpscaleThreshold > rhs.videoZoomFactorUpscaleThreshold
        }
        guard lhs.videoMaxZoomFactor == rhs.videoMaxZoomFactor else {
            return lhs.videoMaxZoomFactor > rhs.videoMaxZoomFactor
        }
        return false
    }
}

extension Sequence {
    func grouped<Key>(by getKey: (Element) -> Key) -> [Key: [Element]] where Key: Hashable {
        Dictionary(grouping: self, by: getKey)
    }
}

extension AVCaptureDevice {
    var relevantFormats: [AVCaptureDevice.Format] {
        self.formats.filter { $0.mediaType == .video && $0.formatDescription.mediaSubType == .init(string: "420v") }
    }
}

extension AVCaptureDevice.Position {
    var position: Camera.Position {
        switch self {
        case .unspecified: return .unspecified
        case .back: return .back
        case .front: return .front
        @unknown default: return .unspecified
        }
    }
}


final class CameraDiscovery {
    private let session: AVCaptureDevice.DiscoverySession
    var cameras: [Camera] {
        session.devices
            .sorted(by: { $0.position < $1.position })
            .map({ Camera(id: $0.uniqueID, localizedName: $0.localizedName, position: $0.position.position) })
    }
    var formats: [Camera.ID: CameraFormats] {
        Dictionary(uniqueKeysWithValues: session.devices.map({
            ($0.uniqueID, $0.relevantFormats.compactMap(CameraFormat.init(_:)))
        })).mapValues(CameraFormats.init(formats:))
    }
    init() {
        session = AVCaptureDevice.DiscoverySession(deviceTypes: [
            .builtInUltraWideCamera,
            .builtInWideAngleCamera,
            .builtInTelephotoCamera,
            .builtInDualCamera,
            .builtInTripleCamera,
        ], mediaType: .video, position: .unspecified)
    }
}

extension CameraSettingsViewModel {
    convenience init(
        selectedCamera: Camera.ID? = nil,
        selectedCameraFormats: CameraFormats? = nil,
        selectedFormat: CameraFormat? = nil,
        preferedFrameRate: Double? = nil
    ) {
        let session = CameraDiscovery()
        self.init(
            cameras: session.cameras,
            formatsOfCamera: session.formats,
            selectedCamera: selectedCamera,
            selectedCameraFormats: selectedCameraFormats,
            selectedFormat: selectedFormat,
            preferedFrameRate: preferedFrameRate
        )
    }
}

class CameraSelectionViewController: UIHostingController<CameraSettingsViewModelWrapper> {
    convenience init() {
        self.init(viewModel: CameraSettingsViewModel())
    }
    init(viewModel: CameraSettingsViewModel) {
        var indirectCallback: (() -> ())?
        super.init(rootView: CameraSettingsViewModelWrapper(settings: viewModel, dismiss: { indirectCallback?() }))
        indirectCallback = { [weak self] in
            self?.presentingViewController?.dismiss(animated: true)
        }
    }
    @objc required dynamic convenience init?(coder aDecoder: NSCoder) {
        self.init(coder: aDecoder, viewModel: CameraSettingsViewModel())
    }
    init?(coder aDecoder: NSCoder, viewModel: CameraSettingsViewModel) {
        var indirectCallback: (() -> ())?
        super.init(coder: aDecoder, rootView: CameraSettingsViewModelWrapper(settings: viewModel, dismiss: { indirectCallback?() }))
        indirectCallback = { [weak self] in
            self?.presentingViewController?.dismiss(animated: true)
        }
    }
}
