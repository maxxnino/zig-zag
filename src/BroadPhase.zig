const std = @import("std");
const basic_type = @import("basic_type.zig");
const Grid = @import("Grid.zig");
const DynamicTree = @import("DynamicTree.zig");
const Rect = basic_type.Rect;
const za = @import("zalgebra");
const Vec2 = basic_type.Vec2;
const Vec2u32 = basic_type.Vec2u32;
const Index = basic_type.Index;
const BroadPhase = @This();

const EntityType = enum {
    small,
    big,
};

pub const Proxy = union(EntityType) {
    /// Index is entity
    small: Index,
    /// Index is node_id in DynamicTree
    big: Index,
};

const GridKey = za.GenericVector(2, i16);

pub const QueryCallback = struct {
    const Payload = union(enum) {
        big: u32,
        small: u32,
    };
    stack: std.ArrayList(Index),
    total: u32 = 0,
    pairs: std.ArrayList(Index),
    pub fn init(allocator: std.mem.Allocator) QueryCallback {
        return .{
            .stack = std.ArrayList(Index).init(allocator),
            .pairs = std.ArrayList(Index).init(allocator),
        };
    }

    pub fn deinit(q: *QueryCallback) void {
        q.stack.deinit();
        q.pairs.deinit();
    }

    pub fn onOverlap(self: *@This(), payload: Payload, entity: u32) void {
        switch (payload) {
            .big => |e| {
                self.total += 1;
                self.pairs.append(e) catch unreachable;
                self.pairs.append(entity) catch unreachable;
            },
            .small => |e| {
                if (e >= entity) return;
                self.total += 1;
                self.pairs.append(e) catch unreachable;
                self.pairs.append(entity) catch unreachable;
            },
        }
    }
    pub fn reset(self: *@This()) void {
        self.total = 0;
        self.pairs.clearRetainingCapacity();
    }
};

const GridMap = std.AutoHashMap(i32, Grid);

const num_rows = 150;
const cell_size = Vec2.set(8);
const grid_size = cell_size.scale(num_rows);
const inv_grid_size = Vec2.set(1 / grid_size.x());
const element_size = cell_size.scale(0.5);
pub const half_element_size = cell_size.scale(0.25);

grid_map: GridMap,
tree: DynamicTree,
allocator: std.mem.Allocator,

pub fn init(allocator: std.mem.Allocator) BroadPhase {
    return .{
        .grid_map = GridMap.init(allocator),
        .tree = DynamicTree.init(allocator),
        .allocator = allocator,
    };
}

pub fn deinit(bp: *BroadPhase) void {
    bp.tree.deinit();
    var it = bp.grid_map.iterator();
    while (it.next()) |kv| {
        kv.value_ptr.deinit();
    }
    bp.grid_map.deinit();
}

pub fn createProxy(bp: *BroadPhase, m_pos: Vec2, h_size: Vec2, entity: Index) Proxy {
    switch (sizeToType(h_size)) {
        .small => {
            const grid_key = posToGridKey(m_pos);
            bp.getOrCreateGrid(grid_key).insert(entity, m_pos);
            return .{ .small = entity };
        },
        .big => {
            const aabb = Rect.newFromCenter(m_pos, h_size);
            return .{ .big = bp.tree.addNode(aabb, entity) };
        },
    }
}

pub fn destroyProxy(bp: *BroadPhase, proxy: Proxy, m_pos: Vec2) void {
    switch (proxy) {
        .small => |entity| {
            const grid_key = posToGridKey(m_pos);
            bp.getGrid(grid_key).remove(entity, m_pos);
        },
        .big => |node_id| {
            bp.tree.removeNode(node_id);
        },
    }
}

pub fn moveProxy(bp: *BroadPhase, proxy: Proxy, from_pos: Vec2, to_pos: Vec2, h_size: Vec2) void {
    switch (proxy) {
        .small => |entity| {
            var from_grid_key = posToGridKey(from_pos);
            var to_grid_key = posToGridKey(to_pos);
            if (from_grid_key.eql(to_grid_key)) {
                bp.getGrid(from_grid_key).move(entity, from_pos, to_pos);
            } else {
                bp.getGrid(from_grid_key).remove(entity, from_pos);
                bp.getOrCreateGrid(to_grid_key).insert(entity, to_pos);
            }
        },
        .big => |node_id| {
            const aabb = Rect.newFromCenter(to_pos, h_size);
            _ = bp.tree.moveNode(node_id, aabb);
        },
    }
}

/// TODO: split query for .small and .big?
pub fn query(
    bp: *BroadPhase,
    m_pos: Vec2,
    h_size: Vec2,
    proxy: Proxy,
    payload: anytype,
    callback: *QueryCallback,
) !void {
    const aabb = Rect.newFromCenter(m_pos, h_size);
    const new_payload: QueryCallback.Payload = blk: {
        if (proxy == .big) {
            const temp = QueryCallback.Payload{ .big = payload };
            try bp.tree.query(&callback.stack, aabb, temp, callback);
            break :blk temp;
        } else {
            break :blk .{ .small = payload };
        }
    };

    bp.queryGrid(aabb, m_pos, h_size, new_payload, callback);
}

pub fn userQuery(bp: *BroadPhase, m_pos: Vec2, h_size: Vec2, payload: anytype, callback: anytype) !void {
    const aabb = Rect.newFromCenter(m_pos, h_size);
    try bp.tree.query(&callback.stack, aabb, payload, callback);
    bp.queryGrid(aabb, m_pos, h_size, payload, callback);
}

pub fn queryGrid(
    bp: *BroadPhase,
    aabb: Rect,
    m_pos: Vec2,
    h_size: Vec2,
    payload: anytype,
    callback: anytype,
) void {
    const extended_aabb = aabb.extent(half_element_size);
    const top_right = posToGridKey(extended_aabb.topRight());
    const bottom_left = posToGridKey(extended_aabb.bottomLeft());

    var bl_grid = bp.getGridOrNull(bottom_left);
    if (bl_grid) |grid| {
        grid.query(m_pos, h_size, payload, callback);
    }

    if (bottom_left.eql(top_right)) return;
    if (bp.getGridOrNull(top_right)) |grid| {
        grid.query(m_pos, h_size, payload, callback);
    }

    const top_left = posToGridKey(extended_aabb.topLeft());
    if (top_left.eql(bottom_left) or top_left.eql(top_right)) return;

    const bottom_right = posToGridKey(extended_aabb.bottomRight());
    if (bp.getGridOrNull(bottom_right)) |grid| {
        grid.query(m_pos, h_size, payload, callback);
    }
    if (bp.getGridOrNull(top_left)) |grid| {
        grid.query(m_pos, h_size, payload, callback);
    }
}

/// TODO: split to getGrid and createGrid function?
fn getOrCreateGrid(bp: *BroadPhase, grid_key: GridKey) *Grid {
    const key = getKey(grid_key);
    const node_ptr = bp.grid_map.getPtr(key);
    if (node_ptr) |node| {
        return node;
    }

    bp.grid_map.putNoClobber(key, Grid.init(
        bp.allocator,
        keyToGridPos(grid_key),
        half_element_size,
        cell_size.x(),
        num_rows,
    )) catch unreachable;
    return bp.grid_map.getPtr(key).?;
}

fn getGrid(bp: *BroadPhase, grid_key: GridKey) *Grid {
    const key = getKey(grid_key);
    return bp.grid_map.getPtr(key).?;
}

fn getGridOrNull(bp: *BroadPhase, grid_key: GridKey) ?*Grid {
    const key = getKey(grid_key);
    return bp.grid_map.getPtr(key);
}

inline fn sizeToType(h_size: Vec2) EntityType {
    return if (@reduce(.Or, h_size.data > element_size.data)) .big else .small;
}

inline fn keyToGridPos(key: GridKey) Vec2 {
    return .{ .data = grid_size.data * key.cast(f32).data };
}

fn posToGridKey(pos: Vec2) GridKey {
    const data = @floor(pos.data * inv_grid_size.data);
    return GridKey.new(
        @floatToInt(i16, data[0]),
        @floatToInt(i16, data[1]),
    );
}

fn getKey(key: GridKey) i32 {
    return @as(i32, key.x()) << 16 | @as(i32, key.y());
}

fn randomPos(random: std.rand.Random, min: f32, max: f32) Vec2 {
    return Vec2.new(
        std.math.max(random.float(f32) * max, min),
        std.math.max(random.float(f32) * max, min),
    );
}

test "Behavior" {
    std.debug.print("\n", .{});
    const allocator = std.testing.allocator;
    var bp = BroadPhase.init(allocator);
    defer bp.deinit();

    var random = std.rand.Xoshiro256.init(0).random();
    const Entity = std.MultiArrayList(struct {
        entity: u32,
        pos: Vec2,
        half_size: Vec2,
        proxy: Proxy = undefined,
    });

    var manager = Entity{};
    defer manager.deinit(allocator);
    const total_small = 10_000;
    const total_big = 1_000;
    const max_x: f32 = 10_000;
    const min_size: f32 = 5.0;
    const max_size: f32 = 50;
    // bp.preCreateGrid(Vec2.zero(), Vec2.new(max_x, max_x));
    try manager.ensureTotalCapacity(allocator, total_big + total_small);

    // Init entities
    {
        var entity: u32 = 0;
        while (entity < total_small) : (entity += 1) {
            manager.appendAssumeCapacity(.{
                .entity = entity,
                .pos = randomPos(random, 0, max_x),
                .half_size = BroadPhase.half_element_size,
            });
        }
        while (entity < total_small + total_big) : (entity += 1) {
            manager.appendAssumeCapacity(.{
                .entity = entity,
                .pos = randomPos(random, 0, max_x),
                .half_size = randomPos(random, min_size, max_size),
            });
        }
    }

    var slice = manager.slice();
    var entities = slice.items(.entity);
    var position = slice.items(.pos);
    var proxy = slice.items(.proxy);
    var h_size = slice.items(.half_size);
    {
        var timer = try std.time.Timer.start();

        var index: u32 = 0;
        while (index < total_small) : (index += 1) {
            const p = bp.createProxy(position[index], h_size[index], entities[index]);
            std.debug.assert(p == .small);
            proxy[index] = p;
        }
        var time_0 = timer.read();
        std.debug.print("add {} entity to grid take {}ms\n", .{ total_small, time_0 / std.time.ns_per_ms });

        timer = try std.time.Timer.start();
        while (index < slice.len) : (index += 1) {
            const p = bp.createProxy(position[index], h_size[index], entities[index]);
            std.debug.assert(p == .big);
            proxy[index] = p;
        }
        time_0 = timer.read();
        std.debug.print("add {} entity to tree take {}ms\n", .{ total_big, time_0 / std.time.ns_per_ms });
    }
    {
        var timer = try std.time.Timer.start();

        var index: u32 = 0;
        while (index < total_small) : (index += 1) {
            bp.destroyProxy(proxy[index], position[index]);
        }
        var time_0 = timer.read();
        std.debug.print("destroyed {} entity to grid take {}ms\n", .{ total_small, time_0 / std.time.ns_per_ms });

        timer = try std.time.Timer.start();
        while (index < slice.len) : (index += 1) {
            bp.destroyProxy(proxy[index], position[index]);
        }
        time_0 = timer.read();
        std.debug.print("destroyed {} entity to tree take {}ms\n", .{ total_big, time_0 / std.time.ns_per_ms });
    }
    {
        var timer = try std.time.Timer.start();

        var index: u32 = 0;
        while (index < total_small) : (index += 1) {
            const p = bp.createProxy(position[index], h_size[index], entities[index]);
            std.debug.assert(p == .small);
            proxy[index] = p;
        }
        var time_0 = timer.read();
        std.debug.print("add {} entity to grid take {}ms\n", .{ total_small, time_0 / std.time.ns_per_ms });

        timer = try std.time.Timer.start();
        while (index < slice.len) : (index += 1) {
            const p = bp.createProxy(position[index], h_size[index], entities[index]);
            std.debug.assert(p == .big);
            proxy[index] = p;
        }
        time_0 = timer.read();
        std.debug.print("add {} entity to tree take {}ms\n", .{ total_big, time_0 / std.time.ns_per_ms });
    }
    const total_loop = 10;
    var current_loop: u32 = 0;
    var move_time: u64 = 0;
    var query_time: u64 = 0;
    var callback = QueryCallback.init(allocator);
    defer callback.deinit();
    while (current_loop < total_loop) : (current_loop += 1) {
        {
            var timer = try std.time.Timer.start();
            var index: u32 = 0;
            while (index < total_big + total_small) : (index += 1) {
                const pos = randomPos(random, 0, max_x);
                bp.moveProxy(proxy[index], position[index], pos, h_size[index]);
                position[index] = pos;
            }
            const time_0 = timer.read();
            move_time += time_0 / std.time.ns_per_ms;
        }
        {
            var index: u32 = 0;
            var timer = try std.time.Timer.start();
            while (index < slice.len) : (index += 1) {
                try bp.query(position[index], h_size[index], proxy[index], entities[index], &callback);
            }
            const time_0 = timer.read();
            query_time += time_0 / std.time.ns_per_ms;
        }
    }
    std.debug.print("move take {}ms\n", .{move_time / total_loop});
    std.debug.print("query take {}ms\n", .{query_time / total_loop});
    std.debug.print("grids: {}\n", .{bp.grid_map.count()});
}
