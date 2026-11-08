const std = @import("std");
const args_parser = @import("args");
const sqlite = @import("services/sql.zig");
const builtin = @import("builtin");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const encrypt = @import("encrypt.zig");
const print = std.debug.print;
const stdout = std.Io.File.stdout().writeStreamingAll;
const types = @import("types.zig");
const Cred = struct { username: ?[]const u8 = null, password: ?[]const u8 = null };
const testing = std.testing;
const expect = testing.expect;
const Errors = types.Errors;

pub fn parse_args_v2(init: std.process.Init) types.diceware_args {
    const options = args_parser.parseForCurrentProcess(types.diceware_args, init, .print) catch return types.diceware_args{};
    defer options.deinit();
    return options.options;
}

pub fn parse_args_v3(init: std.process.Init) !?types.Verbs {
    const options = args_parser.parseWithVerbForCurrentProcess(types.Options, types.Verbs, init, .print) catch return error.Error_Parsing_Args;
    return options.verb;
}

// Returns a AutoHashMap which we would have to deinitlize
pub fn load_word_list(allocator: Allocator, io: Io, fileName: []const u8) !std.AutoHashMap(u32, []const u8) {
    const file = try std.Io.Dir.openFile(std.Io.Dir.cwd(), io, fileName, .{});
    defer file.close(io);
    //buffer to load the list
    const buf = try allocator.alloc(u8, 4096);

    // buffer free after loading the list is done
    defer allocator.free(buf);

    var reader = file.reader(io, buf);
    var map = std.AutoHashMap(u32, []const u8).init(allocator);
    var line_no: usize = 0;
    while (try reader.interface.takeDelimiter('\n')) |line| {
        line_no += 1;
        var w = std.mem.splitAny(u8, line, "\t");
        const index = try std.fmt.parseInt(u32, w.next().?, 10);
        const word = try allocator.dupe(u8, w.next().?);
        try map.put(index, word);
    }
    return map;
}

pub fn generate_diceware_password(allocator: Allocator, io: Io, cli_args: types.diceware_args) !std.ArrayList([]const u8) {
    const file = try std.Io.Dir.openFile(std.Io.Dir.cwd(), io, types.word_list, .{});
    defer file.close(io);

    var map = try load_word_list(allocator, io, types.word_list);
    defer {
        var it = map.valueIterator();
        while (it.next()) |ele| allocator.free(ele.*);
        map.deinit();
    }

    var arrayList: std.ArrayList([]const u8) = .empty;
    errdefer arrayList.deinit(allocator);

    for (0..cli_args.number_words) |_| {
        const randomNum = generateRandonNumber(io);

        const p = map.get(randomNum) orelse {
            std.log.err("{d}", .{randomNum});
            return error.NumberInvalid;
        };
        try arrayList.append(allocator, try allocator.dupe(u8, p));
    }
    return arrayList;
}

pub fn password_generator(io: Io, buff: []u8) !void {
    if (buff.len > 255) return Errors.PASSWORD_LENGTH_NOT_ALLOWED;
    const all = types.lower ++ types.special ++ types.digits ++ types.upper;
    for (buff) |*char| {
        const random_number = generateRandonNumber(io);
        char.* = all[random_number % all.len];
    }
}

test "TC-01 check password generator" {
    var test_allocator = std.testing.allocator;
    const test_io = std.testing.io;
    const test_pwd_length: usize = 10;
    const buff = try test_allocator.alloc(u8, test_pwd_length);
    try password_generator(test_io, buff);
    test_allocator.free(buff);
    const comp = buff.len;
    try testing.expectEqual(@as(usize, test_pwd_length), comp);
}

test "TC-02 check password generator zero length 0" {
    var test_allocator = std.testing.allocator;
    const test_io = std.testing.io;
    const test_pwd_length: usize = 0;
    const buff = try test_allocator.alloc(u8, test_pwd_length);
    try password_generator(test_io, buff);
    test_allocator.free(buff);
    const comp = buff.len;
    try testing.expectEqual(@as(usize, test_pwd_length), comp);
}

test "TC-03 check password generator zero length > 255" {
    var test_allocator = std.testing.allocator;
    const test_io = std.testing.io;
    const test_pwd_length: usize = 256;
    const buff = try test_allocator.alloc(u8, test_pwd_length);
    defer test_allocator.free(buff);
    try testing.expectError(Errors.PASSWORD_LENGTH_NOT_ALLOWED, password_generator(test_io, buff));
}

pub fn print_password(array_list: std.ArrayList([]const u8), arguments: types.diceware_args) void {
    for (array_list.items) |j| {
        print("{s}", .{j});
        if (array_list.getLast().ptr != j.ptr) {
            print("{s}", .{arguments.separator});
        }
    }
}

pub fn std_print(io: Io, comptime fmt: []const u8, args: anytype) !void {
    var std_buff: [1024]u8 = undefined;
    var std_writer = std.Io.File.stdout().writer(io, &std_buff);
    const std_out = &std_writer.interface;
    try std_out.print(fmt, args);
    try std_out.flush();
}

pub fn std_err(io: Io, comptime fmt: []const u8, args: anytype) !void {
    var std_buff: [1024]u8 = undefined;
    var std_writer = std.Io.File.stderr().writer(io, &std_buff);
    const std_out = &std_writer.interface;
    try std_out.print(fmt, args);
    try std_out.flush();
}
pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const arguments = parse_args_v3(init) catch |err| {
        try std_err(io, "Failed to parse arguments: {s}\n", .{@errorName(err)});
        return;
    } orelse {
        try std_err(io, "No arguments provided. Need help? --help\n", .{});
        return;
    };
    std.log.debug("{any}", .{arguments});

    // allocator
    const allocator = init.gpa;
    // initilize db
    var _conn = try sqlite.Db.connect(types.db_name);
    try _conn.initilize_pw_db(allocator, null);
    defer _conn.deinit();

    switch (arguments) {
        .generate => |opts| {
            if (opts.password) {
                // only generate password and displays on the screen
                const buff = try allocator.alloc(u8, opts.l);
                defer allocator.free(buff);
                password_generator(io, buff) catch |err| {
                    switch (err) {
                        Errors.PASSWORD_LENGTH_NOT_ALLOWED => {
                            try std_err(io, "{s} Must be less than 256\n", .{@errorName(err)});
                        },
                        else => {
                            try std_err(io, "UNKWN ERR: {s}\n", .{@errorName(err)});
                        },
                    }
                    return;
                };
                try std_print(io, "Password: {s}", .{buff});
                return;
            }
            if (opts.vault) {}
        },
        // else => |i| {
        //     try std_print(io, "[TODO] {any}", .{i});
        // },
        .get => |opts| {
            if (opts.username.len > 0) {
                // gets the password by username
                get_password_copy_to_clipboard(allocator, &_conn, io, opts.username) catch |err| {
                    switch (err) {
                        Errors.USERNAME_NOT_FOUND => {
                            try std_err(io, "{s}\n", .{@errorName(err)});
                        },
                        else => {
                            try std_err(io, "UKNOWN GET PWD ERROR: {s}\n", .{@errorName(err)});
                        },
                    }
                };
            }
            // if (opts.vault) {}
        },
        .list => |otps| {
            if (otps.passwords) {
                const rows: []types.Row = try list_password(allocator, &_conn);
                defer {
                    for (rows) |row| {
                        if (row.username) |username| allocator.free(username);
                        if (row.password) |password| allocator.free(password);
                    }
                    allocator.free(rows);
                }
                for (0..rows.len) |idx| {
                    const r = rows[idx];
                    const u = r.username orelse continue;
                    const p = r.password orelse continue;
                    try std_print(io, "{s} ---> {s}\n", .{ u, p });
                }
            }
            // if (otps.vault) {}
        },
        .set => |otps| {
            const p = otps.password orelse return Errors.INVALID_PASSWORD;
            const u = otps.username orelse return Errors.INVALID_USERNAME;
            try insert_password(allocator, &_conn, u, p);
            // if (otps.vault) {}
        },
        .del => |opts| {
            const u = opts.username orelse {
                try std_err(io, "Invalid username", .{});
                return;
            };
            try _conn.remove_row_with_username(allocator, u);
        },
    }
}

fn generateRandonNumber(io: Io) u32 {
    const source: std.Random.IoSource = .{ .io = io };
    const random = source.interface();
    var i: u8 = 0;
    var randomNumber: u32 = 0;
    while (i < 5) {
        const roll = random.intRangeAtMost(u8, 1, 6);
        randomNumber = randomNumber * 10 + roll;
        i += 1;
    }
    return randomNumber;
}

fn list_password(allocator: Allocator, _conn: *sqlite.Db) ![]types.Row {
    const rows = try _conn.list_pw(allocator);
    return rows;
}

fn get_password_copy_to_clipboard(allocator: Allocator, _conn: *sqlite.Db, io: Io, username: []const u8) !void {
    const _pw = try _conn.get_pw(allocator, username);
    if (_pw) |_p| {
        try copyToClipboard(io, _p);
        return;
    }
    return Errors.USERNAME_NOT_FOUND;
}

fn insert_password(allocator: Allocator, _conn: *sqlite.Db, u: []const u8, p: []const u8) !void {
    try _conn.insert_pw(allocator, u, p);
}

pub fn copyToClipboard(io: Io, text: []const u8) !void {
    const argv = switch (builtin.os.tag) {
        .macos => &.{"pbcopy"},
        .linux => &.{ "xclip", "-selection", "clipboard" },
        else => return error.UnsupportedOperatingSystem,
    };

    // Initialize the child process
    var child = try std.process.spawn(io, .{ .argv = argv, .stdin = .pipe, .stderr = .inherit, .stdout = .inherit });
    var writer = child.stdin.?.writer(io, &.{});

    // creates a writer
    try writer.interface.writeAll(text);
    // closes the stdin
    child.stdin.?.close(io);

    // sets null so that its not available
    child.stdin = null;

    // waiting it to get completed
    const term = try child.wait(io);

    // Check if the process exited with an error
    switch (term) {
        .exited => |code| if (code != 0) return error.ClipboardCommandFailed,
        else => return error.ClipboardCommandInterrupted,
    }
}
