import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

extension WebFetchService {
    func isBlockedHostOrResolvedPrivate(_ host: String) -> Bool {
        if isBlockedHost(host) {
            return true
        }
        return resolvesToBlockedAddress(host)
    }

    func isBlockedHost(_ host: String) -> Bool {
        let normalizedHost = host
            .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            .split(separator: "%", maxSplits: 1, omittingEmptySubsequences: true)
            .first
            .map(String.init)?
            .lowercased() ?? host.lowercased()

        if normalizedHost == "localhost" || normalizedHost == "::1" || normalizedHost == "0.0.0.0" {
            return true
        }
        if normalizedHost.hasSuffix(".local") {
            return true
        }

        if let ipv4 = parseIPv4(normalizedHost) {
            return isBlockedIPv4(ipv4)
        }

        if let ipv6 = parseIPv6(normalizedHost) {
            return isBlockedIPv6(ipv6)
        }

        return false
    }

    private func isBlockedIPv4(_ ipv4: (Int, Int, Int, Int)) -> Bool {
        let a = ipv4.0
        let b = ipv4.1

        if a == 0 { return true }                           // 0.0.0.0/8
        if a == 10 { return true }                          // 10.0.0.0/8
        if a == 127 { return true }                         // 127.0.0.0/8 (loopback)
        if a == 169 && b == 254 { return true }            // 169.254.0.0/16 (link-local)
        if a == 172 && (16...31).contains(b) { return true } // 172.16.0.0/12
        if a == 192 && b == 168 { return true }            // 192.168.0.0/16
        if a == 100 && (64...127).contains(b) { return true } // 100.64.0.0/10 (CGNAT)
        if a == 198 && (b == 18 || b == 19) { return true } // 198.18.0.0/15 (benchmark)
        return false
    }

    private func isBlockedIPv6(_ bytes: [UInt8]) -> Bool {
        guard bytes.count == 16 else { return true }

        let isUnspecified = bytes.allSatisfy { $0 == 0 }
        if isUnspecified { return true }                    // ::/128

        let isLoopback = bytes[0..<15].allSatisfy { $0 == 0 } && bytes[15] == 1
        if isLoopback { return true }                       // ::1/128

        if (bytes[0] & 0xFE) == 0xFC { return true }        // fc00::/7 (ULA)
        if bytes[0] == 0xFE && (bytes[1] & 0xC0) == 0x80 { return true } // fe80::/10 (link-local)
        if bytes[0] == 0xFF { return true }                 // ff00::/8 (multicast)

        // ::ffff:a.b.c.d mapped IPv4
        let isIPv4Mapped = bytes[0..<10].allSatisfy { $0 == 0 } && bytes[10] == 0xFF && bytes[11] == 0xFF
        if isIPv4Mapped {
            let mappedIPv4 = (Int(bytes[12]), Int(bytes[13]), Int(bytes[14]), Int(bytes[15]))
            return isBlockedIPv4(mappedIPv4)
        }

        return false
    }

    private func resolvesToBlockedAddress(_ host: String) -> Bool {
        var hints = addrinfo(
            ai_flags: AI_ADDRCONFIG,
            ai_family: AF_UNSPEC,
            ai_socktype: Int32(SOCK_STREAM),
            ai_protocol: 0,
            ai_addrlen: 0,
            ai_canonname: nil,
            ai_addr: nil,
            ai_next: nil
        )

        var result: UnsafeMutablePointer<addrinfo>?
        let lookup = getaddrinfo(host, nil, &hints, &result)
        guard lookup == 0, let result else {
            return false
        }
        defer { freeaddrinfo(result) }

        var current: UnsafeMutablePointer<addrinfo>? = result
        while let info = current?.pointee {
            if info.ai_family == AF_INET,
               let addr = info.ai_addr?.withMemoryRebound(to: sockaddr_in.self, capacity: 1, { $0.pointee }) {
                let ip = UInt32(bigEndian: addr.sin_addr.s_addr)
                let a = Int((ip >> 24) & 0xFF)
                let b = Int((ip >> 16) & 0xFF)
                let c = Int((ip >> 8) & 0xFF)
                let d = Int(ip & 0xFF)
                if isBlockedIPv4((a, b, c, d)) {
                    return true
                }
            }

            if info.ai_family == AF_INET6,
               let addr6 = info.ai_addr?.withMemoryRebound(to: sockaddr_in6.self, capacity: 1, { $0.pointee }) {
                let bytes = withUnsafeBytes(of: addr6.sin6_addr) { Array($0) }
                if isBlockedIPv6(bytes) {
                    return true
                }
            }
            current = info.ai_next
        }

        return false
    }

    func parseIPv4(_ host: String) -> (Int, Int, Int, Int)? {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        let octets = parts.compactMap { Int($0) }
        guard octets.count == 4 else { return nil }
        guard octets.allSatisfy({ (0...255).contains($0) }) else { return nil }
        return (octets[0], octets[1], octets[2], octets[3])
    }

    private func parseIPv6(_ host: String) -> [UInt8]? {
        var storage = in6_addr()
        let result = host.withCString { inet_pton(AF_INET6, $0, &storage) }
        guard result == 1 else { return nil }
        return withUnsafeBytes(of: storage) { Array($0) }
    }
}
