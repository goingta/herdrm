import Darwin
import Foundation
import Network

/// Negotiates one unauthenticated HTTP CONNECT tunnel on an owned, nonblocking
/// TCP socket. The caller retains ownership and closes it on every failure.
enum HTTPConnect {
    static func validateTarget(_ target: SSHEndpoint) throws {
        guard target.port > 0, !target.host.isEmpty,
              !target.host.contains(where: { $0.isWhitespace || $0.isNewline }),
              !target.host.unicodeScalars.contains(where: { $0.value < 33 || $0.value == 127 }),
              !target.host.contains(where: { "/@?#[]".contains($0) }),
              (!target.host.contains(":") || IPv6Address(target.host) != nil) else {
            throw SSHError.invalidEndpoint
        }
    }

    static func negotiate(descriptor: Int32, target: SSHEndpoint, until deadline: ContinuousClock.Instant) async throws {
        try validateTarget(target)
        let authority = target.host.contains(":") ? "[\(target.host)]:\(target.port)" : "\(target.host):\(target.port)"
        var noSignal: Int32 = 1
        guard setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size)) == 0 else {
            throw SSHError.connectionFailed
        }
        let request = Data("CONNECT \(authority) HTTP/1.1\r\nHost: \(authority)\r\n\r\n".utf8)
        var offset = 0
        while offset < request.count {
            try checkProgress(until: deadline)
            let count = request.withUnsafeBytes { Darwin.write(descriptor, $0.baseAddress!.advanced(by: offset), $0.count - offset) }
            if count > 0 { offset += count }
            else if count < 0, errno == EINTR { continue }
            else if count < 0, errno == EAGAIN || errno == EWOULDBLOCK {
                try await SocketReadiness.wait(descriptor: descriptor, directions: .write, until: deadline)
            } else { throw SSHError.connectionFailed }
        }

        // Stop exactly at CRLFCRLF. A gateway may send its HTTP response and
        // the server's first SSH bytes in one packet; libssh2 must receive all
        // of those SSH bytes. Bounded one-byte reads avoid buffering a banner.
        var header = Data()
        while header.count < 16_384 {
            try checkProgress(until: deadline)
            var byte: UInt8 = 0
            let count = Darwin.read(descriptor, &byte, 1)
            if count == 1 {
                header.append(byte)
                if header.suffix(4) == Data([13, 10, 13, 10]) {
                    try validateResponse(header)
                    return
                }
            } else if count < 0, errno == EINTR { continue }
            else if count < 0, errno == EAGAIN || errno == EWOULDBLOCK {
                try await SocketReadiness.wait(descriptor: descriptor, directions: .read, until: deadline)
            } else { throw SSHError.invalidHTTPConnectResponse }
        }
        throw SSHError.invalidHTTPConnectResponse
    }

    private static func validateResponse(_ data: Data) throws {
        guard let response = String(data: data, encoding: .ascii) else { throw SSHError.invalidHTTPConnectResponse }
        let lines = response.components(separatedBy: "\r\n")
        guard lines.allSatisfy({ line in
            line.utf8.allSatisfy { $0 == 9 || (32...126).contains($0) }
        }) else { throw SSHError.invalidHTTPConnectResponse }
        let statusLine = lines[0].split(separator: " ", omittingEmptySubsequences: false)
        guard statusLine.count >= 2, ["HTTP/1.0", "HTTP/1.1"].contains(String(statusLine[0])),
              statusLine[1].count == 3, statusLine[1].allSatisfy(\.isNumber),
              let status = Int(statusLine[1]), (100...599).contains(status),
              lines.dropFirst().dropLast(2).allSatisfy({ line in
                  guard let colon = line.firstIndex(of: ":"), colon != line.startIndex else { return false }
                  return line[..<colon].utf8.allSatisfy { byte in
                      (48...57).contains(byte) || (65...90).contains(byte) || (97...122).contains(byte)
                          || Array("!#$%&'*+-.^_`|~".utf8).contains(byte)
                  }
              }) else { throw SSHError.invalidHTTPConnectResponse }
        guard (200...299).contains(status) else { throw SSHError.httpConnectRejected(status: status) }
    }

    private static func checkProgress(until deadline: ContinuousClock.Instant) throws {
        if Task.isCancelled { throw SSHError.cancelled }
        if .now >= deadline { throw SSHError.timedOut }
    }
}
