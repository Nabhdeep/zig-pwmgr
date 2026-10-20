const std = @import("std");
const zqlite = @import("zqlite");
const Conn = zqlite.Conn;
const Allocator = std.mem.Allocator;
pub const Db = struct {
    conn: Conn,
    pw_table_name: []const u8 = "pw",

    pub fn connect(path: [*:0]const u8) !Db {
        const flags = zqlite.OpenFlags.Create | zqlite.OpenFlags.EXResCode;
        var _conn = try zqlite.open(path, flags);
        errdefer _conn.close();
        return .{ .conn = _conn };
    }

    pub fn deinit(self: *Db) void {
        self.conn.close();
    }

    pub fn initilize_pw_db(self: *Db, allocator: Allocator, name: ?[]const u8) !void {
        const acutal_pw_name = name orelse "pw";
        const query = try std.fmt.allocPrint(
            allocator,
            \\CREATE TABLE IF NOT EXISTS "{s}" (
            \\    id INTEGER PRIMARY KEY,
            \\    username TEXT NOT NULL,
            \\    password TEXT NOT NULL
            \\)
        ,
            .{acutal_pw_name},
        );
        defer allocator.free(query);
        try self.conn.exec(query, .{});
        self.pw_table_name = acutal_pw_name;
    }

    pub fn insert_pw(self: *Db, allocator: Allocator, k: []const u8, v: []const u8) !void {
        const query: []const u8 = try std.fmt.allocPrint(allocator, "INSERT INTO {s} (username, password) VALUES (?1, ?2)", .{self.pw_table_name});
        defer allocator.free(query);
        try self.conn.exec(query, .{ k, v });
    }

    pub fn get_pw(self: *Db, allocator: Allocator, k: []const u8) !?[]const u8 {
        const query: []const u8 = try std.fmt.allocPrint(allocator, "SELECT password FROM \"{s}\" WHERE username = ?1", .{self.pw_table_name});
        defer allocator.free(query);
        const _r = try self.conn.row(query, .{k});
        if (_r) |row| {
            return row.text(0);
        }
        return null;
    }
};
