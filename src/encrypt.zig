const std = @import("std");
const crypto = std.crypto;
const Allocator = std.mem.Allocator;
const Io = std.Io;

// store salt nonce , cipher text in db
// use passpharse to decrypt
pub fn generate_keys(passphrase: []const u8, salt: []const u8) ![64]u8 {
    var key: [64]u8 = undefined;
    try std.crypto.pwhash.pbkdf2(&key, passphrase, salt, 600_000, std.crypto.auth.hmac.sha2.HmacSha256);
    return key;
}

pub fn generate_salt(io: Io) [64]u8 {
    var salt: [64]u8 = undefined;
    io.random(&salt);
    return salt;
}
