# Module 6: Advanced Data Structures — Sorted Sets (Optional)

## Required Reading

| Topic | Resource |
|-------|----------|
| Skip list algorithm | [Skip list — Wikipedia](https://en.wikipedia.org/wiki/Skip_list) |
| Redis Sorted Sets | [Redis Sorted Sets](https://redis.io/docs/latest/data-types/sorted-sets/) |
| `@fieldParentPtr` | [Zig Language Reference — @fieldParentPtr](https://ziglang.org/documentation/master/#fieldParentPtr) |
| Pointer manipulation in Zig | [Zig Language Reference — Pointers](https://ziglang.org/documentation/master/#Pointers) |

| ← Prev | Next → |
|--------|--------|
| [Module 5: Persistence](05-persistence.md) | — (End of course) |

---

## Objective

Implement the Sorted Set data type using a skip list. Add `ZADD`, `ZRANGE`, and `ZSCORE` commands so the server can store score-member pairs and query by rank or member.

---

## Key Zig Concepts

### Skip Lists

A skip list is a probabilistic data structure:

- Each node has a `key` (or score) and multiple `forward` pointers (levels).
- Level 0 is a sorted linked list; higher levels skip over nodes.
- Search: start at the highest level, move right while `next.key < target`, then move down.
- Insert: random level for the new node; insert at each level like a linked list.

### `@fieldParentPtr`

Given a pointer to a struct field, get the parent struct:

```zig
const Node = struct {
    score: f64,
    member: []const u8,
    forward: [max_level]*Node,
};
// If we have a *Node.forward[i], we can get the Node via @fieldParentPtr.
```

### Pointer Manipulation

Skip list insertion requires careful pointer updates at each level. Draw the before/after states.

---

## Task 1: Define the Skip List Node

```zig
const max_level = 32;

const Node = struct {
    score: f64,
    member: []const u8,
    forward: [max_level]?*Node,
};
```

---

## Task 2: Implement Level Selection

Use a random level when inserting. Common approach: level 0 with probability 1, level 1 with 0.25, level 2 with 0.0625, etc. This yields O(log n) expected height. Use `std.crypto.random` for a cryptographically secure source, or `std.rand` for deterministic tests.

```zig
fn randomLevel() usize {
    var level: usize = 0;
    while (level < max_level - 1 and (std.crypto.random.int(u32) % 4) == 0) {
        level += 1;
    }
    return level;
}
```

---

## Task 3: Implement `SortedSet`

```zig
pub const SortedSet = struct {
    allocator: std.mem.Allocator,
    header: *Node,
    len: usize = 0,
    member_to_score: std.StringHashMap(f64), // O(1) for ZSCORE

    pub fn init(allocator: std.mem.Allocator) SortedSet { ... }
    pub fn deinit(self: *SortedSet) void { ... }
    pub fn zadd(self: *SortedSet, score: f64, member: []const u8) !void { ... }
    pub fn zrange(self: *SortedSet, start: i64, stop: i64) ![]struct { score: f64, member: []const u8 } { ... }
    pub fn zscore(self: *SortedSet, member: []const u8) ?f64 { ... }
};
```

---

## Task 4: Implement `zadd`

1. Parse score and member from args.
2. If member exists, remove from skip list (update forward pointers).
3. Insert new node at the chosen level.
4. Update `member_to_score`.

---

## Task 5: Implement `zrange` and `zscore`

- **zrange:** Walk the level-0 list from `start` to `stop` (support negative indices like Redis).
- **zscore:** Look up in `member_to_score`.

---

## Task 6: Add Commands to `handleCommand`

```zig
if (std.mem.eql(u8, cmd_name, "ZADD")) {
    // ZADD key score member
    if (args.len != 3) return resp.errValue("ERR wrong number of arguments for ZADD");
    const key = getBulkString(args[0]) orelse return ...;
    const score_str = getBulkString(args[1]) orelse return ...;
    const member = getBulkString(args[2]) orelse return ...;
    const score = std.fmt.parseFloat(f64, score_str) catch return resp.errValue("ERR invalid score");
    // Get or create SortedSet for key, call zadd, return integer 1
}
if (std.mem.eql(u8, cmd_name, "ZRANGE")) { ... }
if (std.mem.eql(u8, cmd_name, "ZSCORE")) { ... }
```

The store currently holds `[]const u8` values. For sorted sets, you need a separate structure: either a `std.StringHashMap(*SortedSet)` keyed by the sorted set name, or extend the store to support multiple value types.

---

## Acceptance Criteria

- [ ] `ZADD myzset 1 "one"` returns `1`.
- [ ] `ZRANGE myzset 0 -1` returns the members in score order.
- [ ] `ZSCORE myzset "one"` returns `1`.
- [ ] Multiple members with different scores are ordered correctly.

---

## End of Course

You have built a Redis-compatible server with:

- RESP parsing
- Command dispatch (PING, ECHO, SET, GET, ZADD, ZRANGE, ZSCORE)
- Custom hash table
- Arena allocator
- AOF persistence
- Sorted sets (skip list)

Consider adding: more commands, TTL/expiry, or a proper event loop.
