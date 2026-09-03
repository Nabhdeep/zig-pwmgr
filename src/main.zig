const std = @import("std");
const Io = std.Io;
const print = std.debug.print;

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const file = try std.Io.Dir.openFile(std.Io.Dir.cwd(), io, "dicewarelist.txt", .{});
    defer file.close(io);

    var allocator = init.gpa;
    const buf = try allocator.alloc(u8, 4096);
    defer allocator.free(buf);
    var reader = file.reader(io, buf);
    var map = std.AutoHashMap(u32, []const u8).init(allocator);
    defer {
        var it = map.valueIterator();
        while (it.next()) |ele| allocator.free(ele.*);
        map.deinit();
    }
    var line_no: usize = 0;
    while (try reader.interface.takeDelimiter('\n')) |line| {
        line_no += 1;
        var w = std.mem.splitAny(u8, line, "\t");
        const index = try std.fmt.parseInt(u32, w.next().?, 10);
        const word = try allocator.dupe(u8, w.next().?);
        try map.put(index, word);
    }
    const args = try init.minimal.args.toSlice(allocator);
    defer allocator.free(args);

    if (args.len != 2) {
        print("Usage: <number of words>", .{});
        return;
    }

    // std.log.w("{s}", .{args[1]});
    const lenPass = try std.fmt.parseInt(u16, args[1][0..], 10);

    for (0..lenPass) |_| {
        const randomNum = generateRandonNumber(io);

        const p = map.get(randomNum) orelse {
            std.log.err("{d}", .{randomNum});
            return error.NumberInvalid;
        };
        print("{s} ", .{p});
    }
}

fn generateRandonNumber(io: Io) u32 {
    const source: std.Random.IoSource = .{ .io = io };
    const random = source.interface();
    var i: u8 = 1;
    var randomNumber: u32 = 1;
    while (i < 5) {
        const num = random.int(u32);
        const mod = (num % 6) + 1;
        randomNumber += mod * std.math.pow(u32, 10, i);
        i += 1;
    }
    return randomNumber;
}
