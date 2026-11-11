const std = @import("std");
const zqlite = @import("zqlite");
const sqlcipher = @import("../lib/sqlcipher.zig");
const Conn = zqlite.Conn;
const Allocator = std.mem.Allocator;
const types = @import("../types.zig");
const Row = types.Row;
const Errors = types.Errors;
const e = types.Db_Errors;
const testing = std.testing;
const SQLITE_OK = sqlcipher.SQLITE_OK;
const SQLITE_DONE = sqlcipher.SQLITE_DONE;
const SQLITE_ROW = sqlcipher.SQLITE_ROW;

pub const Db = struct {
    conn: *sqlcipher.struct_sqlite3,
    pw_table_name: []const u8 = "pw",

    pub fn connect(path: [*:0]const u8) !Db {
        // fn sqlite3_open(filename: [*c]const u8, ppDb: [*c]?*struct_sqlite3) c_int
        std.log.debug("{s}\n", .{path});
        var _conn: ?*sqlcipher.struct_sqlite3 = null;
        // const flags = zqlite.OpenFlags.Create | zqlite.OpenFlags.EXResCode;
        // var _conn = try zqlite.open(path, flags);
        if (sqlcipher.sqlite3_open(path, &_conn) != sqlcipher.SQLITE_OK) {
            return e.DatabaseOpenFailed;
        }
        const conn = _conn orelse return e.DatabaseOpenFailed;
        errdefer _ = sqlcipher.sqlite3_close(conn);
        return .{ .conn = conn };
    }

    pub fn deinit(self: *Db) !void {
        if (self.conn.close() != SQLITE_OK) {
            return e.CloseError;
        }
    }

    pub fn key_check(self: *Db, key: *const anyopaque, kLen: usize) !void {
        // https://sqlite.org/com/see.html
        // check just after the connection
        const result = sqlcipher.sqlite3_key(self.conn, key, @intCast(kLen));
        switch (result) {
            SQLITE_OK => return,
            else => {
                std.debug.print("Passpharse Error: {s}\n", .{sqlcipher.sqlite3_errmsg(self.conn)});
                return e.InvalidPassphrase;
            },
        }
    }

    pub fn initilize_pw_db(self: *Db, allocator: Allocator, name: ?[]const u8) !void {
        const acutal_pw_name = name orelse "pw";
        const query = try std.fmt.allocPrintSentinel(
            allocator,
            \\CREATE TABLE IF NOT EXISTS "{s}" (
            \\    id INTEGER PRIMARY KEY,
            \\    username TEXT NOT NULL,
            \\    password TEXT NOT NULL
            \\)
        ,
            .{acutal_pw_name},
            0,
        );
        defer allocator.free(query);
        const result = self.conn.exec(query.ptr, null, null, null);
        if (result != sqlcipher.SQLITE_OK) {
            std.debug.print("SQL error: {s}\n", .{sqlcipher.sqlite3_errmsg(self.conn)});
            return e.DatabaseOpenFailed;
        }
        self.pw_table_name = acutal_pw_name;
    }

    pub fn insert_pw(self: *Db, allocator: Allocator, k: [:0]const u8, v: [:0]const u8) !void {
        //https://www.sqlite.org/c3ref/stmt.html
        // as c accepts 0 terminated slice
        const query: [:0]const u8 = try std.fmt.allocPrintSentinel(
            allocator,
            "INSERT INTO {s} (username, password) VALUES (?1, ?2)",
            .{self.pw_table_name},
            0,
        );
        defer allocator.free(query);

        // prepare statement
        var _ppStmt: ?*sqlcipher.struct_sqlite3_stmt = null;

        //https://www.sqlite.org/c3ref/prepare.html
        // run the prepare statement

        // we have put -1 in the place of len nBytes
        // as docs mentions that if negative then it will be the length to 0 terminated string
        const ppre = sqlcipher.sqlite3_prepare(self.conn, query.ptr, -1, &_ppStmt, null);
        if (ppre != SQLITE_OK) {
            return e.PrepareFailed;
        }
        defer _ = sqlcipher.sqlite3_finalize(_ppStmt);
        //bind text
        //https://sqlite.org/c3ref/bind_blob.html
        // username / email / something to assign to
        if (sqlcipher.sqlite3_bind_text(_ppStmt, 1, k.ptr, -1, null) != SQLITE_OK) {
            return e.BindFailed;
        }
        // password
        if (sqlcipher.sqlite3_bind_text(_ppStmt, 2, v.ptr, -1, null) != SQLITE_OK) {
            return e.BindFailed;
        }
        if (sqlcipher.sqlite3_step(_ppStmt) != SQLITE_DONE) {
            return e.InsertFailed;
        }
    }

    pub fn get_pw(self: *Db, allocator: Allocator, k: [:0]const u8) !?[]const u8 {
        const query: [:0]const u8 = try std.fmt.allocPrintSentinel(allocator, "SELECT password FROM \"{s}\" WHERE username = ?1", .{self.pw_table_name}, 0);
        defer allocator.free(query);
        var _ppStmt: ?*sqlcipher.struct_sqlite3_stmt = null;
        // prepare
        const ppre = sqlcipher.sqlite3_prepare(self.conn, query.ptr, -1, &_ppStmt, null);
        if (ppre != SQLITE_OK) {
            return e.PrepareFailed;
        }
        defer _ = sqlcipher.sqlite3_finalize(_ppStmt);

        if (sqlcipher.sqlite3_bind_text(_ppStmt, 1, k, -1, sqlcipher.SQLITE_STATIC) != SQLITE_OK) {
            return e.BindFailed;
        }

        var c: ?[]const u8 = null;
        while (true) {
            const result = sqlcipher.sqlite3_step(_ppStmt);
            switch (result) {
                SQLITE_ROW => {
                    const t = sqlcipher.sqlite3_column_text(_ppStmt, 0) orelse return e.NullPointer;
                    c = try allocator.dupe(u8, std.mem.span(t));
                    break;
                },
                SQLITE_DONE => break,
                else => {
                    return e.GetFailed;
                },
            }
        }
        return c;
    }

    pub fn list_pw(self: *Db, allocator: Allocator) ![]Row {
        const query: [:0]const u8 = try std.fmt.allocPrintSentinel(allocator, "SELECT * FROM \"{s}\"", .{self.pw_table_name}, 0);
        defer allocator.free(query);

        var _ppStmt: ?*sqlcipher.struct_sqlite3_stmt = null;
        const ppre = sqlcipher.sqlite3_prepare(self.conn, query.ptr, -1, &_ppStmt, null);
        if (ppre != SQLITE_OK) {
            return e.PrepareFailed;
        }
        defer _ = sqlcipher.sqlite3_finalize(_ppStmt);

        var rows: std.ArrayList(Row) = .empty;
        defer rows.deinit(allocator);

        while (true) {
            const result = sqlcipher.sqlite3_step(_ppStmt);
            switch (result) {
                SQLITE_ROW => {
                    const p = sqlcipher.sqlite3_column_text(_ppStmt, 2) orelse return e.NullPointer;
                    const u = sqlcipher.sqlite3_column_text(_ppStmt, 1) orelse return e.NullPointer;
                    try rows.append(
                        allocator,
                        .{
                            .password = try allocator.dupe(u8, std.mem.span(p)),
                            .username = try allocator.dupe(u8, std.mem.span(u)),
                        },
                    );
                    break;
                },
                SQLITE_DONE => break,
                else => {
                    return e.GetFailed;
                },
            }
        }

        return rows.toOwnedSlice(allocator);
    }
    pub fn remove_row_with_username(self: *Db, allocator: Allocator, u: [:0]const u8) !void {
        const query: [:0]const u8 = try std.fmt.allocPrintSentinel(allocator, "DELETE FROM \"{s}\" WHERE username = ?1", .{self.pw_table_name}, 0);
        defer allocator.free(query);

        var _ppStmt: ?*sqlcipher.struct_sqlite3_stmt = null;
        const ppre = sqlcipher.sqlite3_prepare(self.conn, query.ptr, -1, &_ppStmt, null);
        if (ppre != SQLITE_OK) {
            return e.PrepareFailed;
        }
        defer _ = sqlcipher.sqlite3_finalize(_ppStmt);

        if (sqlcipher.sqlite3_bind_text(_ppStmt, 1, u, -1, sqlcipher.SQLITE_STATIC) != SQLITE_OK) {
            return e.BindFailed;
        }

        if (sqlcipher.sqlite3_step(_ppStmt) != SQLITE_DONE) {
            return e.DeletionFailed;
        }
    }
};

fn db_tear_down(io: std.Io) !void {
    const cwd = std.Io.Dir.cwd();
    try cwd.deleteFile(io, std.mem.span(types.test_db_name));
}
fn test_connect(allocator: Allocator) !Db {
    var db = try Db.connect(types.test_db_name);
    _ = try db.initilize_pw_db(allocator, "test");
    return db;
}

test "TC-01" {
    const io = testing.io;
    const allocator = testing.allocator;
    var db = try Db.connect(types.test_db_name);
    const t = try db.initilize_pw_db(allocator, "test");
    try testing.expect(@TypeOf(t) == void);
    // for tear down of the db
    try db_tear_down(io);
}

test "TC-02" {
    // const io = testing.io;
    const allocator = testing.allocator;
    var db = try test_connect(allocator);
    const u: [:0]const u8 = try allocator.dupeSentinel(u8, "k1", 0);
    const p: [:0]const u8 = try allocator.dupeSentinel(u8, "p1", 0);
    defer allocator.free(u);
    defer allocator.free(p);
    const ret = try db.insert_pw(allocator, u, p);
    try testing.expect(@TypeOf(ret) == void);
}

test "TC-03" {
    // const io = testing.io;
    const allocator = testing.allocator;
    var db = try test_connect(allocator);
    const u: [:0]const u8 = try allocator.dupeSentinel(u8, "k1", 0);
    defer allocator.free(u);
    const ret = try db.get_pw(allocator, u);
    defer if (ret) |pw| allocator.free(pw);
    try testing.expect(ret != null);
    try testing.expectEqualStrings("p1", ret.?);
}

test "TC-04" {
    // const io = testing.io;
    const allocator = testing.allocator;
    var db = try test_connect(allocator);
    const u: [:0]const u8 = try allocator.dupeSentinel(u8, "k2", 0);
    defer allocator.free(u);
    const ret = try db.get_pw(allocator, u);
    try testing.expect(ret == null);
}

test "TC-05" {
    // const io = testing.io;
    const allocator = testing.allocator;
    var db = try test_connect(allocator);
    const ret = try db.list_pw(allocator);
    defer {
        for (0..ret.len) |i| {
            const r = ret[i];
            if (r.password) |p| allocator.free(p);
            if (r.username) |u| allocator.free(u);
        }
        allocator.free(ret);
    }

    for (0..ret.len) |i| {
        const r = ret[i];
        try testing.expectEqualStrings("p1", r.password.?);
        try testing.expectEqualStrings("k1", r.username.?);
    }
}

test "TC-06" {
    const io = testing.io;
    const allocator = testing.allocator;
    var db = try test_connect(allocator);
    const u: [:0]const u8 = try allocator.dupeSentinel(u8, "k1", 0);
    defer allocator.free(u);
    const ret = try db.remove_row_with_username(allocator, u);
    try testing.expect(@TypeOf(ret) == void);
    try db_tear_down(io);
}
