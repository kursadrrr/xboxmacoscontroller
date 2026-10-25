import Foundation
import CryptoKit
import CommonCrypto
import Security
import Darwin

// MARK: - Binary Buffer Reader / Writer (Big-Endian SmartGlass Format)

struct SGWriter {
    private(set) var data = Data()

    mutating func writeUInt8(_ val: UInt8) {
        data.append(val)
    }

    mutating func writeUInt16(_ val: UInt16) {
        var be = val.bigEndian
        data.append(Data(bytes: &be, count: 2))
    }

    mutating func writeUInt32(_ val: UInt32) {
        var be = val.bigEndian
        data.append(Data(bytes: &be, count: 4))
    }

    mutating func writeInt32(_ val: Int32) {
        var be = val.bigEndian
        data.append(Data(bytes: &be, count: 4))
    }

    mutating func writeUInt64(_ val: UInt64) {
        var be = val.bigEndian
        data.append(Data(bytes: &be, count: 8))
    }

    mutating func writeBytes(_ bytes: Data) {
        data.append(bytes)
    }

    /// SGString: UInt16BE(utf8.count) + utf8 bytes + 0x00 terminator
    mutating func writeSGString(_ str: String) {
        let utf8 = Data(str.utf8)
        writeUInt16(UInt16(utf8.count))
        writeBytes(utf8)
        writeUInt8(0x00)
    }
}

struct SGReader {
    let data: Data
    private(set) var offset: Int = 0

    var remaining: Int {
        max(0, data.count - offset)
    }

    mutating func readUInt8() -> UInt8 {
        guard offset + 1 <= data.count else { return 0 }
        let v = data[data.startIndex + offset]
        offset += 1
        return v
    }

    mutating func readUInt16() -> UInt16 {
        guard offset + 2 <= data.count else { return 0 }
        let b0 = UInt16(data[data.startIndex + offset])
        let b1 = UInt16(data[data.startIndex + offset + 1])
        offset += 2
        return (b0 << 8) | b1
    }

    mutating func readUInt32() -> UInt32 {
        guard offset + 4 <= data.count else { return 0 }
        let b0 = UInt32(data[data.startIndex + offset])
        let b1 = UInt32(data[data.startIndex + offset + 1])
        let b2 = UInt32(data[data.startIndex + offset + 2])
        let b3 = UInt32(data[data.startIndex + offset + 3])
        offset += 4
        return (b0 << 24) | (b1 << 16) | (b2 << 8) | b3
    }

    mutating func readInt32() -> Int32 {
        Int32(bitPattern: readUInt32())
    }

    mutating func readUInt64() -> UInt64 {
        let hi = UInt64(readUInt32())
        let lo = UInt64(readUInt32())
        return (hi << 32) | lo
    }

    mutating func readBytes(_ count: Int? = nil) -> Data {
        let len = count ?? remaining
        guard len > 0, offset + len <= data.count else {
            let sub = data.subdata(in: (data.startIndex + min(offset, data.count))..<data.endIndex)
            offset = data.count
            return sub
        }
        let start = data.startIndex + offset
        let sub = data.subdata(in: start..<(start + len))
        offset += len
        return sub
    }

    mutating func readSGString() -> String {
        let len = Int(readUInt16())
        let strData = readBytes(len)
        _ = readUInt8() // NUL terminator
        return String(data: strData, encoding: .utf8) ?? ""
    }
}

// MARK: - SmartGlass Cryptography (ECDH P-256 + SHA-512 KDF + AES-128-CBC + HMAC-SHA256)

final class SGCrypto {
    private(set) var publicKey64 = Data()      // 64-byte X||Y uncompressed P-256 public key (without 0x04)
    private(set) var encryptionKey = Data()    // 16-byte AES-128 key (secret[0..<16])
    private(set) var baseIV = Data()           // 16-byte IV derivation key (secret[16..<32])
    private(set) var hashKey = Data()          // 32-byte HMAC-SHA256 key (secret[32..<64])

    var isLoaded: Bool {
        encryptionKey.count == 16 && baseIV.count == 16 && hashKey.count == 32
    }

    /// Parses the Xbox's DER X.509 certificate from discovery_response (0xDD01),
    /// extracts the Live ID (Subject CN) and P-256 public key, and performs ECDH + SHA-512 KDF.
    static func fromXboxCertificate(_ certDER: Data) -> (crypto: SGCrypto, liveId: String)? {
        guard let cert = SecCertificateCreateWithData(nil, certDER as CFData) else {
            return nil
        }
        let liveId = (SecCertificateCopySubjectSummary(cert) as String?) ?? ""
        guard let secKey = SecCertificateCopyKey(cert),
              let pubKeyCF = SecKeyCopyExternalRepresentation(secKey, nil) else {
            return nil
        }
        let consolePubKeyX963 = pubKeyCF as Data // 65 bytes: 0x04 || X(32B) || Y(32B)
        guard let consolePubKey = try? P256.KeyAgreement.PublicKey(x963Representation: consolePubKeyX963) else {
            return nil
        }

        let clientPrivKey = P256.KeyAgreement.PrivateKey()
        guard let sharedSecret = try? clientPrivKey.sharedSecretFromKeyAgreement(with: consolePubKey) else {
            return nil
        }

        let sharedSecretBytes = sharedSecret.withUnsafeBytes { Data($0) }
        let clientPubX963 = clientPrivKey.publicKey.x963Representation // 65 bytes (0x04 || X || Y)
        let clientPub64 = clientPubX963.dropFirst() // 64 bytes (X || Y)

        // KDF: SHA-512( d637f1aae2f0418c || sharedSecret || a8f81a574e228ab7 )
        let prefix = Data([0xd6, 0x37, 0xf1, 0xaa, 0xe2, 0xf0, 0x41, 0x8c])
        let suffix = Data([0xa8, 0xf8, 0x1a, 0x57, 0x4e, 0x22, 0x8a, 0xb7])
        var kdfInput = Data()
        kdfInput.append(prefix)
        kdfInput.append(sharedSecretBytes)
        kdfInput.append(suffix)

        let digest = Data(SHA512.hash(data: kdfInput)) // 64 bytes
        let crypto = SGCrypto()
        crypto.publicKey64 = Data(clientPub64)
        crypto.encryptionKey = digest.subdata(in: 0..<16)
        crypto.baseIV = digest.subdata(in: 16..<32)
        crypto.hashKey = digest.subdata(in: 32..<64)

        return (crypto, liveId)
    }

    /// AES-128-CBC without auto-padding (matches SGCrypto._encrypt / _decrypt in com.xboxcontroller.app)
    func aes128CBC(data: Data, key: Data, iv: Data = Data(count: 16), encrypt: Bool) -> Data {
        guard !data.isEmpty, key.count == kCCKeySizeAES128, iv.count == kCCBlockSizeAES128 else {
            return Data()
        }
        // If decrypting unaligned data, pad with zeros to 16-byte boundary
        var input = data
        if !encrypt && (input.count % 16 != 0) {
            let rem = 16 - (input.count % 16)
            input.append(Data(count: rem))
        }
        let outLength = input.count + kCCBlockSizeAES128
        var outBuffer = Data(count: outLength)
        var numBytesProcessed: size_t = 0

        let status = outBuffer.withUnsafeMutableBytes { outPtr in
            input.withUnsafeBytes { inPtr in
                key.withUnsafeBytes { keyPtr in
                    iv.withUnsafeBytes { ivPtr in
                        CCCrypt(
                            CCOperation(encrypt ? kCCEncrypt : kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES128),
                            CCOptions(0), // No automatic PKCS7 padding; handled explicitly per SmartGlass spec
                            keyPtr.baseAddress, kCCKeySizeAES128,
                            ivPtr.baseAddress,
                            inPtr.baseAddress, input.count,
                            outPtr.baseAddress, outLength,
                            &numBytesProcessed
                        )
                    }
                }
            }
        }
        guard status == kCCSuccess else { return Data() }
        return outBuffer.prefix(numBytesProcessed)
    }

    /// Generates per-packet IV for 0xD00D messages by encrypting the first 16 bytes of the header with baseIV
    func derivePacketIV(headerFirst16: Data) -> Data {
        aes128CBC(data: headerFirst16.prefix(16), key: baseIV, iv: Data(count: 16), encrypt: true)
    }

    /// HMAC-SHA256 signature (32 bytes)
    func sign(_ data: Data) -> Data {
        let symKey = SymmetricKey(data: hashKey)
        let mac = HMAC<SHA256>.authenticationCode(for: data, using: symKey)
        return Data(mac)
    }

    /// SmartGlass PKCS#7-style alignment padding: only adds padding when length % 16 > 0
    static func padTo16(_ payload: Data) -> Data {
        let rem = payload.count % 16
        guard rem > 0 else { return payload }
        let padVal = UInt8(16 - rem)
        var padded = payload
        padded.append(Data(repeating: padVal, count: Int(padVal)))
        return padded
    }
}

// MARK: - Gamepad & Media Bitmasks (Exact match with com.xboxcontroller.app)

enum GamepadButton: String, CaseIterable, Identifiable {
    case nexus = "nexus"
    case view = "view"
    case menu = "menu"
    case a = "a"
    case b = "b"
    case x = "x"
    case y = "y"
    case up = "up"
    case down = "down"
    case left = "left"
    case right = "right"
    case leftShoulder = "left_shoulder"
    case rightShoulder = "right_shoulder"

    var id: String { rawValue }

    var bitmask: UInt16 {
        switch self {
        case .nexus:         return 0x0002 // 2
        case .view:          return 0x0004 // 4
        case .menu:          return 0x0008 // 8
        case .a:             return 0x0010 // 16
        case .b:             return 0x0020 // 32
        case .x:             return 0x0040 // 64
        case .y:             return 0x0080 // 128
        case .up:            return 0x0100 // 256
        case .down:          return 0x0200 // 512
        case .left:          return 0x0400 // 1024
        case .right:         return 0x0800 // 2048
        case .leftShoulder:  return 0x1000 // 4096
        case .rightShoulder: return 0x2000 // 8192
        }
    }

    var label: String {
        switch self {
        case .nexus:         return "Xbox Home"
        case .view:          return "View"
        case .menu:          return "Menu"
        case .a:             return "A"
        case .b:             return "B"
        case .x:             return "X"
        case .y:             return "Y"
        case .up:            return "Yukarı"
        case .down:          return "Aşağı"
        case .left:          return "Sol"
        case .right:         return "Sağ"
        case .leftShoulder:  return "LB"
        case .rightShoulder: return "RB"
        }
    }
}

enum MediaCommand: String, CaseIterable, Identifiable {
    case play = "play"
    case pause = "pause"
    case playPause = "playpause"
    case stop = "stop"
    case record = "record"
    case nextTrack = "next_track"
    case prevTrack = "prev_track"
    case fastForward = "fast_forward"
    case rewind = "rewind"
    case channelUp = "channel_up"
    case channelDown = "channel_down"
    case back = "back"
    case view = "view"
    case menu = "menu"

    var id: String { rawValue }

    var code: UInt32 {
        switch self {
        case .play:        return 2
        case .pause:       return 4
        case .playPause:   return 8
        case .stop:        return 16
        case .record:      return 32
        case .nextTrack:   return 64
        case .prevTrack:   return 128
        case .fastForward: return 256
        case .rewind:      return 512
        case .channelUp:   return 1024
        case .channelDown: return 2048
        case .back:        return 4096
        case .view:        return 8192
        case .menu:        return 16384
        }
    }
}

// MARK: - Discovered / Saved Console Model

struct XboxConsoleDevice: Identifiable, Codable, Equatable {
    var id: String { ip }
    var name: String
    var ip: String
    var uuid: String
    var liveId: String
    var lastSeen: Date
}

// MARK: - SmartGlass Client Engine

@MainActor
final class SmartGlassClient: ObservableObject {
    enum ConnectionState: Equatable {
        case disconnected
        case scanning
        case connecting(String)
        case connected(XboxConsoleDevice)
        case error(String)
    }

    @Published var state: ConnectionState = .disconnected
    @Published var discoveredConsoles: [XboxConsoleDevice] = []
    @Published var savedConsoles: [XboxConsoleDevice] = []
    @Published var manualIP: String = ""
    @Published var hasActiveTextInput: Bool = false
    @Published var activeAppTitleId: UInt32 = 0
    @Published var activeMediaTitleId: UInt32 = 0
    @Published var activeAppAumId: String = ""
    @Published var activeAppDisplayName: String = "Xbox"
    @Published var isKodiActive: Bool = false
    @Published var statusLog: String = "Hazır — Xbox aramak için Tara'ya basın" {
        didSet {
            logDebug("STATUS: \(statusLog)")
        }
    }

    func logDebug(_ msg: String) {
        let line = "[\(ISO8601DateFormatter().string(from: Date()))] \(msg)\n"
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: "/tmp/xbox_toolbar.log"),
               let fh = try? FileHandle(forWritingTo: URL(fileURLWithPath: "/tmp/xbox_toolbar.log")) {
                fh.seekToEndOfFile()
                try? fh.write(contentsOf: data)
                try? fh.close()
            } else {
                try? data.write(to: URL(fileURLWithPath: "/tmp/xbox_toolbar.log"))
            }
        }
    }
    @Published var keyboardShortcutsEnabled: Bool = false
    @Published var iptvWatchdogEnabled: Bool = false
    @Published var iptvReloadMode: Int = 0 // 0: CH- -> CH+, 1: B -> A, 2: Stop -> Play
    @Published var dpadInputMode: Int = 0 // 0: D-Pad (+Kodi), 1: Sol Analog (+Kodi), 2: D-Pad + Sol Analog (+Kodi)

    // Protocol internal state
    private var sockFD: Int32 = -1
    private var readSource: DispatchSourceRead?
    private let socketQueue = DispatchQueue(label: "com.xboxiptv.smartglass.udp", qos: .userInteractive)
    private var keepaliveTimer: Timer?
    private var watchdogTimer: Timer?

    private var currentConsole: XboxConsoleDevice?
    private var currentCertDER: Data?
    private var crypto: SGCrypto?
    private var participantId: UInt32 = 0
    private var requestNum: UInt32 = 0
    private var lastReceivedRemoteSeqNum: UInt32 = 0
    private var isConnectRequestInFlight: Bool = false
    private var mediaRequestId: UInt64 = 1
    private var lastReceivedTime: Date = .distantPast
    private let kodiClientUid: UInt32 = UInt32(truncatingIfNeeded: Int(Date().timeIntervalSince1970))

    // Service channel IDs (8-byte target_channel_id assigned by Xbox)
    private var inputChannelId: Data?
    private var mediaChannelId: Data?
    private var textChannelId: Data?
    private var channelsRequested: Bool = false

    // SystemText session state
    private var textSessionId: UInt32 = 0
    private var currentTextVersion: UInt32 = 0

    private let savedConsolesKey = "com.xboxiptv.savedConsoles.v1"

    init() {
        loadSavedConsoles()
        setupSocket()
        if let first = savedConsoles.first {
            manualIP = first.ip
            Task {
                try? await Task.sleep(nanoseconds: 250_000_000)
                connect(to: first.ip)
            }
        } else {
            Task {
                try? await Task.sleep(nanoseconds: 250_000_000)
                discoverConsoles()
            }
        }
    }

    // MARK: - Persistence

    private func loadSavedConsoles() {
        guard let data = UserDefaults.standard.data(forKey: savedConsolesKey),
              let decoded = try? JSONDecoder().decode([XboxConsoleDevice].self, from: data) else {
            return
        }
        savedConsoles = decoded
        discoveredConsoles = decoded
    }

    private func saveConsoleToHistory(_ device: XboxConsoleDevice) {
        var list = savedConsoles.filter { $0.ip != device.ip }
        list.insert(device, at: 0)
        if list.count > 8 { list = Array(list.prefix(8)) }
        savedConsoles = list
        if let encoded = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(encoded, forKey: savedConsolesKey)
        }
    }

    func removeSavedConsole(_ device: XboxConsoleDevice) {
        savedConsoles.removeAll { $0.ip == device.ip }
        discoveredConsoles.removeAll { $0.ip == device.ip }
        if let encoded = try? JSONEncoder().encode(savedConsoles) {
            UserDefaults.standard.set(encoded, forKey: savedConsolesKey)
        }
    }

    // MARK: - POSIX Non-Blocking UDP Socket Setup

    private func setupSocket() {
        closeSocket()
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else {
            statusLog = "UDP soketi açılamadı"
            return
        }
        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &yes, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(fd, SOL_SOCKET, SO_REUSEPORT, &yes, socklen_t(MemoryLayout<Int32>.size))

        let flags = fcntl(fd, F_GETFL, 0)
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(0).bigEndian
        addr.sin_addr.s_addr = INADDR_ANY

        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if bindResult < 0 {
            Darwin.close(fd)
            statusLog = "UDP bind hatası"
            return
        }

        sockFD = fd
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: socketQueue)
        source.setEventHandler { [weak self] in
            self?.readIncomingDatagrams(fd: fd)
        }
        source.setCancelHandler {
            Darwin.close(fd)
        }
        source.resume()
        readSource = source
    }

    private func closeSocket() {
        readSource?.cancel()
        readSource = nil
        sockFD = -1
    }

    private nonisolated func readIncomingDatagrams(fd: Int32) {
        var buffer = [UInt8](repeating: 0, count: 65536)
        while true {
            var srcAddr = sockaddr_in()
            var addrLen = socklen_t(MemoryLayout<sockaddr_in>.size)
            let bytesRead = withUnsafeMutablePointer(to: &srcAddr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { addrPtr in
                    recvfrom(fd, &buffer, buffer.count, 0, addrPtr, &addrLen)
                }
            }
            if bytesRead <= 0 {
                break
            }
            let packet = Data(buffer[0..<bytesRead])
            var ipBuf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            var sinAddr = srcAddr.sin_addr
            inet_ntop(AF_INET, &sinAddr, &ipBuf, socklen_t(INET_ADDRSTRLEN))
            let senderIP = String(cString: ipBuf)

            Task { @MainActor [weak self] in
                self?.handleIncomingPacket(packet, from: senderIP)
            }
        }
    }

    private func sendUDP(_ data: Data, to ip: String, port: UInt16 = 5050) {
        guard sockFD >= 0 else { return }
        let fd = sockFD
        socketQueue.async {
            var dest = sockaddr_in()
            dest.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            dest.sin_family = sa_family_t(AF_INET)
            dest.sin_port = port.bigEndian
            guard inet_pton(AF_INET, ip, &dest.sin_addr) == 1 else { return }

            data.withUnsafeBytes { rawBuf in
                guard let base = rawBuf.baseAddress else { return }
                withUnsafePointer(to: &dest) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { addrPtr in
                        _ = sendto(fd, base, data.count, 0, addrPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
            }
        }
    }

    // MARK: - Local Network Interface Helper

    private func getLocalIPv4Prefixes() -> [String] {
        var prefixes: Set<String> = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return [] }
        defer { freeifaddrs(ifaddr) }

        var ptr: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while let current = ptr {
            let interface = current.pointee
            let family = interface.ifa_addr.pointee.sa_family
            if family == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                if name.hasPrefix("en") || name.hasPrefix("bridge") || name.hasPrefix("wlan") {
                    var addr = interface.ifa_addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr }
                    var buf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                    inet_ntop(AF_INET, &addr, &buf, socklen_t(INET_ADDRSTRLEN))
                    let ip = String(cString: buf)
                    let parts = ip.split(separator: ".")
                    if parts.count == 4 && parts[0] != "127" && parts[0] != "169" {
                        prefixes.insert("\(parts[0]).\(parts[1]).\(parts[2])")
                    }
                }
            }
            ptr = interface.ifa_next
        }
        return Array(prefixes)
    }

    // MARK: - 1. Discovery (0xDD00 -> 0xDD01)

    /// Exact 16-byte simple.discovery_request packet from com.xboxcontroller.app:
    /// dd 00 00 0a 00 00 00 00 00 00 00 03 00 00 00 02
    private func buildDiscoveryRequestPacket() -> Data {
        Data([
            0xDD, 0x00,             // Magic: simple.discovery_request
            0x00, 0x0A,             // Payload length: 10
            0x00, 0x00,             // Version: 0
            0x00, 0x00, 0x00, 0x00, // Flags: 0
            0x00, 0x03,             // Client type: 3 (Android / Mobile)
            0x00, 0x00,             // Min version: 0
            0x00, 0x02              // Max version: 2
        ])
    }

    private var shouldAutoConnectOnDiscovery: Bool = true

    func discoverConsoles(autoConnect: Bool = true) {
        shouldAutoConnectOnDiscovery = autoConnect
        if sockFD < 0 { setupSocket() }
        if case .disconnected = state {
            state = .scanning
        }
        statusLog = "Yerel ağda Xbox taranıyor (UDP 5050)..."

        let pkt = buildDiscoveryRequestPacket()

        // 1. Broadcast to 255.255.255.255:5050
        sendUDP(pkt, to: "255.255.255.255")

        // 2. Unicast to manual IP and saved console IPs immediately
        let trimmedManual = manualIP.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedManual.isEmpty {
            sendUDP(pkt, to: trimmedManual)
        }
        for saved in savedConsoles {
            sendUDP(pkt, to: saved.ip)
        }

        // 3. Unicast to subnet broadcast addresses (e.g. 192.168.50.255) without flooding 254 nonexistent ARP entries
        let prefixes = getLocalIPv4Prefixes()
        for prefix in prefixes {
            sendUDP(pkt, to: "\(prefix).255")
        }

        // Retry unicast to manualIP / savedConsoles after 400ms in case first UDP packet was lost
        Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            if case .connected = self.state { return }
            if !trimmedManual.isEmpty {
                self.sendUDP(pkt, to: trimmedManual)
            }
            for saved in self.savedConsoles {
                self.sendUDP(pkt, to: saved.ip)
            }
        }

        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if case .scanning = self.state {
                if let first = self.discoveredConsoles.first {
                    self.statusLog = "Xbox bulundu: \(first.name) (\(first.ip))"
                    self.state = .disconnected
                } else {
                    self.statusLog = "Açık Xbox bulunamadı. IP girip Bağlan'a basabilirsiniz."
                    self.state = .disconnected
                }
            }
        }
    }

    // MARK: - 2. Power On (0xDD02) & Power Off (0xA039)

    func powerOn(device: XboxConsoleDevice? = nil) {
        let targetDevice = device ?? currentConsole ?? discoveredConsoles.first ?? savedConsoles.first
        guard let dev = targetDevice, !dev.liveId.isEmpty else {
            statusLog = "Power On için daha önce bağlanılmış bir Xbox (Live ID) gerekli."
            return
        }
        statusLog = "\(dev.name) uyandırılıyor (Power On 0xDD02)..."

        var payload = SGWriter()
        payload.writeSGString(dev.liveId.uppercased())
        let payloadBytes = payload.data

        var pkt = SGWriter()
        pkt.writeUInt16(0xDD02)
        pkt.writeUInt16(UInt16(payloadBytes.count))
        pkt.writeUInt16(0x0000)
        pkt.writeBytes(payloadBytes)

        let raw = pkt.data
        let prefixes = getLocalIPv4Prefixes()
        for i in 0..<5 {
            Task {
                try? await Task.sleep(nanoseconds: UInt64(i) * 600_000_000)
                self.sendUDP(raw, to: dev.ip)
                self.sendUDP(raw, to: "255.255.255.255")
                for p in prefixes {
                    self.sendUDP(raw, to: "\(p).255")
                }
                if i == 4 {
                    self.discoverConsoles()
                }
            }
        }
    }

    func powerOff() {
        guard case .connected(let dev) = state else {
            statusLog = "Kapatmak için önce Xbox'a bağlanın."
            return
        }
        var w = SGWriter()
        w.writeSGString(dev.liveId)
        sendEncryptedMessage(flagHex: 0xA039, channelId: Data(count: 8), payload: w.data)
        statusLog = "\(dev.name) kapatma komutu gönderildi."
    }

    // MARK: - 3. Connect Handshake (0xCC00 -> 0xCC01 -> 0xD00D local_join + open channels)

    func connect(to ip: String) {
        let cleanIP = ip.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanIP.isEmpty else {
            statusLog = "Lütfen geçerli bir Xbox IP adresi girin."
            return
        }
        // Gracefully close any existing SmartGlass session first so old session packets don't collide
        if case .connected = state {
            var w = SGWriter()
            w.writeUInt32(4)
            w.writeUInt32(0)
            sendEncryptedMessage(flagHex: 0x802A, channelId: Data(count: 8), payload: w.data)
        }
        keepaliveTimer?.invalidate()
        keepaliveTimer = nil
        isConnectRequestInFlight = false
        shouldAutoConnectOnDiscovery = false

        manualIP = cleanIP
        if sockFD < 0 { setupSocket() }

        state = .connecting(cleanIP)
        statusLog = "\(cleanIP) adresindeki Xbox ile el sıkışılıyor..."

        // Send discovery packet directly to target IP; when 0xDD01 arrives, handleDiscoveryResponse will trigger sendConnectRequest!
        let pkt = buildDiscoveryRequestPacket()
        sendUDP(pkt, to: cleanIP)

        // Retry discovery ping after 900ms ONLY if 0xDD01 hasn't arrived yet
        Task {
            try? await Task.sleep(nanoseconds: 900_000_000)
            if case .connecting(let target) = self.state, target == cleanIP, !self.isConnectRequestInFlight {
                self.sendUDP(pkt, to: cleanIP)
            }
            try? await Task.sleep(nanoseconds: 4_500_000_000)
            if case .connecting(let target) = self.state, target == cleanIP {
                self.isConnectRequestInFlight = false
                self.state = .error("Xbox yanıt vermedi (\(cleanIP):5050)")
                self.statusLog = "Bağlantı zaman aşımı: Xbox açık ve aynı ağda mı?"
            }
        }
    }

    func disconnect() {
        if case .connected(let dev) = state {
            var w = SGWriter()
            w.writeUInt32(4) // reason
            w.writeUInt32(0) // error_code
            sendEncryptedMessage(flagHex: 0x802A, channelId: Data(count: 8), payload: w.data)
            statusLog = "\(dev.name) bağlantısı kesildi."
        }
        keepaliveTimer?.invalidate()
        keepaliveTimer = nil
        inputChannelId = nil
        mediaChannelId = nil
        textChannelId = nil
        channelsRequested = false
        hasActiveTextInput = false
        isConnectRequestInFlight = false
        state = .disconnected
    }

    private func sendConnectRequest(to device: XboxConsoleDevice, certDER: Data) {
        guard !isConnectRequestInFlight else { return }
        guard let (sgCrypto, liveId) = SGCrypto.fromXboxCertificate(certDER) else {
            state = .error("Sertifika çözülemedi")
            statusLog = "Xbox X.509 sertifikası okunamadı."
            return
        }
        isConnectRequestInFlight = true
        var updatedDevice = device
        if !liveId.isEmpty {
            updatedDevice.liveId = liveId
        }
        self.currentConsole = updatedDevice
        self.currentCertDER = certDER
        self.crypto = sgCrypto
        self.requestNum = 0
        self.lastReceivedRemoteSeqNum = 0
        self.participantId = 0
        self.inputChannelId = nil
        self.mediaChannelId = nil
        self.textChannelId = nil
        self.channelsRequested = false

        // Build protected_payload of connect_request (Module 1574):
        // userhash (sgString ""), jwt (sgString ""), connect_request_num (0), group_start (0), group_end (1)
        var prot = SGWriter()
        prot.writeSGString("")
        prot.writeSGString("")
        prot.writeUInt32(0)
        prot.writeUInt32(0)
        prot.writeUInt32(1)

        let unpaddedProtectedLen = UInt16(prot.data.count)
        let paddedProtected = SGCrypto.padTo16(prot.data)

        // Random 16-byte UUID & 16-byte IV for connect_request
        var uuidBytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, 16, &uuidBytes)
        let connectIV = sgCrypto.baseIV // 16 bytes

        let encryptedProtected = sgCrypto.aes128CBC(
            data: paddedProtected,
            key: sgCrypto.encryptionKey,
            iv: connectIV,
            encrypt: true
        )

        // Unprotected payload: uuid(16B) + public_key_type(2B = 0x0000) + public_key(64B) + iv(16B) = 98 bytes
        var unprot = SGWriter()
        unprot.writeBytes(Data(uuidBytes))
        unprot.writeUInt16(0x0000) // EC_DH_P256
        unprot.writeBytes(sgCrypto.publicKey64)
        unprot.writeBytes(connectIV)

        // Header (8 bytes): 0xCC00 + UInt16BE(unprotected.count = 98) + UInt16BE(unpaddedProtectedLen) + UInt16BE(version = 2)
        var pkt = SGWriter()
        pkt.writeUInt16(0xCC00)
        pkt.writeUInt16(UInt16(unprot.data.count)) // 98 (0x0062)
        pkt.writeUInt16(unpaddedProtectedLen)      // unpadded protected payload length (18)
        pkt.writeUInt16(0x0002) // version 2
        pkt.writeBytes(unprot.data)
        pkt.writeBytes(encryptedProtected)

        let signature = sgCrypto.sign(pkt.data)
        pkt.writeBytes(signature)

        sendUDP(pkt.data, to: updatedDevice.ip)
        statusLog = "\(updatedDevice.name) (\(updatedDevice.ip)) bağlantı onayı bekleniyor..."
    }

    // MARK: - 4. Incoming Packet Dispatcher

    private func handleIncomingPacket(_ data: Data, from senderIP: String) {
        guard data.count >= 4 else { return }
        var reader = SGReader(data: data)
        let magic = reader.readUInt16()

        switch magic {
        case 0xDD01: // simple.discovery_response
            handleDiscoveryResponse(&reader, from: senderIP)

        case 0xCC01: // simple.connect_response
            handleConnectResponse(fullData: data, from: senderIP)

        case 0xD00D: // encrypted session message
            handleSessionMessage(fullData: data, from: senderIP)

        default:
            break
        }
    }

    private func handleDiscoveryResponse(_ reader: inout SGReader, from senderIP: String) {
        _ = reader.readUInt16() // payload_length
        _ = reader.readUInt16() // version
        _ = reader.readUInt32() // flags
        _ = reader.readUInt16() // client_type
        let name = reader.readSGString()
        let uuid = reader.readSGString()
        _ = reader.readUInt32() // last_error
        let certLen = Int(reader.readUInt16())
        let certDER = reader.readBytes(certLen)

        var liveId = ""
        if let (_, extractedLiveId) = SGCrypto.fromXboxCertificate(certDER) {
            liveId = extractedLiveId
        }

        let device = XboxConsoleDevice(
            name: name.isEmpty ? "Xbox" : name,
            ip: senderIP,
            uuid: uuid,
            liveId: liveId,
            lastSeen: Date()
        )

        if let idx = discoveredConsoles.firstIndex(where: { $0.ip == senderIP }) {
            discoveredConsoles[idx] = device
        } else {
            discoveredConsoles.insert(device, at: 0)
        }
        saveConsoleToHistory(device)
        if manualIP.isEmpty {
            manualIP = senderIP
        }

        // Ignore duplicate discovery responses if already connected or handshake is already in flight
        if case .connected = state { return }
        guard !isConnectRequestInFlight else { return }

        if case .connecting(let targetIP) = state, targetIP == senderIP {
            sendConnectRequest(to: device, certDER: certDER)
        } else if shouldAutoConnectOnDiscovery {
            shouldAutoConnectOnDiscovery = false
            manualIP = senderIP
            state = .connecting(senderIP)
            sendConnectRequest(to: device, certDER: certDER)
        } else if case .scanning = state {
            statusLog = "Xbox bulundu: \(device.name) (\(senderIP))"
            state = .disconnected
        }
    }

    private func handleConnectResponse(fullData: Data, from senderIP: String) {
        if case .connected = state { return }
        guard let sgCrypto = crypto, fullData.count >= 8 + 16 + 16 + 32 else { return }
        var reader = SGReader(data: fullData)
        _ = reader.readUInt16() // 0xCC01
        _ = reader.readUInt16() // unprotected_len (16)
        let protectedLen = Int(reader.readUInt16())
        _ = reader.readUInt16() // version (2)
        let responseIV = reader.readBytes(16)
        let remainingBytes = reader.readBytes()
        guard remainingBytes.count >= 32 else { return }

        let ciphertext = remainingBytes.prefix(remainingBytes.count - 32)
        let decrypted = sgCrypto.aes128CBC(
            data: Data(ciphertext),
            key: sgCrypto.encryptionKey,
            iv: responseIV,
            encrypt: false
        )
        let payloadSlice = decrypted.prefix(min(protectedLen, decrypted.count))
        var pReader = SGReader(data: Data(payloadSlice))
        let connectResult = pReader.readUInt16()
        _ = pReader.readUInt16() // pairing_state
        let assignedParticipantId = pReader.readUInt32()

        isConnectRequestInFlight = false

        guard connectResult == 0 else {
            state = .error("Xbox bağlantıyı reddetti (Kod: \(connectResult))")
            statusLog = "Xbox bağlantıyı reddetti (Kod: \(connectResult)). Xbox'ta 'Herhangi bir cihazdan bağlantıya izin ver' açık olmalı."
            return
        }

        self.participantId = assignedParticipantId
        self.lastReceivedTime = Date()
        self.lastReceivedRemoteSeqNum = 0

        let connectedDev = currentConsole ?? XboxConsoleDevice(
            name: "Xbox",
            ip: senderIP,
            uuid: "",
            liveId: "",
            lastSeen: Date()
        )
        saveConsoleToHistory(connectedDev)
        state = .connected(connectedDev)
        statusLog = "\(connectedDev.name) bağlandı — Kanallar açılıyor..."

        // 1. Send message.local_join (0x2003) on Core channel (0)
        sendLocalJoin()

        // 2. Request service channels (SystemInput=1, SystemMedia=2, SystemText=3)
        requestAllServiceChannels()

        // 3. Also send Kodi EventServer HELO packet to UDP 9777 in case Kodi is running
        sendKodiHelo(to: connectedDev.ip)

        // 4. Start keepalive loop
        startKeepaliveLoop()
    }

    private func handleSessionMessage(fullData: Data, from senderIP: String) {
        guard let sgCrypto = crypto, fullData.count >= 26 + 32 else { return }

        var reader = SGReader(data: fullData)
        _ = reader.readUInt16() // 0xD00D
        let payloadLength = Int(reader.readUInt16())
        let seqNum = reader.readUInt32()
        let targetParticipantId = reader.readUInt32()
        _ = reader.readUInt32() // source_participant_id
        let rawFlags = reader.readUInt16()
        let channelId = reader.readBytes(8)
        let rest = reader.readBytes()
        guard rest.count >= 32 else { return }

        // 1. Check participantId (exact match with decompiled_bundle.js line 736286)
        guard targetParticipantId == self.participantId else {
            return
        }

        // 2. Verify HMAC-SHA256 signature to reject packets from stale sessions on the Xbox
        let signedBytes = Data(fullData.prefix(fullData.count - 32))
        let packetSig = Data(rest.suffix(32))
        guard sgCrypto.sign(signedBytes) == packetSig else {
            return
        }

        lastReceivedTime = Date()
        if seqNum > lastReceivedRemoteSeqNum {
            lastReceivedRemoteSeqNum = seqNum
        }

        let needAck = ((rawFlags >> 13) & 0x01) == 1
        let msgType = rawFlags & 0x0FFF

        // Immediately send message.acknowledge (0x8001) if need_ack is set
        if needAck {
            sendAcknowledge(lowWatermark: lastReceivedRemoteSeqNum, processedId: seqNum)
        }

        let ciphertext = Data(rest.prefix(rest.count - 32))
        guard !ciphertext.isEmpty else { return }

        let packetIV = sgCrypto.derivePacketIV(headerFirst16: fullData.prefix(16))
        let decrypted = sgCrypto.aes128CBC(
            data: ciphertext,
            key: sgCrypto.encryptionKey,
            iv: packetIV,
            encrypt: false
        )
        let cleartext = Data(decrypted.prefix(min(payloadLength, decrypted.count)))
        var mReader = SGReader(data: cleartext)

        if msgType != 0x01E {
            let hexStr = cleartext.map { String(format: "%02x", $0) }.joined()
            logDebug("RECV 0xD00D msgType=0x\(String(format: "%03X", msgType)) (\(msgType)) len=\(cleartext.count) hex=\(hexStr)")
        }

        switch msgType {
        case 0x01E: // 30: console_status
            _ = mReader.readUInt32() // live_tv_provider
            _ = mReader.readUInt32() // major
            _ = mReader.readUInt32() // minor
            _ = mReader.readUInt32() // build
            _ = mReader.readSGString() // locale
            let appCount = Int(mReader.readUInt16())
            var aumList: [String] = []
            for i in 0..<appCount {
                let tid = mReader.readUInt32()
                _ = mReader.readBytes(2)  // flags
                _ = mReader.readBytes(16) // product_id
                _ = mReader.readBytes(16) // sandbox_id
                let aum = mReader.readSGString()
                if i == 0 {
                    activeAppTitleId = tid
                }
                if !aum.isEmpty {
                    aumList.append(aum)
                }
            }
            let combinedAum = aumList.joined(separator: " | ")
            if combinedAum != activeAppAumId {
                activeAppAumId = combinedAum
                let lower = combinedAum.lowercased()
                let wasKodi = isKodiActive
                isKodiActive = lower.contains("kodi") || lower.contains("xbmc")
                if isKodiActive {
                    activeAppDisplayName = "Kodi"
                    if !wasKodi, case .connected(let dev) = state {
                        sendKodiHelo(to: dev.ip)
                    }
                } else if lower.contains("bafplayer") {
                    activeAppDisplayName = "BAFPlayer IPTV"
                } else if lower.contains("windowsstore") {
                    activeAppDisplayName = "Microsoft Store"
                } else if lower.contains("dashboard") || lower.contains("home") {
                    activeAppDisplayName = "Xbox Ana Ekran"
                } else if let first = aumList.first {
                    activeAppDisplayName = first.components(separatedBy: "_").first ?? first
                }
                logDebug("ACTIVE APP: \(combinedAum) (titleId=\(activeAppTitleId), isKodi=\(isKodiActive))")
            }
            if !channelsRequested {
                requestAllServiceChannels()
            }

        case 0x027: // 39: start_channel_response
            let reqId = mReader.readUInt32()
            let targetChanId = mReader.readBytes(8)
            let result = mReader.readUInt32()
            if result == 0 {
                switch reqId {
                case 1:
                    inputChannelId = targetChanId
                    statusLog = LocalizationManager.shared.readyStatus
                case 2:
                    mediaChannelId = targetChanId
                case 3:
                    textChannelId = targetChanId
                default:
                    break
                }
            }

        case 0xF03: // 3843: media_state
            let mediaTitle = mReader.readUInt32()
            if mediaTitle != 0 {
                activeMediaTitleId = mediaTitle
            }

        case 0xF2B: // 3883: SystemTextConfiguration
            let sessionId64 = mReader.readUInt64()
            let bufVer = mReader.readUInt32()
            textSessionId = UInt32(truncatingIfNeeded: sessionId64)
            currentTextVersion = bufVer
            hasActiveTextInput = true
            statusLog = "Xbox klavyesi aktif (Session #\(textSessionId), v\(currentTextVersion))"

        case 0xF2C: // 3884: SystemTextInput
            let sessId = mReader.readUInt32()
            let baseVer = mReader.readUInt32()
            let submittedVer = mReader.readUInt32()
            if sessId != 0 {
                textSessionId = sessId
            }
            currentTextVersion = submittedVer
            sendSystemTextAck(sessionId: textSessionId, versionAck: submittedVer)
            hasActiveTextInput = true
            logDebug("SystemTextInput sess=\(textSessionId) base=\(baseVer) sub=\(submittedVer)")

        case 0xF34: // 3892: SystemTextAcknowledge
            let sessId = mReader.readUInt32()
            let verAck = mReader.readUInt32()
            if sessId != 0 {
                textSessionId = sessId
                hasActiveTextInput = true
            }
            currentTextVersion = max(currentTextVersion, verAck)
            logDebug("SystemTextAcknowledge sess=\(sessId) verAck=\(verAck)")

        case 0xF35: // 3893: SystemTextDone / OSK version update
            let sessId = mReader.readUInt32()
            let ver = mReader.readUInt32()
            let flags = mReader.readUInt32()
            let res = mReader.readUInt32()
            logDebug("SystemTextDone sess=\(sessId) ver=\(ver) flags=\(flags) res=\(res) curSess=\(textSessionId)")
            if sessId != 0 {
                textSessionId = sessId
                if ver > 0 {
                    currentTextVersion = max(currentTextVersion, ver)
                }
                hasActiveTextInput = true
                statusLog = "Xbox klavyesi hazır (Session #\(sessId), v\(currentTextVersion))"
            } else {
                hasActiveTextInput = false
                statusLog = "Xbox ekran klavyesi kapandı."
            }

        case 0x02A: // 42: disconnect
            statusLog = "Xbox oturumu sonlandırdı."
            state = .disconnected

        default:
            _ = channelId
        }
    }

    // MARK: - 5. Encrypted 0xD00D Packet Builder & Sender

    private func nextRequestNum() -> UInt32 {
        let cur = requestNum
        requestNum &+= 1
        return cur
    }

    private func sendEncryptedMessage(flagHex: UInt16, channelId: Data, payload: Data) {
        guard let sgCrypto = crypto, case .connected(let dev) = state else { return }
        let seq = nextRequestNum()

        // 26-byte 0xD00D header
        var header = SGWriter()
        header.writeUInt16(0xD00D)
        header.writeUInt16(UInt16(payload.count)) // unpadded payload length
        header.writeUInt32(seq)
        header.writeUInt32(0)                     // target_participant_id = 0
        header.writeUInt32(participantId)         // source_participant_id
        header.writeUInt16(flagHex)
        let chan = channelId.count == 8 ? channelId : Data(count: 8)
        header.writeBytes(chan)

        let paddedPayload = SGCrypto.padTo16(payload)
        let packetIV = sgCrypto.derivePacketIV(headerFirst16: header.data.prefix(16))
        let encryptedPayload = sgCrypto.aes128CBC(
            data: paddedPayload,
            key: sgCrypto.encryptionKey,
            iv: packetIV,
            encrypt: true
        )

        var fullPacket = header.data
        fullPacket.append(encryptedPayload)
        let sig = sgCrypto.sign(fullPacket)
        fullPacket.append(sig)

        sendUDP(fullPacket, to: dev.ip)
    }

    private func sendLocalJoin() {
        var w = SGWriter()
        w.writeUInt16(3)    // client_type = 3
        w.writeUInt16(1080) // native_width
        w.writeUInt16(1920) // native_height
        w.writeUInt16(96)   // dpi_x
        w.writeUInt16(96)   // dpi_y
        w.writeBytes(Data(repeating: 0xFF, count: 8)) // device_capabilities
        w.writeUInt32(15)   // client_version
        w.writeUInt32(6)    // os_major_version
        w.writeUInt32(2)    // os_minor_version
        w.writeSGString("Xbox-Smartglass-Node")
        sendEncryptedMessage(flagHex: 0x2003, channelId: Data(count: 8), payload: w.data)
    }

    private func sendAcknowledge(lowWatermark: UInt32, processedId: UInt32?) {
        var w = SGWriter()
        w.writeUInt32(lowWatermark)
        if let pid = processedId {
            w.writeUInt32(1) // processed_list length = 1
            w.writeUInt32(pid)
        } else {
            w.writeUInt32(0) // processed_list length = 0
        }
        w.writeUInt32(0) // rejected_list length = 0
        sendEncryptedMessage(flagHex: 0x8001, channelId: Data(count: 8), payload: w.data)
    }

    private func requestAllServiceChannels() {
        channelsRequested = true
        // 1. SystemInput: fa20b8ca66fb46e0adb60b978a59d35f
        sendStartChannelRequest(
            requestId: 1,
            serviceUUIDHex: "fa20b8ca66fb46e0adb60b978a59d35f"
        )
        // 2. SystemMedia: 48a9ca24eb6d4e128c43d57469edd3cd
        sendStartChannelRequest(
            requestId: 2,
            serviceUUIDHex: "48a9ca24eb6d4e128c43d57469edd3cd"
        )
        // 3. SystemText: 7af3e6a2488b40cba93179c04b7da3a0
        sendStartChannelRequest(
            requestId: 3,
            serviceUUIDHex: "7af3e6a2488b40cba93179c04b7da3a0"
        )
    }

    private func sendStartChannelRequest(requestId: UInt32, serviceUUIDHex: String) {
        var w = SGWriter()
        w.writeUInt32(requestId)
        w.writeUInt32(0) // title_id = 0
        w.writeBytes(Data(hexString: serviceUUIDHex))
        w.writeUInt32(0) // activity_id = 0
        sendEncryptedMessage(flagHex: 0xA026, channelId: Data(count: 8), payload: w.data)
    }

    private func startKeepaliveLoop() {
        keepaliveTimer?.invalidate()
        keepaliveTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, case .connected(let dev) = self.state else { return }
                let idle = Date().timeIntervalSince(self.lastReceivedTime)
                if idle >= 4.0 && idle < 30.0 {
                    self.sendAcknowledge(lowWatermark: self.lastReceivedRemoteSeqNum, processedId: nil)
                } else if idle >= 35.0 {
                    // Auto-reconnect on silent timeout so toolbar controller stays permanently ready!
                    self.statusLog = "Oturum yenileniyor (\(dev.name))..."
                    self.connect(to: dev.ip)
                }
            }
        }
    }

    // MARK: - 6. Gamepad Button, Media, SystemText & Kodi Hybrid Senders

    func sendButton(_ button: GamepadButton) {
        guard case .connected(let dev) = state else {
            statusLog = "Önce Xbox'a bağlanın (\(button.label))"
            return
        }
        guard let chanId = inputChannelId else {
            requestAllServiceChannels()
            statusLog = "Input kanalı açılıyor, tekrar basın..."
            return
        }

        // Compute mask and optional thumbstick axes according to dpadInputMode
        var mask = button.bitmask
        var lx: Float = 0
        var ly: Float = 0
        if dpadInputMode == 1 || dpadInputMode == 2 {
            switch button {
            case .up:    ly = 1.0;  if dpadInputMode == 1 { mask = 0 }
            case .down:  ly = -1.0; if dpadInputMode == 1 { mask = 0 }
            case .left:  lx = -1.0; if dpadInputMode == 1 { mask = 0 }
            case .right: lx = 1.0;  if dpadInputMode == 1 { mask = 0 }
            default: break
            }
        }

        // 1. Send SmartGlass Gamepad press packet (buttons = mask + thumbstick)
        let pressPayload = buildGamepadPayload(mask: mask, leftThumbX: lx, leftThumbY: ly)
        sendEncryptedMessage(flagHex: 0x8F0A, channelId: chanId, payload: pressPayload)

        // 2. Also send Kodi EventServer UDP 9777 action (because Xbox OS blocks SmartGlass 0x8F0A inside Kodi UWP!)
        if button != .nexus {
            sendKodiButtonAction(button, to: dev.ip)
        }

        statusLog = isKodiActive ? "Tuş gönderildi (SmartGlass + Kodi): \(button.label)" : "Tuş gönderildi: \(button.label)"

        // Send release packet (buttons = 0, axes = 0) after 110ms
        Task {
            try? await Task.sleep(nanoseconds: 110_000_000)
            let releasePayload = self.buildGamepadPayload(mask: 0, leftThumbX: 0, leftThumbY: 0)
            self.sendEncryptedMessage(flagHex: 0x8F0A, channelId: chanId, payload: releasePayload)
        }
    }

    private func buildGamepadPayload(mask: UInt16, leftThumbX: Float = 0, leftThumbY: Float = 0) -> Data {
        var w = SGWriter()
        let ms = UInt64(Date().timeIntervalSince1970 * 1000)
        w.writeUInt64(ms)
        w.writeUInt16(mask)
        w.writeUInt32(0) // left_trigger
        w.writeUInt32(0) // right_trigger
        w.writeUInt32(leftThumbX.bitPattern) // left_thumbstick_x (Float32BE)
        w.writeUInt32(leftThumbY.bitPattern) // left_thumbstick_y (Float32BE)
        w.writeUInt32(0) // right_thumbstick_x
        w.writeUInt32(0) // right_thumbstick_y
        return w.data
    }

    func sendMediaCommand(_ cmd: MediaCommand) {
        guard case .connected(let dev) = state else {
            statusLog = "Önce Xbox'a bağlanın (\(cmd.rawValue))"
            return
        }
        guard let chanId = mediaChannelId else {
            requestAllServiceChannels()
            statusLog = "Medya kanalı açılıyor..."
            return
        }

        var w = SGWriter()
        w.writeUInt64(mediaRequestId)
        mediaRequestId &+= 1
        w.writeUInt32(activeMediaTitleId)
        w.writeUInt32(cmd.code)

        sendEncryptedMessage(flagHex: 0xAF01, channelId: chanId, payload: w.data)
        sendKodiMediaAction(cmd, to: dev.ip)
        statusLog = "Medya komutu: \(cmd.rawValue)"
    }

    private func sendSystemTextAck(sessionId: UInt32, versionAck: UInt32) {
        guard let chanId = textChannelId else { return }
        var w = SGWriter()
        w.writeUInt32(sessionId)
        w.writeUInt32(versionAck)
        sendEncryptedMessage(flagHex: 0xAF34, channelId: chanId, payload: w.data)
    }

    func sendTextInput(_ text: String) {
        guard case .connected(let dev) = state else {
            statusLog = "Metin göndermek için önce Xbox'a bağlanın."
            return
        }
        guard let chanId = textChannelId else {
            statusLog = "SystemText kanalı henüz hazır değil."
            return
        }

        let submittedVer = currentTextVersion &+ 1
        let utf8Len = UInt32(text.utf8.count)

        var w = SGWriter()
        w.writeUInt32(textSessionId)
        w.writeUInt32(currentTextVersion) // BaseVersion
        w.writeUInt32(submittedVer)       // SubmittedVersion
        w.writeUInt32(utf8Len)            // TotalTextBytelength
        w.writeInt32(-1)                  // SelectionStart
        w.writeInt32(-1)                  // SelectionLength
        w.writeUInt16(0)                  // Flags
        w.writeUInt32(0)                  // TextChunkByteStart
        w.writeSGString(text)             // TextChunk

        sendEncryptedMessage(flagHex: 0xAF2C, channelId: chanId, payload: w.data)
        logDebug("SENT SystemTextInput sess=\(textSessionId) base=\(currentTextVersion) sub=\(submittedVer) len=\(utf8Len)")
        currentTextVersion = submittedVer

        // Also send text to Kodi if Kodi is active (via JSON-RPC TCP 9090 / HTTP 8080)
        sendKodiTextInput(text, to: dev.ip)

        statusLog = "Metin Xbox klavyesine gönderildi (\(text.count) karakter)"
    }

    // MARK: - 6B. Kodi Direct EventServer (UDP 9777) & JSON-RPC (TCP 9090 / HTTP 8080)

    /// Builds a 32-byte XBMC EventServer UDP header + payload (xbmcclient.py protocol)
    private func buildKodiEventPacket(packetType: UInt16, payload: Data) -> Data {
        var w = SGWriter()
        w.writeBytes(Data([0x58, 0x42, 0x4D, 0x43])) // "XBMC"
        w.writeUInt8(2)                              // majver = 2
        w.writeUInt8(0)                              // minver = 0
        w.writeUInt16(packetType)                    // PT_HELO=1, PT_BUTTON=3, PT_ACTION=10
        w.writeUInt32(1)                             // seq = 1
        w.writeUInt32(1)                             // maxseq = 1
        w.writeUInt16(UInt16(payload.count))         // payload_size
        w.writeUInt32(kodiClientUid)                 // uid
        w.writeBytes(Data(count: 10))                // reserved (10 zero bytes)
        w.writeBytes(payload)
        return w.data
    }

    private func sendKodiHelo(to ip: String) {
        var p = SGWriter()
        p.writeBytes(Data("XboxToolbarController".utf8))
        p.writeUInt8(0)  // null terminator
        p.writeUInt8(0)  // ICON_NONE
        p.writeUInt16(0) // port
        p.writeUInt32(0) // reserved1
        p.writeUInt32(0) // reserved2
        let pkt = buildKodiEventPacket(packetType: 0x0001, payload: p.data)
        sendUDP(pkt, to: ip, port: 9777)
    }

    private func sendKodiAction(_ actionMessage: String, actionType: UInt8 = 0x02, to ip: String) {
        var p = SGWriter()
        p.writeUInt8(actionType) // 0x02 = ACTION_BUTTON, 0x01 = ACTION_EXECBUILTIN
        p.writeBytes(Data(actionMessage.utf8))
        p.writeUInt8(0)          // null-terminated string
        let pkt = buildKodiEventPacket(packetType: 0x000A, payload: p.data) // PT_ACTION = 0x0A
        sendUDP(pkt, to: ip, port: 9777)
    }

    private func sendKodiButtonAction(_ button: GamepadButton, to ip: String) {
        let action: String
        switch button {
        case .up:            action = "Up"
        case .down:          action = "Down"
        case .left:          action = "Left"
        case .right:         action = "Right"
        case .a:             action = "Select"
        case .b:             action = "Back"
        case .x:             action = "OSD"
        case .y:             action = "Info"
        case .menu:          action = "ContextMenu"
        case .view:          action = "FullScreen"
        case .leftShoulder:  action = "PageUp"
        case .rightShoulder: action = "PageDown"
        case .nexus:         return
        }
        sendKodiAction(action, actionType: 0x02, to: ip)
    }

    private func sendKodiMediaAction(_ cmd: MediaCommand, to ip: String) {
        let action: String
        switch cmd {
        case .play, .pause, .playPause: action = "PlayPause"
        case .stop:                     action = "Stop"
        case .fastForward:              action = "FastForward"
        case .rewind:                   action = "Rewind"
        case .channelUp, .nextTrack:    action = "ChannelUp"
        case .channelDown, .prevTrack:  action = "ChannelDown"
        case .back:                     action = "Back"
        case .menu:                     action = "ContextMenu"
        case .view:                     action = "Info"
        case .record:                   action = "Record"
        }
        sendKodiAction(action, actionType: 0x02, to: ip)
    }

    private func sendKodiTextInput(_ text: String, to ip: String) {
        // Send Input.SendText to Kodi JSON-RPC HTTP 8080 (if enabled)
        guard let url = URL(string: "http://\(ip):8080/jsonrpc") else { return }
        var req = URLRequest(url: url, timeoutInterval: 1.5)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "jsonrpc": "2.0",
            "method": "Input.SendText",
            "params": ["text": text, "done": false],
            "id": 1
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: req) { _, _, _ in }.resume()
    }

    // MARK: - 7. IPTV Anti-Freeze / Stream Reload Macro

    /// Solves the Xbox IPTV freeze problem by executing a quick reload sequence
    func reloadIPTVStream() {
        guard case .connected = state else {
            statusLog = "IPTV yenilemek için önce Xbox'a bağlanın."
            return
        }
        Task {
            switch iptvReloadMode {
            case 0:
                statusLog = "IPTV Canlandırılıyor: Kanal Aşağı -> Kanal Yukarı..."
                sendMediaCommand(.channelDown)
                try? await Task.sleep(nanoseconds: 900_000_000)
                sendMediaCommand(.channelUp)
                statusLog = "IPTV yayını yenilendi (CH- / CH+)"
            case 1:
                statusLog = "IPTV Canlandırılıyor: Geri (B) -> Seç (A)..."
                sendButton(.b)
                try? await Task.sleep(nanoseconds: 750_000_000)
                sendButton(.a)
                statusLog = "IPTV yayını yenilendi (B -> A)"
            default:
                statusLog = "IPTV Canlandırılıyor: Stop -> Play..."
                sendMediaCommand(.stop)
                try? await Task.sleep(nanoseconds: 650_000_000)
                sendMediaCommand(.play)
                statusLog = "IPTV yayını yenilendi (Stop -> Play)"
            }
        }
    }
}

// MARK: - Data Hex Helper

extension Data {
    init(hexString: String) {
        self.init()
        var hex = hexString
        if hex.count % 2 != 0 { hex = "0" + hex }
        var index = hex.startIndex
        while index < hex.endIndex {
            let nextIndex = hex.index(index, offsetBy: 2)
            if let b = UInt8(hex[index..<nextIndex], radix: 16) {
                self.append(b)
            }
            index = nextIndex
        }
    }
}
