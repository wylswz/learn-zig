/// RESP (Redis Serialization Protocol) parser.
///
/// Wire format: +OK\r\n  -ERR\r\n  :42\r\n  $6\r\nfoobar\r\n  *2\r\n...
const std = @import("std");

const crlf = "\r\n";
const cr: u8 = '\r';

pub const Type = struct {
    pub const simple_string = '+';
    pub const error_string = '-';
    pub const integer = ':';
    pub const bulk_string = '$';
    pub const array = '*';
};

// ---------------------------------------------------------------------------
// Value type (given — implement writeTo)
// ---------------------------------------------------------------------------

pub const Value = union(enum) {
    simple_string: []const u8,
    error_string: []const u8,
    integer: i64,
    bulk_string: ?[]const u8,
    array: ?[]Value,

    pub fn of_str(s: []const u8) Value {
        return .{ .simple_string = s };
    }

    pub fn of_int(n: i64) Value {
        return .{ .integer = n };
    }

    pub fn of_bulk_string(s: []const u8) Value {
        return .{ .bulk_string = s };
    }

    pub fn of_array(elems: []Value) Value {
        return .{ .array = elems };
    }

    pub fn writeTo(self: Value, writer: anytype) !void {
        switch (self) {
            .simple_string => |s| {
                try writer.writeAll("+");
                try writer.writeAll(s);
                try writer.writeAll(crlf);
            },
            .error_string => |s| {
                try writer.writeAll("-");
                try writer.writeAll(s);
                try writer.writeAll(crlf);
            },
            .integer => |n| try writer.print(":{d}{s}", .{ n, crlf }),
            .bulk_string => |maybe| {
                if (maybe) |s| {
                    try writer.print("${d}{s}", .{ s.len, crlf });
                    try writer.writeAll(s);
                    try writer.writeAll(crlf);
                } else try writer.writeAll("$-1{s}", .{crlf});
            },
            .array => |maybe| {
                if (maybe) |elems| {
                    try writer.print("*{d}{s}", .{ elems.len, crlf });
                    for (elems) |elem| try elem.writeTo(writer);
                } else try writer.writeAll("*-1{s}", .{crlf});
            },
        }
    }
};

// ---------------------------------------------------------------------------
// Parser (TODO: implement in Module 1)
// ---------------------------------------------------------------------------

pub const ParseError = error{
    IOError,
    UnexpectedEof,
    InvalidPrefix,
    InvalidLength,
    MissingCrLf,
    NegativeLength,
};

pub const Parser = struct {
    reader: std.io.AnyReader,
    allocator: std.mem.Allocator,

    pub fn init(reader: std.io.AnyReader, allocator: std.mem.Allocator) Parser {
        return .{ .reader = reader, .allocator = allocator };
    }

    pub fn parse(self: *Parser) anyerror!Value {
        if (self.reader.readByte()) |_type| {
            var buf: std.ArrayList(u8) = .empty;
            defer buf.deinit(self.allocator);
            const writer = buf.writer(self.allocator);
            switch (_type) {
                Type.simple_string => {
                    try self.reader.streamUntilDelimiter(writer, cr, null);
                    return Value.of_str(try self.allocator.dupe(u8, buf.items));
                },

                else => return ParseError.InvalidPrefix,
            }
        } else |err| {
            return err;
        }
    }
};

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

pub const ok = Value{ .simple_string = "OK" };
pub const pong = Value{ .simple_string = "PONG" };
pub const null_bulk = Value{ .bulk_string = null };

pub fn errValue(msg: []const u8) Value {
    return Value{ .error_string = msg };
}

pub fn bulkString(s: []const u8) Value {
    return Value{ .bulk_string = s };
}

pub fn integer(n: i64) Value {
    return Value{ .integer = n };
}

pub fn freeValue(allocator: std.mem.Allocator, v: Value) void {
    switch (v) {
        .simple_string => |s| allocator.free(s),
        .error_string => |s| allocator.free(s),
        .integer => {},
        .bulk_string => |maybe| if (maybe) |s| allocator.free(s),
        .array => |maybe| {
            if (maybe) |elems| {
                for (elems) |elem| freeValue(allocator, elem);
                allocator.free(elems);
            }
        },
    }
}

// ---------------------------------------------------------------------------
// Tests (pass when Parser.parse is implemented)
// ---------------------------------------------------------------------------

const testing = std.testing;

fn parseFromSlice(allocator: std.mem.Allocator, input: []const u8) !Value {
    var fbs = std.io.fixedBufferStream(input);
    var parser = Parser.init(fbs.reader().any(), allocator);
    return parser.parse();
}

test "simple string" {
    const val = try parseFromSlice(testing.allocator, "+OK\r\n");
    try testing.expectEqualStrings("OK", val.simple_string);
    testing.allocator.free(val.simple_string);
}

test "integer" {
    const val = try parseFromSlice(testing.allocator, ":1000\r\n");
    try testing.expectEqual(@as(i64, 1000), val.integer);
}

test "bulk string" {
    const val = try parseFromSlice(testing.allocator, "$6\r\nfoobar\r\n");
    const s = val.bulk_string.?;
    defer testing.allocator.free(s);
    try testing.expectEqualStrings("foobar", s);
}

test "array" {
    const val = try parseFromSlice(testing.allocator, "*2\r\n$3\r\nfoo\r\n$3\r\nbar\r\n");
    const elems = val.array.?;
    defer {
        for (elems) |elem| if (elem.bulk_string) |s| testing.allocator.free(s);
        testing.allocator.free(elems);
    }
    try testing.expectEqual(@as(usize, 2), elems.len);
    try testing.expectEqualStrings("foo", elems[0].bulk_string.?);
    try testing.expectEqualStrings("bar", elems[1].bulk_string.?);
}
