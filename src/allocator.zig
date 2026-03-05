/// Per-connection arena allocator. Use for parser and command allocations.
/// TODO: Implement or wire up (Module 4). Use std.heap.ArenaAllocator or build your own.
const std = @import("std");

pub const ConnectionArena = struct {
    arena: std.heap.ArenaAllocator,

    pub fn init(backing: std.mem.Allocator) ConnectionArena {
        return .{ .arena = std.heap.ArenaAllocator.init(backing) };
    }

    pub fn allocator(self: *ConnectionArena) std.mem.Allocator {
        return self.arena.allocator();
    }

    /// Free all allocations in the arena. Call after each command.
    pub fn reset(self: *ConnectionArena) void {
        _ = self.arena.reset(.free_all);
    }

    pub fn deinit(self: *ConnectionArena) void {
        self.arena.deinit();
    }
};

const testing = std.testing;

test "arena alloc and reset" {
    var arena = ConnectionArena.init(testing.allocator);
    defer arena.deinit();

    const a1 = try arena.allocator().alloc(u8, 10);
    try testing.expectEqual(@as(usize, 10), a1.len);

    arena.reset();

    const a2 = try arena.allocator().alloc(u8, 5);
    try testing.expectEqual(@as(usize, 5), a2.len);
}
