//
//  RTPH264Sender.swift
//  RTPViewer
//
//  Created by David Nadoba on 17.04.20.
//  Copyright © 2020 David Nadoba. All rights reserved.
//

import Foundation
import VideoToolbox
import SwiftRTP
import BinaryKit
import RTPAVKit

import AVFoundation
import Network

extension CVPixelBuffer {
    /// Returns the width of the PixelBuffer in pixels.
    var width: Int { CVPixelBufferGetWidth(self) }
    /// Returns the height of the PixelBuffer in pixels.
    var height: Int { CVPixelBufferGetHeight(self) }
}

public final class RTPH264Sender {
    private let queue: DispatchQueue
    private var encoder: VideoEncoder?
    private let connection: NWConnection
    private var rtpSerialzer: RTPSerialzer = .init(maxSizeOfPacket: 9216, synchronisationSource: RTPSynchronizationSource(rawValue: .random(in: UInt32.min...UInt32.max)))
    private lazy var h264Serialzer: H264.NALNonInterleavedPacketSerializer<Data> = .init(maxSizeOfNalu: rtpSerialzer.maxSizeOfPayload)
    public init(endpoint: NWEndpoint, targetQueue: DispatchQueue? = nil) {
        queue = DispatchQueue(label: "de.nadoba.\(RTPH264AssetSender.self)", target: targetQueue)
        connection = NWConnection(to: endpoint, using: .udp)
        connection.start(queue: queue)
    }
    
    @discardableResult
    public func setupEncoderIfNeeded(width: Int, height: Int) -> VideoEncoder {
        if let encoder = self.encoder, encoder.width == width, encoder.height == encoder.height {
            return encoder
        }
        let encoder = try! VideoEncoder(
            width: width,
            height: height,
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
        
        self.encoder = encoder
        return encoder
    }
    
    public func encodeAndSendFrame(_ frame: CVPixelBuffer, presentationTimeStamp: CMTime, frameDuration: CMTime) {
        do {
            let encoder = setupEncoderIfNeeded(width: frame.width, height: frame.height)
            try encoder.encodeFrame(imageBuffer: frame, presentationTimeStamp: presentationTimeStamp, duration: frameDuration, frameProperties: [:
                //kVTEncodeFrameOptionKey_ForceKeyFrame: true,
            ])
        } catch {
            print(error, #file, #line)
        }
    }
    private func sendBuffer(_ sampleBuffer: CMSampleBuffer) {
        let nalus = sampleBuffer.convertToH264NALUnitsAndAddPPSAndSPSIfNeeded(dataType: Data.self)
        
        let timestamp = UInt32(sampleBuffer.presentationTimeStamp.convertScale(90_000, method: .default).value)
        sendNalus(nalus, timestamp: timestamp)
    }
    private func sendNalus(_ nalus: [H264.NALUnit<Data>], timestamp: UInt32) {
        guard connection.maximumDatagramSize > 0 else { return }
        rtpSerialzer.maxSizeOfPacket = 9216
        h264Serialzer.maxSizeOfNaluPacket = rtpSerialzer.maxSizeOfPayload
        do {
            let packets = try h264Serialzer.serialize(nalus, timestamp: timestamp, lastNALUsForGivenTimestamp: true)
            connection.batch {
                for packet in packets {
                    do {
                        let data: Data = try rtpSerialzer.serialze(packet)
                        connection.send(content: data, completion: .idempotent)
                    } catch {
                        print(error, #file, #line)
                    }
                }
            }
        } catch {
            print(error, #file, #line)
        }
    }
}

final class RTPH264AssetSender {
    private let queue = DispatchQueue(label: "de.nadoba.\(RTPH264AssetSender.self)")
    private let item: AVPlayerItem
    private let player: AVPlayer
    private let timer: RepeatingTimer
    private let output: AVPlayerItemVideoOutput
    private let frameDuration: CMTime
    private let sender: RTPH264Sender
    
    init(endpoint: NWEndpoint) {
        sender = RTPH264Sender(endpoint: .hostPort(host: "127.0.0.1", port: 1234), targetQueue: queue)
        let asset = AVAsset(url: Bundle.main.url(forResource: "SalesPerSecond(1)", withExtension: ".mov")!)
        let track = asset.tracks(withMediaCharacteristic: .visual).first!
        let frameRate = track.nominalFrameRate
        let size = track.naturalSize
        let duration = asset.duration.seconds
        frameDuration = CMTime(seconds: Double(1/frameRate), preferredTimescale: 60_000)
        
        output = AVPlayerItemVideoOutput()
        item = AVPlayerItem(asset: asset)
        item.add(output)
        
        
        player = AVPlayer(playerItem: item)
        
        timer = RepeatingTimer(refreshRate: Double(frameRate), queue: queue)
        
        sender.setupEncoderIfNeeded(width: Int(size.width), height: Int(size.height))
        
        timer.eventHandler = { [weak self] in
            self?.eventHandler()
        }
        
        let loopTimer = Timer.init(timeInterval: duration, repeats: true) { _ in
            self.player.pause()
            self.player.seek(to: .zero)
            self.player.play()
        }
        let startDelayTimer = Timer.init(timeInterval: 0.5, repeats: false) { _ in
            self.timer.resume()
            self.player.play()
            RunLoop.main.add(loopTimer, forMode: .common)
        }
        RunLoop.main.add(startDelayTimer, forMode: .common)
    }
    
    private func eventHandler() {
        var displayTime = CMTime()
        guard let buffer = output.copyPixelBuffer(forItemTime: item.currentTime(), itemTimeForDisplay: &displayTime) else {
            print("could not copy pixel buffer")
            return
        }
        sender.encodeAndSendFrame(buffer, presentationTimeStamp: displayTime, frameDuration: frameDuration)
    }
}
