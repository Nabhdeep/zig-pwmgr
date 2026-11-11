const std = @import("std");
const args_parser = @import("args");
// const sqlite = @import("services/sql.zig");
const builtin = @import("builtin");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const print = std.debug.print;
const stdout = std.Io.File.stdout().writeStreamingAll;
const types = @import("types.zig");
const Cred = struct { username: ?[]const u8 = null, password: ?[]const u8 = null };
const testing = std.testing;
const expect = testing.expect;
const Errors = types.Errors;
const zigini = @import("zigini");
const Config = @import("Config.zig").Config;
const encrypt = @import("encrypt.zig");
const sqlC = @import("./services/sqlC.zig");
const toml = @import("toml");
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
pub fn std_in(allocator: Allocator, io: Io, question: []const u8) ![]u8 {
    var in_buff: [1024]u8 = undefined;
    var in_reader = std.Io.File.reader(.stdin(), io, &in_buff);
    try std_print(io, "{s}", .{question});
    const line = try in_reader.interface.takeDelimiter('\n') orelse return "";
    std.log.debug("In line: {s}", .{line});
    return allocator.dupe(u8, line);
}

pub fn ask_password(allocator: Allocator, io: Io, buff: []u8) !usize {
    const _key = try std_in(allocator, io, "Passphrase: ");
    defer allocator.free(_key);
    @memcpy(buff[0.._key.len], _key);
    return _key.len;
}

// test "TC_01: check ask_password " {
//     const allocator = testing.allocator;
//     const io = testing.io;
//     var buff: [256]u8 = undefined;
//     const p_zi = try ask_password(allocator, io, &buff);
//     try testing.expectEqualStrings("password", buff[0..p_zi]);
// }

pub fn get_basr_dir(init: std.process.Init) !?[]const u8 {
    const config_dir = init.environ_map.get("XDG_DATA_HOME") orelse fallback: {
        const p = init.environ_map.get("HOME") orelse {
            try std_err(init.io, "Unbale to get home dir\n", .{});
            return null;
        };
        const path = try std.fs.path.join(
            init.gpa,
            &.{ p, ".local", "share" },
        );
        break :fallback path;
    };

    return config_dir;
}

pub fn get_config(init: std.process.Init) !toml.Parsed(Config) {
    var parser = toml.Parser(Config).init(init.gpa);
    defer parser.deinit();
    const config_dir = try get_basr_dir(init) orelse {
        return Errors.CofigPathFailed;
    };
    defer init.gpa.free(config_dir);
    const file_path = try std.fs.path.join(
        init.gpa,
        &.{ config_dir, "pwmgr", "config.toml" },
    );
    defer init.gpa.free(file_path);
    std.log.debug("Base Config path: {s}\n", .{file_path});
    return parser.parseFile(init.io, file_path);
}
// for now using  toml file which is parsed
// TODO: Statefull password so that its not asked multiple times
// TODO: Create config file and config flow
// TODO: check for null config
pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const allocator = init.gpa;
    const arguments = parse_args_v3(init) catch |err| {
        try std_err(io, "Failed to parse arguments: {s}\n", .{@errorName(err)});
        return;
    } orelse {
        try std_err(io, "No arguments provided. Need help? --help\n", .{});
        return;
    };
    std.log.debug("Args: {any}", .{arguments});
    // config home
    const parsed = try get_config(init);
    const config = parsed.value;
    defer parsed.deinit();
    std.log.debug("BaseDir: {any}", .{config});
    // allocator
    // initilize db
    const cg = try std.fmt.allocPrintSentinel(allocator, "{s}/newdb.sqlite", .{config.base_dir}, 0);
    defer allocator.free(cg);

    // DB connection
    var _conn = try sqlC.Db.connect(cg);

    var passphrase_buff: [256]u8 = undefined;
    defer @memset(&passphrase_buff, 0);

    const passphrase_len = try ask_password(allocator, io, &passphrase_buff);

    const passphrase = passphrase_buff[0..passphrase_len];
    try _conn.key_check(passphrase.ptr, passphrase.len);

    try _conn.initilize_pw_db(allocator, null);
    defer {
        _ = _conn.deinit() catch {
            std.log.err("DB Close Error:\n", .{});
        };
    }

    switch (arguments) {
        .generate => |opts| {
            if (opts.password) {
                // only generate password and displays on the screen
                const buff = try allocator.alloc(u8, opts.l);
                defer allocator.free(buff);
                // password is saved in buff
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

                if (opts.save) {
                    const line = try std_in(allocator, io, "Username: ");
                    defer allocator.free(line);
                    if (line.len == 0) return Errors.INVALID_USERNAME;
                    try insert_password(allocator, &_conn, line, buff);
                    return;
                } else {
                    try std_print(io, "{s}", .{buff});
                }
                return;
            }
        },
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
            if (otps.vault) {
                try list_vault(allocator, io, config.base_dir);
            }
        },
        .set => |otps| {
            user_pw: {
                const p = otps.password orelse break :user_pw;
                const u = otps.username orelse break :user_pw;
                try insert_password(allocator, &_conn, u, p);
            }
            // vault: {
            //     const v = otps.vault orelse break :vault;
            // }
            // if (otps.vault) {}
        },
        .del => |opts| {
            username: {
                const u = opts.username orelse break :username;
                const _u = try get_sentinel_string(allocator, u);
                defer allocator.free(_u);
                try _conn.remove_row_with_username(allocator, _u);
            }

            vault: {
                const vault_name = opts.vault orelse break :vault;
                delete_vault(allocator, io, vault_name, config.base_dir) catch |err| {
                    switch (err) {
                        error.FileNotFound => {
                            try std_err(io, "File not found\n", .{});
                        },
                        else => {
                            try std_err(io, "Unkown del error: {s}\n", .{@errorName(err)});
                        },
                    }
                };
            }
        },
        .init => |opts| {
            vault: {
                const value_name = opts.vault orelse break :vault;
                create_vault(allocator, io, value_name, config.base_dir) catch |err| switch (err) {
                    error.PathAlreadyExists => {
                        try std_err(io, "Vault Already exist\n", .{});
                        return;
                    },
                    else => {
                        try std_err(io, "Create Vault Error: {s}\n", .{@errorName(err)});
                        return;
                    },
                };
                try create_config_file(allocator, io, "config", config.base_dir);
            }
            // switch (opts) {
            //     .vault => |v| {
            //         std.log.debug("Vault: {v}", .{v.vault.n});
            //         // try create_vault(allocator, io, v, config_dir);
            //     },
            // }
        },
    }
}

fn create_config_file(allocator: Allocator, io: Io, config_file_name: []const u8, base_dir: []const u8) !void {
    return create_file(allocator, io, base_dir, config_file_name, ".ini");
}

fn read_config(allocator: Allocator, io: Io, path: []const u8) !void {
    const pwmgr_config_reader = zigini.Ini(Config).init(allocator);
    defer pwmgr_config_reader.deinit();
    _ = try pwmgr_config_reader.readFileToStruct(io, path, .{});
}

fn input_value_config_file(allocator: Allocator, io: Io, path: []const u8, update: Config) !void {
    const pwmgr_config_reader = zigini.Ini(Config).init(allocator);
    defer pwmgr_config_reader.deinit();
    const config = try pwmgr_config_reader.readFileToStruct(io, path, .{});
    var std_buff: [1024]u8 = undefined;
    var std_writer = std.Io.File.stdout().writer(io, &std_buff);
    const std_out = &std_writer.interface;
    if (update.vault_name.len > 0) {
        config.vault_name = update.vault_name;
    } else {
        return;
    }
    try zigini.writeFromStruct(config, std_out, null, .{});
    return;
}

fn create_file(allocator: Allocator, io: Io, base_dir: []const u8, name: []const u8, ext: []const u8) !void {
    const cwd = std.Io.Dir.cwd();

    const file_name = try std.mem.concat(allocator, u8, &.{ name, ext });
    defer allocator.free(file_name);

    const full_path_and_file = try std.fs.path.join(allocator, &.{ base_dir, file_name });
    defer allocator.free(full_path_and_file);

    std.log.warn("{s}", .{base_dir});
    try cwd.createDirPath(io, base_dir);
    _ = try cwd.createFile(io, full_path_and_file, .{ .exclusive = true });
    return;
}

fn create_vault(allocator: Allocator, io: Io, name: []const u8, base_dir: []const u8) !void {
    return create_file(allocator, io, base_dir, name, ".sqlite");
}

fn list_vault(allocator: Allocator, io: Io, base_dir: []const u8) !void {
    const full_path = try std.fs.path.join(allocator, &.{ base_dir, types.Name });
    defer allocator.free(full_path);

    const dir = try std.Io.Dir.cwd().openDir(io, full_path, .{ .iterate = true });
    defer dir.close(io);

    var walker = try dir.walk(allocator);
    defer walker.deinit();
    while (try walker.next(io)) |w| {
        if (w.kind == .file and std.mem.endsWith(u8, w.basename, ".sqlite")) {
            try std_print(io, "{d}: {s}\n", .{ w.depth(), w.basename[0 .. w.basename.len - 7] });
        }
    }
}

fn delete_vault(allocator: Allocator, io: Io, name: []const u8, base_dir: []const u8) !void {
    const file_name = try std.mem.concat(allocator, u8, &.{ name, ".sqlite" });
    defer allocator.free(file_name);

    const dir = try std.Io.Dir.cwd().openDir(io, base_dir, .{ .iterate = true });
    defer dir.close(io);

    const delete_path = try std.fs.path.join(allocator, &.{ base_dir, file_name });
    defer allocator.free(delete_path);
    try dir.deleteFile(io, delete_path);
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

fn list_password(allocator: Allocator, _conn: *sqlC.Db) ![]types.Row {
    const rows = try _conn.list_pw(allocator);
    return rows;
}

fn get_password_copy_to_clipboard(allocator: Allocator, _conn: *sqlC.Db, io: Io, username: []const u8) !void {
    const _u = try get_sentinel_string(allocator, username);
    defer allocator.free(_u);
    const _pw = try _conn.get_pw(allocator, _u) orelse return Errors.USERNAME_NOT_FOUND;
    defer allocator.free(_pw);
    try copyToClipboard(io, _pw);
    return;
}

fn insert_password(allocator: Allocator, _conn: *sqlC.Db, u: []const u8, p: []const u8) !void {
    const _u = try get_sentinel_string(allocator, u);
    const _p = try get_sentinel_string(allocator, p);
    defer {
        allocator.free(_u);
        allocator.free(_p);
    }
    try _conn.insert_pw(allocator, _u, _p);
}

fn get_sentinel_string(allocator: Allocator, u: []const u8) ![:0]const u8 {
    return allocator.dupeSentinel(u8, u, 0);
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
