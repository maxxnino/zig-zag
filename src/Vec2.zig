const std = @import("std");
const math = std.math;

pub const Vec2 = Vector2(f32);
pub const Vec2_f64 = Vector2(f64);
pub const Vec2_i32 = Vector2(i32);

/// A 2 dimensional vector.
pub fn Vector2(comptime T: type) type {
    if (@typeInfo(T) != .Float and @typeInfo(T) != .Int) {
        @compileError("Vector2 not implemented for " ++ @typeName(T));
    }

    return struct {
        x: T,
        y: T,

        const Self = @This();

        /// Construct vector from given 2 components.
        pub fn new(x: T, y: T) Self {
            return .{ .x = x, .y = y };
        }

        /// Set all components to the same given value.
        pub fn set(val: T) Self {
            return Self.new(val, val);
        }

        pub fn zero() Self {
            return Self.new(0, 0);
        }

        pub fn one() Self {
            return Self.new(1, 1);
        }

        pub fn up() Self {
            return Self.new(0, 1);
        }

        /// Cast a type to another type. Only for integers and floats.
        /// It's like builtins: @intCast, @floatCast, @intToFloat, @floatToInt.
        pub fn cast(self: Self, dest: anytype) Vector2(dest) {
            const source_info = @typeInfo(T);
            const dest_info = @typeInfo(dest);

            if (source_info == .Float and dest_info == .Int) {
                const x = @floatToInt(dest, self.x);
                const y = @floatToInt(dest, self.y);
                return Vector2(dest).new(x, y);
            }

            if (source_info == .Int and dest_info == .Float) {
                const x = @intToFloat(dest, self.x);
                const y = @intToFloat(dest, self.y);
                return Vector2(dest).new(x, y);
            }

            return switch (dest_info) {
                .Float => {
                    const x = @floatCast(dest, self.x);
                    const y = @floatCast(dest, self.y);
                    return Vector2(dest).new(x, y);
                },
                .Int => {
                    const x = @intCast(dest, self.x);
                    const y = @intCast(dest, self.y);
                    return Vector2(dest).new(x, y);
                },
                else => panic(
                    "Error, given type should be integer or float.\n",
                    .{},
                ),
            };
        }

        /// Construct new vector from slice.
        pub fn fromSlice(slice: []const T) Self {
            return Self.new(slice[0], slice[1]);
        }

        /// Transform vector to array.
        pub fn toArray(self: Self) [2]T {
            return .{ self.x, self.y };
        }

        /// Return the angle in degrees between two vectors.
        //pub fn getAngle(left: Self, right: Self) T {
        //    const dot_product = Self.dot(left.norm(), right.norm());
        //    return root.toDegrees(math.acos(dot_product));
        //}

        /// Compute the length (magnitude) of given vector |a|.
        pub fn length(self: Self) T {
            return math.sqrt((self.x * self.x) + (self.y * self.y));
        }

        /// Compute the distance between two points.
        pub fn distance(a: Self, b: Self) T {
            return math.sqrt(
                math.pow(T, b.x - a.x, 2) + math.pow(T, b.y - a.y, 2),
            );
        }

        /// Construct new normalized vector from a given vector.
        pub fn norm(self: Self) Self {
            var l = length(self);
            return Self.new(self.x / l, self.y / l);
        }

        pub fn eql(left: Self, right: Self) bool {
            return left.x == right.x and left.y == right.y;
        }

        /// Substraction between two given vector.
        pub fn sub(left: Self, right: Self) Self {
            return Self.new(left.x - right.x, left.y - right.y);
        }

        /// Addition betwen two given vector.
        pub fn add(left: Self, right: Self) Self {
            return Self.new(left.x + right.x, left.y + right.y);
        }

        /// Multiply each components by the given scalar.
        pub fn scale(v: Self, scalar: T) Self {
            return Self.new(v.x * scalar, v.y * scalar);
        }

        /// Return the dot product between two given vector.
        pub fn dot(left: Self, right: Self) T {
            return (left.x * right.x) + (left.y * right.y);
        }

        /// Lerp between two vectors.
        // pub fn lerp(left: Self, right: Self, t: T) Self {
        //     const x = root.lerp(T, left.x, right.x, t);
        //     const y = root.lerp(T, left.y, right.y, t);
        //     return Self.new(x, y);
        // }

        /// Construct a new vector from the min components between two vectors.
        pub fn min(left: Self, right: Self) Self {
            return Self.new(
                math.min(left.x, right.x),
                math.min(left.y, right.y),
            );
        }

        /// Construct a new vector from the max components between two vectors.
        pub fn max(left: Self, right: Self) Self {
            return Self.new(
                math.max(left.x, right.x),
                math.max(left.y, right.y),
            );
        }
    };
}
