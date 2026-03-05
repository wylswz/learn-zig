# Module 5: Persistence — The Append-Only File (AOF)

## Required Reading

| Topic | Resource |
|-------|----------|
| Redis AOF persistence | [Redis Persistence — AOF](https://redis.io/docs/latest/operate/oss_and_stack/management/persistence/#append-only-file) |
| Zig file I/O | [std.fs — Zig Standard Library](https://ziglang.org/documentation/master/std/std/fs.zig) |
| Buffered I/O | [std.io.bufferedWriter — Zig Standard Library](https://ziglang.org/documentation/master/std/std/io.zig) |
| `std.fs.File` reader/writer | [std.fs.File — Zig Standard Library](https://ziglang.org/documentation/master/std/std/fs.zig#File) |

| ← Prev | Next → |
|--------|--------|
| [Module 4: Allocators](04-allocators.md) | [Module 6: Sorted Sets](06-sorted-sets.md) |

---

## Objective

Implement AOF persistence so that every write command is appended to disk. On server startup, replay the AOF log to restore state. After a restart, `GET` returns values that were `SET` before the restart.

---

## Key Zig Concepts

### File I/O with `std.fs`

- `std.fs.cwd().openFile(path, .{})` — open for read
- `std.fs.cwd().createFile(path, .{})` — create or truncate for write
- `file.reader()` / `file.writer()` — get buffered I/O
- `file.seekTo(0)` — rewind for replay

### Buffered Writers

For appending, use a buffered writer to reduce syscalls:

```zig
var buffered = std.io.bufferedWriter(file.writer());
try cmd.writeTo(buffered.writer());
try buffered.flush();
```

### Serialization

The AOF stores the raw RESP command. No custom format — we reuse `Value.writeTo`. A SET command is written as `*3\r\n$3\r\nSET\r\n$3\r\nkey\r\n$5\r\nvalue\r\n`.

**Durability note:** For production, consider `file.sync()` after each append to ensure data reaches disk. For this course we rely on the OS buffer; `flush()` only flushes the Zig buffer to the kernel.

---

## Task 1: Create `src/aof.zig`

Define an AOF abstraction:

```zig
pub const Aof = struct {
    file: std.fs.File,
    allocator: std.mem.Allocator,

    pub fn open(path: []const u8, allocator: std.mem.Allocator) !Aof { ... }
    pub fn create(path: []const u8) !Aof { ... }
    pub fn append(self: *Aof, cmd: resp.Value) !void { ... }
    pub fn replay(self: *Aof, store: *Store, allocator: std.mem.Allocator) !void { ... }
    pub fn deinit(self: *Aof) void { ... }
};
```

---

## Task 2: Implement `open` and `create`

- **open:** Open existing file for append. Create if it doesn't exist.
- **create:** Create or truncate for a fresh AOF.

Use `std.fs.cwd().openFile` with `.mode = .read_write` and `.lock = .exclusive` (or similar) for append.

---

## Task 3: Implement `append`

For each write command, serialize the full RESP array to the file and flush:

```zig
pub fn append(self: *Aof, cmd: resp.Value) !void {
    var buffered = std.io.bufferedWriter(self.file.writer());
    try cmd.writeTo(buffered.writer());
    try buffered.flush();
}
```

---

## Task 4: Implement `replay`

1. Seek to the start of the file.
2. Create a RESP parser with the file as the reader.
3. Loop: parse a value, if it's an array dispatch to a minimal command handler (SET only for now), until EOF.

You need a way to apply a parsed command to the store without going through the full command handler. Either duplicate the SET logic or pass the store to a helper that executes the command.

---

## Task 5: Integrate into `main.zig`

1. On startup, check for `appendonly.aof`. If it exists, open it and call `replay` to restore the store.
2. If it doesn't exist, create it.
3. Pass the AOF to `handleConnection` (or to `handleCommand`).
4. After each write command (SET), call `aof.append(cmd)`.

---

## Task 6: Wire `handleCommand` to AOF

Update `handleCommand` to accept an optional `?*Aof`. When handling SET, if `aof != null`, call `aof.append(cmd)` before returning OK.

---

## Acceptance Criteria

- [ ] `zig build` succeeds.
- [ ] `SET mykey myvalue` appends to `appendonly.aof`.
- [ ] Restarting the server and running `GET mykey` returns `"myvalue"`.
- [ ] The AOF file contains valid RESP (human-readable with `cat`).

---

## What's Next

In **Module 6** (optional) we implement Sorted Sets using a skip list and add `ZADD`, `ZRANGE`, and `ZSCORE`.
