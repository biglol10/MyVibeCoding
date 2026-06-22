import Darwin
import Foundation

public struct NetworkSampler {
    private var previous: NetworkCounter?

    public init() {}

    public mutating func sample() throws -> NetworkSnapshot {
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0, let first = interfaces else {
            throw SamplerError.systemCallFailed("getifaddrs")
        }
        defer { freeifaddrs(first) }

        let now = Date()
        var bestCounter: NetworkCounter?
        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        while let current = pointer {
            defer { pointer = current.pointee.ifa_next }
            guard let address = current.pointee.ifa_addr,
                  Int32(address.pointee.sa_family) == AF_LINK,
                  let data = current.pointee.ifa_data
            else {
                continue
            }

            let flags = current.pointee.ifa_flags
            guard (flags & UInt32(IFF_UP)) != 0,
                  (flags & UInt32(IFF_LOOPBACK)) == 0
            else {
                continue
            }

            let name = String(cString: current.pointee.ifa_name)
            let ifData = data.assumingMemoryBound(to: if_data.self).pointee
            let counter = NetworkCounter(
                name: name,
                receivedBytes: UInt64(ifData.ifi_ibytes),
                sentBytes: UInt64(ifData.ifi_obytes),
                sampledAt: now
            )

            if let existing = bestCounter {
                if counter.receivedBytes + counter.sentBytes > existing.receivedBytes + existing.sentBytes {
                    bestCounter = counter
                }
            } else {
                bestCounter = counter
            }
        }

        guard let counter = bestCounter else {
            throw SamplerError.unavailable("No active network interface")
        }

        let previousCounter = previous
        previous = counter

        let downloadSpeed: UInt64
        let uploadSpeed: UInt64
        if let previousCounter, previousCounter.name == counter.name {
            let elapsed = max(0.001, counter.sampledAt.timeIntervalSince(previousCounter.sampledAt))
            downloadSpeed = counter.receivedBytes > previousCounter.receivedBytes
                ? UInt64(Double(counter.receivedBytes - previousCounter.receivedBytes) / elapsed)
                : 0
            uploadSpeed = counter.sentBytes > previousCounter.sentBytes
                ? UInt64(Double(counter.sentBytes - previousCounter.sentBytes) / elapsed)
                : 0
        } else {
            downloadSpeed = 0
            uploadSpeed = 0
        }

        return NetworkSnapshot(
            interfaceName: counter.name,
            downloadBytesPerSecond: downloadSpeed,
            uploadBytesPerSecond: uploadSpeed,
            receivedBytes: counter.receivedBytes,
            sentBytes: counter.sentBytes,
            isConnected: true,
            sampledAt: now
        )
    }
}

private struct NetworkCounter {
    let name: String
    let receivedBytes: UInt64
    let sentBytes: UInt64
    let sampledAt: Date
}
