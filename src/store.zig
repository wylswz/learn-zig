/// A custom hash table with FNV-1a hashing and separate chaining.
/// TODO: Implement from scratch (Module 3). Replace the stubs below.
const std = @import("std");

pub const Store = struct {
    allocator: std.mem.Allocator,
    // TODO: add fields (buckets, len, Node type, etc.)

    pub fn init(allocator: std.mem.Allocator) Store {
        _ = allocator;
        @panic("TODO: implement Store.init");
    }

    pub fn deinit(self: *Store) void {
        _ = self;
        @panic("TODO: implement Store.deinit");
    }

    pub fn get(self: Store, key: []const u8) ?[]const u8 {
        _ = self;
        _ = key;
        @panic("TODO: implement Store.get");
    }

    pub fn put(self: *Store, key: []const u8, value: []const u8) !void {
        _ = self;
        _ = key;
        _ = value;
        @panic("TODO: implement Store.put");
    }

    pub fn fetchPut(self: *Store, key: []const u8, value: []const u8) !?struct { key: []const u8, value: []const u8 } {
        _ = self;
        _ = key;
        _ = value;
        @panic("TODO: implement Store.fetchPut");
    }
};

const testing = std.testing;

test "store put and get" {
    var store = Store.init(testing.allocator);
    defer store.deinit();

    try store.put("foo", "bar");
    try store.put("baz", "qux");

    try testing.expectEqualStrings("bar", store.get("foo").?);
    try testing.expectEqualStrings("qux", store.get("baz").?);
    try testing.expect(store.get("missing") == null);
}

test "store overwrite" {
    var store = Store.init(testing.allocator);
    defer store.deinit();

    try store.put("k", "v1");
    try store.put("k", "v2");
    try testing.expectEqualStrings("v2", store.get("k").?);
}

test "store fetchPut" {
    var store = Store.init(testing.allocator);
    defer store.deinit();

    const key = try testing.allocator.dupe(u8, "x");
    const v1 = try testing.allocator.dupe(u8, "1");
    try testing.expect((try store.fetchPut(key, v1)) == null);

    const v2 = try testing.allocator.dupe(u8, "2");
    const old = (try store.fetchPut(key, v2)).?;
    try testing.expectEqualStrings("1", old.value);
    try testing.expectEqualStrings("2", store.get("x").?);
    testing.allocator.free(old.key);
    testing.allocator.free(old.value);
}
