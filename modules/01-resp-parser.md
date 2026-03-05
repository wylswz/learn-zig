# Module 1: The RESP Protocol Parser

## Required Reading

| Topic | Resource |
|-------|----------|
| RESP protocol specification | [Redis Protocol Specification](https://redis.io/docs/latest/develop/reference/protocol-spec) |
| Tagged unions | [Zig Language Reference — Tagged union](https://ziglang.org/documentation/master/#Tagged-union) |
| Error unions | [Zig Language Reference — Error Unions](https://ziglang.org/documentation/master/#Error-Unions) |
| Compile-time execution | [Zig Language Reference — comptime](https://ziglang.org/documentation/master/#comptime) |
| `std.io.Reader` interface | [std.io — Zig Standard Library](https://ziglang.org/documentation/master/std/std/io.zig) |
| `std.ArrayList` | [std.ArrayList — Zig Standard Library](https://ziglang.org/documentation/master/std/std/ArrayList.zig) |

| ← Prev | Next → |
|--------|--------|
| [Module 0: Setup](00-setup.md) | [Module 2: Commands](02-commands.md) |

---

## Objective

Implement a parser for the Redis Serialization Protocol (RESP) — the wire format that Redis and `redis-cli` use to exchange commands and responses. By the end of this module you will have a tagged union representing all RESP types, a streaming parser that reads from any `std.io.Reader`, and a test suite that validates parsing correctness.

---

## Key Zig Concepts

### Tagged Unions — `union(enum)`

Zig's tagged unions combine a discriminant (the "tag") with a payload. Unlike C unions, the compiler tracks which variant is active, so you cannot accidentally read the wrong field:

```zig
const Value = union(enum) {
    simple_string: []const u8,
    integer: i64,
    array: []Value,
};

var v: Value = .{ .integer = 42 };
// v.integer is valid; v.simple_string would be undefined behavior
```

Use `switch` to exhaustively handle all variants:

```zig
switch (v) {
    .simple_string => |s| std.debug.print("string: {s}\n", .{s}),
    .integer => |n| std.debug.print("int: {d}\n", .{n}),
    .array => |elems| for (elems) |e| process(e),
}
```

### Error Unions — `!T`

A function that can fail returns `!ReturnType`, which is shorthand for `Error!ReturnType`. The `try` keyword propagates errors; `catch` handles them inline:

```zig
fn parse(reader: Reader) !Value {
    const byte = reader.readByte() catch return error.UnexpectedEof;
    // ...
}
```

### `comptime` — Compile-Time Execution

Zig can run code at compile time. Use `comptime` blocks or parameters to generate lookup tables, validate invariants, or specialize logic:

```zig
const CommandTable = struct {
    fn get(comptime name: []const u8) ?Command {
        // evaluated once at compile time
        return switch (name.len) {
            3 => if (std.mem.eql(u8, name, "GET")) .get else if (std.mem.eql(u8, name, "SET")) .set else null,
            4 => if (std.mem.eql(u8, name, "PING")) .ping else null,
            else => null,
        };
    }
};
```

### `std.io.Reader` — Abstract Input

The `Reader` interface abstracts over files, sockets, and buffers. Our parser takes `std.io.AnyReader` so it can read from a TCP stream, a fixed buffer, or a file — without knowing the concrete type.

---

## The RESP Specification

| Type         | Prefix | Format                    | Example                |
|--------------|--------|---------------------------|------------------------|
| Simple String| `+`    | `+<text>\r\n`             | `+OK\r\n`              |
| Error        | `-`    | `-<text>\r\n`             | `-ERR unknown\r\n`     |
| Integer      | `:`    | `:<number>\r\n`           | `:42\r\n`              |
| Bulk String  | `$`    | `$<len>\r\n<bytes>\r\n`   | `$6\r\nfoobar\r\n`     |
| Array        | `*`    | `*<count>\r\n<elems>...`  | `*2\r\n$3\r\nfoo\r\n$3\r\nbar\r\n` |

- **Null bulk string:** `$-1\r\n` — no payload.
- **Null array:** `*-1\r\n` — no elements.
- All line endings are `\r\n` (CRLF).

---

## Task 1: Define the `Value` Tagged Union

Create `src/resp.zig` and define the union:

```zig
pub const Value = union(enum) {
    simple_string: []const u8,
    error_string: []const u8,
    integer: i64,
    bulk_string: ?[]const u8,  // null = $-1
    array: ?[]Value,           // null = *-1
};
```

Use `?[]const u8` and `?[]Value` to represent null bulk strings and null arrays. The `?` wraps the type in an optional — `null` or a value.

---

## Task 2: Implement `writeTo` for Serialization

Add a method to serialize a `Value` back to RESP wire format. This is useful for sending responses and for AOF replay later:

```zig
pub fn writeTo(self: Value, writer: anytype) !void {
    switch (self) {
        .simple_string => |s| {
            try writer.writeAll("+");
            try writer.writeAll(s);
            try writer.writeAll("\r\n");
        },
        .error_string => |s| {
            try writer.writeAll("-");
            try writer.writeAll(s);
            try writer.writeAll("\r\n");
        },
        .integer => |n| {
            try writer.print(":{d}\r\n", .{n});
        },
        .bulk_string => |maybe| {
            if (maybe) |s| {
                try writer.print("${d}\r\n", .{s.len});
                try writer.writeAll(s);
                try writer.writeAll("\r\n");
            } else {
                try writer.writeAll("$-1\r\n");
            }
        },
        .array => |maybe| {
            if (maybe) |elems| {
                try writer.print("*{d}\r\n", .{elems.len});
                for (elems) |elem| try elem.writeTo(writer);
            } else {
                try writer.writeAll("*-1\r\n");
            }
        },
    }
}
```

The `anytype` writer parameter works with `std.ArrayList(u8).writer()`, `std.fs.File.writer()`, or any type with `writeAll` and `print`.

---

## Task 3: Define the Parser and Error Set

```zig
pub const ParseError = error{
    UnexpectedEof,
    InvalidPrefix,
    InvalidLength,
    MissingCrLf,
    NegativeLength,
    IntegerOverflow,
};

pub const Parser = struct {
    reader: std.io.AnyReader,
    allocator: std.mem.Allocator,

    pub fn init(reader: std.io.AnyReader, allocator: std.mem.Allocator) Parser {
        return .{ .reader = reader, .allocator = allocator };
    }

    pub fn parse(self: *Parser) (ParseError || std.mem.Allocator.Error || error{EndOfStream})!Value {
        const prefix = self.reader.readByte() catch return error.UnexpectedEof;
        return switch (prefix) {
            '+' => Value{ .simple_string = try self.readLine() },
            '-' => Value{ .error_string = try self.readLine() },
            ':' => Value{ .integer = try self.readInteger() },
            '$' => Value{ .bulk_string = try self.readBulkString() },
            '*' => Value{ .array = try self.readArray() },
            else => error.InvalidPrefix,
        };
    }
    // ... readLine, readInteger, readBulkString, readArray
};
```

The parser needs an allocator because bulk strings and arrays allocate memory. Simple strings and error strings also allocate (for the line buffer). The caller owns the returned `Value` and must free bulk strings, arrays, and simple/error strings when done.

---

## Task 4: Implement `readLine`

Read until `\r\n`, return the line without the CRLF. Use `std.ArrayList(u8)` to accumulate bytes:

```zig
fn readLine(self: *Parser) ![]const u8 {
    var list: std.ArrayList(u8) = .empty;
    defer list.deinit(self.allocator);
    while (true) {
        const byte = self.reader.readByte() catch return error.UnexpectedEof;
        if (byte == '\r') {
            const next = self.reader.readByte() catch return error.UnexpectedEof;
            if (next != '\n') return error.MissingCrLf;
            break;
        }
        try list.append(self.allocator, byte);
    }
    return try list.toOwnedSlice(self.allocator);
}
```

In Zig 0.15, `ArrayList` is unmanaged — it does not store the allocator. Use `.empty` to initialize, and pass the allocator to `append`, `deinit`, and `toOwnedSlice`.

---

## Task 5: Implement `readInteger` and `readBulkString`

```zig
fn readInteger(self: *Parser) !i64 {
    const line = try self.readLine();
    defer self.allocator.free(line);
    return std.fmt.parseInt(i64, line, 10) catch error.InvalidLength;
}

fn readBulkString(self: *Parser) !?[]const u8 {
    const len = try self.readInteger();
    if (len < -1) return error.NegativeLength;
    if (len == -1) return null;

    const n: usize = @intCast(len);
    const buf = try self.allocator.alloc(u8, n);
    errdefer self.allocator.free(buf);

    const read = self.reader.readAll(buf) catch return error.UnexpectedEof;
    if (read != n) return error.UnexpectedEof;

    var crlf: [2]u8 = undefined;
    const cr = self.reader.readAll(&crlf) catch return error.UnexpectedEof;
    if (cr != 2 or crlf[0] != '\r' or crlf[1] != '\n') return error.MissingCrLf;

    return buf;
}
```

`@intCast` converts the signed length to `usize`; the parser has already rejected negative values other than -1. The `errdefer` ensures we free `buf` if a later step fails — Zig's error handling keeps cleanup explicit.

---

## Task 6: Implement `readArray`

Parse the element count, then recursively parse each element:

```zig
fn readArray(self: *Parser) !?[]Value {
    const len = try self.readInteger();
    if (len < -1) return error.NegativeLength;
    if (len == -1) return null;

    const n: usize = @intCast(len);
    const elems = try self.allocator.alloc(Value, n);
    errdefer self.allocator.free(elems);

    for (elems) |*elem| {
        elem.* = try self.parse();
    }
    return elems;
}
```

---

## Task 7: Add Helper Constructors

These simplify building responses in the command layer:

```zig
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
```

---

## Task 8: Write the Test Suite

Add `test` blocks at the bottom of `resp.zig`:

```zig
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

test "null bulk string" {
    const val = try parseFromSlice(testing.allocator, "$-1\r\n");
    try testing.expectEqual(@as(?[]const u8, null), val.bulk_string);
}

test "array" {
    const val = try parseFromSlice(testing.allocator, "*2\r\n$3\r\nfoo\r\n$3\r\nbar\r\n");
    const elems = val.array.?;
    defer {
        for (elems) |elem| {
            if (elem.bulk_string) |s| testing.allocator.free(s);
        }
        testing.allocator.free(elems);
    }
    try testing.expectEqual(@as(usize, 2), elems.len);
    try testing.expectEqualStrings("foo", elems[0].bulk_string.?);
    try testing.expectEqualStrings("bar", elems[1].bulk_string.?);
}
```

Run tests with `zig build test`.

---

## Update `build.zig` for Multi-File Tests

Add `resp.zig` to the test step so both `main.zig` and `resp.zig` tests run:

```zig
for ([_][]const u8{ "src/main.zig", "src/resp.zig" }) |src| {
    const test_exe = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path(src),
            .target = target,
            .optimize = optimize,
        }),
    });
    const run_tests = b.addRunArtifact(test_exe);
    test_step.dependOn(&run_tests.step);
}
```

---

## Acceptance Criteria

- [ ] All `zig build test` tests pass.
- [ ] The parser correctly parses simple strings, errors, integers, bulk strings (including null), and arrays (including null).
- [ ] `writeTo` serializes values back to valid RESP.
- [ ] Nested arrays parse correctly (e.g. `*2\r\n*2\r\n:1\r\n:2\r\n+hello\r\n`).

---

## Memory Ownership Summary

| Value variant    | Who allocates? | Who frees? |
|------------------|----------------|------------|
| simple_string    | Parser (readLine) | Caller |
| error_string     | Parser (readLine) | Caller |
| integer          | —              | —         |
| bulk_string      | Parser         | Caller    |
| array            | Parser         | Caller (recursively free elements) |

When you integrate the parser into the server (Module 2), you will process the command, send the response, then free the parsed `Value` and all its nested allocations.

---

## What's Next

In **Module 2** we will integrate the RESP parser into the TCP server, create a command dispatch loop, and implement `PING`, `ECHO`, `SET`, and `GET`. The server will store key-value pairs in a temporary variable before we replace it with a proper hash table in Module 3.
