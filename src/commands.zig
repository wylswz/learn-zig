/// Command handling and dispatch for Redis-compatible commands.
const std = @import("std");
const resp = @import("resp.zig");
const store_mod = @import("store.zig");
const aof_mod = @import("aof.zig");

pub const Store = store_mod.Store;

/// Handle a parsed RESP array command.
/// aof: optional, for Module 5 — append write commands when set.
pub fn handleCommand(
    allocator: std.mem.Allocator,
    store: *Store,
    cmd: resp.Value,
    aof: ?*aof_mod.Aof,
) (std.mem.Allocator.Error || error{UnknownCommand})!resp.Value {
    const elems = cmd.array orelse return resp.errValue("ERR command must be an array");
    if (elems.len == 0) return resp.errValue("ERR empty command");

    const cmd_name = getBulkString(elems[0]) orelse return resp.errValue("ERR command name must be bulk string");
    const args = elems[1..];

    if (std.mem.eql(u8, cmd_name, "PING")) return resp.pong;
    if (std.mem.eql(u8, cmd_name, "ECHO")) {
        if (args.len != 1) return resp.errValue("ERR wrong number of arguments for ECHO");
        const msg = getBulkString(args[0]) orelse return resp.errValue("ERR ECHO argument must be bulk string");
        return resp.bulkString(msg);
    }
    if (std.mem.eql(u8, cmd_name, "SET")) {
        if (args.len != 2) return resp.errValue("ERR wrong number of arguments for SET");
        // TODO: get key/val from args, dup, store.fetchPut, aof.append(cmd) if aof, return OK
        _ = allocator;
        _ = store;
        _ = aof;
        @panic("TODO: implement SET");
    }
    if (std.mem.eql(u8, cmd_name, "GET")) {
        if (args.len != 1) return resp.errValue("ERR wrong number of arguments for GET");
        // TODO: get key from args, store.get, return bulk or null_bulk
        _ = store;
        @panic("TODO: implement GET");
    }
    if (std.mem.eql(u8, cmd_name, "ZADD")) {
        if (args.len != 3) return resp.errValue("ERR wrong number of arguments for ZADD");
        // TODO: Module 6 — ZADD key score member
        _ = allocator;
        _ = store;
        @panic("TODO: implement ZADD (Module 6)");
    }
    if (std.mem.eql(u8, cmd_name, "ZRANGE")) {
        if (args.len != 3) return resp.errValue("ERR wrong number of arguments for ZRANGE");
        // TODO: Module 6 — ZRANGE key start stop
        _ = store;
        @panic("TODO: implement ZRANGE (Module 6)");
    }
    if (std.mem.eql(u8, cmd_name, "ZSCORE")) {
        if (args.len != 2) return resp.errValue("ERR wrong number of arguments for ZSCORE");
        // TODO: Module 6 — ZSCORE key member
        _ = store;
        @panic("TODO: implement ZSCORE (Module 6)");
    }

    return resp.errValue("ERR unknown command");
}

fn getBulkString(v: resp.Value) ?[]const u8 {
    return v.bulk_string orelse return null;
}
