const std = @import("std");
pub const Rect = @import("rect.zig").RectFloat;
pub const za = @import("zalgebra");
pub const Vec2 = za.Vec2;
pub const Vec2u32 = za.GenericVector(2, u32);
pub const Index = u32;
pub const node_null = std.math.maxInt(Index);
