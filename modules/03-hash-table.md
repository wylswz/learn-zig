# Module 3: The Core Data Store — A Custom Hash Table

## Required Reading

| Topic | Resource |
|-------|----------|
| Hash tables (separate chaining) | [Hash table — Wikipedia](https://en.wikipedia.org/wiki/Hash_table#Separate_chaining) |
| FNV-1a hash algorithm | [Fowler–Noll–Vo hash function — Wikipedia](https://en.wikipedia.org/wiki/Fowler%E2%80%93Noll%E2%80%93Vo_hash_function) |
| Zig pointers and optionals | [Zig Language Reference — Pointers](https://ziglang.org/documentation/master/#Pointers), [Optionals](https://ziglang.org/documentation/master/#Optionals) |
| `@sizeOf` and `@alignOf` | [Zig Language Reference — @sizeOf](https://ziglang.org/documentation/master/#sizeOf), [@alignOf](https://ziglang.org/documentation/master/#alignOf) |
| `std.mem.eql` | [std.mem — Zig Standard Library](https://ziglang.org/documentation/master/std/std/mem.zig) |

| ← Prev | Next → |
|--------|--------|
| [Module 2: Commands](02-commands.md) | [Module 4: Allocators](04-allocators.md) |

---

## Objective

Replace the temporary `std.StringHashMap` (or the stub in `store.zig`) with a custom hash table built from scratch. By the end of this module you will have a working key-value store using FNV-1a hashing and separate chaining for collision resolution.

---

## Key Zig Concepts

### Generics and `comptime`

Our store uses `[]const u8` for both keys and values. Zig's `comptime` lets you build generic data structures; for this module we keep the types fixed to simplify the implementation.

### Pointer Manipulation

The hash table uses a linked list for each bucket. You will work with `?*Node` (optional pointer to node) and `next: ?*Node` to chain entries:

```zig
const Node = struct {
    key: []const u8,
    value: []const u8,
    next: ?*Node,
};
```

### `@sizeOf` and `@alignOf`

When allocating nodes with `allocator.create(Node)`, Zig uses `@sizeOf(Node)` and `@alignOf(Node)` automatically. Understanding these helps when debugging layout issues.

### Memory Ownership

The store **owns** all keys and values it stores. On `put`, you duplicate the key and value with `allocator.dupe`. On `deinit` or when replacing an entry, you free the old key and value.

---

## Data Structure Design

```
buckets: []?*Node   (array of bucket heads)
         │
         ├─[0]──> Node("foo","bar") ──> Node("baz","qux") ──> null
         ├─[1]──> null
         ├─[2]──> Node("x","y") ──> null
         └─...
```

- **Buckets:** A slice of optional node pointers. Index = `hash(key) % buckets.len`.
- **Separate chaining:** Collisions append to a linked list in the same bucket.
- **Load factor:** When `len / capacity > 0.75`, double the number of buckets and rehash.

---

## Task 1: Define the Node and Store Layout

Add the `Node` struct and store fields:

```zig
const Node = struct {
    key: []const u8,
    value: []const u8,
    next: ?*Node,
};

pub const Store = struct {
    allocator: std.mem.Allocator,
    buckets: []?*Node,
    len: usize = 0,

    const default_capacity = 16;
    const max_load_factor = 0.75;
    // ...
};
```

---

## Task 2: Implement FNV-1a Hash

Use the 64-bit FNV-1a algorithm for string hashing:

```zig
fn fnv1a(s: []const u8) u64 {
    var h: u64 = 14695981039346656037; // FNV offset basis
    for (s) |b| {
        h ^= b;
        h *%= 1099511628211; // FNV prime
    }
    return h;
}
```

Use `%` with `buckets.len` to get the bucket index. **Optimization:** Keep `buckets.len` as a power of 2 (16, 32, 64, …) so you can use `hash & (buckets.len - 1)` instead of `%` — bitwise AND is faster than modulo.

---

## Task 3: Implement `init` and `deinit`

**init:** Allocate `default_capacity` buckets, set each to `null`.

**deinit:** For each bucket, walk the linked list, free each node's key and value, destroy the node, then free the buckets slice.

```zig
pub fn deinit(self: *Store) void {
    for (self.buckets) |*bucket| {
        var node = bucket.*;
        while (node) |n| {
            const next = n.next;
            self.allocator.free(n.key);
            self.allocator.free(n.value);
            self.allocator.destroy(n);
            node = next;
        }
    }
    self.allocator.free(self.buckets);
    self.* = undefined;
}
```

---

## Task 4: Implement `get`

1. Compute `idx = fnv1a(key) % self.buckets.len`.
2. Walk the chain at `self.buckets[idx]`.
3. Use `std.mem.eql(u8, n.key, key)` to find a match.
4. Return `n.value` or `null` if not found.

---

## Task 5: Implement `put` (or `fetchPut`)

**put:** Insert or overwrite. If the key exists, free the old value and update. Otherwise, allocate a new node, dup key and value, and prepend to the bucket.

**fetchPut:** Same logic, but when replacing return `.{ .key = old_key, .value = old_value }` so the caller can free them. When inserting, return `null`.

`commands.zig` expects `fetchPut`:

```zig
if (try store.fetchPut(key_dup, val_dup)) |old| {
    allocator.free(old.key);
    allocator.free(old.value);
}
```

---

## Task 6: Implement Growth

When `(len + 1) / buckets.len > max_load_factor`, allocate a new bucket array of size `buckets.len * 2`, rehash all existing nodes into it, then free the old buckets and replace.

---

## Task 7: Wire Up `commands.zig`

Ensure `commands.zig` uses `store_mod.Store` and that SET/GET call `store.fetchPut` and `store.get`. Remove the `@panic("TODO: ...")` stubs and implement the command bodies using the store.

---

## Acceptance Criteria

- [ ] `zig build` and `zig build test` succeed.
- [ ] `redis-cli -p 6379 SET mykey myvalue` returns `OK`.
- [ ] `redis-cli -p 6379 GET mykey` returns `"myvalue"`.
- [ ] Multiple keys can be stored and retrieved.
- [ ] Overwriting a key updates the value correctly.
- [ ] No memory leaks (run under Valgrind or similar if available).

---

## What's Next

In **Module 4** we will implement a custom arena allocator and thread it through the server. This gives explicit control over per-connection memory and simplifies cleanup.
