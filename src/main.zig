const std = @import("std");
const resp = @import("resp.zig");
const commands = @import("commands.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var store = commands.Store.init(allocator);
    defer store.deinit();

    const address = try std.net.Address.parseIp4("127.0.0.1", 6379);
    var server = try address.listen(.{ .reuse_address = true });
    defer server.deinit();

    std.debug.print("Listening on 127.0.0.1:6379\n", .{});

    while (true) {
        const connection = server.accept() catch break;
        defer connection.stream.close();

        std.debug.print("Client connected from {any}\n", .{connection.address});
        handleConnection(allocator, &store, connection.stream) catch |err| {
            std.debug.print("Connection error: {any}\n", .{err});
        };
    }
}

fn handleConnection(
    allocator: std.mem.Allocator,
    store: *commands.Store,
    stream: std.net.Stream,
) !void {
    var read_buf: [4096]u8 = undefined;
    var write_buf: [4096]u8 = undefined;
    var reader = stream.reader(&read_buf);
    var writer = stream.writer(&write_buf);

    while (true) {
        const any_reader = std.io.Reader.adaptToOldInterface(reader.interface());
        var parser = resp.Parser.init(any_reader, allocator);
        const cmd = parser.parse() catch |err| switch (err) {
            error.EndOfStream, error.UnexpectedEof => return,
            else => return err,
        };
        defer resp.freeValue(allocator, cmd);

        const response = commands.handleCommand(allocator, store, cmd, null) catch |err| {
            try resp.errValue(@errorName(err)).writeTo(&writer.interface);
            continue;
        };

        try response.writeTo(&writer.interface);
    }
}
