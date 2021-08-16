const za = @import("zalgebra");

pub fn Aabb(comptime T: type) type {
    if (@typeInfo(T) != .Float and @typeInfo(T) != .Int) {
        @compileError("Aabb not implemented for " ++ @typeName(T));
    }

    return struct {
        pub const Vec2 = za.Vector2(T);
        const Self = @This();

        upper_bound: Vec2,
        lower_bound: Vec2,

        /// Contruct Aabb form given 2 Vector2
        pub fn new(upper_bound: Vec2, lower_bound: Vec2) Self {
            return .{
                .upper_bound = upper_bound,
                .lower_bound = lower_bound,
            };
        }

        pub fn testOverlap(a: Self, b: Self) bool {
            const d1 = Vec2.sub(b.lower_bound, a.upper_bound);
            const d2 = Vec2.sub(a.lower_bound, b.upper_bound);
            if (d1.x > 0 or d1.y > 0) return false;
            if (d2.x > 0 or d2.y > 0) return false;
            return true;
        }

        /// Contruct new aabb with 2 given aabb
        pub fn combine(a: Self, b: Self) Self {
            return Self.new(
                Vec2.max(a.upper_bound, b.upper_bound),
                Vec2.min(a.lower_bound, b.lower_bound),
            );
        }

        pub fn getPerimeter(self: Self) T {
            const wx = self.upper_bound.x - self.lower_bound.x;
            const wy = self.upper_bound.y - self.lower_bound.y;
            return 2 * (wx + wy);
        }

        pub fn zero() Self {
            return Self.new(Vec2.zero(), Vec2.zero());
        }
    };
}
