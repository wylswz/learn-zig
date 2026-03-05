/// Sorted Set using a skip list. For ZADD, ZRANGE, ZSCORE.
/// TODO: Implement (Module 6).
const std = @import("std");

pub const SortedSet = struct {
    allocator: std.mem.Allocator,
    // TODO: add fields (header node, member_to_score map, etc.)

    pub fn init(allocator: std.mem.Allocator) SortedSet {
        _ = allocator;
        @panic("TODO: implement SortedSet.init");
    }

    pub fn deinit(self: *SortedSet) void {
        _ = self;
        @panic("TODO: implement SortedSet.deinit");
    }

    pub fn zadd(self: *SortedSet, score: f64, member: []const u8) !void {
        _ = self;
        _ = score;
        _ = member;
        @panic("TODO: implement SortedSet.zadd");
    }

    pub fn zrange(self: *SortedSet, start: i64, stop: i64) ![]struct { score: f64, member: []const u8 } {
        _ = self;
        _ = start;
        _ = stop;
        @panic("TODO: implement SortedSet.zrange");
    }

    pub fn zscore(self: *SortedSet, member: []const u8) ?f64 {
        _ = self;
        _ = member;
        @panic("TODO: implement SortedSet.zscore");
    }
};
