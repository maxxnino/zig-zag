const std = @import("std");
const Rect = @import("rect.zig").Rect;

const assert = std.debug.assert;

pub fn DynamicTree(comptime T: type) type {
    return struct {
        const NodeList = std.MultiArrayList(struct { child1: u32, child2: u32, parent: u32, height: i16, aabb: Aabb });
        const node_null = std.math.maxInt(u32);

        root: u32,
        free_list: u32,
        node_list: NodeList,
        heights: []i16,
        parents: []u32,
        child1s: []u32,
        child2s: []u32,
        aabbs: []Aabb,
        allocator: *std.mem.Allocator,

        pub const Aabb = Rect(T);
        const Self = @This();

        pub fn init(allocator: *std.mem.Allocator) Self {
            return .{
                .root = node_null,
                .free_list = node_null,
                .node_list = NodeList{},
                .heights = undefined,
                .parents = undefined,
                .child1s = undefined,
                .child2s = undefined,
                .aabbs = undefined,
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            self.node_list.deinit(self.allocator);
        }

        pub fn query(self: Self, aabb: Aabb, callback: anytype) void {
            var stack = std.ArrayList(u32).init(self.allocator);
            defer stack.deinit();
            stack.append(self.root) catch unreachable;
            while (stack.items.len > 0) {
                const node_id = stack.pop();
                if (node_id == node_null) continue;

                if (self.aabbs[node_id].testOverlap(aabb)) {
                    if (self.isLeaf(node_id)) {
                        const proceed = callback(node_id);
                        if (proceed == false) return;
                    } else {
                        stack.append(self.child1s[node_id]) catch unreachable;
                        stack.append(self.child2s[node_id]) catch unreachable;
                    }
                }
            }
        }

        pub fn print(self: Self, extra: []const u8) void {
            std.debug.print("==== {s} ====\n", .{extra});
            std.debug.print("height: {any}\n", .{self.heights});
            std.debug.print("child1: {any}\n", .{self.child1s});
            std.debug.print("child2: {any}\n", .{self.child2s});
            std.debug.print("parent: {any}\n", .{self.parents});
            var next = self.free_list;
            std.debug.print("free_list: ", .{});
            while (next != node_null) : (next = self.child1s[next]) {
                std.debug.print("{},", .{next});
            }
            std.debug.print("\n", .{});
        }

        pub fn addNode(self: *Self, aabb: Aabb) u32 {
            const node_id = self.allocateNode();
            self.aabbs[node_id] = aabb;
            self.heights[node_id] = 0;
            self.insertLeaf(node_id);
            return node_id;
        }

        pub fn removeNode(self: *Self, node_id: u32) void {
            self.removeLeaf(node_id);
            self.freeNode(node_id);
        }

        fn allocateNode(self: *Self) u32 {
            const node_id = self.popFreeNode();
            if (node_id) |value| {
                self.heights[value] = 0;
                self.parents[value] = node_null;
                self.child1s[value] = node_null;
                self.child2s[value] = node_null;
                return value;
            }

            self.node_list.append(self.allocator, .{
                .parent = node_null,
                .child1 = node_null,
                .child2 = node_null,
                .height = 0,
                .aabb = Aabb.zero(),
            }) catch unreachable;
            var slice = self.node_list.slice();
            self.parents = slice.items(.parent);
            self.child1s = slice.items(.child1);
            self.child2s = slice.items(.child2);
            self.heights = slice.items(.height);
            self.aabbs = slice.items(.aabb);
            return @intCast(u32, self.node_list.len - 1);
        }

        fn addFreeNode(self: *Self, free_node_index: u32) void {
            self.child1s[free_node_index] = self.free_list;
            self.free_list = free_node_index;
        }

        fn popFreeNode(self: *Self) ?u32 {
            if (self.free_list == node_null) return null;
            const first = self.free_list;
            self.free_list = self.child1s[first];
            return first;
        }

        fn freeNode(self: *Self, node_id: u32) void {
            // TODO: b2Assert(0 <= nodeId && nodeId < m_nodeCapacity);
            self.heights[node_id] = -1;
            self.child1s[node_id] = node_null;
            self.addFreeNode(node_id);
        }

        fn isLeaf(self: Self, node_id: u32) bool {
            return self.child1s[node_id] == node_null;
        }

        fn insertLeaf(self: *Self, leaf: u32) void {
            // TODO: what is this? self.m_insertionCount += 1;
            if (self.root == node_null) {
                self.root = leaf;
                self.parents[leaf] = node_null;
                return;
            }

            // Find the best sibling for this node
            const leaf_aabb = self.aabbs[leaf];
            var index = self.root;
            while (self.isLeaf(index) == false) {
                const child1 = self.child1s[index];
                const child2 = self.child2s[index];

                const area = self.aabbs[index].getPerimeter();

                const combined_aabb = leaf_aabb.combine(self.aabbs[index]);
                const combined_area = combined_aabb.getPerimeter();

                // Cost of creating a new parent for this node and the new leaf
                const cost = 2 * combined_area;

                // Minimum cost of pushing the leaf further down the tree
                const inheritance_cost = 2 * (combined_area - area);

                // Cost of descending into child1
                const cost1 = blk: {
                    if (self.isLeaf(child1)) {
                        const aabb = leaf_aabb.combine(self.aabbs[child1]);
                        break :blk aabb.getPerimeter() + inheritance_cost;
                    } else {
                        const aabb = leaf_aabb.combine(self.aabbs[child1]);
                        const old_area = self.aabbs[child1].getPerimeter();
                        const new_area = aabb.getPerimeter();
                        break :blk (new_area - old_area) + inheritance_cost;
                    }
                };

                // Cost of descending into child2
                const cost2 = blk: {
                    if (self.isLeaf(child2)) {
                        const aabb = leaf_aabb.combine(self.aabbs[child2]);
                        break :blk aabb.getPerimeter() + inheritance_cost;
                    } else {
                        const aabb = leaf_aabb.combine(self.aabbs[child2]);
                        const old_area = self.aabbs[child2].getPerimeter();
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
            const old_parent = self.parents[sibling];
            const new_parent = self.allocateNode();
            self.parents[new_parent] = old_parent;
            self.aabbs[new_parent] = leaf_aabb.combine(self.aabbs[sibling]);
            self.heights[new_parent] = self.heights[sibling] + 1;

            if (old_parent != node_null) {
                // The sibling was not the root.
                if (self.child1s[old_parent] == sibling) {
                    self.child1s[old_parent] = new_parent;
                } else {
                    self.child2s[old_parent] = new_parent;
                }

                self.child1s[new_parent] = sibling;
                self.child2s[new_parent] = leaf;
                self.parents[sibling] = new_parent;
                self.parents[leaf] = new_parent;
            } else {
                // The sibling was the root.
                self.child1s[new_parent] = sibling;
                self.child2s[new_parent] = leaf;
                self.parents[sibling] = new_parent;
                self.parents[leaf] = new_parent;
                self.root = new_parent;
            }

            // Walk back up the tree fixing heights and AABBs
            var i = self.parents[leaf];
            while (i != node_null) : (i = self.parents[i]) {
                i = self.balance(i);

                const child1 = self.child1s[i];
                const child2 = self.child2s[i];

                assert(child1 != node_null);

                self.heights[i] = 1 + std.math.max(
                    self.heights[child1],
                    self.heights[child2],
                );
                self.aabbs[i] = self.aabbs[child1].combine(self.aabbs[child2]);
            }
        }
        fn balance(self: *Self, node_id: u32) u32 {
            assert(node_id != node_null);
            const ia = node_id;
            if (self.isLeaf(ia) and self.heights[ia] < 2) {
                return ia;
            }

            const ib = self.child1s[ia];
            const ic = self.child2s[ia];
            // TODO: b2Assert(0 <= iB && iB < m_nodeCapacity);
            //b2Assert(0 <= iC && iC < m_nodeCapacity);

            // var b = &self.nodes[ib];
            // var c = &self.nodes[ic];
            const balance_height = self.heights[ic] - self.heights[ib];

            // Rotate C up
            if (balance_height > 1) {
                const @"if" = self.child1s[ic];
                const ig = self.child2s[ic];
                // var f = &self.nodes[@"if"];
                // var g = &self.nodes[ig];
                // TODO: b2Assert(0 <= iF && iF < m_nodeCapacity);
                //b2Assert(0 <= iG && iG < m_nodeCapacity);

                // Swap A and C
                self.child1s[ic] = ia;
                self.parents[ic] = self.parents[ia];
                self.parents[ia] = ic;

                // A's old parent should point to C
                if (self.parents[ic] != node_null) {
                    const c_parent = self.parents[ic];
                    if (self.child1s[c_parent] == ia) {
                        self.child1s[c_parent] = ic;
                    } else {
                        assert(self.child2s[c_parent] == ia);
                        self.child2s[c_parent] = ic;
                    }
                } else {
                    self.root = ic;
                }

                // Rotate
                if (self.heights[@"if"] > self.heights[ig]) {
                    self.child2s[ic] = @"if";
                    self.child2s[ia] = ig;
                    self.parents[ig] = ia;
                    self.aabbs[ia] = self.aabbs[ib].combine(self.aabbs[ig]);
                    self.aabbs[ic] = self.aabbs[ia].combine(self.aabbs[@"if"]);

                    self.heights[ia] = 1 + std.math.max(self.heights[ib], self.heights[ig]);
                    self.heights[ic] = 1 + std.math.max(self.heights[ia], self.heights[@"if"]);
                } else {
                    self.child2s[ic] = ig;
                    self.child2s[ia] = @"if";
                    self.parents[@"if"] = ia;
                    self.aabbs[ia] = self.aabbs[ib].combine(self.aabbs[@"if"]);
                    self.aabbs[ic] = self.aabbs[ia].combine(self.aabbs[ig]);

                    self.heights[ia] = 1 + std.math.max(self.heights[ib], self.heights[@"if"]);
                    self.heights[ic] = 1 + std.math.max(self.heights[ia], self.heights[ig]);
                }

                return ic;
            }

            // Rotate B up
            if (balance_height < -1) {
                const id = self.child1s[ib];
                const ie = self.child2s[ib];
                // var d = &self.nodes[id];
                // var e = &self.nodes[ie];
                // TODO: b2Assert(0 <= iD && iD < m_nodeCapacity);
                //b2Assert(0 <= iE && iE < m_nodeCapacity);

                // Swap A and B
                self.child1s[ib] = ia;
                self.parents[ib] = self.parents[ia];
                self.parents[ia] = ib;

                // A's old parent should point to B
                if (self.parents[ib] != node_null) {
                    const b_parent = self.parents[ib];
                    if (self.child1s[b_parent] == ia) {
                        self.child1s[b_parent] = ib;
                    } else {
                        assert(self.child2s[b_parent] == ia);
                        self.child2s[b_parent] = ib;
                    }
                } else {
                    self.root = ib;
                }

                // Rotate
                if (self.heights[id] > self.heights[ie]) {
                    self.child2s[ib] = id;
                    self.child1s[ia] = ie;
                    self.parents[ie] = ia;
                    self.aabbs[ia] = self.aabbs[ic].combine(self.aabbs[ie]);
                    self.aabbs[ib] = self.aabbs[ia].combine(self.aabbs[id]);

                    self.heights[ia] = 1 + std.math.max(self.heights[ic], self.heights[ie]);
                    self.heights[ib] = 1 + std.math.max(self.heights[ia], self.heights[id]);
                } else {
                    self.child2s[ib] = ie;
                    self.child1s[ia] = id;
                    self.parents[id] = ia;
                    self.aabbs[ia] = self.aabbs[ic].combine(self.aabbs[id]);
                    self.aabbs[ib] = self.aabbs[ia].combine(self.aabbs[ie]);

                    self.heights[ia] = 1 + std.math.max(self.heights[ic], self.heights[id]);
                    self.heights[ib] = 1 + std.math.max(self.heights[ia], self.heights[ie]);
                }

                return ib;
            }

            return ia;
        }
        fn removeLeaf(self: *Self, leaf: u32) void {
            assert(self.root != node_null);
            if (leaf == self.root) {
                self.root = node_null;
                return;
            }
            const parent = self.parents[leaf];
            var grand_parent = self.parents[parent];
            const sibling = if (self.child1s[parent] == leaf) self.child2s[parent] else self.child1s[parent];

            if (grand_parent != node_null) {
                // Destroy parent and connect sibling to grandParent.
                if (self.child1s[grand_parent] == parent) {
                    self.child1s[grand_parent] = sibling;
                } else {
                    self.child2s[grand_parent] = sibling;
                }
                self.parents[sibling] = grand_parent;
                self.freeNode(parent);

                // Adjust ancestor bounds.
                var index = grand_parent;
                while (index != node_null) : (index = self.parents[index]) {
                    index = self.balance(index);

                    const child1 = self.child1s[index];
                    const child2 = self.child2s[index];

                    self.aabbs[index] = self.aabbs[child1].combine(self.aabbs[child2]);
                    self.heights[index] = 1 + std.math.max(self.heights[child1], self.heights[child2]);
                }
            } else {
                self.root = sibling;
                self.parents[sibling] = node_null;
                self.freeNode(parent);
            }
        }
    };
}

fn queryCallback(node_id: u32) bool {
    std.debug.print("Overlap with: {}\n", .{node_id});
    return true;
}

test "Dynamic Tree add/remove Node" {
    std.debug.print("\n", .{});
    const DyT = DynamicTree(i32);
    var dt = DyT.init(std.testing.allocator);
    defer dt.deinit();
    const Aabb = DyT.Aabb;
    const Vec2 = Aabb.Vec2;
    const aabb = Aabb.new(
        Vec2.new(1, 1),
        Vec2.new(3, 3),
    );
    const aabb1 = Aabb.new(
        Vec2.new(2, 2),
        Vec2.new(4, 4),
    );

    std.debug.print("==== query 1 ====\n", .{});
    dt.query(aabb1, queryCallback);

    var id = dt.addNode(aabb);
    dt.print("add 1 node");

    std.debug.print("==== query 2 ====\n", .{});
    dt.query(aabb1, queryCallback);

    var id2 = dt.addNode(aabb);
    dt.print("add another node");
    dt.removeNode(id);
    dt.print("remove 1 node");

    std.debug.print("==== query 3 ====\n", .{});
    dt.query(aabb1, queryCallback);

    dt.removeNode(id2);
    dt.print("remove 1 node");

    std.debug.print("==== query 5 ====\n", .{});
    dt.query(aabb1, queryCallback);
    id = dt.addNode(aabb);
    id = dt.addNode(aabb);
    id = dt.addNode(aabb);
    dt.print("add 3 node");
}
