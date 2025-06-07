const std = @import("std");
const vm_file = @import("virtual_machine.zig");
const value_file = @import("value.zig");

const Allocator = std.mem.Allocator;
const VirtualMachine = vm_file.VirtualMachine;
const String = value_file.String;

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
    vm: *VirtualMachine,
    interned_strings: std.StringHashMap(*GcObject(String)),

    const Self = @This();

    pub fn init(backing_allocator: Allocator, vm: *VirtualMachine) Self {
        return .{
            .backing_allocator = backing_allocator,
            .vm = vm,
            .interned_strings = std.StringHashMap(*GcObject(String)).init(backing_allocator),
        };
    }

    pub fn deinit(self: *Self) void {
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
        self.vm.traceRoots();
        self.sweep();
        self.resetMarks();
    }

    fn sweep(self: *Self) void {
        var current = self.objects;

        while (current) |node| {
            const next = node.next;

            if (!node.marked) {
                if (node == self.objects) {
                    self.objects = node.next;
                }
                node.unlink();

                node.destroy_fn(self.backing_allocator, node);

                // Safe subtraction to prevent underflow
                if (self.bytes_allocated >= node.size) {
                    self.bytes_allocated -= node.size;
                } else {
                    std.log.warn("GC accounting error: trying to subtract {} from {}", .{ node.size, self.bytes_allocated });
                    self.bytes_allocated = 0;
                }
            }

            current = next;
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
