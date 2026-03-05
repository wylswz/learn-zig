# Module 2: Handling Commands & The PING/PONG Loop

## Required Reading

| Topic | Resource |
|-------|----------|
| Switch expressions | [Zig Language Reference — switch](https://ziglang.org/documentation/master/#switch) |
| String comparison | [std.mem.eql — Zig Standard Library](https://ziglang.org/documentation/master/std/std/mem.zig#eql) |
| Slices and memory | [Zig Language Reference — Slices](https://ziglang.org/documentation/master/#Slices) |
| `std.net.Stream` (Zig 0.15) | [std.net — Zig Standard Library](https://ziglang.org/documentation/master/std/std/net.zig) |
| `std.StringHashMap` | [std.HashMap — Zig Standard Library](https://ziglang.org/documentation/master/std/std/HashMap.zig) |

| ← Prev | Next → |
|--------|--------|
| [Module 1: RESP Parser](01-resp-parser.md) | [Module 3: Hash Table](03-hash-table.md) |

---

## Objective

Integrate the RESP parser into the TCP server, create a command dispatch loop, and implement `PING`, `ECHO`, `SET`, and `GET`. The server will store key-value pairs in a temporary `std.StringHashMap` until we replace it with a custom hash table in Module 3.

---

## Key Zig Concepts

### Switch Dispatch on Command Names

Commands arrive as RESP arrays: `*N\r\n$3\r\nSET\r\n$3\r\nkey\r\n$5\r\nvalue\r\n`. The first element is the command name; the rest are arguments. We use `std.mem.eql` for case-sensitive string comparison:

```zig
if (std.mem.eql(u8, cmd_name, "PING")) return resp.pong;
if (std.mem.eql(u8, cmd_name, "ECHO")) { ... }
```

### Slices and String Handling

Command arguments are `[]const u8` slices. We use `getBulkString` to extract bulk string payloads from `Value.bulk_string`. The slices point into memory owned by the parsed command; we duplicate with `allocator.dupe` when storing in the hash map so we own the data.

### Zig 0.15 Networking API

In Zig 0.15, `std.net.Stream` uses buffered readers and writers:

```zig
var read_buf: [4096]u8 = undefined;
var write_buf: [4096]u8 = undefined;
var reader = stream.reader(&read_buf);
var writer = stream.writer(&write_buf);
```

To obtain an `std.io.AnyReader` for the RESP parser, use:

```zig
const any_reader = std.io.Reader.adaptToOldInterface(reader.interface());
```

To write responses, use the writer's interface:

```zig
try response.writeTo(&writer.interface);
```

---

## Task 1: Create `src/commands.zig`

Define the temporary store and command handler:

```zig
pub const Store = std.StringHashMap([]const u8);

pub fn handleCommand(
    allocator: std.mem.Allocator,
    store: *Store,
    cmd: resp.Value,
) !resp.Value {
    const elems = cmd.array orelse return resp.errValue("ERR command must be an array");
    if (elems.len == 0) return resp.errValue("ERR empty command");

    const cmd_name = getBulkString(elems[0]) orelse return resp.errValue("ERR command name must be bulk string");
    const args = elems[1..];

    if (std.mem.eql(u8, cmd_name, "PING")) return resp.pong;
    if (std.mem.eql(u8, cmd_name, "ECHO")) { ... }
    if (std.mem.eql(u8, cmd_name, "SET")) { ... }
    if (std.mem.eql(u8, cmd_name, "GET")) { ... }

    return resp.errValue("ERR unknown command");
}
```

---

## Task 2: Implement PING and ECHO

```zig
if (std.mem.eql(u8, cmd_name, "PING")) {
    return resp.pong;
}
if (std.mem.eql(u8, cmd_name, "ECHO")) {
    if (args.len != 1) return resp.errValue("ERR wrong number of arguments for ECHO");
    const msg = getBulkString(args[0]) orelse return resp.errValue("ERR ECHO argument must be bulk string");
    return resp.bulkString(msg);
}
```

`resp.bulkString(msg)` returns a Value that references `msg` — we do not own it. The response is sent immediately and not stored, so no free is needed.

---

## Task 3: Implement SET and GET

For SET we duplicate the key and value so the store owns them. Use `fetchPut` to replace existing entries and free the old key/value:

```zig
if (std.mem.eql(u8, cmd_name, "SET")) {
    if (args.len != 2) return resp.errValue("ERR wrong number of arguments for SET");
    const key = getBulkString(args[0]) orelse return resp.errValue("ERR SET key must be bulk string");
    const val = getBulkString(args[1]) orelse return resp.errValue("ERR SET value must be bulk string");
    const key_dup = try allocator.dupe(u8, key);
    const val_dup = try allocator.dupe(u8, val);
    if (try store.fetchPut(key_dup, val_dup)) |old| {
        allocator.free(old.key);
        allocator.free(old.value);
    }
    return resp.ok;
}
if (std.mem.eql(u8, cmd_name, "GET")) {
    if (args.len != 1) return resp.errValue("ERR wrong number of arguments for GET");
    const key = getBulkString(args[0]) orelse return resp.errValue("ERR GET key must be bulk string");
    const val = store.get(key);
    return if (val) |v| resp.bulkString(v) else resp.null_bulk;
}
```

---

## Task 4: Add `freeValue` to `resp.zig`

The caller must free the parsed command after handling. Add a helper:

```zig
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
```

---

## Task 5: Update `main.zig` — Connection Loop

1. Create a `GeneralPurposeAllocator` and the store.
2. Accept connections in a loop.
3. For each connection, run a command loop: parse, handle, write response, free command.

```zig
while (true) {
    const connection = server.accept() catch break;
    defer connection.stream.close();
    handleConnection(allocator, &store, connection.stream) catch |err| {
        std.debug.print("Connection error: {any}\n", .{err});
    };
}
```

---

## Task 6: Implement `handleConnection`

```zig
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

        const response = commands.handleCommand(allocator, store, cmd) catch |err| {
            try resp.errValue(@errorName(err)).writeTo(&writer.interface);
            continue;
        };

        try response.writeTo(&writer.interface);
    }
}
```

---

## Task 7: Store Cleanup on Shutdown

When the server exits, free all keys and values in the store before `deinit`:

```zig
defer {
    var it = store.iterator();
    while (it.next()) |entry| {
        allocator.free(entry.key_ptr.*);
        allocator.free(entry.value_ptr.*);
    }
    store.deinit();
}
```

---

## Acceptance Criteria

- [ ] `zig build` and `zig build test` succeed.
- [ ] `redis-cli -p 6379 PING` returns `PONG`.
- [ ] `redis-cli -p 6379 ECHO hello` returns `"hello"`.
- [ ] `redis-cli -p 6379 SET mykey myvalue` returns `OK`.
- [ ] `redis-cli -p 6379 GET mykey` returns `"myvalue"`.
- [ ] `redis-cli -p 6379 GET nonexistent` returns `(nil)`.

---

## What's Next

In **Module 3** we will replace `std.StringHashMap` with a custom hash table built from scratch. This will introduce Zig's generics, pointer manipulation, and collision resolution (separate chaining).
