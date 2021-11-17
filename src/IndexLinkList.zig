const basic_type = @import("basic_type.zig");
const Index = basic_type.Index;
const node_null = basic_type.node_null;
const IndexLinkList = @This();
const Child = @import("DynamicTree.zig").Child;

first: u32 = node_null,

/// Insert a new node at the head.
pub fn prepend(list: *IndexLinkList, node: Index, next: []Index) void {
    next[node] = list.first;
    list.first = node;
}

pub fn getFirst(list: IndexLinkList) ?Index {
    return if (list.first != node_null) list.first else null;
}

pub fn popFirst(list: *IndexLinkList, next: []Index) ?Index {
    if (list.first == node_null) return null;
    const first = list.first;
    list.first = next[first];
    return first;
}
