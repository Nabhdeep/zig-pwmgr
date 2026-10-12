const std = @import("std");
const args_parser = @import("args");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const print = std.debug.print;
const stdout = std.Io.File.stdout().writeStreamingAll;

const lower: []const u8 = &[_]u8{ 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z' };

const upper: []const u8 = &[_]u8{ 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z' };

const digits: []const u8 = &[_]u8{ '0', '1', '2', '3', '4', '5', '6', '7', '8', '9' };

const special: []const u8 = &[_]u8{ '!', '@', '#', '$', '%', '^', '&', '*', '(', ')' };

const all: []const u8 = lower ++ upper ++ digits ++ special;
const diceware_args = struct {
    number_words: u16 = 6,
    separator: []const u8 = "",
    capitalize: bool = false,
    add_number: bool = false,
    add_special: bool = false,
    diceware: bool = false,
    word_list: []const u8 = "dicewarelist.txt",

    pub const shorthands = .{
        .N = "number_words",
        .S = "separator",
        .c = "capitalize",
        .n = "add_number",
        .s = "add_special",
    };
};

pub fn parse_args_v2(init: std.process.Init) diceware_args {
    const options = args_parser.parseForCurrentProcess(diceware_args, init, .print) catch return diceware_args{};
    defer options.deinit();
    return options.options;
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

pub fn generate_diceware_password(allocator: Allocator, io: Io, cli_args: diceware_args) !std.ArrayList([]const u8) {
    const file = try std.Io.Dir.openFile(std.Io.Dir.cwd(), io, cli_args.word_list, .{});
    defer file.close(io);

    var map = try load_word_list(allocator, io, cli_args.word_list);
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

pub fn password_generator(allocator: Allocator, io: Io, cli_args: diceware_args) !std.ArrayList([]const u8) {
    const buff = try allocator.alloc(u8, cli_args.number_words);
    for (0..cli_args.number_words) |i| {
        const random_number = generateRandonNumber(io);
        buff[i] = all[random_number % (all.len - 1)];
    }
    var array_list: std.ArrayList([]const u8) = .empty;
    errdefer array_list.deinit(allocator);
    try array_list.append(allocator, buff);
    return array_list;
}

pub fn print_password(array_list: std.ArrayList([]const u8), arguments: diceware_args) void {
    for (array_list.items) |j| {
        print("{s}", .{j});
        if (array_list.getLast().ptr != j.ptr) {
            print("{s}", .{arguments.separator});
        }
    }
}
pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const arguments = parse_args_v2(init);

    // allocator
    const allocator = init.gpa;
    var array_list: std.ArrayList([]const u8) = .empty;

    defer {
        for (array_list.items) |w| allocator.free(w);

        array_list.deinit(allocator);
    }
    if (arguments.diceware) {
        array_list = try generate_diceware_password(allocator, io, arguments);
    } else {
        array_list = try password_generator(allocator, io, arguments);
    }
    print_password(array_list, arguments);
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
