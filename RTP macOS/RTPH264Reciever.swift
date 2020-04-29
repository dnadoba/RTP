//
//  RTPH264Reciever.swift
//  RTPViewer
//
//  Created by David Nadoba on 10.04.20.
//  Copyright © 2020 David Nadoba. All rights reserved.
//

import Foundation
import Network
import SwiftRTP
import BinaryKit
import Dispatch
import VideoToolbox

final class VideoDecoder {
    typealias Callback = (_ imageBuffer: CVPixelBuffer?, _ presentationTimeStamp: CMTime, _ presentationDuration: CMTime) -> ()
    fileprivate var session: VTDecompressionSession
    var callback: Callback?
    init(formatDescription: CMVideoFormatDescription) throws {
        var session: VTDecompressionSession?
        let callback = VTDecompressionOutputCallbackRecord(
            decompressionOutputCallback: { (decompressionOutputRefCon, sourceFrameRefCon, status, infoFlags, imageBuffer, presentationTimeStamp, presentationDuration) in
                guard status == kOSReturnSuccess else {
                    print(OSStatusError(osStatus: status, description: "VTDecompressionOutputCallbackRecord"))
                    return
                }
        },
            decompressionOutputRefCon: nil)
        let status = withUnsafePointer(to: callback) { (callbackPointer) in
            VTDecompressionSessionCreate(
                allocator: nil, formatDescription: formatDescription,
                decoderSpecification: nil,
                imageBufferAttributes: nil,
                outputCallback: callbackPointer, decompressionSessionOut: &session)
        }
        
        guard status == kOSReturnSuccess, let unwrapedSession = session else {
            throw OSStatusError(osStatus: status, description: "failed to create \(VTDecompressionSession.self) from \(formatDescription)")
        }
        self.session = unwrapedSession
    }
    private func decompressionOutputCallback(imageBuffer: CVPixelBuffer?, presentationTimeStamp: CMTime, presentationDuration: CMTime) {
        callback?(imageBuffer, presentationTimeStamp, presentationDuration)
    }
    @discardableResult
    func decodeFrame(sampleBuffer: CMSampleBuffer, flags: VTDecodeFrameFlags = VTDecodeFrameFlags()) throws -> VTDecodeInfoFlags {
        var infoFlags = VTDecodeInfoFlags()
        let status = VTDecompressionSessionDecodeFrame(session,
                                          sampleBuffer: sampleBuffer,
                                          flags: flags,
                                          frameRefcon: nil,
                                          infoFlagsOut: &infoFlags)
        guard status == kOSReturnSuccess else {
            throw OSStatusError(osStatus: status, description: "failed to decode frame \(sampleBuffer) info flags: \(infoFlags)")
        }
        return infoFlags
    }
    func canAcceptFormatDescription(_ formatDescription: CMFormatDescription) -> Bool {
        VTDecompressionSessionCanAcceptFormatDescription(session, formatDescription: formatDescription)
    }
}

final class RTPH264Reciever {
    typealias Callback = (CMSampleBuffer) -> ()
    var connection: NWConnection?
    let queue = DispatchQueue(label: "de.nadoba.\(RTPH264Reciever.self).udp")
    let listen: NWListener
    var callback: Callback?
    private var timeManager: VideoPresentationTimeManager
    init(host: NWEndpoint.Host, port: NWEndpoint.Port, timebase: CMTimebase) {
        timeManager = .init(timebase: timebase)
        let parameters = NWParameters.udp
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: "0.0.0.0", port: port)
        listen = try! NWListener(using: parameters)
        
        listen.newConnectionHandler = { connection in
            
            connection.start(queue: self.queue)
            self.scheduleReciveMessage(connection: connection)
            
        }
        listen.start(queue: queue)
    }
    
    func scheduleReciveMessage(connection: NWConnection) {

        connection.receiveMessage { [weak self] (data, context, isComplete, error) in
            guard let self = self else { return }
            defer {
                self.scheduleReciveMessage(connection: connection)
            }
            guard isComplete else {
                print("did recieve incomplete message")
                return
            }
            if let error = error {
                print(error)
                return
            }
            guard let data = data else {
                print("recive message is complete and no error but also no data")
                return
            }
            self.didReciveData(data)
        }
    }
    private func didReciveData(_ data: Data) {
        do {
            try parse(data)
        } catch {
            print(error)
        }
    }
    private var h264Parser = H264.NALNonInterleavedPacketParser<Data>()
    var prevSequenceNumber: UInt16?
    private func parse(_ data: Data) throws {
        var reader = BinaryReader(bytes: data)
        let header = try RTPHeader(from: &reader)
        defer { prevSequenceNumber = header.sequenceNumber }
        if let prevSequenceNumber = prevSequenceNumber,
        prevSequenceNumber >= header.sequenceNumber && prevSequenceNumber != UInt16.max {
            print("packets in wrong order prevSequenceNumber: \(prevSequenceNumber) current: \(header.sequenceNumber)")
        }
        if let prevSequenceNumber = prevSequenceNumber,
            abs(Int(header.sequenceNumber) - Int(prevSequenceNumber)) != 1 {
            print("packet lost prevSequenceNumber: \(prevSequenceNumber) current: \(header.sequenceNumber)")
        }
        let nalUnits = try h264Parser.readPackage(from: &reader)
        if !nalUnits.isEmpty {
            didReciveNALUnits(nalUnits, header: header)
        }
    }
    
    private var sequenceParameterSet: H264.NALUnit<Data>? {
        didSet {
            if oldValue != sequenceParameterSet {
                formatDescription = nil
            }
        }
    }
    private var pictureParameterSet: H264.NALUnit<Data>? {
        didSet {
            if oldValue != pictureParameterSet {
                formatDescription = nil
            }
        }
    }
    private var formatDescription: CMVideoFormatDescription?
    private var decoder: VideoDecoder?
    
    private func didReciveNALUnits(_ nalus: [H264.NALUnit<Data>], header: RTPHeader) {
        for nalu in nalus {
            self.didReciveNALUnit(nalu, header: header)
        }
        if formatDescription == nil,
            let sequenceParameterSet = self.sequenceParameterSet,
            let pictureParameterSet = self.pictureParameterSet {
            do {
                let formatDescription = try CMVideoFormatDescriptionCreateForH264From(
                    sequenceParameterSet: sequenceParameterSet,
                    pictureParameterSet: pictureParameterSet
                )
                self.formatDescription = formatDescription
                if let newFormatDescription = formatDescription {
                    if let decoder = decoder {
                        if !decoder.canAcceptFormatDescription(newFormatDescription) {
                            self.decoder = try VideoDecoder(formatDescription: newFormatDescription)
                        }
                    } else {
                        self.decoder = try VideoDecoder(formatDescription: newFormatDescription)
                    }
                }
            } catch {
                print(error)
            }
        }
        
        
        for vclNalu in nalus.filter({ $0.header.type.isVideoCodingLayer }) {
            didReciveVCLNALU(vclNalu, header: header)
        }
    }
    private func didReciveNALUnit(_ nalu: H264.NALUnit<Data>, header: RTPHeader) {
        if nalu.header.type == .sequenceParameterSet {
            sequenceParameterSet = nalu
            formatDescription = nil
        }
        if nalu.header.type == .pictureParameterSet {
            pictureParameterSet = nalu
            formatDescription = nil
        }
    }
    private func didReciveVCLNALU(_ nalu: H264.NALUnit<Data>, header: RTPHeader) {
        guard let formatDescription = formatDescription else {
            print("did recieve VCL NALU of type \(nalu.header.type) before formatDescription is ready")
            return
        }
        let presentationTime = timeManager.getPresentationTime(for: Int64(header.timestamp))
        do {
            let buffer = try nalu.sampleBuffer(formatDescription: formatDescription, time: presentationTime, duration: .invalid)
            if let callback = callback {
                callback(buffer)
            } else {
                try self.decoder?.decodeFrame(sampleBuffer: buffer, flags: [._1xRealTimePlayback, ._EnableAsynchronousDecompression])
            }
        } catch {
            print(error)
        }
    }
}

import CoreMedia

struct OSStatusError: Error {
    var osStatus: OSStatus
    var description: String = "none"
}
func CMVideoFormatDescriptionCreateForH264From(sequenceParameterSet: H264.NALUnit<Data>, pictureParameterSet: H264.NALUnit<Data>) throws -> CMVideoFormatDescription? {
    try sequenceParameterSet.bytes.withUnsafeBytes { (sequenceParameterPointer: UnsafeRawBufferPointer) in
        try pictureParameterSet.bytes.withUnsafeBytes { (pictureParameterPointers: UnsafeRawBufferPointer) in
            let parameterBuffers = [
                sequenceParameterPointer,
                pictureParameterPointers,
            ]
            let parameters = parameterBuffers.map({ $0.baseAddress!.assumingMemoryBound(to: UInt8.self) })
            let paramterSizes = parameterBuffers.map(\.count)
            var formatDescription: CMFormatDescription?

            let status = CMVideoFormatDescriptionCreateFromH264ParameterSets(
                allocator: nil,
                parameterSetCount: parameters.count,
                parameterSetPointers: parameters,
                parameterSetSizes: paramterSizes,
                nalUnitHeaderLength: 4,
                formatDescriptionOut: &formatDescription)
            guard status == kOSReturnSuccess, let unwrapedFormatDescription = formatDescription else {
                throw OSStatusError(osStatus: status)
            }
            return unwrapedFormatDescription
        }
    }
}

extension BinaryFloatingPoint {
    @inlinable
    public func interpolatedValue(to end: Self, at position: Double) -> Self {
        let start = self
        return (end - start) * Self(position) + start
    }
}

struct VideoPresentationTimeManager {
    static let rtpClockRate: Int32 = 90_000
    var timescale: Int32
    var initalBufferTime: CMTime
    var bufferDelay: CMTime?
    var timebase: CMTimebase
    init(initalBufferTime: CMTime, timescale: Int32 = VideoPresentationTimeManager.rtpClockRate, timebase: CMTimebase) {
        self.initalBufferTime = initalBufferTime
        self.timescale = timescale
        self.timebase = timebase
    }
    init(
        innitalBufferTimeInSeconds: TimeInterval = 0,//6ms
        timescale: Int32 = VideoPresentationTimeManager.rtpClockRate,
        timebase: CMTimebase
    ) {
        self.init(initalBufferTime: CMTime(seconds: innitalBufferTimeInSeconds, preferredTimescale: timescale), timescale: timescale, timebase: timebase)
    }
    private func makeTime(from timestamp: Int64) -> CMTime {
        CMTime(value: timestamp, timescale: timescale)
    }
    private func getDelay() -> CMTime {
        bufferDelay ?? initalBufferTime
    }
    var remoteStartTime: CMTime?
    private mutating func getRemoteOffset(for time: CMTime) -> CMTime {
        guard let firstTimestamp = remoteStartTime else {
            self.resetRemoteStart(to: time)
            return .zero
        }
        return time - firstTimestamp
    }
    var localStartTime: CMTime?
    var prevOffset: CMTime?
    private mutating func resetRemoteStart(to time: CMTime) {
        self.remoteStartTime = time
        self.localStartTime = nil
    }
    mutating func getPresentationTime(for timestamp: Int64) -> CMTime {
        let time = makeTime(from: timestamp)
        var timeOffset = getRemoteOffset(for: time)
        defer { prevOffset = timeOffset }
        // reset offset if needed
        if let prevOffset = prevOffset {
            let difference = abs(timeOffset.seconds - prevOffset.seconds)
            if difference > 1 {
                resetRemoteStart(to: time)
                timeOffset = .zero
            }
        }
        let localStartTime: CMTime = {
            guard let localStartTime = self.localStartTime else {
                let now = timebase.time.convertScale(timescale, method: .default)
                self.localStartTime = now
                return now
            }
            return localStartTime
        }()
        let localTimestamp = localStartTime + timeOffset
        let absDrif = (localTimestamp + getDelay() - timebase.time).seconds
        
        //print("drift", absDrif * 1000, "ms")
        let currentDelay = getDelay().seconds
        //print("currentDelay:", currentDelay * 1000, "ms")
        let destinationDelay = (timebase.time - localTimestamp).seconds + 0.016
        let newDelay = currentDelay.interpolatedValue(to: destinationDelay, at: 0.05)
        
        
        bufferDelay = CMTime(seconds: newDelay, preferredTimescale: timescale)
        return localTimestamp + getDelay()
        //return timebase.time
    }
}

private func freeBlock(_ refCon: UnsafeMutableRawPointer?, doomedMemoryBlock: UnsafeMutableRawPointer, sizeInBytes: Int) -> Void {
    let unmanagedData = Unmanaged<NSData>.fromOpaque(refCon!)
    unmanagedData.release()
}

public extension DispatchData {
    func toCMBlockBuffer() throws -> CMBlockBuffer {
        return try self.withUnsafeBytes {
            (pointer: UnsafePointer<UInt8>) -> CMBlockBuffer in
            
            let data = NSMutableData(bytes: pointer, length: count)
            
            var source = CMBlockBufferCustomBlockSource()
            source.refCon = Unmanaged.passRetained(data).toOpaque()
            source.FreeBlock = freeBlock
            
            
            var blockBuffer: CMBlockBuffer?
            
            let result = CMBlockBufferCreateWithMemoryBlock(
                allocator: kCFAllocatorDefault,        // structureAllocator
                memoryBlock: data.mutableBytes,          // memoryBlock
                blockLength: data.length,                // blockLength
                blockAllocator: kCFAllocatorNull,           // blockAllocator
                customBlockSource: &source,                    // customBlockSource
                offsetToData: 0,                          // offsetToData
                dataLength: data.length,                // dataLength
                flags: 0,                          // flags
                blockBufferOut: &blockBuffer)               // newBBufOut
            if OSStatus(result) != kCMBlockBufferNoErr {
                throw OSStatusError(osStatus: result, description: "CMBlockBufferCreateWithMemoryBlock")
            }
            
            assert(CMBlockBufferGetDataLength(blockBuffer!) == data.length)
            return blockBuffer!
        }
    }
}

fileprivate let h264ClockRate: Int32 = 90_000

enum SampleBufferError: Error {
    case canNotCreateBufferFromZeroNalus
    case canNotCreateBufferFromNalusOfDifferentHeaders
}

extension H264.NALUnit where D == Data {
    func sampleBuffer(formatDescription: CMFormatDescription, time: CMTime, duration: CMTime = .invalid) throws -> CMSampleBuffer {
        // Prepend the size of the data to the data as a 32-bit network endian uint. (keyword: "elementary stream")
        let offset = 0
        let size = UInt32((self.payload.count - offset) + 1)
        
        let prefix = size.toNetworkByteOrder.data + Data([self.header.byte])
        var data = prefix.withUnsafeBytes{ (header) in
            DispatchData(bytes: header)
        }
        assert(data.count == 5)
        self.payload.withUnsafeBytes { (payload) in
            let payload = UnsafeRawBufferPointer(start: payload.baseAddress!.advanced(by: offset), count: payload.count - offset)
            data.append(payload)
        }
        assert(data.count == size + 4)
        
        let blockBuffer = try data.toCMBlockBuffer()
        
        // So what about STAP???? From CMSampleBufferCreate "Behavior is undefined if samples in a CMSampleBuffer (or even in multiple buffers in the same stream) have the same presentationTimeStamp"
        
        // Computer the duration and time
        
        
        
        // Inputs to CMSampleBufferCreate
        let timingInfo: [CMSampleTimingInfo] = [CMSampleTimingInfo(duration: duration, presentationTimeStamp: time, decodeTimeStamp: .invalid)]
        let sampleSizes: [Int] = [CMBlockBufferGetDataLength(blockBuffer)]
        
        // Outputs from CMSampleBufferCreate
        var sampleBuffer: CMSampleBuffer?
        
        let result = CMSampleBufferCreate(
            allocator: kCFAllocatorDefault,            // allocator: CFAllocator?,
            dataBuffer: blockBuffer,                    // dataBuffer: CMBlockBuffer?,
            dataReady: true,                           // dataReady: Boolean,
            makeDataReadyCallback: nil,                            // makeDataReadyCallback: CMSampleBufferMakeDataReadyCallback?,
            refcon: nil,                            // makeDataReadyRefcon: UnsafeMutablePointer<Void>,
            formatDescription: formatDescription,              // formatDescription: CMFormatDescription?,
            sampleCount: 1,                              // numSamples: CMItemCount,
            sampleTimingEntryCount: timingInfo.count,               // numSampleTimingEntries: CMItemCount,
            sampleTimingArray: timingInfo,                     // sampleTimingArray: UnsafePointer<CMSampleTimingInfo>,
            sampleSizeEntryCount: sampleSizes.count,              // numSampleSizeEntries: CMItemCount,
            sampleSizeArray: sampleSizes,                    // sampleSizeArray: UnsafePointer<Int>,
            sampleBufferOut: &sampleBuffer                   // sBufOut: UnsafeMutablePointer<Unmanaged<CMSampleBuffer>?>
        )
        
        guard result == kOSReturnSuccess, let unwrapedSampleBuffer = sampleBuffer else {
            throw OSStatusError(osStatus: result, description: "CMSampleBufferCreate() failed")
        }
        
        //    if let attachmentsOfSampleBuffers = CMSampleBufferGetSampleAttachmentsArray(unwrapedSampleBuffer, createIfNecessary: true) as? [NSMutableDictionary] {
        //        for attachments in attachmentsOfSampleBuffers {
        //            attachments[kCMSampleAttachmentKey_DisplayImmediately] = NSNumber(value: true)
        //        }
        //    }
        
        return unwrapedSampleBuffer
    }
}
