const std = @import("std");
const log = std.log.scoped(.dynamic_tree);
const assert = std.debug.assert;
const basic_type = @import("basic_type.zig");
const IndexLinkList = @import("IndexLinkList.zig");
const Rect = basic_type.Rect;
const Vec2 = basic_type.Vec2;
const Index = basic_type.Index;
const node_null = basic_type.node_null;

const DynamicTree = @This();
const Node = struct {
    /// If child1 == node_null, child2 is entity
    child1: Index = node_null,
    child2: Index = node_null,
    parent: Index = node_null,
    height: i16 = 0,
    aabb: Rect = Rect.zero(),
};

const NodeList = std.MultiArrayList(Node);

root: Index,
free_list: IndexLinkList,
node_list: NodeList,
nodes: NodeList.Slice,
allocator: *std.mem.Allocator,

pub fn init(allocator: *std.mem.Allocator) DynamicTree {
    var node_list = NodeList{};
    return .{
        .root = node_null,
        .free_list = IndexLinkList{},
        .node_list = NodeList{},
        .nodes = node_list.slice(),
        .allocator = allocator,
    };
}

pub fn deinit(self: *DynamicTree) void {
    self.node_list.deinit(self.allocator);
}

pub fn query(self: DynamicTree, stack: *std.ArrayList(Index), aabb: Rect, payload: anytype, callback: anytype) !void {
    const CallBack = std.meta.Child(@TypeOf(callback));
    if (!@hasDecl(CallBack, "onOverlap")) {
        @compileError("Expect " ++ @typeName(@TypeOf(callback)) ++ " has onCallback function");
    }
    defer stack.clearRetainingCapacity();
    try stack.append(self.root);
    const aabbs = self.nodes.items(.aabb);
    const child1s = self.nodes.items(.child1);
    const child2s = self.nodes.items(.child2);
    while (stack.items.len > 0) {
        const node_id = stack.pop();
        if (node_id == node_null) continue;

        if (aabbs[node_id].testOverlap(aabb)) {
            if (isLeaf(node_id, child1s)) {
                callback.onOverlap(payload, child2s[node_id]);
            } else {
                try stack.append(child1s[node_id]);
                try stack.append(child2s[node_id]);
            }
        }
    }
}
pub fn print(self: DynamicTree, extra: []const u8) void {
    const h = self.nodes.items(.height);
    const c1 = self.nodes.items(.child1);
    const c2 = self.nodes.items(.child2);
    const p = self.nodes.items(.parent);
    log.debug("==== {s} ====\n", .{extra});
    log.debug("height: {any}\n", .{h});
    log.debug("child1: {any}\n", .{c1});
    log.debug("child2: {any}\n", .{c2});
    log.debug("parent: {any}\n", .{p});
    var next = self.free_list;
    log.debug("free_list: ", .{});
    while (next != node_null) : (next = c1[next]) {
        log.debug("{},", .{next});
    }
    std.debug.print("\n", .{});
}

pub fn addNode(self: *DynamicTree, aabb: Rect, entity: Index) Index {
    const node_id = self.allocateNode();
    self.nodes.items(.aabb)[node_id] = aabb;
    self.nodes.items(.height)[node_id] = 0;
    self.nodes.items(.child2)[node_id] = entity;
    self.insertLeaf(node_id);
    return node_id;
}

pub fn removeNode(self: *DynamicTree, node_id: Index) void {
    self.removeLeaf(node_id);
    self.freeNode(node_id);
}

// TODO: fatten aabb?
// pub fn moveNode(tree: *DynamicTree, node_id: u32, aabb: Rect, displacement: Vec2) bool {
pub fn moveNode(tree: *DynamicTree, node_id: Index, aabb: Rect) bool {
    var aabbs = tree.nodes.items(.aabb);
    if (aabbs[node_id].contains(aabb)) {
        return false;
    }

    tree.removeLeaf(node_id);
    aabbs[node_id] = aabb;
    tree.insertLeaf(node_id);
    // TODO: tree.aabbs[proxyId].moved = true;

    return true;
}

fn allocateNode(self: *DynamicTree) Index {
    const node_id = self.free_list.popFirst(self.nodes.items(.child1));
    if (node_id) |value| {
        self.node_list.set(value, .{});
        return value;
    }

    self.node_list.append(self.allocator, .{}) catch unreachable;
    self.nodes = self.node_list.slice();
    return @intCast(Index, self.node_list.len - 1);
}

fn freeNode(self: *DynamicTree, node_id: Index) void {
    // TODO: b2Assert(0 <= nodeId && nodeId < m_nodeCapacity);
    self.nodes.items(.height)[node_id] = -1;
    self.free_list.prepend(node_id, self.nodes.items(.child1));
}

fn isLeaf(node_id: Index, child1s: []const Index) bool {
    return child1s[node_id] == node_null;
}

fn insertLeaf(self: *DynamicTree, leaf: Index) void {
    // TODO: what is this? self.m_insertionCount += 1;
    var parents = self.nodes.items(.parent);
    if (self.root == node_null) {
        self.root = leaf;
        parents[leaf] = node_null;
        return;
    }

    // Find the best sibling for this node
    var aabbs = self.nodes.items(.aabb);
    var child1s = self.nodes.items(.child1);
    var child2s = self.nodes.items(.child2);
    const leaf_aabb = aabbs[leaf];
    var index = self.root;
    while (isLeaf(index, child1s) == false) {
        const child1 = child1s[index];
        const child2 = child2s[index];

        const area = aabbs[index].getPerimeter();

        const combined_aabb = leaf_aabb.combine(aabbs[index]);
        const combined_area = combined_aabb.getPerimeter();

        // Cost of creating a new parent for this node and the new leaf
        const cost = 2 * combined_area;

        // Minimum cost of pushing the leaf further down the tree
        const inheritance_cost = 2 * (combined_area - area);

        // Cost of descending into child1
        const cost1 = blk: {
            if (isLeaf(child1, child1s)) {
                const aabb = leaf_aabb.combine(aabbs[child1]);
                break :blk aabb.getPerimeter() + inheritance_cost;
            } else {
                const aabb = leaf_aabb.combine(aabbs[child1]);
                const old_area = aabbs[child1].getPerimeter();
                const new_area = aabb.getPerimeter();
                break :blk (new_area - old_area) + inheritance_cost;
            }
        };

        // Cost of descending into child2
        const cost2 = blk: {
            if (isLeaf(child2, child1s)) {
                const aabb = leaf_aabb.combine(aabbs[child2]);
                break :blk aabb.getPerimeter() + inheritance_cost;
            } else {
                const aabb = leaf_aabb.combine(aabbs[child2]);
                const old_area = aabbs[child2].getPerimeter();
                const new_area = aabb.getPerimeter();
                break :blk new_area - old_area + inheritance_cost;
            }
        };

        // Descend according to the minimum cost.
        if (cost < cost1 and cost < cost2) break;

        // Descend
        if (cost1 < cost2) {
            index = child1;
        } else {
            index = child2;
        }
    }

    const sibling = index;

    // Create a new parent.
    const old_parent = parents[sibling];
    const new_parent = self.allocateNode();

    parents = self.nodes.items(.parent);
    aabbs = self.nodes.items(.aabb);
    var heights = self.nodes.items(.height);

    parents[new_parent] = old_parent;
    aabbs[new_parent] = leaf_aabb.combine(aabbs[sibling]);
    heights[new_parent] = heights[sibling] + 1;

    child1s = self.nodes.items(.child1);
    child2s = self.nodes.items(.child2);
    if (old_parent != node_null) {
        // The sibling was not the root.
        if (child1s[old_parent] == sibling) {
            child1s[old_parent] = new_parent;
        } else {
            child2s[old_parent] = new_parent;
        }

        parents[leaf] = new_parent;
    } else {
        // The sibling was the root.
        parents[leaf] = new_parent;
        self.root = new_parent;
    }
    child1s[new_parent] = sibling;
    child2s[new_parent] = leaf;
    parents[sibling] = new_parent;

    // Walk back up the tree fixing heights and AABBs
    var i = parents[leaf];
    while (i != node_null) : (i = parents[i]) {
        i = self.balance(i);

        const child1 = child1s[i];
        const child2 = child2s[i];

        assert(child1 != node_null);

        heights[i] = 1 + std.math.max(
            heights[child1],
            heights[child2],
        );
        aabbs[i] = aabbs[child1].combine(aabbs[child2]);
    }
}
fn balance(self: *DynamicTree, node_id: Index) Index {
    var heights = self.nodes.items(.height);
    var child1s = self.nodes.items(.child1);
    assert(node_id != node_null);
    const ia = node_id;
    if (isLeaf(ia, child1s) or heights[ia] < 2) {
        return ia;
    }

    var child2s = self.nodes.items(.child2);
    const ib = child1s[ia];
    const ic = child2s[ia];
    // TODO: b2Assert(0 <= iB && iB < m_nodeCapacity);
    //b2Assert(0 <= iC && iC < m_nodeCapacity);

    // var b = &self.nodes[ib];
    // var c = &self.nodes[ic];
    const balance_height = heights[ic] - heights[ib];

    // Rotate C up
    if (balance_height > 1) {
        var parents = self.nodes.items(.parent);
        const @"if" = child1s[ic];
        const ig = child2s[ic];
        // var f = &self.nodes[@"if"];
        // var g = &self.nodes[ig];
        // TODO: b2Assert(0 <= iF && iF < m_nodeCapacity);
        //b2Assert(0 <= iG && iG < m_nodeCapacity);

        // Swap A and C
        child1s[ic] = ia;
        parents[ic] = parents[ia];
        parents[ia] = ic;

        // A's old parent should point to C
        if (parents[ic] != node_null) {
            const c_parent = parents[ic];
            if (child1s[c_parent] == ia) {
                child1s[c_parent] = ic;
            } else {
                assert(child2s[c_parent] == ia);
                child2s[c_parent] = ic;
            }
        } else {
            self.root = ic;
        }

        // Rotate
        if (heights[@"if"] > heights[ig]) {
            var aabbs = self.nodes.items(.aabb);
            child2s[ic] = @"if";
            child2s[ia] = ig;
            parents[ig] = ia;
            aabbs[ia] = aabbs[ib].combine(aabbs[ig]);
            aabbs[ic] = aabbs[ia].combine(aabbs[@"if"]);

            heights[ia] = 1 + std.math.max(heights[ib], heights[ig]);
            heights[ic] = 1 + std.math.max(heights[ia], heights[@"if"]);
        } else {
            var aabbs = self.nodes.items(.aabb);
            child2s[ic] = ig;
            child2s[ia] = @"if";
            parents[@"if"] = ia;
            aabbs[ia] = aabbs[ib].combine(aabbs[@"if"]);
            aabbs[ic] = aabbs[ia].combine(aabbs[ig]);

            heights[ia] = 1 + std.math.max(heights[ib], heights[@"if"]);
            heights[ic] = 1 + std.math.max(heights[ia], heights[ig]);
        }

        return ic;
    }

    // Rotate B up
    if (balance_height < -1) {
        var parents = self.nodes.items(.parent);
        const id = child1s[ib];
        const ie = child2s[ib];
        // var d = &self.nodes[id];
        // var e = &self.nodes[ie];
        // TODO: b2Assert(0 <= iD && iD < m_nodeCapacity);
        //b2Assert(0 <= iE && iE < m_nodeCapacity);

        // Swap A and B
        child1s[ib] = ia;
        parents[ib] = parents[ia];
        parents[ia] = ib;

        // A's old parent should point to B
        if (parents[ib] != node_null) {
            const b_parent = parents[ib];
            if (child1s[b_parent] == ia) {
                child1s[b_parent] = ib;
            } else {
                assert(child2s[b_parent] == ia);
                child2s[b_parent] = ib;
            }
        } else {
            self.root = ib;
        }

        // Rotate
        if (heights[id] > heights[ie]) {
            var aabbs = self.nodes.items(.aabb);
            child2s[ib] = id;
            child1s[ia] = ie;
            parents[ie] = ia;
            aabbs[ia] = aabbs[ic].combine(aabbs[ie]);
            aabbs[ib] = aabbs[ia].combine(aabbs[id]);

            heights[ia] = 1 + std.math.max(heights[ic], heights[ie]);
            heights[ib] = 1 + std.math.max(heights[ia], heights[id]);
        } else {
            var aabbs = self.nodes.items(.aabb);
            child2s[ib] = ie;
            child1s[ia] = id;
            parents[id] = ia;
            aabbs[ia] = aabbs[ic].combine(aabbs[id]);
            aabbs[ib] = aabbs[ia].combine(aabbs[ie]);

            heights[ia] = 1 + std.math.max(heights[ic], heights[id]);
            heights[ib] = 1 + std.math.max(heights[ia], heights[ie]);
        }

        return ib;
    }

    return ia;
}
fn removeLeaf(self: *DynamicTree, leaf: Index) void {
    assert(self.root != node_null);
    if (leaf == self.root) {
        self.root = node_null;
        return;
    }
    var parents = self.nodes.items(.parent);
    var child1s = self.nodes.items(.child1);
    var child2s = self.nodes.items(.child2);
    const parent = parents[leaf];
    var grand_parent = parents[parent];
    const sibling = if (child1s[parent] == leaf) child2s[parent] else child1s[parent];

    self.freeNode(parent);
    if (grand_parent != node_null) {
        // Destroy parent and connect sibling to grandParent.
        if (child1s[grand_parent] == parent) {
            child1s[grand_parent] = sibling;
        } else {
            child2s[grand_parent] = sibling;
        }
        parents[sibling] = grand_parent;

        // Adjust ancestor bounds.
        var index = grand_parent;
        var aabbs = self.nodes.items(.aabb);
        var heights = self.nodes.items(.height);
        while (index != node_null) : (index = parents[index]) {
            index = self.balance(index);

            const child1 = child1s[index];
            const child2 = child2s[index];

            aabbs[index] = aabbs[child1].combine(aabbs[child2]);
            heights[index] = 1 + std.math.max(heights[child1], heights[child2]);
        }
    } else {
        self.root = sibling;
        parents[sibling] = node_null;
    }
}

fn floatFromRange(prng: std.rand.Random, min: i32, max: i32) f32 {
    return @intToFloat(f32, prng.intRangeAtMost(i32, min, max));
}
test "behavior" {
    std.debug.print("\n", .{});
    var dt = DynamicTree.init(std.testing.allocator);
    defer dt.deinit();
    var rects = std.ArrayList(Rect).init(std.testing.allocator);
    defer rects.deinit();

    try rects.append(Rect.newFromCenter(
        Vec2.new(-2, -2),
        Vec2.new(2, 2),
    ));
    try rects.append(Rect.newFromCenter(
        Vec2.new(-1, -1),
        Vec2.new(3, 3),
    ));
    try rects.append(Rect.newFromCenter(
        Vec2.new(-3, -3),
        Vec2.new(4, 4),
    ));
    try rects.append(Rect.newFromCenter(
        Vec2.new(2, 2),
        Vec2.new(4, 4),
    ));
    try rects.append(Rect.newFromCenter(
        Vec2.new(-3, -3),
        Vec2.new(-1, -1),
    ));
    for (rects.items) |entry, i| {
        _ = dt.addNode(entry, @intCast(u32, i));
    }
    const expected_output = [_]u32{
        0, 3,
        0, 4,
        0, 1,
        0, 2,
        1, 3,
        1, 4,
        1, 2,
        2, 3,
        2, 4,
    };

    {
        const QueryCallback = struct {
            const fixed_cap = 1048;
            couter: u32 = 0,
            array: [expected_output.len]u32 = undefined,
            buffer: [fixed_cap]u8 = undefined,
            pub fn onOverlap(self: *@This(), payload: u32, entity: u32) void {
                if (payload >= entity) return;
                self.array[self.couter * 2] = payload;
                self.array[self.couter * 2 + 1] = entity;
                self.couter += 1;
                // std.debug.print("{} - {}\n", .{ payload, entity });
            }
        };
        var callback = QueryCallback{};
        var stack = std.ArrayList(Index).init(std.testing.allocator);
        defer stack.deinit();
        for (rects.items) |aabb, i| {
            try dt.query(&stack, aabb, @intCast(u32, i), &callback);
        }
        for (&expected_output) |entry, i| {
            try std.testing.expect(entry == callback.array[i]);
        }
    }
}

test "Performance" {
    std.debug.print("\n", .{});
    var dt = DynamicTree.init(std.testing.allocator);
    defer dt.deinit();
    const total = 10000;
    var random = std.rand.Xoshiro256.init(0).random();
    const max_size = 20;
    const min_size = 1;
    const max = 3000;
    const min = -3000;
    var entities = std.ArrayList(Rect).init(std.testing.allocator);
    defer entities.deinit();
    try entities.ensureTotalCapacity(total);

    {
        var timer = try std.time.Timer.start();
        var entity: u32 = 0;
        while (entity < total) : (entity += 1) {
            const aabb = Rect.newFromCenter(
                Vec2.new(
                    floatFromRange(random, min, max),
                    floatFromRange(random, min, max),
                ),
                Vec2.new(
                    floatFromRange(random, min_size, max_size),
                    floatFromRange(random, min_size, max_size),
                ),
            );
            _ = dt.addNode(aabb, entity);
            try entities.append(aabb);
        }
        const time_0 = timer.read();
        std.debug.print("add {} entity take {}ms\n", .{ total, time_0 / std.time.ns_per_ms });
    }

    {
        const QueryCallback = struct {
            const fixed_cap = 1048;
            total: u32 = 0,
            buffer: [fixed_cap]u8 = undefined,
            pub fn onOverlap(self: *@This(), payload: u32, entity: u32) void {
                if (payload >= entity) return;
                self.total += 1;
            }
        };
        var callback = QueryCallback{};
        var stack = std.ArrayList(Index).init(std.testing.allocator);
        defer stack.deinit();
        var timer = try std.time.Timer.start();
        for (entities.items) |aabb, i| {
            try dt.query(&stack, aabb, @intCast(u32, i), &callback);
        }
        var time_0 = timer.read();
        std.debug.print("callback query {} entity, with {} callback take {}ms\n", .{
            total,
            callback.total,
            time_0 / std.time.ns_per_ms,
        });
    }
}
