import Foundation
import Darwin
import CryptoKit
import CommonCrypto
import Security
import SQLite3

struct HelperFailure: Error, LocalizedError {
    let code: String
    let title: String
    let detail: String
    var errorDescription: String? { detail }
}

func require(_ condition: @autoclosure () throws -> Bool, _ code: String, _ title: String, _ detail: String) throws {
    if try !condition() { throw HelperFailure(code: code, title: title, detail: detail) }
}

func readableFailure(_ error: Error) -> HelperFailure {
    if let known = error as? HelperFailure { return known }
    return HelperFailure(code: "operation_stopped", title: "The operation stopped",
                         detail: "No raw error logs or credentials are shown. Keep any backup and try checking this Mac again.")
}

extension Data {
    var hex: String { map { String(format: "%02x", $0) }.joined() }
    var sha256: Data { Data(SHA256.hash(data: self)) }
    func same(as other: Data) -> Bool {
        guard count == other.count else { return false }
        return zip(self, other).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }
}

enum Format {
    static let version = "0.3.0"
    static let appID = "com.anthropic.claudefordesktop"
    static let teamID = "Q6L2SF6YDW"
    static let limit = 32 * 1024 * 1024
    static let appleEpoch: Double = 978307200
    static let chromeEpoch: Double = 11644473600
    static let domains = ["claude.ai", ".claude.ai"]
    static let names = ["sessionKey", "lastActiveOrg", "anthropic-device-id"]
    static let columns = ["creation_utc", "host_key", "top_frame_site_key", "name", "value", "encrypted_value", "path", "expires_utc", "is_secure", "is_httponly", "last_access_utc", "has_expires", "is_persistent", "priority", "samesite", "source_scheme", "source_port", "last_update_utc", "source_type", "has_cross_site_ancestor"]
    static let uniqueColumns = ["host_key", "top_frame_site_key", "has_cross_site_ancestor", "name", "path", "source_scheme", "source_port"]
    static let selection = "host_key IN ('claude.ai','.claude.ai') AND name IN ('sessionKey','lastActiveOrg','anthropic-device-id') AND path='/' AND top_frame_site_key=''"
}

struct LocalPaths {
    let home: URL
    let app: URL
    var profile: URL { home.appendingPathComponent("Library/Application Support/Claude") }
    var database: URL { profile.appendingPathComponent("Cookies") }
    var safari: URL { home.appendingPathComponent("Library/Containers/com.apple.Safari/Data/Library/Cookies/Cookies.binarycookies") }
    var backups: URL { home.appendingPathComponent("Library/Application Support/Claude Sign-In Helper/Backups") }
    var log: URL { home.appendingPathComponent("Library/Logs/Claude/main.log") }

    static func discover() throws -> LocalPaths {
        try require(getuid() != 0 && geteuid() == getuid(), "account", "Use your own Mac account", "Open this app normally, without administrator or sudo execution.")
        guard let entry = getpwuid(getuid()) else { throw HelperFailure(code: "account", title: "Account unavailable", detail: "Your local Mac account could not be identified.") }
        let home = URL(fileURLWithPath: String(cString: entry.pointee.pw_dir), isDirectory: true)
        for app in [URL(fileURLWithPath: "/Applications/Claude.app"), home.appendingPathComponent("Applications/Claude.app")] {
            if FileManager.default.fileExists(atPath: app.path) { return LocalPaths(home: home, app: app) }
        }
        throw HelperFailure(code: "app_missing", title: "Install Claude Desktop first", detail: "Install the official Claude Desktop app, open it once, then quit it and check again.")
    }
}

func fileInfo(_ url: URL) throws -> stat {
    var info = stat()
    guard lstat(url.path, &info) == 0 else {
        if errno == EACCES || errno == EPERM {
            throw HelperFailure(code: "file_access", title: "macOS needs your permission", detail: "This app cannot read the protected local data yet. Open the access guide for instructions.")
        }
        throw HelperFailure(code: "file_missing", title: "Local data is not available", detail: "Open Safari and the official Claude app once. Keep Safari signed in, quit Claude, then check again.")
    }
    try require(info.st_uid == getuid(), "owner", "A different Mac account owns this file", "Only this Mac account’s local data can be used.")
    return info
}

func safeRead(_ url: URL, limit: Int = Format.limit, offset: UInt64 = 0) throws -> Data {
    let fd = open(url.path, O_RDONLY | O_NOFOLLOW)
    guard fd >= 0 else {
        if errno == EACCES || errno == EPERM {
            throw HelperFailure(code: "file_access", title: "macOS needs your permission", detail: "Safari protects its saved sign-in data. Open the access guide to allow this app to read it.")
        }
        throw HelperFailure(code: "file_missing", title: "Saved data is unavailable", detail: "A required file is missing or unsupported. Open Safari and Claude Desktop once, then check again.")
    }
    let stream = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    defer { try? stream.close() }
    var info = stat()
    try require(fstat(fd, &info) == 0 && info.st_uid == getuid() && (info.st_mode & S_IFMT) == S_IFREG,
                "owner", "Unexpected file type", "The source must be a regular file owned by your Mac account.")
    try require(info.st_size >= 0 && offset <= UInt64(info.st_size) && UInt64(info.st_size) - offset <= UInt64(limit),
                "file_size", "This file is outside the preview’s limits", "The app stopped without changing your data.")
    try stream.seek(toOffset: offset)
    let result = try stream.read(upToCount: limit + 1) ?? Data()
    try require(result.count <= limit, "file_size", "The file changed while reading", "Try checking again.")
    return result
}

struct SessionCookie {
    let domain: String
    let name: String
    let value: Data
    let expires: Double
    let created: Double
    let httpOnly: Bool
}

enum SafariReader {
    private static func invalid() -> HelperFailure {
        HelperFailure(code: "safari_format", title: "This Safari format is not supported", detail: "The saved cookie file is incomplete or uses a different format. No changes were made.")
    }
    private static func integer(_ data: Data, _ offset: Int, _ count: Int = 4, big: Bool = false) throws -> UInt64 {
        guard offset >= 0, count > 0, offset <= data.count - count else { throw invalid() }
        let bytes = Array(data[offset..<(offset + count)])
        return (big ? bytes : Array(bytes.reversed())).reduce(0) { ($0 << 8) | UInt64($1) }
    }
    static func parse(_ data: Data, now: Double = Date().timeIntervalSince1970) throws -> [String: SessionCookie] {
        guard data.count >= 8, data.count <= Format.limit, data.prefix(4) == Data("cook".utf8) else { throw invalid() }
        let pages = Int(try integer(data, 4, big: true))
        guard pages > 0, pages <= 10000, 8 + pages * 4 <= data.count else { throw invalid() }
        var cursor = 8 + pages * 4
        var found: [String: SessionCookie] = [:]
        var expired = false
        for pageNumber in 0..<pages {
            let size = Int(try integer(data, 8 + pageNumber * 4, big: true))
            guard size >= 12, size <= data.count - cursor else { throw invalid() }
            let page = data.subdata(in: cursor..<(cursor + size)); cursor += size
            let count = Int(try integer(page, 4))
            guard count <= 100000, 8 + count * 4 <= size else { throw invalid() }
            for n in 0..<count {
                let offset = Int(try integer(page, 8 + n * 4))
                guard offset >= 8 + count * 4, offset <= size - 56 else { throw invalid() }
                let length = Int(try integer(page, offset))
                guard length >= 56, length <= size - offset else { throw invalid() }
                let record = page.subdata(in: offset..<(offset + length))
                func field(_ index: Int) throws -> Data {
                    let start = Int(try integer(record, index))
                    guard start >= 56, start < length, let end = record[start...].firstIndex(of: 0) else { throw invalid() }
                    return record.subdata(in: start..<end)
                }
                let domainData = try field(16)
                guard Format.domains.map({ Data($0.utf8) }).contains(domainData) else { continue }
                let nameData = try field(20)
                if ["sessionKeyV2", "sessionKeyV3"].map({ Data($0.utf8) }).contains(nameData) {
                    throw HelperFailure(code: "new_session_format", title: "A newer sign-in format was found", detail: "This preview cannot transfer newer or multiple-account sessions. Your saved sign-ins are unchanged.")
                }
                guard let name = Format.names.first(where: { Data($0.utf8) == nameData }) else { continue }
                let expires = Double(bitPattern: try integer(record, 40, 8)) + Format.appleEpoch
                let created = Double(bitPattern: try integer(record, 48, 8)) + Format.appleEpoch
                guard expires.isFinite, created.isFinite, expires + Format.chromeEpoch < 9e12 else { throw invalid() }
                if expires <= now { expired = expired || name == "sessionKey"; continue }
                try require(try field(24) == Data("/".utf8), "cookie_scope", "Unexpected session scope", "This preview cannot safely transfer that Safari session.")
                let flags = try integer(record, 8)
                try require(flags & 1 != 0 && (name != "sessionKey" || flags & 4 != 0), "cookie_flags", "The session cannot be transferred", "The required cookie protection flags are missing.")
                try require(found[name] == nil, "ambiguous", "More than one session was found", "This preview cannot choose between multiple Safari sessions. Nothing was changed.")
                let value = try field(28)
                try require(!value.isEmpty && value.count <= 16384, "cookie_value", "The session is not supported", "The saved session has an unexpected size.")
                found[name] = SessionCookie(domain: String(decoding: domainData, as: UTF8.self), name: name,
                                             value: value, expires: expires, created: min(max(created, 0), now), httpOnly: flags & 4 != 0)
            }
        }
        try require(found["sessionKey"] != nil, expired ? "session_expired" : "session_missing",
                    expired ? "Your Safari session has expired" : "No Safari sign-in was found",
                    "Claude must already work in Safari’s default profile on this Mac. An iPhone-only login cannot be transferred by this app.")
        return found
    }
}

enum CookieCrypto {
    static func derive(_ password: Data) throws -> Data {
        var output = [UInt8](repeating: 0, count: 16)
        let salt = Array("saltysalt".utf8)
        let result = password.withUnsafeBytes { secret in
            salt.withUnsafeBufferPointer { saltBuffer in
                CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), secret.baseAddress?.assumingMemoryBound(to: Int8.self),
                                    password.count, saltBuffer.baseAddress, salt.count, CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1), 1003, &output, 16)
            }
        }
        try require(result == kCCSuccess, "crypto", "Encryption could not be prepared", "No login data was changed.")
        return Data(output)
    }
    static func keyFromKeychain() throws -> Data {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: "Claude Safe Storage",
                                    kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let password = result as? Data, !password.isEmpty else {
            throw HelperFailure(code: "keychain", title: "Keychain access was not granted", detail: "Choose Allow in the macOS prompt for Claude Safe Storage, then try again. Enter your Mac password only in that macOS dialog.")
        }
        return try derive(password)
    }
    static func transform(_ input: Data, key: Data, decrypt: Bool = false) throws -> Data {
        try require(key.count == 16, "crypto", "Unexpected encryption key", "No login data was changed.")
        let capacity = input.count + kCCBlockSizeAES128
        var output = [UInt8](repeating: 0, count: capacity)
        let iv = [UInt8](repeating: 32, count: 16)
        var written = 0
        let status = key.withUnsafeBytes { keyBytes in
            input.withUnsafeBytes { bytes in
                iv.withUnsafeBufferPointer { ivBytes in
                    CCCrypt(CCOperation(decrypt ? kCCDecrypt : kCCEncrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding),
                            keyBytes.baseAddress, key.count, ivBytes.baseAddress, bytes.baseAddress, input.count, &output, capacity, &written)
                }
            }
        }
        try require(status == kCCSuccess, "crypto", "Encryption verification failed", "The saved data does not match the expected encryption. Nothing was imported.")
        return Data(output.prefix(written))
    }
    static func seal(_ cookie: SessionCookie, key: Data) throws -> Data {
        let plaintext = Data(cookie.domain.utf8).sha256 + cookie.value
        let ciphertext = try transform(plaintext, key: key)
        try require(try transform(ciphertext, key: key, decrypt: true).same(as: plaintext), "crypto", "Encryption verification failed", "Nothing was imported.")
        return Data("v10".utf8) + ciphertext
    }
    static func open(_ encrypted: Data, domain: String, key: Data) throws -> Data {
        try require(encrypted.prefix(3) == Data("v10".utf8), "crypto_version", "A different encryption format was found", "This preview will not change that cookie store.")
        let plain = try transform(Data(encrypted.dropFirst(3)), key: key, decrypt: true)
        try require(Data(plain.prefix(32)).same(as: Data(domain.utf8).sha256), "wrong_key", "The encryption key does not match", "No login data was changed.")
        return Data(plain.dropFirst(32))
    }
}

enum SQLValue: Equatable {
    case integer(Int64), text(String), blob(Data), null
    var string: String { if case .text(let s) = self { return s }; return "" }
    var number: Int64 { if case .integer(let n) = self { return n }; return 0 }
    var data: Data { if case .blob(let d) = self { return d }; return Data() }
    var json: Any {
        switch self { case .integer(let n): return n; case .text(let s): return s; case .blob(let d): return d.hex; case .null: return NSNull() }
    }
}

final class CookieDatabase {
    var handle: OpaquePointer?
    let url: URL
    init(_ url: URL, writable: Bool = false, create: Bool = false, validate: Bool = true) throws {
        self.url = url
        // Foundation shortens /private/var to /var when resolving URLs. SQLite's
        // NOFOLLOW correctly rejects that system symlink; keep its physical path.
        var sqlitePath = url.path
        if sqlitePath.hasPrefix("/var/") || sqlitePath.hasPrefix("/tmp/") { sqlitePath = "/private" + sqlitePath }
        if create {
            let descriptor = open(sqlitePath, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
            try require(descriptor >= 0, "database_create", "The private backup could not be created", "An existing file will not be overwritten. No login data was changed.")
            close(descriptor)
        } else {
            let info = try fileInfo(url)
            try require(info.st_mode & S_IFMT == S_IFREG, "database_owner", "Unexpected cookie file", "The cookie database cannot be a symbolic link or a different file type.")
        }
        let flags = (writable || create ? SQLITE_OPEN_READWRITE : SQLITE_OPEN_READONLY) | SQLITE_OPEN_NOFOLLOW
        let status = sqlite3_open_v2(sqlitePath, &handle, flags, nil)
        guard status == SQLITE_OK else {
            if let h = handle { sqlite3_close(h); handle = nil }
            throw HelperFailure(code: "database_access", title: "Desktop’s saved data is unavailable", detail: "Open Claude Desktop once, then quit it. If macOS still blocks access, open the access guide.")
        }
        sqlite3_busy_timeout(handle, 5000)
        do {
            if writable || create {
                try require(sqlite3_db_readonly(handle, "main") == 0, "database_readonly", "The cookie store is read-only", "No login data was changed. Check the file permissions before trying again.")
            }
            if validate { try validateFormat() }
        }
        catch { sqlite3_close(handle); handle = nil; throw error }
    }
    deinit { if let h = handle { sqlite3_close(h) } }
    @discardableResult
    func query(_ sql: String, _ values: [SQLValue] = []) throws -> [[SQLValue]] {
        var statement: OpaquePointer?
        try require(sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK,
                    "database_query", "Cookie storage is not compatible", "The expected database operation could not be prepared.")
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            let status: Int32
            switch value {
            case .integer(let n): status = sqlite3_bind_int64(statement, index, n)
            case .text(let s): status = s.withCString { sqlite3_bind_text(statement, index, $0, -1, transient) }
            case .blob(let d): status = d.withUnsafeBytes { sqlite3_bind_blob(statement, index, $0.baseAddress, Int32(d.count), transient) }
            case .null: status = sqlite3_bind_null(statement, index)
            }
            try require(status == SQLITE_OK, "database_bind", "The database operation stopped", "No credential details are included in this error.")
        }
        var rows: [[SQLValue]] = []
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { return rows }
            try require(status == SQLITE_ROW, "database_write", "The database operation stopped", "The app may be open or the disk unavailable. Keep your backup and try checking again.")
            var row: [SQLValue] = []
            for index in 0..<sqlite3_column_count(statement) {
                switch sqlite3_column_type(statement, index) {
                case SQLITE_INTEGER: row.append(.integer(sqlite3_column_int64(statement, index)))
                case SQLITE_TEXT: row.append(.text(String(cString: sqlite3_column_text(statement, index))))
                case SQLITE_BLOB:
                    let count = Int(sqlite3_column_bytes(statement, index))
                    if let ptr = sqlite3_column_blob(statement, index), count > 0 { row.append(.blob(Data(bytes: ptr, count: count))) }
                    else { row.append(.blob(Data())) }
                default: row.append(.null)
                }
            }
            rows.append(row)
            try require(rows.count <= 100000, "database_size", "This database is outside the preview’s limits", "No data will be imported.")
        }
    }
    func validateFormat() throws {
        let version = try query("SELECT value FROM meta WHERE key='version'").first?.first?.string
        try require(version == "24", "database_version", "A newer storage format was found", "This preview supports cookie database version 24. Your existing data was not changed.")
        let columns = try query("PRAGMA table_info(cookies)").map { $0[1].string }
        try require(columns == Format.columns, "database_schema", "Desktop’s storage format has changed", "This preview cannot safely edit this version.")
        let indexes = try query("PRAGMA index_list(cookies)")
        var validIndex = false
        for row in indexes where row[2].number == 1 {
            let quoted = row[1].string.replacingOccurrences(of: "\"", with: "\"\"")
            if try query("PRAGMA index_info(\"\(quoted)\")").map({ $0[2].string }) == Format.uniqueColumns { validIndex = true }
        }
        try require(validIndex, "database_index", "Desktop’s storage format has changed", "Its expected cookie index could not be verified.")
        try integrity()
        try require(try query("PRAGMA journal_mode").first?.first?.string == "delete", "database_journal", "A different database mode was found", "This preview cannot edit that store.")
    }
    func integrity() throws {
        try require(try query("PRAGMA quick_check").first?.first?.string == "ok", "database_integrity", "The database check did not pass", "The helper will not change a damaged cookie store.")
    }
    func hasLogin() throws -> Bool {
        try !query("SELECT 1 FROM cookies WHERE host_key IN ('claude.ai','.claude.ai') AND name IN ('sessionKey','sessionKeyV2','sessionKeyV3') LIMIT 1").isEmpty
    }
    func requireNoLogin() throws {
        try require(try !hasLogin(), "session_exists", "Desktop already has a saved sign-in", "Your current Desktop session will be preserved. Open Claude to use it.")
    }
    func verifyKey(_ key: Data) throws {
        let rows = try query("SELECT host_key,encrypted_value,value FROM cookies WHERE host_key IN ('claude.ai','.claude.ai') AND name='anthropic-device-id'")
        try require(!rows.isEmpty, "initialize", "Open Claude Desktop once first", "The app needs to create its encrypted cookie store. Open it, quit it, then check again.")
        for row in rows {
            try require(row[2].string.isEmpty, "crypto_version", "The encryption format is not supported", "No data was imported.")
            _ = try CookieCrypto.open(row[1].data, domain: row[0].string, key: key)
        }
    }
    func insert(_ row: [SQLValue]) throws {
        try query("INSERT INTO cookies (" + Format.columns.joined(separator: ",") + ") VALUES (" + Array(repeating: "?", count: Format.columns.count).joined(separator: ",") + ")", row)
    }
    func selectedRows() throws -> [[SQLValue]] { try query("SELECT " + Format.columns.joined(separator: ",") + " FROM cookies WHERE " + Format.selection) }
    func fingerprint() throws -> String {
        let rows = try query("SELECT host_key,top_frame_site_key,name,path,value,encrypted_value,is_secure,is_httponly,source_scheme,source_port,has_cross_site_ancestor FROM cookies WHERE " + Format.selection + " ORDER BY host_key,name,path")
        return try JSONSerialization.data(withJSONObject: rows.map { $0.map(\.json) }, options: [.withoutEscapingSlashes]).sha256.hex
    }
    func backup(to url: URL) throws {
        let target = try CookieDatabase(url, writable: true, create: true, validate: false)
        guard let backup = sqlite3_backup_init(target.handle, "main", handle, "main") else {
            throw HelperFailure(code: "backup", title: "The backup could not be created", detail: "No login data was changed.")
        }
        let step = sqlite3_backup_step(backup, -1)
        let finish = sqlite3_backup_finish(backup)
        try require(step == SQLITE_DONE && finish == SQLITE_OK, "backup", "The backup could not be completed", "No login data was changed.")
        try target.validateFormat()
    }
}

func encryptedRow(_ cookie: SessionCookie, key: Data, now: Double = Date().timeIntervalSince1970) throws -> [SQLValue] {
    let timestamp = Int64((now + Format.chromeEpoch) * 1e6)
    return [.integer(Int64((cookie.created + Format.chromeEpoch) * 1e6)), .text(cookie.domain), .text(""), .text(cookie.name), .text(""),
            .blob(try CookieCrypto.seal(cookie, key: key)), .text("/"), .integer(Int64((cookie.expires + Format.chromeEpoch) * 1e6)),
            .integer(1), .integer(cookie.httpOnly ? 1 : 0), .integer(timestamp), .integer(1), .integer(1), .integer(1), .integer(1),
            .integer(2), .integer(443), .integer(timestamp), .integer(1), .integer(1)]
}
