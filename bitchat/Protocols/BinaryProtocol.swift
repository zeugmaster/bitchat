//
// BinaryProtocol.swift
// bitchat
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import Foundation
import os.log

extension Data {
    func trimmingNullBytes() -> Data {
        // Find the first null byte
        if let nullIndex = self.firstIndex(of: 0) {
            return self.prefix(nullIndex)
        }
        return self
    }
}

// Binary Protocol Format:
// Header (Fixed 13 bytes):
// - Version: 1 byte
// - Type: 1 byte  
// - TTL: 1 byte
// - Timestamp: 8 bytes (UInt64)
// - Flags: 1 byte (bit 0: hasRecipient, bit 1: hasSignature)
// - PayloadLength: 2 bytes (UInt16)
//
// Variable sections:
// - SenderID: 8 bytes (fixed)
// - RecipientID: 8 bytes (if hasRecipient flag set)
// - Payload: Variable length
// - Signature: 64 bytes (if hasSignature flag set)

struct BinaryProtocol {
    static let headerSize = 13
    static let senderIDSize = 8
    static let recipientIDSize = 8
    static let signatureSize = 64
    
    struct Flags {
        static let hasRecipient: UInt8 = 0x01
        static let hasSignature: UInt8 = 0x02
        static let isCompressed: UInt8 = 0x04
    }
    
    // Encode BitchatPacket to binary format
    static func encode(_ packet: BitchatPacket) -> Data? {
        var data = Data()
        
        SecurityLogger.log("🔵 PROTOCOL DEBUG: Encoding packet", 
                         category: SecurityLogger.noise, level: .debug)
        SecurityLogger.log("   Type: \(MessageType(rawValue: packet.type)?.description ?? "Unknown") (\(packet.type))", 
                         category: SecurityLogger.noise, level: .debug)
        SecurityLogger.log("   TTL: \(packet.ttl)", 
                         category: SecurityLogger.noise, level: .debug)
        SecurityLogger.log("   Payload size: \(packet.payload.count) bytes", 
                         category: SecurityLogger.noise, level: .debug)
        
        
        // Try to compress payload if beneficial
        var payload = packet.payload
        var originalPayloadSize: UInt16? = nil
        var isCompressed = false
        
        if CompressionUtil.shouldCompress(payload) {
            if let compressedPayload = CompressionUtil.compress(payload) {
                // Store original size for decompression (2 bytes after payload)
                originalPayloadSize = UInt16(payload.count)
                payload = compressedPayload
                isCompressed = true
                SecurityLogger.log("   ✅ Compression successful: \(packet.payload.count) → \(compressedPayload.count) bytes", 
                                 category: SecurityLogger.noise, level: .debug)
            } else {
                SecurityLogger.log("   ⚠️ Compression failed, using original payload", 
                                 category: SecurityLogger.noise, level: .debug)
            }
        } else {
            SecurityLogger.log("   ℹ️ Compression not beneficial for \(payload.count) bytes", 
                             category: SecurityLogger.noise, level: .debug)
        }
        
        // Header
        data.append(packet.version)
        data.append(packet.type)
        data.append(packet.ttl)
        
        // Timestamp (8 bytes, big-endian)
        for i in (0..<8).reversed() {
            data.append(UInt8((packet.timestamp >> (i * 8)) & 0xFF))
        }
        
        // Flags
        var flags: UInt8 = 0
        if packet.recipientID != nil {
            flags |= Flags.hasRecipient
        }
        if packet.signature != nil {
            flags |= Flags.hasSignature
        }
        if isCompressed {
            flags |= Flags.isCompressed
        }
        data.append(flags)
        
        // Payload length (2 bytes, big-endian) - includes original size if compressed
        let payloadDataSize = payload.count + (isCompressed ? 2 : 0)
        let payloadLength = UInt16(payloadDataSize)
        
        SecurityLogger.log("   Header size: 13 bytes, Payload: \(payloadLength) bytes", 
                         category: SecurityLogger.noise, level: .debug)
        
        
        data.append(UInt8((payloadLength >> 8) & 0xFF))
        data.append(UInt8(payloadLength & 0xFF))
        
        // SenderID (exactly 8 bytes)
        let senderBytes = packet.senderID.prefix(senderIDSize)
        data.append(senderBytes)
        if senderBytes.count < senderIDSize {
            data.append(Data(repeating: 0, count: senderIDSize - senderBytes.count))
        }
        
        // RecipientID (if present)
        if let recipientID = packet.recipientID {
            let recipientBytes = recipientID.prefix(recipientIDSize)
            data.append(recipientBytes)
            if recipientBytes.count < recipientIDSize {
                data.append(Data(repeating: 0, count: recipientIDSize - recipientBytes.count))
            }
        }
        
        // Payload (with original size prepended if compressed)
        if isCompressed, let originalSize = originalPayloadSize {
            // Prepend original size (2 bytes, big-endian)
            data.append(UInt8((originalSize >> 8) & 0xFF))
            data.append(UInt8(originalSize & 0xFF))
        }
        data.append(payload)
        
        // Signature (if present)
        if let signature = packet.signature {
            data.append(signature.prefix(signatureSize))
        }
        
        
        // Apply padding to standard block sizes for traffic analysis resistance
        let optimalSize = MessagePadding.optimalBlockSize(for: data.count)
        let paddedData = MessagePadding.pad(data, toSize: optimalSize)
        
        let totalSize = paddedData.count
        SecurityLogger.log("   Final encoded size: \(totalSize) bytes (padded from \(data.count) to \(optimalSize))", 
                         category: SecurityLogger.noise, level: .debug)
        
        // Debug log for fragment padding issues
        if data.count < 256 && paddedData.count != 256 && packet.type >= MessageType.fragmentStart.rawValue && packet.type <= MessageType.fragmentEnd.rawValue {
            SecurityLogger.log("   ⚠️ Fragment not padded to 256: data=\(data.count), padded=\(paddedData.count), optimal=\(optimalSize)", 
                             category: SecurityLogger.noise, level: .warning)
        }
        
        // Check if this will need fragmentation
        if totalSize > 512 {
            SecurityLogger.log("   ⚠️ Packet will require fragmentation (\(totalSize) > 512 bytes)", 
                             category: SecurityLogger.noise, level: .info)
        }
        
        return paddedData
    }
    
    // Decode binary data to BitchatPacket
    static func decode(_ data: Data) -> BitchatPacket? {
        SecurityLogger.log("🔷 PROTOCOL DEBUG: Decoding packet", 
                         category: SecurityLogger.noise, level: .debug)
        SecurityLogger.log("   Raw data size: \(data.count) bytes", 
                         category: SecurityLogger.noise, level: .debug)
        
        // Safety check for reasonable data size to prevent DoS
        guard data.count <= 128 * 1024 else { 
            SecurityLogger.log("   🔴 Packet too large: \(data.count) bytes (max 128KB)", 
                             category: SecurityLogger.noise, level: .error)
            return nil 
        } // Max 128KB total
        
        // Try to detect if data is padded or not
        // Padded data will have consistent padding bytes at the end
        let unpaddedData: Data
        if data.count > 512 {
            // Large packets might not be padded due to PKCS#7 limitation
            // Check if it looks like valid padding
            let lastByte = data[data.count - 1]
            if lastByte > 0 && lastByte <= 255 && data.count > Int(lastByte) {
                // Could be padding, but verify it's consistent
                var looksLikePadding = true
                if lastByte > 1 {
                    let paddingStart = data.count - Int(lastByte)
                    for i in paddingStart..<(data.count - 1) {
                        if data[i] != lastByte {
                            looksLikePadding = false
                            break
                        }
                    }
                }
                
                if looksLikePadding {
                    unpaddedData = MessagePadding.unpad(data)
                    SecurityLogger.log("   After unpadding: \(unpaddedData.count) bytes (removed \(data.count - unpaddedData.count) bytes)", 
                                     category: SecurityLogger.noise, level: .debug)
                } else {
                    // Not valid padding, use as-is
                    unpaddedData = data
                    SecurityLogger.log("   No valid padding detected, using raw data: \(data.count) bytes", 
                                     category: SecurityLogger.noise, level: .debug)
                }
            } else {
                // Can't be valid padding
                unpaddedData = data
                SecurityLogger.log("   Large packet without padding: \(data.count) bytes", 
                                 category: SecurityLogger.noise, level: .debug)
            }
        } else {
            // Small packets should always be padded to block size
            unpaddedData = MessagePadding.unpad(data)
            SecurityLogger.log("   After unpadding: \(unpaddedData.count) bytes", 
                             category: SecurityLogger.noise, level: .debug)
        }
        
        // Basic length check
        guard unpaddedData.count >= headerSize + senderIDSize else { 
            SecurityLogger.log("   🔴 Packet too small: \(unpaddedData.count) bytes (min \(headerSize + senderIDSize))", 
                             category: SecurityLogger.noise, level: .error)
            return nil 
        }
        
        var offset = 0
        
        // Header - with bounds checking for each field
        guard offset < unpaddedData.count else { return nil }
        let version = unpaddedData[offset]; offset += 1
        // Check if version is supported
        guard ProtocolVersion.isSupported(version) else { 
            SecurityLogger.log("   🔴 Unsupported protocol version: \(version)", 
                             category: SecurityLogger.noise, level: .error)
            return nil 
        }
        
        guard offset < unpaddedData.count else { return nil }
        let type = unpaddedData[offset]; offset += 1
        
        guard offset < unpaddedData.count else { return nil }
        let ttl = unpaddedData[offset]; offset += 1
        
        // Timestamp
        guard offset + 8 <= unpaddedData.count else { return nil }
        let timestampData = unpaddedData[offset..<offset+8]
        let timestamp = timestampData.reduce(0) { result, byte in
            (result << 8) | UInt64(byte)
        }
        offset += 8
        
        // Flags
        guard offset < unpaddedData.count else { return nil }
        let flags = unpaddedData[offset]; offset += 1
        let hasRecipient = (flags & Flags.hasRecipient) != 0
        let hasSignature = (flags & Flags.hasSignature) != 0
        let isCompressed = (flags & Flags.isCompressed) != 0
        
        // Payload length
        guard offset + 2 <= unpaddedData.count else { return nil }
        let payloadLengthData = unpaddedData[offset..<offset+2]
        let payloadLength = payloadLengthData.reduce(0) { result, byte in
            (result << 8) | UInt16(byte)
        }
        offset += 2
        
        // Sanity check for payload length to prevent DoS attacks
        guard payloadLength <= 32768 else { return nil } // Max 32KB payload (within UInt16 range)
        
        // Calculate expected total size
        var expectedSize = headerSize + senderIDSize + Int(payloadLength)
        if hasRecipient {
            expectedSize += recipientIDSize
        }
        if hasSignature {
            expectedSize += signatureSize
        }
        
        guard unpaddedData.count >= expectedSize else { 
            return nil 
        }
        
        // SenderID
        guard offset + senderIDSize <= unpaddedData.count else { return nil }
        let senderID = unpaddedData[offset..<offset+senderIDSize]
        offset += senderIDSize
        
        // RecipientID
        var recipientID: Data?
        if hasRecipient {
            guard offset + recipientIDSize <= unpaddedData.count else { return nil }
            recipientID = unpaddedData[offset..<offset+recipientIDSize]
            offset += recipientIDSize
        }
        
        // Payload
        let payload: Data
        if isCompressed {
            // First 2 bytes are original size
            guard Int(payloadLength) >= 2 else { return nil }
            guard offset + 2 <= unpaddedData.count else { return nil }
            let originalSizeData = unpaddedData[offset..<offset+2]
            let originalSize = Int(originalSizeData.reduce(0) { result, byte in
                (result << 8) | UInt16(byte)
            })
            offset += 2
            
            // Compressed payload
            let compressedLength = Int(payloadLength) - 2
            guard offset + compressedLength <= unpaddedData.count else { return nil }
            let compressedPayload = unpaddedData[offset..<offset+compressedLength]
            offset += compressedLength
            
            // Decompress
            guard let decompressedPayload = CompressionUtil.decompress(compressedPayload, originalSize: originalSize) else {
                return nil
            }
            payload = decompressedPayload
        } else {
            guard offset + Int(payloadLength) <= unpaddedData.count else { return nil }
            payload = unpaddedData[offset..<offset+Int(payloadLength)]
            offset += Int(payloadLength)
        }
        
        // Signature
        var signature: Data?
        if hasSignature {
            guard offset + signatureSize <= unpaddedData.count else { return nil }
            signature = unpaddedData[offset..<offset+signatureSize]
        }
        
        SecurityLogger.log("   ✅ Successfully decoded packet", 
                         category: SecurityLogger.noise, level: .debug)
        SecurityLogger.log("   Type: \(MessageType(rawValue: type)?.description ?? "Unknown") (\(type))", 
                         category: SecurityLogger.noise, level: .debug)
        SecurityLogger.log("   TTL: \(ttl)", 
                         category: SecurityLogger.noise, level: .debug)
        SecurityLogger.log("   Sender: \(senderID.hexEncodedString())", 
                         category: SecurityLogger.noise, level: .debug)
        SecurityLogger.log("   Has recipient: \(hasRecipient)", 
                         category: SecurityLogger.noise, level: .debug)
        SecurityLogger.log("   Payload size: \(payload.count) bytes", 
                         category: SecurityLogger.noise, level: .debug)
        SecurityLogger.log("   Compressed: \(isCompressed)", 
                         category: SecurityLogger.noise, level: .debug)
        
        return BitchatPacket(
            type: type,
            senderID: senderID,
            recipientID: recipientID,
            timestamp: timestamp,
            payload: payload,
            signature: signature,
            ttl: ttl
        )
    }
}

// Binary encoding for BitchatMessage
extension BitchatMessage {
    func toBinaryPayload() -> Data? {
        var data = Data()
        
        SecurityLogger.log("🟦 MESSAGE DEBUG: Encoding BitchatMessage to binary", 
                         category: SecurityLogger.noise, level: .debug)
        SecurityLogger.log("   ID: \(id)", 
                         category: SecurityLogger.noise, level: .debug)
        SecurityLogger.log("   Sender: \(sender)", 
                         category: SecurityLogger.noise, level: .debug)
        SecurityLogger.log("   Content length: \(content.count) chars", 
                         category: SecurityLogger.noise, level: .debug)
        SecurityLogger.log("   Private: \(isPrivate), Encrypted: \(isEncrypted)", 
                         category: SecurityLogger.noise, level: .debug)
        SecurityLogger.log("   Channel: \(channel ?? "none")", 
                         category: SecurityLogger.noise, level: .debug)
        
        // Message format:
        // - Flags: 1 byte (bit 0: isRelay, bit 1: isPrivate, bit 2: hasOriginalSender, bit 3: hasRecipientNickname, bit 4: hasSenderPeerID, bit 5: hasMentions, bit 6: hasChannel, bit 7: isEncrypted)
        // - Timestamp: 8 bytes (seconds since epoch)
        // - ID length: 1 byte
        // - ID: variable
        // - Sender length: 1 byte
        // - Sender: variable
        // - Content length: 2 bytes
        // - Content: variable (or encrypted content if isEncrypted)
        // Optional fields based on flags:
        // - Original sender length + data
        // - Recipient nickname length + data
        // - Sender peer ID length + data
        // - Mentions array
        // - Channel hashtag
        
        var flags: UInt8 = 0
        if isRelay { flags |= 0x01 }
        if isPrivate { flags |= 0x02 }
        if originalSender != nil { flags |= 0x04 }
        if recipientNickname != nil { flags |= 0x08 }
        if senderPeerID != nil { flags |= 0x10 }
        if mentions != nil && !mentions!.isEmpty { flags |= 0x20 }
        if channel != nil { flags |= 0x40 }
        if isEncrypted { flags |= 0x80 }
        
        data.append(flags)
        
        // Timestamp (in milliseconds)
        let timestampMillis = UInt64(timestamp.timeIntervalSince1970 * 1000)
        // Encode as 8 bytes, big-endian
        for i in (0..<8).reversed() {
            data.append(UInt8((timestampMillis >> (i * 8)) & 0xFF))
        }
        
        // ID
        if let idData = id.data(using: .utf8) {
            data.append(UInt8(min(idData.count, 255)))
            data.append(idData.prefix(255))
        } else {
            data.append(0)
        }
        
        // Sender
        if let senderData = sender.data(using: .utf8) {
            data.append(UInt8(min(senderData.count, 255)))
            data.append(senderData.prefix(255))
        } else {
            data.append(0)
        }
        
        // Content or encrypted content
        if isEncrypted, let encryptedContent = encryptedContent {
            let length = UInt16(min(encryptedContent.count, 65535))
            // Encode length as 2 bytes, big-endian
            data.append(UInt8((length >> 8) & 0xFF))
            data.append(UInt8(length & 0xFF))
            data.append(encryptedContent.prefix(Int(length)))
        } else if let contentData = content.data(using: .utf8) {
            let length = UInt16(min(contentData.count, 65535))
            // Encode length as 2 bytes, big-endian
            data.append(UInt8((length >> 8) & 0xFF))
            data.append(UInt8(length & 0xFF))
            data.append(contentData.prefix(Int(length)))
        } else {
            data.append(contentsOf: [0, 0])
        }
        
        // Optional fields
        if let originalSender = originalSender, let origData = originalSender.data(using: .utf8) {
            data.append(UInt8(min(origData.count, 255)))
            data.append(origData.prefix(255))
        }
        
        if let recipientNickname = recipientNickname, let recipData = recipientNickname.data(using: .utf8) {
            data.append(UInt8(min(recipData.count, 255)))
            data.append(recipData.prefix(255))
        }
        
        if let senderPeerID = senderPeerID, let peerData = senderPeerID.data(using: .utf8) {
            data.append(UInt8(min(peerData.count, 255)))
            data.append(peerData.prefix(255))
        }
        
        // Mentions array
        if let mentions = mentions {
            data.append(UInt8(min(mentions.count, 255))) // Number of mentions
            for mention in mentions.prefix(255) {
                if let mentionData = mention.data(using: .utf8) {
                    data.append(UInt8(min(mentionData.count, 255)))
                    data.append(mentionData.prefix(255))
                } else {
                    data.append(0)
                }
            }
        }
        
        // Channel hashtag
        if let channel = channel, let channelData = channel.data(using: .utf8) {
            data.append(UInt8(min(channelData.count, 255)))
            data.append(channelData.prefix(255))
        }
        
        SecurityLogger.log("   Encoded message size: \(data.count) bytes", 
                         category: SecurityLogger.noise, level: .debug)
        
        return data
    }
    
    static func fromBinaryPayload(_ data: Data) -> BitchatMessage? {
        // Create an immutable copy to prevent threading issues
        let dataCopy = Data(data)
        
        SecurityLogger.log("🟪 MESSAGE DEBUG: Decoding BitchatMessage from binary", 
                         category: SecurityLogger.noise, level: .debug)
        SecurityLogger.log("   Binary data size: \(data.count) bytes", 
                         category: SecurityLogger.noise, level: .debug)
        
        
        guard dataCopy.count >= 13 else { 
            return nil 
        }
        
        var offset = 0
        
        // Flags
        guard offset < dataCopy.count else { 
            return nil 
        }
        let flags = dataCopy[offset]; offset += 1
        let isRelay = (flags & 0x01) != 0
        let isPrivate = (flags & 0x02) != 0
        let hasOriginalSender = (flags & 0x04) != 0
        let hasRecipientNickname = (flags & 0x08) != 0
        let hasSenderPeerID = (flags & 0x10) != 0
        let hasMentions = (flags & 0x20) != 0
        let hasChannel = (flags & 0x40) != 0
        let isEncrypted = (flags & 0x80) != 0
        
        // Timestamp
        guard offset + 8 <= dataCopy.count else { 
            return nil 
        }
        let timestampData = dataCopy[offset..<offset+8]
        let timestampMillis = timestampData.reduce(0) { result, byte in
            (result << 8) | UInt64(byte)
        }
        offset += 8
        let timestamp = Date(timeIntervalSince1970: TimeInterval(timestampMillis) / 1000.0)
        
        // ID
        guard offset < dataCopy.count else { 
            return nil 
        }
        let idLength = Int(dataCopy[offset]); offset += 1
        guard offset + idLength <= dataCopy.count else { 
            return nil 
        }
        let id = String(data: dataCopy[offset..<offset+idLength], encoding: .utf8) ?? UUID().uuidString
        offset += idLength
        
        // Sender
        guard offset < dataCopy.count else { 
            return nil 
        }
        let senderLength = Int(dataCopy[offset]); offset += 1
        guard offset + senderLength <= dataCopy.count else { 
            return nil 
        }
        let sender = String(data: dataCopy[offset..<offset+senderLength], encoding: .utf8) ?? "unknown"
        offset += senderLength
        
        // Content
        guard offset + 2 <= dataCopy.count else { 
            return nil 
        }
        let contentLengthData = dataCopy[offset..<offset+2]
        let contentLength = Int(contentLengthData.reduce(0) { result, byte in
            (result << 8) | UInt16(byte)
        })
        offset += 2
        guard offset + contentLength <= dataCopy.count else { 
            return nil 
        }
        
        let content: String
        let encryptedContent: Data?
        
        if isEncrypted {
            // Content is encrypted, store as Data
            encryptedContent = dataCopy[offset..<offset+contentLength]
            content = ""  // Empty placeholder
        } else {
            // Normal string content
            content = String(data: dataCopy[offset..<offset+contentLength], encoding: .utf8) ?? ""
            encryptedContent = nil
        }
        offset += contentLength
        
        // Optional fields
        var originalSender: String?
        if hasOriginalSender && offset < dataCopy.count {
            let length = Int(dataCopy[offset]); offset += 1
            if offset + length <= dataCopy.count {
                originalSender = String(data: dataCopy[offset..<offset+length], encoding: .utf8)
                offset += length
            }
        }
        
        var recipientNickname: String?
        if hasRecipientNickname && offset < dataCopy.count {
            let length = Int(dataCopy[offset]); offset += 1
            if offset + length <= dataCopy.count {
                recipientNickname = String(data: dataCopy[offset..<offset+length], encoding: .utf8)
                offset += length
            }
        }
        
        var senderPeerID: String?
        if hasSenderPeerID && offset < dataCopy.count {
            let length = Int(dataCopy[offset]); offset += 1
            if offset + length <= dataCopy.count {
                senderPeerID = String(data: dataCopy[offset..<offset+length], encoding: .utf8)
                offset += length
            }
        }
        
        // Mentions array
        var mentions: [String]?
        if hasMentions && offset < dataCopy.count {
            let mentionCount = Int(dataCopy[offset]); offset += 1
            if mentionCount > 0 {
                mentions = []
                for _ in 0..<mentionCount {
                    if offset < dataCopy.count {
                        let length = Int(dataCopy[offset]); offset += 1
                        if offset + length <= dataCopy.count {
                            if let mention = String(data: dataCopy[offset..<offset+length], encoding: .utf8) {
                                mentions?.append(mention)
                            }
                            offset += length
                        }
                    }
                }
            }
        }
        
        // Channel
        var channel: String? = nil
        if hasChannel && offset < dataCopy.count {
            let length = Int(dataCopy[offset]); offset += 1
            if offset + length <= dataCopy.count {
                channel = String(data: dataCopy[offset..<offset+length], encoding: .utf8)
                offset += length
            }
        }
        
        let message = BitchatMessage(
            id: id,
            sender: sender,
            content: content,
            timestamp: timestamp,
            isRelay: isRelay,
            originalSender: originalSender,
            isPrivate: isPrivate,
            recipientNickname: recipientNickname,
            senderPeerID: senderPeerID,
            mentions: mentions,
            channel: channel,
            encryptedContent: encryptedContent,
            isEncrypted: isEncrypted
        )
        
        SecurityLogger.log("   ✅ Successfully decoded message", 
                         category: SecurityLogger.noise, level: .debug)
        SecurityLogger.log("   ID: \(id)", 
                         category: SecurityLogger.noise, level: .debug)
        SecurityLogger.log("   Sender: \(sender)", 
                         category: SecurityLogger.noise, level: .debug)
        SecurityLogger.log("   Private: \(isPrivate), Encrypted: \(isEncrypted)", 
                         category: SecurityLogger.noise, level: .debug)
        SecurityLogger.log("   Channel: \(channel ?? "none")", 
                         category: SecurityLogger.noise, level: .debug)
        
        return message
    }
}