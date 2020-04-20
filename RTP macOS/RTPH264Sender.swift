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

final class RTPH264Sender {
    private let queue = DispatchQueue(label: "de.nadoba.\(RTPH264Sender.self)")
    private let item: AVPlayerItem
    private let player: AVPlayer
    private let timer: RepeatingTimer
    private let encoder: VideoEncoder
    private let output: AVPlayerItemVideoOutput
    private let frameDuration: CMTime
    private let connection = NWConnection(to: .hostPort(host: "127.0.0.1", port: 1234), using: .udp)
    private var rtpSerialzer: RTPSerialzer
    private var h264Serialzer: H264.NALNonInterleavedPacketSerializer<Data>
    
    init() {
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
        
        rtpSerialzer = .init(maxSizeOfPacket: connection.maximumDatagramSize, synchronisationSource: RTPSynchronizationSource(rawValue: .random(in: UInt32.min...UInt32.max)))
        h264Serialzer = .init(maxSizeOfNalu: rtpSerialzer.maxSizeOfPayload)
        
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
        
        connection.start(queue: queue)
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
        do {
            print("encode frame")
            try encoder.encodeFrame(imageBuffer: buffer, presentationTimeStamp: displayTime, duration: frameDuration, frameProperties: [:
                //kVTEncodeFrameOptionKey_ForceKeyFrame: true,
            ])
        } catch {
            print(error)
        }
    }
    
    
    private func sendBuffer(_ sampleBuffer: CMSampleBuffer) {
        let lengthOfSizePrefix = 4
        var nalus = [H264.NALUnit<Data>]()
        let presentationTimeStamp = sampleBuffer.presentationTimeStamp
        CMSampleBufferCallBlockForEachSample(sampleBuffer) { (buffer, count) -> OSStatus in
            if let dataBuffer = buffer.dataBuffer {
                do {
                    let newNalus = try dataBuffer.withContiguousStorage { storage -> [H264.NALUnit<Data>] in
                        let storage = storage.bindMemory(to: UInt8.self)
                        var reader = BinaryReader(bytes: storage)
                        var newNalus = [H264.NALUnit<Data>]()
                        while !reader.isEmpty {
                            let length = try reader.readInteger(type: UInt32.self)
                            let header = try H264.NALUnitHeader(from: &reader)
                            let payload = Data(try reader.readBytes(Int(length) - 1))
                            newNalus.append(H264.NALUnit<Data>(header: header, payload: payload))
                        }
                        return newNalus
                    }
                    nalus.append(contentsOf: newNalus)
                } catch {
                    print(error)
                }
            }
            return kOSReturnSuccess
        }
        if nalus.contains(where: { $0.header.type == H264.NALUnitType.instantaneousDecodingRefreshCodedSlice }),
            let formatDescription = sampleBuffer.formatDescription {
            let parameterSet = formatDescription.h264ParameterSets()
            nalus.insert(contentsOf: parameterSet, at: 0)
        }
        sendNalus(nalus, timestamp: UInt32(presentationTimeStamp.convertScale(90_000, method: .default).value))
        
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
                        print("size of packet", data.count, "maximumDatagramSize", connection.maximumDatagramSize)
                        connection.send(content: data, completion: .idempotent)
                    } catch {
                        print(error)
                    }
                }
            }
        } catch {
            print(error)
        }
    }
}


extension CMFormatDescription {
    func h264ParameterSets() -> [H264.NALUnit<Data>] {
        var nalus = [H264.NALUnit<Data>]()
        var index = 0
        var count = 0
        CMVideoFormatDescriptionGetH264ParameterSetAtIndex(self, parameterSetIndex: -1, parameterSetPointerOut: nil, parameterSetSizeOut: nil, parameterSetCountOut: &count, nalUnitHeaderLengthOut: nil)
        while index < count {
            defer { index += 1 }
            do {
                var pointerOut: UnsafePointer<UInt8>?
                var size = 0
                CMVideoFormatDescriptionGetH264ParameterSetAtIndex(self, parameterSetIndex: index, parameterSetPointerOut: &pointerOut, parameterSetSizeOut: &size, parameterSetCountOut: nil, nalUnitHeaderLengthOut: nil)
                if let pointerOut = pointerOut {
                    let data = Data.init(bytes: pointerOut, count: size)
                    var reader = BinaryReader(bytes: data)
                    let nalu = H264.NALUnit(header: try .init(from: &reader), payload: try reader.readRemainingBytes())
                    nalus.append(nalu)
                } else {
                    print("could not get H264ParameterSet")
                }
            } catch {
                print(error)
            }
        }
        return nalus
    }
}
