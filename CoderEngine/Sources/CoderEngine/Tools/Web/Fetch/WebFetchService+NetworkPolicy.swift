import Foundation

extension WebFetchService {
    func isBlockedHost(_ host: String) -> Bool {
        if host == "localhost" || host == "::1" || host == "0.0.0.0" {
            return true
        }
        guard let ipv4 = parseIPv4(host) else {
            return false
        }
        let a = ipv4.0
        let b = ipv4.1

        if a == 10 { return true }                    // 10.0.0.0/8
        if a == 127 { return true }                   // 127.0.0.0/8 (loopback)
        if a == 192 && b == 168 { return true }      // 192.168.0.0/16
        if a == 172 && (16...31).contains(b) { return true }  // 172.16.0.0/12
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
}
