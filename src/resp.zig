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
    pub const bulk_string = '$'; // $<length>\r\n<data>\r\n
    pub const array = '*';
    pub const _null = '_';
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
    _null: void,

    pub fn of_str(s: []const u8) Value {
        return .{ .simple_string = s };
    }

    pub fn of_error_string(s: []const u8) Value {
        return .{ .error_string = s };
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

    pub fn of_null() Value {
        return .{ ._null = {} };
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
            ._null => try writer.writeAll("_{s}", .{crlf}),
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

    fn is_digit(c: u8) bool {
        return c >= '0' and c <= '9';
    }

    fn int_to_usize(i: i64) usize {
        return @intCast(i);
    }

    // read next integer from the reader, until the next \r\n.
    fn read_integer(self: *Parser) !i64 {
        var buf: std.ArrayList(u8) = .empty;
        defer buf.deinit(self.allocator);
        const writer = buf.writer(self.allocator);
        try self.reader.streamUntilDelimiter(writer, cr, null);
        // \r is already read, so just skip \n
        try self.reader.skipBytes(1, .{});
        return try std.fmt.parseInt(i64, buf.items, 10);
    }

    // used after streamUntilDelimiter to skip the last \n since
    // only \r is read.
    fn skip_last(self: *Parser) !void {
        try self.reader.skipBytes(1, .{});
    }

    pub fn parse(self: *Parser) anyerror!Value {
        var buf: std.ArrayList(u8) = .empty;
        defer buf.deinit(self.allocator);
        const writer = buf.writer(self.allocator);

        if (self.reader.readByte()) |_type| {
            switch (_type) {
                Type.simple_string => {
                    try self.reader.streamUntilDelimiter(writer, cr, null);
                    try self.skip_last();
                    return Value.of_str(try self.allocator.dupe(u8, buf.items));
                },
                Type.error_string => {
                    try self.reader.streamUntilDelimiter(writer, cr, null);
                    try self.skip_last();
                    return Value.of_error_string(try self.allocator.dupe(u8, buf.items));
                },
                Type.integer => {
                    var sign: u8 = '+';
                    const head = try self.reader.readByte();
                    if (!is_digit(head)) {
                        if (head != '-' and head != '+') {
                            return ParseError.InvalidPrefix;
                        }
                        sign = head;
                    } else {
                        // must write back if first byte is a digit.
                        try writer.writeByte(head);
                    }
                    try self.reader.streamUntilDelimiter(writer, cr, null);
                    try self.skip_last();
                    const i = try std.fmt.parseInt(i64, buf.items, 10);
                    return Value.of_int(if (sign == '-') -i else i);
                },
                Type.bulk_string => {
                    const length = try self.read_integer();
                    if (length < 0) return Value.of_null();
                    if (length == 0) return Value.of_bulk_string("");

                    const fix_buf = try self.allocator.alloc(
                        u8,
                        int_to_usize(length),
                    );
                    defer self.allocator.free(fix_buf);
                    const read_len: usize = try self.reader.readAll(fix_buf);
                    if (read_len != int_to_usize(length)) {
                        return ParseError.UnexpectedEof;
                    }
                    try self.skip_last();
                    try self.skip_last();
                    return Value.of_bulk_string(try self.allocator.dupe(u8, fix_buf));
                },

                Type.array => {
                    const length = try self.read_integer();
                    if (length < 0) return ParseError.NegativeLength;
                    if (length == 0) return Value.of_array(&[0]Value{});
                    // TODO: recursively parse elements
                    const fix_buf = try self.allocator.alloc(
                        Value,
                        int_to_usize(length),
                    );
                    defer self.allocator.free(fix_buf);
                    for (fix_buf) |*item| {
                        item.* = try self.parse();
                    }
                    return Value.of_array(try self.allocator.dupe(Value, fix_buf));
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
        ._null => {},
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
    freeValue(testing.allocator, val);
}

test "integer" {
    const val = try parseFromSlice(testing.allocator, ":1000\r\n");
    try testing.expectEqual(@as(i64, 1000), val.integer);
    freeValue(testing.allocator, val);
}

test "negative integer" {
    const val = try parseFromSlice(testing.allocator, ":-1000\r\n");
    try testing.expectEqual(@as(i64, -1000), val.integer);
    freeValue(testing.allocator, val);
}

test "error string" {
    const val = try parseFromSlice(testing.allocator, "-ERR\r\n");
    try testing.expectEqualStrings("ERR", val.error_string);
    freeValue(testing.allocator, val);
}

test "bulk string" {
    const val = try parseFromSlice(testing.allocator, "$6\r\nfoobar\r\n");
    const s = val.bulk_string.?;
    try testing.expectEqualStrings("foobar", s);
    freeValue(testing.allocator, val);
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
