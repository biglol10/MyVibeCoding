import Darwin
import Foundation

public struct NetworkSampler {
    private var previousByName: [String: NetworkCounter] = [:]

    public init() {}

    public mutating func sample() throws -> NetworkSnapshot {
        let now = Date()
        let counters = try Self.readInterfaceCounters(sampledAt: now)
        guard let counter = Self.selectedCounter(from: counters, previousByName: previousByName) else {
            throw SamplerError.unavailable("No active network interface")
        }

        let previousCounter = previousByName[counter.name]
        previousByName = Dictionary(uniqueKeysWithValues: counters.map { ($0.name, $0) })
        let speeds = Self.speeds(previous: previousCounter, current: counter)

        return NetworkSnapshot(
            interfaceName: counter.name,
            downloadBytesPerSecond: speeds.downloadBytesPerSecond,
            uploadBytesPerSecond: speeds.uploadBytesPerSecond,
            receivedBytes: counter.receivedBytes,
            sentBytes: counter.sentBytes,
            isConnected: true,
            sampledAt: now
        )
    }

    static func speeds(previous: NetworkCounter?, current: NetworkCounter) -> NetworkSpeeds {
        guard let previous, previous.name == current.name else {
            return NetworkSpeeds(downloadBytesPerSecond: 0, uploadBytesPerSecond: 0)
        }

        let elapsed = max(0.001, current.sampledAt.timeIntervalSince(previous.sampledAt))
        let downloadSpeed = current.receivedBytes >= previous.receivedBytes
            ? UInt64(Double(current.receivedBytes - previous.receivedBytes) / elapsed)
            : 0
        let uploadSpeed = current.sentBytes >= previous.sentBytes
            ? UInt64(Double(current.sentBytes - previous.sentBytes) / elapsed)
            : 0
        return NetworkSpeeds(downloadBytesPerSecond: downloadSpeed, uploadBytesPerSecond: uploadSpeed)
    }

    static func selectedCounter(from counters: [NetworkCounter], previousByName: [String: NetworkCounter]) -> NetworkCounter? {
        guard counters.isEmpty == false else { return nil }

        if previousByName.isEmpty == false,
           let active = counters.max(by: { lhs, rhs in
               activityDelta(for: lhs, previousByName: previousByName) < activityDelta(for: rhs, previousByName: previousByName)
           }),
           activityDelta(for: active, previousByName: previousByName) > 0 {
            return active
        }

        return counters.max(by: { lhs, rhs in
            lhs.receivedBytes + lhs.sentBytes < rhs.receivedBytes + rhs.sentBytes
        })
    }

    private static func activityDelta(for counter: NetworkCounter, previousByName: [String: NetworkCounter]) -> UInt64 {
        guard let previous = previousByName[counter.name] else { return 0 }
        let receivedDelta = counter.receivedBytes >= previous.receivedBytes ? counter.receivedBytes - previous.receivedBytes : 0
        let sentDelta = counter.sentBytes >= previous.sentBytes ? counter.sentBytes - previous.sentBytes : 0
        return receivedDelta + sentDelta
    }

    private static func readInterfaceCounters(sampledAt: Date) throws -> [NetworkCounter] {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var length = 0
        guard sysctl(&mib, u_int(mib.count), nil, &length, nil, 0) == 0 else {
            throw SamplerError.systemCallFailed("sysctl NET_RT_IFLIST2 size")
        }

        var buffer = [UInt8](repeating: 0, count: length)
        guard sysctl(&mib, u_int(mib.count), &buffer, &length, nil, 0) == 0 else {
            throw SamplerError.systemCallFailed("sysctl NET_RT_IFLIST2")
        }

        return buffer.withUnsafeBytes { rawBuffer in
            var counters: [NetworkCounter] = []
            var offset = 0
            while offset + MemoryLayout<if_msghdr>.size <= length {
                let header = rawBuffer.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)
                let messageLength = Int(header.ifm_msglen)
                guard messageLength > 0 else { break }

                if Int32(header.ifm_type) == RTM_IFINFO2,
                   offset + MemoryLayout<if_msghdr2>.size <= length {
                    let message = rawBuffer.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                    if let counter = counter(from: message, sampledAt: sampledAt) {
                        counters.append(counter)
                    }
                }

                offset += messageLength
            }
            return counters
        }
    }

    private static func counter(from message: if_msghdr2, sampledAt: Date) -> NetworkCounter? {
        let flags = UInt32(bitPattern: message.ifm_flags)
        guard (flags & UInt32(IFF_UP)) != 0,
              (flags & UInt32(IFF_LOOPBACK)) == 0,
              let name = interfaceName(for: message.ifm_index)
        else {
            return nil
        }

        return NetworkCounter(
            name: name,
            receivedBytes: message.ifm_data.ifi_ibytes,
            sentBytes: message.ifm_data.ifi_obytes,
            sampledAt: sampledAt
        )
    }

    private static func interfaceName(for index: UInt16) -> String? {
        var name = [CChar](repeating: 0, count: Int(IF_NAMESIZE))
        return name.withUnsafeMutableBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress,
                  if_indextoname(UInt32(index), baseAddress) != nil
            else {
                return nil
            }
            return String(cString: baseAddress)
        }
    }
}

struct NetworkCounter: Equatable, Sendable {
    let name: String
    let receivedBytes: UInt64
    let sentBytes: UInt64
    let sampledAt: Date
}

struct NetworkSpeeds: Equatable, Sendable {
    let downloadBytesPerSecond: UInt64
    let uploadBytesPerSecond: UInt64
}
