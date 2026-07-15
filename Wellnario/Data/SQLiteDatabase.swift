import Foundation
import SQLite3

enum SQLiteStoreError: Error, LocalizedError {
    case open(path: String, message: String)
    case prepare(sql: String, message: String)
    case bind(message: String)
    case step(sql: String, message: String)
    case execute(sql: String, message: String)
    case missingColumn(String)
    case invalidColumn(name: String, expected: String)

    var errorDescription: String? {
        switch self {
        case let .open(path, message): return "Unable to open SQLite database at \(path): \(message)"
        case let .prepare(sql, message): return "Unable to prepare SQLite statement \(sql): \(message)"
        case let .bind(message): return "Unable to bind SQLite value: \(message)"
        case let .step(sql, message): return "Unable to execute SQLite statement \(sql): \(message)"
        case let .execute(sql, message): return "Unable to execute SQLite script \(sql): \(message)"
        case let .missingColumn(name): return "Missing SQLite column \(name)."
        case let .invalidColumn(name, expected): return "SQLite column \(name) is not \(expected)."
        }
    }
}

enum SQLiteBinding {
    case null
    case text(String)
    case integer(Int64)
    case real(Double)
}

struct SQLiteRow {
    fileprivate let values: [String: SQLiteBinding]

    func string(_ name: String) throws -> String {
        guard let value = values[name] else { throw SQLiteStoreError.missingColumn(name) }
        guard case let .text(result) = value else {
            throw SQLiteStoreError.invalidColumn(name: name, expected: "text")
        }
        return result
    }

    func optionalString(_ name: String) throws -> String? {
        guard let value = values[name] else { throw SQLiteStoreError.missingColumn(name) }
        switch value {
        case .null: return nil
        case let .text(result): return result
        default: throw SQLiteStoreError.invalidColumn(name: name, expected: "text or null")
        }
    }

    func integer(_ name: String) throws -> Int64 {
        guard let value = values[name] else { throw SQLiteStoreError.missingColumn(name) }
        guard case let .integer(result) = value else {
            throw SQLiteStoreError.invalidColumn(name: name, expected: "integer")
        }
        return result
    }

    func optionalInteger(_ name: String) throws -> Int64? {
        guard let value = values[name] else { throw SQLiteStoreError.missingColumn(name) }
        switch value {
        case .null: return nil
        case let .integer(result): return result
        default: throw SQLiteStoreError.invalidColumn(name: name, expected: "integer or null")
        }
    }

    func double(_ name: String) throws -> Double {
        guard let value = values[name] else { throw SQLiteStoreError.missingColumn(name) }
        switch value {
        case let .real(result): return result
        case let .integer(result): return Double(result)
        default: throw SQLiteStoreError.invalidColumn(name: name, expected: "real")
        }
    }

    func optionalDouble(_ name: String) throws -> Double? {
        guard let value = values[name] else { throw SQLiteStoreError.missingColumn(name) }
        switch value {
        case .null: return nil
        case let .real(result): return result
        case let .integer(result): return Double(result)
        default: throw SQLiteStoreError.invalidColumn(name: name, expected: "real or null")
        }
    }
}

final class SQLiteDatabase {
    let url: URL
    private var handle: OpaquePointer?

    init(url: URL) throws {
        self.url = url
        let path: String
        if url.path == ":memory:"
            || url.lastPathComponent == ":memory:"
            || url.absoluteString == ":memory:" {
            path = ":memory:"
        } else {
            path = url.path
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        }

        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        let result = sqlite3_open_v2(path, &handle, flags, nil)
        guard result == SQLITE_OK, let handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "Unknown error"
            if let handle { sqlite3_close(handle) }
            self.handle = nil
            throw SQLiteStoreError.open(path: path, message: message)
        }

        do {
            try executeScript("PRAGMA foreign_keys = ON;")
            try executeScript("PRAGMA busy_timeout = 5000;")
            if path != ":memory:" {
                try executeScript("PRAGMA journal_mode = WAL;")
                try executeScript("PRAGMA synchronous = NORMAL;")
            }
        } catch {
            sqlite3_close(handle)
            self.handle = nil
            throw error
        }
    }

    deinit {
        if let handle { sqlite3_close(handle) }
    }

    func executeScript(_ sql: String) throws {
        guard let handle else { throw SQLiteStoreError.execute(sql: sql, message: "Closed database") }
        var errorMessage: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(handle, sql, nil, nil, &errorMessage)
        guard result == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? String(cString: sqlite3_errmsg(handle))
            sqlite3_free(errorMessage)
            throw SQLiteStoreError.execute(sql: sql, message: message)
        }
    }

    @discardableResult
    func execute(_ sql: String, bindings: [SQLiteBinding] = []) throws -> Int {
        try withStatement(sql) { statement in
            try bind(bindings, to: statement)
            let result = sqlite3_step(statement)
            guard result == SQLITE_DONE else {
                throw SQLiteStoreError.step(sql: sql, message: errorMessage)
            }
            return Int(sqlite3_changes(handle))
        }
    }

    func query(_ sql: String, bindings: [SQLiteBinding] = []) throws -> [SQLiteRow] {
        try withStatement(sql) { statement in
            try bind(bindings, to: statement)
            var rows: [SQLiteRow] = []
            while true {
                let result = sqlite3_step(statement)
                if result == SQLITE_DONE { break }
                guard result == SQLITE_ROW else {
                    throw SQLiteStoreError.step(sql: sql, message: errorMessage)
                }

                var values: [String: SQLiteBinding] = [:]
                for index in 0..<sqlite3_column_count(statement) {
                    guard let rawName = sqlite3_column_name(statement, index) else { continue }
                    let name = String(cString: rawName)
                    switch sqlite3_column_type(statement, index) {
                    case SQLITE_NULL:
                        values[name] = .null
                    case SQLITE_INTEGER:
                        values[name] = .integer(sqlite3_column_int64(statement, index))
                    case SQLITE_FLOAT:
                        values[name] = .real(sqlite3_column_double(statement, index))
                    case SQLITE_TEXT:
                        if let rawText = sqlite3_column_text(statement, index) {
                            values[name] = .text(String(cString: rawText))
                        } else {
                            values[name] = .text("")
                        }
                    default:
                        values[name] = .null
                    }
                }
                rows.append(SQLiteRow(values: values))
            }
            return rows
        }
    }

    func scalarInteger(_ sql: String, bindings: [SQLiteBinding] = []) throws -> Int64 {
        let rows = try query(sql, bindings: bindings)
        guard let row = rows.first, let firstName = row.values.keys.first else { return 0 }
        return try row.integer(firstName)
    }

    func transaction<T>(_ body: () throws -> T) throws -> T {
        try executeScript("BEGIN IMMEDIATE;")
        do {
            let value = try body()
            try executeScript("COMMIT;")
            return value
        } catch {
            try? executeScript("ROLLBACK;")
            throw error
        }
    }

    private var errorMessage: String {
        guard let handle else { return "Closed database" }
        return String(cString: sqlite3_errmsg(handle))
    }

    private func withStatement<T>(_ sql: String, _ body: (OpaquePointer) throws -> T) throws -> T {
        guard let handle else { throw SQLiteStoreError.prepare(sql: sql, message: "Closed database") }
        var statement: OpaquePointer?
        let result = sqlite3_prepare_v2(handle, sql, -1, &statement, nil)
        guard result == SQLITE_OK, let statement else {
            throw SQLiteStoreError.prepare(sql: sql, message: errorMessage)
        }
        defer { sqlite3_finalize(statement) }
        return try body(statement)
    }

    private func bind(_ bindings: [SQLiteBinding], to statement: OpaquePointer) throws {
        for (offset, binding) in bindings.enumerated() {
            let index = Int32(offset + 1)
            let result: Int32
            switch binding {
            case .null:
                result = sqlite3_bind_null(statement, index)
            case let .integer(value):
                result = sqlite3_bind_int64(statement, index, value)
            case let .real(value):
                result = sqlite3_bind_double(statement, index, value)
            case let .text(value):
                result = value.withCString { pointer in
                    sqlite3_bind_text(statement, index, pointer, -1, transientDestructor())
                }
            }
            guard result == SQLITE_OK else {
                throw SQLiteStoreError.bind(message: errorMessage)
            }
        }
    }
}

private func transientDestructor() -> sqlite3_destructor_type {
    unsafeBitCast(-1, to: sqlite3_destructor_type.self)
}
