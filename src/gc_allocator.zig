const std = @import("std");
const vm_file = @import("virtual_machine.zig");
const value_file = @import("value.zig");

const Allocator = std.mem.Allocator;
const VirtualMachine = vm_file.VirtualMachine;
const String = value_file.String;
const Value = value_file.Value;

const ObjectType = enum {
    object,
    function,
    list,
    string,
    // ... other types
};

const DestroyFn = *const fn (allocator: Allocator, ptr: *anyopaque) void;

pub const GcNode = struct {
    marked: bool = false,
    next: ?*GcNode = null,
    previous: ?*GcNode = null,
    object_type: ObjectType,
    size: usize,
    destroy_fn: DestroyFn,

    const Self = @This();

    pub fn unlink(self: *Self) void {
        if (self.previous) |prev| {
            prev.next = self.next;
        }
        if (self.next) |next| {
            next.previous = self.previous;
        }
        self.previous = null;
        self.next = null;
    }
};

/// Wrapper that makes any type GC-trackable
pub fn GcObject(comptime T: type) type {
    return struct {
        header: GcNode,
        data: T,

        const Self = @This();

        /// Get the GcNode header for this object
        pub fn getGcNode(self: *Self) *GcNode {
            return &self.header;
        }

        /// Get the object type for debugging/introspection
        pub fn getObjectType(self: *Self) ObjectType {
            return self.header.object_type;
        }

        /// Generic destroy function for most objects
        fn destroy(allocator: Allocator, ptr: *anyopaque) void {
            const self_ptr: *Self = @ptrCast(@alignCast(ptr));
            allocator.destroy(self_ptr);
        }

        /// Special destroy function for String objects
        fn destroyString(allocator: Allocator, ptr: *anyopaque) void {
            const self_ptr: *GcObject(String) = @ptrCast(@alignCast(ptr));
            // Free the string data first
            allocator.free(self_ptr.data.value);
            // Then destroy the wrapper
            allocator.destroy(self_ptr);
        }
    };
}

pub const GcAllocator = struct {
    objects: ?*GcNode = null,
    backing_allocator: Allocator,
    bytes_allocated: usize = 0,
    gc_threshold: usize = 1024 * 1024, // 1 MB
    vm: ?*VirtualMachine,
    interned_strings: std.StringHashMap(*GcObject(String)),

    const Self = @This();

    pub fn init(backing_allocator: Allocator) Self {
        return .{
            .backing_allocator = backing_allocator,
            .vm = null,
            .interned_strings = std.StringHashMap(*GcObject(String)).init(backing_allocator),
        };
    }

    pub fn setVm(self: *Self, vm: *VirtualMachine) void {
        self.vm = vm;
    }

    // pub fn deinit(self: *Self) void {
    //     var current = self.objects;
    //     while (current != null) {
    //         const next = current.?.next;
    //         current.?.destroy_fn(self.backing_allocator, current.?);
    //         current = next;
    //     }
    //     self.interned_strings.deinit();
    //     std.debug.print("TOTAL BYTES ALLOCATED: {d}\n", .{self.bytes_allocated});
    // }
    //
    pub fn deinit(self: *Self) void {
        // Clean up objects FIRST (while HashMap is still valid)
        var current = self.objects;
        while (current != null) {
            const next = current.?.next;

            // Convert GcNode* back to the original GcObject(T)*
            const gc_obj_ptr: *GcObject(String) = @fieldParentPtr("header", current.?);
            current.?.destroy_fn(self.backing_allocator, gc_obj_ptr);

            current = next;
        }

        // THEN clean up the HashMap
        self.interned_strings.deinit();

        std.debug.print("TOTAL BYTES ALLOCATED: {d}\n", .{self.bytes_allocated});
    }

    /// Generic allocation helper - used by specific methods
    fn allocGcObject(self: *Self, comptime T: type, object_type: ObjectType, destroy_fn: DestroyFn) !*GcObject(T) {
        if (self.bytes_allocated > self.gc_threshold) {
            self.collect();
        }

        const GcT = GcObject(T);
        const total_size = @sizeOf(GcT);

        const obj = try self.backing_allocator.create(GcT);
        self.bytes_allocated += total_size;

        // Initialize the header
        obj.header = GcNode{
            .object_type = object_type,
            .size = total_size,
            .destroy_fn = destroy_fn,
        };

        self.pushNode(&obj.header);

        // Note: data field is uninitialized - caller must initialize it
        return obj;
    }

    /// Allocate a language object (hash map, etc.)
    pub fn allocObject(self: *Self, comptime T: type) !*GcObject(T) {
        return self.allocGcObject(T, .object);
    }

    /// Allocate a function object
    pub fn allocFunction(self: *Self, comptime T: type) !*GcObject(T) {
        return self.allocGcObject(T, .function);
    }

    /// Allocate a list/array object
    pub fn allocList(self: *Self, comptime T: type) !*GcObject(T) {
        return self.allocGcObject(T, .list);
    }

    /// Allocate a string object
    pub fn allocString(self: *Self, str: []const u8) !*GcObject(String) {
        if (self.interned_strings.get(str)) |exists| {
            std.debug.print("INTERNED STRINGS: {d}\n", .{self.interned_strings.count()});
            return exists;
        }

        const owned_str = try self.backing_allocator.dupe(u8, str);
        var newString = try self.allocGcObject(String, .string, GcObject(String).destroyString);
        newString.data = String{ .value = owned_str };

        try self.interned_strings.put(str, newString);
        std.debug.print("INTERNED STRINGS: {d}\n", .{self.interned_strings.count()});
        return newString;
    }

    /// Mark any GC object during tracing
    pub fn markObject(self: *Self, obj: anytype) void {
        const node = obj.getGcNode();
        if (node.marked) return; // Already visited

        node.marked = true;

        const data_type = @TypeOf(obj.data);
        const type_info = @typeInfo(data_type);

        switch (type_info) {
            .@"struct", .@"union", .@"enum" => {
                // Call type-specific tracing if the type supports it
                if (@hasDecl(data_type, "traceReferences")) {
                    obj.data.traceReferences(self);
                }
            },
            else => {
                // For other types (slices, arrays, primitives, etc.), no tracing needed
            },
        }
    }

    // Allocator Interface Methods
    pub fn allocator(self: *Self) Allocator {
        return Allocator{
            .ptr = self,
            .vtable = &.{
                .alloc = alloc,
                .free = free,
                .resize = resize,
                .remap = remap,
            },
        };
    }

    fn alloc(ctx: *anyopaque, len: usize, alignment: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
        const self: *Self = @ptrCast(@alignCast(ctx));

        const result = self.backing_allocator.rawAlloc(len, alignment, ret_addr);
        if (result != null) {
            self.bytes_allocated += len;
        }

        return result;
    }

    fn resize(ctx: *anyopaque, buf: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) bool {
        _ = ctx;
        _ = buf;
        _ = alignment;
        _ = new_len;
        _ = ret_addr;

        return false;
    }

    fn remap(ctx: *anyopaque, buf: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
        _ = ctx;
        _ = buf;
        _ = alignment;
        _ = new_len;
        _ = ret_addr;

        return null;
    }

    fn free(ctx: *anyopaque, buf: []u8, alignment: std.mem.Alignment, ret_addr: usize) void {
        const self: *Self = @ptrCast(@alignCast(ctx));
        self.backing_allocator.rawFree(buf, alignment, ret_addr);
        self.bytes_allocated -= buf.len;
    }

    pub fn collect(self: *Self) void {
        if (self.vm) |vm| {
            vm.traceRoots();
        }
        self.sweep();
        self.resetMarks();
    }

    pub fn sweep(self: *Self) void {
        var current = self.objects;

        while (current != null) {
            if (current) |node| {
                const next = node.next;

                if (!node.marked) {
                    if (node == self.objects) {
                        self.objects = next;
                    }
                    node.unlink();

                    const current_size = node.size;

                    node.destroy_fn(self.backing_allocator, node);

                    // Safe subtraction to prevent underflow
                    if (self.bytes_allocated >= current_size) {
                        self.bytes_allocated -= current_size;
                    } else {
                        std.log.warn("GC accounting error: trying to subtract {} from {}", .{ current_size, self.bytes_allocated });
                        self.bytes_allocated = 0;
                    }
                }
                current = next;
            }
        }
    }

    fn resetMarks(self: *Self) void {
        var current = self.objects;
        while (current) |node| {
            node.marked = false;
            current = node.next;
        }
    }

    fn pushNode(self: *Self, node: *GcNode) void {
        if (self.objects != null) {
            self.objects.?.previous = node;
        }
        node.next = self.objects;
        self.objects = node;
    }
};

const testing = std.testing;

test "GcAllocator basic allocation and deallocation" {
    var gc = GcAllocator.init(testing.allocator);
    defer gc.deinit();

    // Test simple object allocation
    const obj = try gc.allocGcObject(struct { x: i32 }, .object, GcObject(struct { x: i32 }).destroy);
    // defer gc.backing_allocator.destroy(obj); // Manually destroy for test

    obj.data.x = 42;
    try testing.expect(obj.data.x == 42);
    try testing.expect(gc.objects != null);
    try testing.expect(gc.bytes_allocated > 0);
}

test "GcAllocator string interning" {
    var gc = GcAllocator.init(testing.allocator);
    defer gc.deinit();

    const str1 = try gc.allocString("hello");
    const str2 = try gc.allocString("hello");
    const str3 = try gc.allocString("world");

    // Should return same pointer for same string
    try testing.expect(str1 == str2);
    // Different strings should get different pointers
    try testing.expect(str1 != str3);
    try testing.expectEqualStrings(str1.data.value, "hello");
    try testing.expectEqualStrings(str3.data.value, "world");
}

test "GcAllocator mark and sweep" {
    var gc = GcAllocator.init(testing.allocator);
    defer gc.deinit();

    // Allocate some objects
    const obj1 = try gc.allocGcObject(struct { val: i32 }, .object, GcObject(struct { val: i32 }).destroy);
    _ = try gc.allocGcObject(struct { val: i32 }, .object, GcObject(struct { val: i32 }).destroy);

    // Mark one object as reachable
    gc.markObject(obj1);

    // Run collection
    gc.sweep();

    // obj1 should still exist, obj2 should be collected
    try testing.expect(gc.objects != null);
    try testing.expect(gc.objects.? == obj1.getGcNode());
    try testing.expect(gc.objects.?.next == null);
}

test "GcAllocator memory accounting" {
    var gc = GcAllocator.init(testing.allocator);
    defer gc.deinit();

    const initial_bytes = gc.bytes_allocated;

    // Allocate a string
    _ = try gc.allocString("test string");
    const after_alloc_bytes = gc.bytes_allocated;
    try testing.expect(after_alloc_bytes > initial_bytes);

    // Mark and sweep should collect it
    gc.sweep();
    try testing.expect(gc.bytes_allocated == initial_bytes);
}

test "GcAllocator integration with VM" {
    var gc = GcAllocator.init(testing.allocator);
    defer gc.deinit();

    var vm = VirtualMachine.init(&gc);
    defer vm.deinit();

    gc.setVm(&vm);

    const str1 = try gc.allocString("hello");
    const str2 = try gc.allocString("world");

    vm.push(Value{ .String = str1 });
    vm.push(Value{ .String = str2 });

    // Force a collection
    gc.collect();

    // Verify objects are still accessible
    try testing.expect(gc.objects != null);
}

// test "GcAllocator stress test" {
//     var gc = GcAllocator.init(testing.allocator);
//     defer gc.deinit();

//     // Allocate many objects
//     const alloc_count = 1000;
//     var objects = std.ArrayList(*GcObject(struct { id: usize })).init(testing.allocator);
//     defer objects.deinit();

//     for (0..alloc_count) |i| {
//         const obj = try gc.allocGcObject(struct { id: usize }, .object, GcObject(struct { id: usize }).destroy);
//         obj.data.id = i;
//         try objects.append(obj);
//     }

//     // Mark every other object
//     for (objects.items, 0..) |obj, i| {
//         if (i % 2 == 0) {
//             gc.markObject(obj);
//         }
//     }

//     // Run collection
//     gc.collect();

//     // Verify half were collected
//     var count: usize = 0;
//     var current = gc.objects;
//     while (current) |node| {
//         count += 1;
//         current = node.next;
//     }
//     try testing.expect(count == alloc_count / 2);
// }

test "GcAllocator destruction order" {
    // This test verifies proper cleanup order
    var gc = GcAllocator.init(testing.allocator);

    // Create some objects
    _ = try gc.allocString("test1");
    _ = try gc.allocString("test2");

    // This should clean up everything without crashes
    gc.deinit();
}

// test "GcNode linking/unlinking" {
//     var gc = GcAllocator.init(testing.allocator);
//     defer gc.deinit();

//     const obj1 = try gc.allocGcObject(struct { x: i32 }, .object, GcObject(struct { x: i32 }).destroy);
//     const obj2 = try gc.allocGcObject(struct { x: i32 }, .object, GcObject(struct { x: i32 }).destroy);
//     const obj3 = try gc.allocGcObject(struct { x: i32 }, .object, GcObject(struct { x: i32 }).destroy);

//     // Verify linked list structure
//     try testing.expect(gc.objects == obj3.getGcNode());
//     try testing.expect(gc.objects.?.next == obj2.getGcNode());
//     try testing.expect(gc.objects.?.next.?.next == obj1.getGcNode());

//     // Test unlinking middle node
//     obj2.getGcNode().unlink();
//     try testing.expect(gc.objects == obj3.getGcNode());
//     try testing.expect(gc.objects.?.next == obj1.getGcNode());
//     try testing.expect(gc.objects.?.next.?.previous == obj3.getGcNode());
// }

// test "GcAllocator edge cases" {
//     var gc = GcAllocator.init(testing.allocator);
//     defer gc.deinit();

//     // Test empty string
//     const empty_str = try gc.allocString("");
//     try testing.expectEqualStrings(empty_str.data.value, "");

//     // Test allocation right at threshold
//     gc.gc_threshold = 64;
//     const small_obj = try gc.allocGcObject(struct { x: i32 }, .object, GcObject(struct { x: i32 }).destroy);
//     try testing.expect(small_obj != null);
// }

test "empty GC behaves correctly" {
    var gc = GcAllocator.init(testing.allocator);
    defer gc.deinit();

    gc.collect(); // Shouldn't crash
    try testing.expect(gc.objects == null);
}
