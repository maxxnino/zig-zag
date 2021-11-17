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
pub const Child = struct {
    left: u32 = node_null,
    right: u32 = node_null,
};
const Node = struct {
    parent: Index = node_null,
    data: Index = node_null,
    height: i16 = 0,
    aabb: Rect = Rect.zero(),
    tag: Tag,
    const Tag = enum {
        /// Data is entity
        entity,
        /// Data is index into Child ArrayList
        child,
    };
};

const NodeList = std.MultiArrayList(Node);

root: Index,
free_list: IndexLinkList,
child_free: IndexLinkList,
node_list: NodeList,
nodes: NodeList.Slice,
childs: std.ArrayList(Child),
allocator: *std.mem.Allocator,

pub fn init(allocator: *std.mem.Allocator) DynamicTree {
    var node_list = NodeList{};
    return .{
        .root = node_null,
        .free_list = IndexLinkList{},
        .child_free = IndexLinkList{},
        .node_list = NodeList{},
        .nodes = node_list.slice(),
        .childs = std.ArrayList(Child).init(allocator),
        .allocator = allocator,
    };
}

pub fn deinit(self: *DynamicTree) void {
    self.node_list.deinit(self.allocator);
    self.childs.deinit();
}

pub fn query(self: DynamicTree, aabb: Rect, entity: Index, allocator: *std.mem.Allocator, callback: anytype) !void {
    const CallBackType = std.meta.Child(@TypeOf(callback));
    if (!@hasDecl(CallBackType, "onOverlap")) {
        @compileError("Expect " ++ @typeName(@TypeOf(callback)) ++ " has onCallback function");
    }
    const have_filter = @hasDecl(CallBackType, "filter");
    var stack = std.ArrayList(Index).init(allocator);
    defer stack.deinit();
    try stack.append(self.root);
    const childs = self.childs.items;
    const aabbs = self.nodes.items(.aabb);
    const data = self.nodes.items(.data);
    const tag = self.nodes.items(.tag);
    while (stack.items.len > 0) {
        const node_id = stack.pop();
        if (node_id == node_null) continue;

        if (aabbs[node_id].testOverlap(aabb)) {
            if (tag[node_id] == .entity) {
                if (data[node_id] == entity) continue;
                if (have_filter) {
                    if (!callback.filter(data[node_id], entity)) continue;
                }
            } else {
                try stack.append(childs[data[node_id]].left);
                try stack.append(childs[data[node_id]].right);
            }
        }
    }
}
// pub fn print(self: DynamicTree, extra: []const u8) void {
//     const h = self.nodes.items(.height);
//     const c1 = self.nodes.items(.child1);
//     const c2 = self.nodes.items(.child2);
//     const p = self.nodes.items(.parent);
//     log.debug("==== {s} ====\n", .{extra});
//     log.debug("height: {any}\n", .{h});
//     log.debug("child1: {any}\n", .{c1});
//     log.debug("child2: {any}\n", .{c2});
//     log.debug("parent: {any}\n", .{p});
//     var next = self.free_list;
//     log.debug("free_list: ", .{});
//     while (next != node_null) : (next = c1[next]) {
//         log.debug("{},", .{next});
//     }
//     std.debug.print("\n", .{});
// }

pub fn addNode(self: *DynamicTree, aabb: Rect, entity: Index) Index {
    const node_id = self.allocateNode(.{
        .data = entity,
        .aabb = aabb,
        .height = 0,
        .tag = .entity,
    });
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

fn allocateNode(self: *DynamicTree, node: Node) Index {
    const node_id = self.free_list.popFirst(self.nodes.items(.parent));
    if (node_id) |value| {
        self.node_list.set(value, node);
        return value;
    }

    self.node_list.append(self.allocator, node) catch unreachable;
    self.nodes = self.node_list.slice();
    return @intCast(Index, self.node_list.len - 1);
}

fn allocateChild(self: *DynamicTree) Index {
    const child_index = self.child_free.popChild(self.childs.items);
    if (child_index) |value| {
        return value;
    }

    self.childs.append(.{}) catch unreachable;
    return @intCast(Index, self.childs.items.len - 1);
}
fn allocateParent(self: *DynamicTree) Index {
    const child_index = self.allocateChild();
    return self.allocateNode(.{ .height = -1, .data = child_index, .tag = .child});
}

fn freeNode(self: *DynamicTree, node_id: Index) void {
    self.free_list.prepend(node_id, self.nodes.items(.parent));
}

fn freeParent(self: *DynamicTree, parent: Index, child: Index) void {
    self.free_list.prepend(parent, self.nodes.items(.parent));
    self.child_free.prependChild(child, self.childs.items);
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
    var childs = self.childs.items;
    var aabbs = self.nodes.items(.aabb);
    var tag = self.nodes.items(.tag);
    var data = self.nodes.items(.data);
    const leaf_aabb = aabbs[leaf];
    var index = self.root;
    while (tag[index] == .child) {
        const i_data = data[index];
        const child1 = childs[i_data].left;
        const child2 = childs[i_data].right;

        const area = aabbs[index].getPerimeter();

        const combined_aabb = leaf_aabb.combine(aabbs[index]);
        const combined_area = combined_aabb.getPerimeter();

        // Cost of creating a new parent for this node and the new leaf
        const cost = 2 * combined_area;

        // Minimum cost of pushing the leaf further down the tree
        const inheritance_cost = 2 * (combined_area - area);

        // Cost of descending into child1
        const cost1 = blk: {
            if (tag[child1] == .entity) {
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
            if (tag[child2] == .entity) {
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
    const new_parent = self.allocateParent();

    parents = self.nodes.items(.parent);
    aabbs = self.nodes.items(.aabb);
    var heights = self.nodes.items(.height);

    parents[new_parent] = old_parent;
    aabbs[new_parent] = leaf_aabb.combine(aabbs[sibling]);
    heights[new_parent] = heights[sibling] + 1;

    childs = self.childs.items;
    data = self.nodes.items(.data);
    if (old_parent != node_null) {
        // The sibling was not the root.
        const old_parent_data = data[old_parent];
        if (childs[old_parent_data].left == sibling) {
            childs[old_parent_data].left = new_parent;
        } else {
            childs[old_parent_data].right = new_parent;
        }

        parents[leaf] = new_parent;
    } else {
        // The sibling was the root.
        parents[leaf] = new_parent;
        self.root = new_parent;
    }
    const new_parent_data = data[new_parent];
    childs[new_parent_data].left = sibling;
    childs[new_parent_data].right = leaf;
    parents[sibling] = new_parent;

    // Walk back up the tree fixing heights and AABBs
    var i = parents[leaf];
    while (i != node_null) : (i = parents[i]) {
        i = self.balance(i);
        const i_data = data[i];

        const child1 = childs[i_data].left;
        const child2 = childs[i_data].right;

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
    const tag = self.nodes.items(.tag);
    assert(node_id != node_null);
    const ia = node_id;
    if (tag[ia] == .entity or heights[ia] < 2) {
        return ia;
    }
    const data = self.nodes.items(.data);

    var childs = self.childs.items;
    const ia_data = data[ia];
    const ib = childs[ia_data].left;
    const ic = childs[ia_data].right;
    // TODO: b2Assert(0 <= iB && iB < m_nodeCapacity);
    //b2Assert(0 <= iC && iC < m_nodeCapacity);

    // var b = &self.nodes[ib];
    // var c = &self.nodes[ic];
    const balance_height = heights[ic] - heights[ib];

    // Rotate C up
    if (balance_height > 1) {
        var parents = self.nodes.items(.parent);
        const ic_data = data[ic];
        const @"if" = childs[ic_data].left;
        const ig = childs[ic_data].right;
        // var f = &self.nodes[@"if"];
        // var g = &self.nodes[ig];
        // TODO: b2Assert(0 <= iF && iF < m_nodeCapacity);
        //b2Assert(0 <= iG && iG < m_nodeCapacity);

        // Swap A and C
        childs[ic_data].left = ia;
        parents[ic] = parents[ia];
        parents[ia] = ic;

        // A's old parent should point to C
        if (parents[ic] != node_null) {
            const c_parent = parents[ic];
            const c_parent_data = data[c_parent];
            if (childs[c_parent_data].left == ia) {
                childs[c_parent_data].left = ic;
            } else {
                assert(childs[c_parent_data].right == ia);
                childs[c_parent_data].right = ic;
            }
        } else {
            self.root = ic;
        }

        // Rotate
        var aabbs = self.nodes.items(.aabb);
        if (heights[@"if"] > heights[ig]) {
            childs[ic_data].right = @"if";
            childs[ia_data].right = ig;
            parents[ig] = ia;
            aabbs[ia] = aabbs[ib].combine(aabbs[ig]);
            aabbs[ic] = aabbs[ia].combine(aabbs[@"if"]);

            heights[ia] = 1 + std.math.max(heights[ib], heights[ig]);
            heights[ic] = 1 + std.math.max(heights[ia], heights[@"if"]);
        } else {
            childs[ic_data].right = ig;
            childs[ia_data].right = @"if";
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
        const ib_data = data[ib];
        const id = childs[ib_data].left;
        const ie = childs[ib_data].right;
        // var d = &self.nodes[id];
        // var e = &self.nodes[ie];
        // TODO: b2Assert(0 <= iD && iD < m_nodeCapacity);
        //b2Assert(0 <= iE && iE < m_nodeCapacity);

        // Swap A and B
        childs[ib_data].left = ia;
        parents[ib] = parents[ia];
        parents[ia] = ib;

        // A's old parent should point to B
        if (parents[ib] != node_null) {
            const b_parent = parents[ib];
            const b_parent_data = data[b_parent];
            if (childs[b_parent_data].left == ia) {
                childs[b_parent_data].left = ib;
            } else {
                assert(childs[b_parent_data].right == ia);
                childs[b_parent_data].right = ib;
            }
        } else {
            self.root = ib;
        }

        // Rotate
        var aabbs = self.nodes.items(.aabb);
        if (heights[id] > heights[ie]) {
            childs[ib_data].right = id;
            childs[ia_data].left = ie;
            parents[ie] = ia;
            aabbs[ia] = aabbs[ic].combine(aabbs[ie]);
            aabbs[ib] = aabbs[ia].combine(aabbs[id]);

            heights[ia] = 1 + std.math.max(heights[ic], heights[ie]);
            heights[ib] = 1 + std.math.max(heights[ia], heights[id]);
        } else {
            childs[ib_data].right = ie;
            childs[ia_data].left = id;
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
    var data = self.nodes.items(.data);
    var childs = self.childs.items;
    const parent = parents[leaf];
    const grand_parent = parents[parent];
    const parent_data = data[parent];
    const sibling = if (childs[parent_data].left == leaf) childs[parent_data].right else childs[parent_data].left;

    self.freeParent(parent);
    if (grand_parent != node_null) {
        // Destroy parent and connect sibling to grandParent.
        const grand_parent_data = data[grand_parent];
        if (childs[grand_parent_data].left == parent) {
            childs[grand_parent_data].left = sibling;
        } else {
            childs[grand_parent_data].right = sibling;
        }
        parents[sibling] = grand_parent;

        // Adjust ancestor bounds.
        var index = grand_parent;
        var aabbs = self.nodes.items(.aabb);
        var heights = self.nodes.items(.height);
        while (index != node_null) : (index = parents[index]) {
            index = self.balance(index);
            const i_data = data[index];

            const child1 = childs[i_data].left;
            const child2 = childs[i_data].right;

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
        Vec2.new(-1, 1),
        Vec2.new(5, 2),
    ));
    try rects.append(Rect.newFromCenter(
        Vec2.new(-2, -7),
        Vec2.new(9, 1),
    ));
    try rects.append(Rect.newFromCenter(
        Vec2.new(-6, -5),
        Vec2.new(-1, 2),
    ));
    try rects.append(Rect.newFromCenter(
        Vec2.new(-1, -2),
        Vec2.new(3, 0),
    ));
    try rects.append(Rect.newFromCenter(
        Vec2.new(-3, -3),
        Vec2.new(2, -1),
    ));
    for (rects.items) |entry, i| {
        _ = dt.addNode(entry, @intCast(u32, i));
    }

    {
        const QueryCallback = struct {
            const fixed_cap = 1048;
            buffer: [fixed_cap]u8 = undefined,
            pub fn onOverlap(self: *@This(), entity: u32) void {
                _ = self;
                std.debug.print("overlap with {}\n", .{entity});
            }
        };
        var callback = QueryCallback{};
        var allocator = std.heap.FixedBufferAllocator.init(callback.buffer[0..callback.buffer.len]);
        for (rects.items) |aabb, i| {
            try dt.query(aabb, @intCast(u32, i), &allocator.allocator, &callback);
        }
    }
}
test "Performance\n" {
    const builtin = @import("builtin");
    if (builtin.mode == .Debug) {
        return error.SkipZigTest;
    }
    log.debug("\n", .{});
    var dt = DynamicTree.init(std.testing.allocator);
    defer dt.deinit();
    const total = 50_000;
    var random = std.rand.Xoshiro256.init(0).random();
    const max_size = 20;
    const min_size = 1;
    const max = 50_000;
    const min = -50_000;
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
            pub fn onOverlap(self: *@This(), entity: u32) void {
                _ = entity;
                self.total += 1;
            }
        };
        var callback = QueryCallback{};
        var allocator = std.heap.FixedBufferAllocator.init(callback.buffer[0..callback.buffer.len]);
        var timer = try std.time.Timer.start();
        for (entities.items) |aabb, i| {
            try dt.query(aabb, @intCast(u32, i), &allocator.allocator, &callback);
        }
        var time_0 = timer.read();
        std.debug.print("callback query {} entity, with {} callback take {}ms\n", .{
            total,
            callback.total,
            time_0 / std.time.ns_per_ms,
        });
    }
}
