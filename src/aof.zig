/// Append-Only File persistence. Replay on startup; append on write.
/// TODO: Implement (Module 5).
const std = @import("std");
const resp = @import("resp.zig");
const store_mod = @import("store.zig");

pub const Aof = struct {
    file: std.fs.File,
    allocator: std.mem.Allocator,

    pub fn open(path: []const u8, allocator: std.mem.Allocator) !Aof {
        _ = path;
        _ = allocator;
        @panic("TODO: implement Aof.open");
    }

    pub fn create(path: []const u8, allocator: std.mem.Allocator) !Aof {
        _ = path;
        _ = allocator;
        @panic("TODO: implement Aof.create");
    }

    /// Append a write command (RESP array) to the AOF file.
    pub fn append(self: *Aof, cmd: resp.Value) !void {
        _ = self;
        _ = cmd;
        @panic("TODO: implement Aof.append");
    }

    /// Replay AOF from the start to restore store state.
    pub fn replay(self: *Aof, store: *store_mod.Store, allocator: std.mem.Allocator) !void {
        _ = self;
        _ = store;
        _ = allocator;
        @panic("TODO: implement Aof.replay");
    }

    pub fn deinit(self: *Aof) void {
        self.file.close();
        self.* = undefined;
    }
};
