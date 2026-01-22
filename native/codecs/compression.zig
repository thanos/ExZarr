const std = @import("std");
const beam = @import("beam");

/// Compresses data using Zig's standard library deflate compression
pub fn deflate_compress(data: []const u8) ![]u8 {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Estimate compressed size
    const max_size = data.len + (data.len / 10) + 16;
    var compressed = try allocator.alloc(u8, max_size);

    var fbs = std.io.fixedBufferStream(compressed);
    var comp = try std.compress.deflate.compressor(fbs.writer(), .{});

    _ = try comp.write(data);
    try comp.finish();

    const compressed_len = fbs.pos;

    // Return a new allocation that beam owns
    const result = try allocator.alloc(u8, compressed_len);
    @memcpy(result, compressed[0..compressed_len]);

    allocator.free(compressed);
    return result;
}

/// Decompresses deflate-compressed data
pub fn deflate_decompress(data: []const u8) ![]u8 {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var fbs = std.io.fixedBufferStream(data);
    var decomp = std.compress.deflate.decompressor(fbs.reader());

    const decompressed = try decomp.reader().readAllAlloc(allocator, std.math.maxInt(usize));
    return decompressed;
}

/// Compresses data using gzip format
pub fn gzip_compress(data: []const u8) ![]u8 {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Estimate compressed size
    const max_size = data.len + (data.len / 10) + 32;
    var compressed = try allocator.alloc(u8, max_size);

    var fbs = std.io.fixedBufferStream(compressed);
    var comp = try std.compress.gzip.compressor(fbs.writer(), .{});

    _ = try comp.write(data);
    try comp.finish();

    const compressed_len = fbs.pos;

    const result = try allocator.alloc(u8, compressed_len);
    @memcpy(result, compressed[0..compressed_len]);

    allocator.free(compressed);
    return result;
}

/// Decompresses gzip-compressed data
pub fn gzip_decompress(data: []const u8) ![]u8 {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var fbs = std.io.fixedBufferStream(data);
    var decomp = try std.compress.gzip.decompressor(fbs.reader());

    const decompressed = try decomp.reader().readAllAlloc(allocator, std.math.maxInt(usize));
    return decompressed;
}
