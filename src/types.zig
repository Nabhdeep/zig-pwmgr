pub const Name = "pwmgr";
pub const Row = struct { username: ?[]const u8, password: ?[]const u8 };

pub const lower: []const u8 = &[_]u8{ 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z' };

pub const upper: []const u8 = &[_]u8{ 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z' };

pub const digits: []const u8 = &[_]u8{ '0', '1', '2', '3', '4', '5', '6', '7', '8', '9' };

pub const special: []const u8 = &[_]u8{ '!', '@', '#', '$', '%', '^', '&', '*', '(', ')' };

pub const db_name: [*:0]const u8 = "data/pw.sqlite";
pub const test_db_name: [*:0]const u8 = "data/test.sqlite";
pub const diceware_args = struct { separator: []const u8 = "", generate: bool = false, username: []const u8 = "", value: []const u8 = "", vault: []const u8 = "", get: ?[]const u8 = null, diceware: bool = false, list: bool = false, number_words: usize = 6 };
pub const word_list: []const u8 = "dicewarelist.txt";
pub const Verbs = union(enum) {
    init: struct { vault: ?[]const u8 = null },
    generate: struct { password: bool = false, l: usize = 6, save: bool = false },
    list: struct { vault: bool = false, usernames: bool = false, passwords: bool = false },
    get: struct { username: []const u8 = "", vault: []const u8 = "" },
    set: struct { username: ?[]const u8 = null, password: ?[]const u8 = null, vault: ?[]const u8 = null },
    del: struct { username: ?[]const u8 = null, vault: ?[]const u8 = null },
};

pub const Options = struct {
    output: ?[]const u8 = null,
    pub const shorthands = .{
        .o = "output",
    };
};

pub const Errors = error{
    PASSWORD_LENGTH_NOT_ALLOWED,
    USERNAME_NOT_FOUND,
    INVALID_PASSWORD,
    INVALID_USERNAME,
    DATABASEOPENFAILED,
};
pub const Db_Errors = error{
    DatabaseOpenFailed,
    PrepareFailed,
    BindFailed,
    InsertFailed,
    GetFailed,
    NullPointer,
    DeletionFailed,
};
