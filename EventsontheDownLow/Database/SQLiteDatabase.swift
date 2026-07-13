import Foundation
import SQLite3

/// Thin wrapper around the C sqlite3 API bundled with iOS.
/// Add `libsqlite3.tbd` to "Link Binary With Libraries" in your target
/// (Build Phases) and `import SQLite3` — no external package needed.
final class SQLiteDatabase {
    private var db: OpaquePointer?
    private let dbQueue = DispatchQueue(label: "com.eventsonthedownlow.sqlite")

    static let shared = SQLiteDatabase()

    private init() {
        openDatabase()
        createTables()
    }

    private var databaseURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("events.sqlite3")
    }

    private func openDatabase() {
        if sqlite3_open(databaseURL.path, &db) != SQLITE_OK {
            #if DEBUG
            print("Unable to open database at \(databaseURL.path)")
            #endif
        }
    }

    private func createTables() {
        let sql = """
        CREATE TABLE IF NOT EXISTS events (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            notes TEXT,
            start_date REAL NOT NULL,
            end_date REAL NOT NULL,
            is_all_day INTEGER NOT NULL DEFAULT 0,
            recurrence_rule TEXT NOT NULL DEFAULT '',
            image_file_name TEXT,
            reminder_offsets TEXT NOT NULL DEFAULT '0',
            last_modified REAL NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_events_start_date ON events(start_date);
        """
        execute(sql)
        migrateAddColumnIfNeeded(name: "image_file_name", definition: "TEXT")
        migrateAddColumnIfNeeded(name: "reminder_offsets", definition: "TEXT NOT NULL DEFAULT '0'")
    }

    /// Existing installs created before a given column existed won't have it
    /// (CREATE TABLE IF NOT EXISTS is a no-op on an already-existing table),
    /// so add it if missing. Used for both image_file_name and, more
    /// recently, reminder_offsets — see the multi-reminder feature.
    private func migrateAddColumnIfNeeded(name: String, definition: String) {
        let columns = query("PRAGMA table_info(events)")
        let hasColumn = columns.contains { ($0["name"] as? String) == name }
        if !hasColumn {
            execute("ALTER TABLE events ADD COLUMN \(name) \(definition)")
        }
    }

    @discardableResult
    func execute(_ sql: String) -> Bool {
        dbQueue.sync {
            var errMsg: UnsafeMutablePointer<Int8>?
            let result = sqlite3_exec(db, sql, nil, nil, &errMsg)
            if result != SQLITE_OK {
                let message = errMsg.map { String(cString: $0) } ?? "unknown error"
                #if DEBUG
                print("SQLite error: \(message)")
                #endif
                sqlite3_free(errMsg)
                return false
            }
            return true
        }
    }

    /// Runs a prepared statement, binding parameters, and returns rows as [[String: Any]]
    func query(_ sql: String, bindings: [Any?] = []) -> [[String: Any]] {
        dbQueue.sync {
            var statement: OpaquePointer?
            var rows: [[String: Any]] = []
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                #if DEBUG
                print("Failed to prepare query: \(sql)")
                #endif
                return rows
            }
            defer { sqlite3_finalize(statement) }
            bind(bindings, to: statement)

            while sqlite3_step(statement) == SQLITE_ROW {
                var row: [String: Any] = [:]
                let columnCount = sqlite3_column_count(statement)
                for i in 0..<columnCount {
                    let name = String(cString: sqlite3_column_name(statement, i))
                    row[name] = columnValue(statement, index: i)
                }
                rows.append(row)
            }
            return rows
        }
    }

    /// Runs an INSERT/UPDATE/DELETE with bound parameters. Returns last inserted rowid for INSERTs.
    @discardableResult
    func run(_ sql: String, bindings: [Any?] = []) -> Int64 {
        dbQueue.sync {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                #if DEBUG
                print("Failed to prepare statement: \(sql)")
                #endif
                return -1
            }
            defer { sqlite3_finalize(statement) }
            bind(bindings, to: statement)

            if sqlite3_step(statement) != SQLITE_DONE {
                #if DEBUG
                print("Failed to execute statement: \(String(cString: sqlite3_errmsg(db)))")
                #endif
                return -1
            }
            return sqlite3_last_insert_rowid(db)
        }
    }

    // MARK: - Binding / reading helpers

    private func bind(_ bindings: [Any?], to statement: OpaquePointer?) {
        for (index, value) in bindings.enumerated() {
            let i = Int32(index + 1)
            switch value {
            case let v as Int64:
                sqlite3_bind_int64(statement, i, v)
            case let v as Int:
                sqlite3_bind_int64(statement, i, Int64(v))
            case let v as Double:
                sqlite3_bind_double(statement, i, v)
            case let v as String:
                sqlite3_bind_text(statement, i, v, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            case is NSNull, nil:
                sqlite3_bind_null(statement, i)
            default:
                sqlite3_bind_null(statement, i)
            }
        }
    }

    private func columnValue(_ statement: OpaquePointer?, index: Int32) -> Any {
        switch sqlite3_column_type(statement, index) {
        case SQLITE_INTEGER: return sqlite3_column_int64(statement, index)
        case SQLITE_FLOAT: return sqlite3_column_double(statement, index)
        case SQLITE_TEXT: return String(cString: sqlite3_column_text(statement, index))
        default: return NSNull()
        }
    }
}
