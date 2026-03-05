# Module 4: Custom Memory Allocators

## Required Reading

| Topic | Resource |
|-------|----------|
| Zig allocator model | [Zig Language Reference — Allocators](https://ziglang.org/documentation/master/#Allocators) |
| `std.mem.Allocator` interface | [std.mem.Allocator — Zig Standard Library](https://ziglang.org/documentation/master/std/std/mem.zig#Allocator) |
| `std.heap.ArenaAllocator` | [std.heap.ArenaAllocator — Zig Standard Library](https://ziglang.org/documentation/master/std/std/heap.zig#ArenaAllocator) |
| Memory allocation patterns | [Zig Learn — Allocators](https://ziglearn.org/chapter-2/) |

| ← Prev | Next → |
|--------|--------|
| [Module 3: Hash Table](03-hash-table.md) | [Module 5: Persistence](05-persistence.md) |

---

## Objective

Take control of memory by implementing and using a custom allocator. You will create an arena allocator for per-connection allocations and refactor the server so that each connection uses its own arena. When a connection closes, freeing the arena releases all its memory in one shot — no per-value cleanup, no leaks.

---

## Key Zig Concepts

### The `std.mem.Allocator` Interface

Every allocator in Zig implements the same interface:

```zig
pub const Allocator = struct {
    allocFn: fn (self: *Allocator, len: usize, ptr_align: u29, len_align: u29, ret_addr: usize) Error![]u8,
    resizeFn: fn (self: *Allocator, buf: []u8, buf_align: u29, new_len: usize, len_align: u29, ret_addr: usize) ?usize,
};
```

Callers use `allocator.alloc()`, `allocator.free()`, etc., which dispatch through this vtable. Your arena will implement this interface.

### Arena Allocation

An arena allocator:
- Allocates from a backing allocator (e.g. `std.heap.page_allocator`)
- Never frees individual allocations
- Supports `reset()` to free all allocations at once
- Is ideal for short-lived, batch allocations (e.g. one parsed command per connection)

### Allocator Propagation

Zig code passes allocators explicitly. There is no global allocator. Functions that allocate take `allocator: std.mem.Allocator` as a parameter. This makes ownership and lifetime explicit.

---

## Task 1: Understand the Current Flow

Today, `handleConnection` uses a single `allocator` (the GPA) for:
- Parser allocations (parsed `Value` and nested data)
- `resp.freeValue(allocator, cmd)` after each command

The store uses the same GPA for keys and values. That is correct — the store outlives the connection.

The problem: every parsed command allocates many small pieces (strings, arrays). We free them one by one with `freeValue`. With an arena, we allocate from the arena and reset it after each command — no per-value frees.

---

## Task 2: Implement `src/allocator.zig` — Arena Allocator

Create an arena that:
1. Wraps a backing allocator
2. Allocates chunks (or a single growing buffer)
3. Exposes `allocator()` returning an `Allocator` that allocates from the arena
4. Exposes `reset()` to free all arena memory
5. Exposes `deinit()` to release the arena

**Option A — Use the standard library:**

```zig
const std = @import("std");

pub const ConnectionArena = struct {
    arena: std.heap.ArenaAllocator,

    pub fn init(backing: std.mem.Allocator) ConnectionArena {
        return .{ .arena = std.heap.ArenaAllocator.init(backing) };
    }

    pub fn allocator(self: *ConnectionArena) std.mem.Allocator {
        return self.arena.allocator();
    }

    pub fn reset(self: *ConnectionArena) void {
        _ = self.arena.reset(.free_all);
    }

    pub fn deinit(self: *ConnectionArena) void {
        self.arena.deinit();
    }
};
```

**Option B — Implement from scratch:** Use a linked list of buffers. On `alloc`, bump a pointer or allocate a new buffer. On `reset`, free all buffers and clear the list.

---

## Task 3: Refactor `handleConnection`

1. At the start of `handleConnection`, create a `ConnectionArena` backed by the GPA (or page allocator).
2. `defer arena.deinit()` when the function returns.
3. In the command loop, at the **start** of each iteration:
   - Call `arena.reset()` to clear previous command allocations.
   - Use `arena.allocator()` for the parser.
4. Remove the `defer resp.freeValue(allocator, cmd)` — the arena reset frees the command.
5. Ensure the response is written **before** the next loop iteration (and thus before the next reset). The response slices (e.g. from GET) point into the store, not the arena, so they remain valid.

**Critical ordering:**
```
loop iteration: [parse → handle → write response] → reset arena → next iteration
                     ↑ arena allocations here    ↑ all freed here
```

---

## Task 4: Pass the Right Allocators

- **Store:** Continue using the main GPA. The store lives for the process lifetime.
- **Parser:** Use `arena.allocator()` so parsed values live in the arena.
- **handleCommand:** Receives the arena allocator for any temporary allocations. For SET, it still dups key/value into the store (store uses GPA). The command handler should use the arena for ephemeral data only.

Update `handleConnection` to pass `arena.allocator()` to the parser and to `handleCommand`.

---

## Acceptance Criteria

- [ ] `zig build` and `zig build test` succeed.
- [ ] The server behaves as before: PING, ECHO, SET, GET work.
- [ ] Each connection uses an arena; each command resets the arena.
- [ ] No `freeValue` call for the parsed command (arena reset handles it).
- [ ] Running under Valgrind (or similar) shows no memory leaks.

---

## What's Next

In **Module 5** we will add persistence via an append-only file (AOF). Every write command will be appended to disk, and on startup we will replay the log to restore state.
