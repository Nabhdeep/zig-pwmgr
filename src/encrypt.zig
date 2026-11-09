const std = @import("std");
const crypto = std.crypto;
const Allocator = std.mem.Allocator;
const Io = std.Io;
const testing = std.testing;
// store salt nonce , cipher text in db
// use passpharse to decrypt
pub fn generate_keys(passphrase: []const u8, salt: []const u8) ![64]u8 {
    var key: [64]u8 = undefined;
    try std.crypto.pwhash.pbkdf2(&key, passphrase, salt, 600_000, std.crypto.auth.hmac.sha2.HmacSha256);
    return key;
}

test "TC-01: checking if keys are same with same pass and salt" {
    const passphres = "bat-ball-black";
    const salt = "salt";
    const key = try generate_keys(passphres, salt);
    const key2 = try generate_keys(passphres, salt);
    try testing.expectEqualSlices(u8, &key, &key2);
}

pub fn generate_salt(io: Io) [64]u8 {
    var salt: [64]u8 = undefined;
    io.random(&salt);
    return salt;
}

test "TC-02: check if we can get 2 different salts" {
    const io = testing.io;
    const s = generate_salt(io);
    const s2 = generate_salt(io);
    try testing.expect(!std.mem.eql(u8, &s, &s2));
}
