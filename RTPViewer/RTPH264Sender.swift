//
//  RTPH264Sender.swift
//  RTPViewer
//
//  Created by David Nadoba on 17.04.20.
//  Copyright © 2020 David Nadoba. All rights reserved.
//

import Foundation
import VideoToolbox

enum VideoCodec {
    case h264
    case h265
    case h265WithAlpha
}

extension VideoCodec {
    var codecType: CMVideoCodecType {
        switch self {
        case .h264: return kCMVideoCodecType_H264
        case .h265: return kCMVideoCodecType_HEVC
        case .h265WithAlpha: return kCMVideoCodecType_HEVCWithAlpha
        }
    }
}

final class VideoEncoder {
    typealias Callback = (CMSampleBuffer, VTEncodeInfoFlags) -> ()
    var callback: Callback?
    private var session: VTCompressionSession!
    init(
        allocator: CFAllocator? = nil,
        width: Int,
        height: Int,
        codec: VideoCodec,
        encoderSpecification: NSDictionary?,
        imageBufferAttributes: NSDictionary?,
        compressedDataAllocator: CFAllocator? = nil
    ) throws {
        let ptr = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        //            let mutablePointer = UnsafeMutableRawPointer.allocate(byteCount: MemoryLayout<VideoEncoder>.size, alignment: MemoryLayout<VideoEncoder>.alignment)
        //            defer { mutablePointer.deallocate() }
        //            mutablePointer.initializeMemory(as: VideoEncoder.self, from: selfPointer, count: 1)
        var session: VTCompressionSession?
        let status = VTCompressionSessionCreate(
            allocator: allocator,
            width: Int32(width),
            height: Int32(height),
            codecType: codec.codecType,
            encoderSpecification: encoderSpecification,
            imageBufferAttributes: imageBufferAttributes,
            compressedDataAllocator: compressedDataAllocator,
            outputCallback: { (selfPointer, _, status, infoFlags, sampleBuffer) in
                let mySelf = Unmanaged<VideoEncoder>.fromOpaque(UnsafeRawPointer(selfPointer!)).takeUnretainedValue()
                guard status == kOSReturnSuccess, let sampleBuffer = sampleBuffer else {
                    print(OSStatusError(osStatus: status, description: "failed to compress frame"))
                    return
                }
                
                mySelf.callback?(sampleBuffer, infoFlags)
                
        }, refcon: ptr, compressionSessionOut: &session)
        
        guard status == kOSReturnSuccess, let unwrapedSession = session else {
            throw OSStatusError(osStatus: status, description: "failed to create \(VTCompressionSession.self) width: \(width) height: \(height) codec: \(codec) encoderSpecification: \(encoderSpecification as Any) imageBufferAttributes: \(imageBufferAttributes as Any)")
        }
        self.session = unwrapedSession
        
    }
    deinit {
        print("deinit")
        if let session = session {
            VTCompressionSessionInvalidate(session)
        }
    }
    @discardableResult
    func encodeFrame(
        imageBuffer: CVImageBuffer,
        presentationTimeStamp: CMTime,
        duration: CMTime,
        frameProperties: NSDictionary? = nil
    ) throws -> VTEncodeInfoFlags {
        var infoFlags = VTEncodeInfoFlags()
        
        let status = VTCompressionSessionEncodeFrame(session, imageBuffer: imageBuffer, presentationTimeStamp: presentationTimeStamp, duration: duration, frameProperties: frameProperties, sourceFrameRefcon: nil, infoFlagsOut: &infoFlags)
        guard status == kOSReturnSuccess else {
            throw OSStatusError(osStatus: status, description: "failed to encode frame \(imageBuffer) presentationTimeStamp: \(presentationTimeStamp) duration\(duration) frameProperties \(frameProperties as Any) info flags: \(infoFlags)")
        }
        return infoFlags
    }
}

import AVFoundation
import Network
final class RTPH264Sender {
    private let queue = DispatchQueue(label: "de.nadoba.\(RTPH264Sender.self)")
    private let item: AVPlayerItem
    private let player: AVPlayer
    private let timer: RepeatingTimer
    private let encoder: VideoEncoder
    private let output: AVPlayerItemVideoOutput
    private let duration: CMTime
    private let connection = NWConnection(to: .hostPort(host: "localhost", port: 1234), using: .udp)

    init() {
        let asset = AVAsset(url: Bundle.main.url(forResource: "SalesPerSecond(1)", withExtension: ".mov")!)
        let track = asset.tracks(withMediaCharacteristic: .visual).first!
        let frameRate = track.nominalFrameRate
        let size = track.naturalSize
        duration = CMTime(seconds: Double(1/frameRate), preferredTimescale: 60_000)
        
        output = AVPlayerItemVideoOutput()
        item = AVPlayerItem(asset: asset)
        item.add(output)
        
        player = AVPlayer(playerItem: item)
        
        timer = RepeatingTimer(refreshRate: Double(frameRate), queue: queue)
        
        encoder = try! VideoEncoder(
            width: Int(size.width),
            height: Int(size.height),
            codec: .h264,
            encoderSpecification: [
                kVTCompressionPropertyKey_AllowFrameReordering: false,
                kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder: true,
                kVTCompressionPropertyKey_RealTime: true,
            ],
            imageBufferAttributes: nil)
        
        encoder.callback = { [weak self] buffer, flags in
            self?.sendBuffer(buffer)
        }
        
        timer.eventHandler = { [weak self] in
            self?.eventHandler()
        }
        timer.resume()
        player.play()
    }
    private func eventHandler() {
        var displayTime = CMTime()
        guard let buffer = output.copyPixelBuffer(forItemTime: item.currentTime(), itemTimeForDisplay: &displayTime) else {
            print("could not copy pixel buffer")
            return
        }
        do {
            print("encode frame")
            try encoder.encodeFrame(imageBuffer: buffer, presentationTimeStamp: displayTime, duration: duration)
        } catch {
            print(error)
        }
    }
    
    
    private func sendBuffer(_ buffer: CMSampleBuffer) {
        CMSampleBufferCallBlockForEachSample(buffer) { (buffer, count) -> OSStatus in
            let presentationTimeStamp = buffer.presentationTimeStamp
            return kOSReturnSuccess
        }
    }
}
