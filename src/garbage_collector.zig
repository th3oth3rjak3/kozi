//! garbage_collector contains all of the memory management for garbage collected
//! objects in the language.

const std = @import("std");
const builtin = @import("builtin");
const object = @import("object.zig");
const virtual_machine = @import("virtual_machine.zig");

const VirtualMachine = virtual_machine.VirtualMachine;
const Object = object.Object;

const TraceFn = *const fn (ctx: *anyopaque, tracer: *Tracer) anyerror!void;

pub const HeapAllocated = union(enum) {
    string: []const u8,
};

pub const GcObject = struct {
    marked: bool,
    next: ?*GcObject,
    value: HeapAllocated,

    pub fn getType(self: *const GcObject) std.meta.Tag(HeapAllocated) {
        return @as(std.meta.Tag(HeapAllocated), self.value);
    }

    pub fn asString(self: *const GcObject) ?[]const u8 {
        return switch (self.value) {
            .string => |str| str,
            // else => null,
        };
    }

    // pub fn asFunction(self: *const GcObject) ?*const ObjFunction {
    //     return switch (self.value) {
    //         .function => |*func| func,
    //         else => null,
    //     };
    // }
};

pub const Tracer = struct {
    gray_stack: std.ArrayList(*GcObject),
    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Tracer {
        return Tracer{
            .gray_stack = std.ArrayList(*GcObject).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.gray_stack.deinit();
    }

    /// Mark an object as reachable
    fn markObject(self: *Self, obj: ?*GcObject) !void {
        if (obj == null or obj.?.marked) return;

        obj.?.marked = true;
        try self.gray_stack.append(obj.?);
    }

    /// Mark a value (handles both stack and heap values)
    pub fn markValue(self: *Self, value: *Object) !void {
        switch (value.*) {
            .String => |obj| try self.markObject(obj),
            else => {}, // Stack values don't need to be marked.
        }
    }

    /// Trace references from gray objects (mark phase)
    fn traceReferences(self: *Self) !void {
        while (self.gray_stack.items.len > 0) {
            const obj = self.gray_stack.pop();
            if (obj) |exists| {
                try self.blackenObject(exists);
            }
        }
    }

    /// Mark all objects referenced by this object
    fn blackenObject(self: *Self, obj: *GcObject) !void {
        _ = self;
        switch (obj.value) {
            .string => {}, // Strings don't reference other objects
            // .function => |func| {
            // // Mark the function name (interned string reference)
            //     try self.markObject(func.name);
            // // Functions might reference other objects in closures/constants
            // // This is where you'd mark closure variables, constants, etc.
            // },
        }
    }
};

const HEAP_GROW_FACTOR = 2;
const GC_HEAP_INIT_SIZE: comptime_int = 1024 * 1024; // 1MB

/// GarbageCollector wraps an allocator and manages memory for the language runtime.
pub const GarbageCollector = struct {
    gc_allocator: std.mem.Allocator,
    trace_fn: ?TraceFn,
    objects: ?*GcObject,
    bytes_allocated: usize,
    next_gc: usize,

    strings: std.hash_map.StringHashMap(*GcObject),
    tracer: Tracer,
    tracing_ctx: ?*anyopaque,

    const Self = @This();

    pub fn init(provided_allocator: std.mem.Allocator) GarbageCollector {
        return GarbageCollector{
            .gc_allocator = provided_allocator,
            .trace_fn = null,
            .objects = null,
            .bytes_allocated = 0,
            .next_gc = GC_HEAP_INIT_SIZE,
            .strings = std.StringHashMap(*GcObject).init(provided_allocator),
            .tracer = Tracer.init(provided_allocator),
            .tracing_ctx = null,
        };
    }

    pub fn deinit(self: *Self) void {
        self.strings.deinit();
        self.freeObjects();
        self.tracer.deinit();
    }

    pub fn allocator(self: *Self) std.mem.Allocator {
        return self.gc_allocator;
    }

    pub fn setTraceCallback(self: *Self, ctx: *anyopaque, trace: TraceFn) void {
        self.trace_fn = trace;
        self.tracing_ctx = ctx;
    }

    /// Free all objects (called during shutdown)
    fn freeObjects(self: *GarbageCollector) void {
        var current = self.objects;
        while (current) |obj| {
            const next = obj.next;
            self.freeObject(obj);
            current = next;
        }
    }

    /// Free a single object and its associated data
    fn freeObject(self: *GarbageCollector, obj: *GcObject) void {
        switch (obj.value) {
            .string => |str| {
                // We own the string data
                self.gc_allocator.free(str);
                // self.allocator.free(@constCast(str));
                self.bytes_allocated -= str.len;
            },
            // .function => |func| {
            //     // We own the bytecode, but NOT the name (it's interned)
            //     self.allocator.free(@constCast(func.chunk));
            //     self.bytes_allocated -= func.chunk.len;
            //     // Don't free func.name - it's managed by string interning
            // },
        }

        self.bytes_allocated -= @sizeOf(GcObject);
        self.gc_allocator.destroy(obj);
    }

    /// Remove unmarked objects (sweep phase)
    fn sweep(self: *GarbageCollector) void {
        // First, remove unmarked strings from intern table
        var string_iter = self.strings.iterator();
        var to_remove = std.ArrayList([]const u8).init(self.gc_allocator);
        defer to_remove.deinit();

        while (string_iter.next()) |entry| {
            if (!entry.value_ptr.*.marked) {
                to_remove.append(entry.key_ptr.*) catch {}; // Best effort
            }
        }

        for (to_remove.items) |key| {
            _ = self.strings.remove(key);
        }

        // Then sweep the object list
        var previous: ?*GcObject = null;
        var current = self.objects;

        while (current) |obj| {
            if (obj.marked) {
                obj.marked = false; // Reset for next GC cycle
                previous = obj;
                current = obj.next;
            } else {
                const unreached = obj;
                current = obj.next;

                if (previous) |prev| {
                    prev.next = current;
                } else {
                    self.objects = current;
                }

                self.freeObject(unreached);
            }
        }
    }

    /// allocateString creates a new string on the heap.
    pub fn allocateString(self: *Self, value: []const u8) !*GcObject {
        if (self.strings.get(value)) |existing| {
            return existing;
        }

        return try self.internString(value);
    }

    /// allocateObject handles allocation of any HeapAllocated type. All objects
    /// passed into this function must be owned.
    fn allocateObject(self: *Self, heap_object: HeapAllocated) !*GcObject {
        const obj = try self.gc_allocator.create(GcObject);
        obj.* = GcObject{
            .marked = false,
            .next = self.objects,
            .value = heap_object,
        };

        self.objects = obj;
        self.bytes_allocated += @sizeOf(GcObject);

        // Add size of the actual data
        switch (heap_object) {
            .string => |str| self.bytes_allocated += str.len,
            // .function => |func| self.bytes_allocated += func.chunk.len,
        }

        if (self.bytes_allocated > self.next_gc) {
            try self.collectGarbage();
        }

        return obj;
    }

    /// Run the mark and sweep garbage collector
    pub fn collectGarbage(self: *GarbageCollector) !void {
        const before = self.bytes_allocated;

        // Mark phase: use the supplied tracing function
        // to mark all the reachable objects.
        if (self.trace_fn) |trace| {
            if (self.tracing_ctx) |ctx| {
                try trace(ctx, &self.tracer);
            }
        }

        // Sweep phase: free unmarked objects
        self.sweep();

        // Adjust the threshold for the next GC
        self.next_gc = @max(self.bytes_allocated * HEAP_GROW_FACTOR, GC_HEAP_INIT_SIZE);

        if (builtin.mode == .Debug) {
            std.debug.print("GC: collected {} bytes (from {} to {}), next at {}\n", .{
                before - self.bytes_allocated,
                before,
                self.bytes_allocated,
                self.next_gc,
            });
        }
    }

    /// Force garbage collection (for testing/debugging)
    pub fn forceGc(self: *GarbageCollector) !void {
        try self.collectGarbage();
    }

    /// Get current memory usage
    pub fn getBytesAllocated(self: *const GcObject) usize {
        return self.bytes_allocated;
    }

    /// internString deduplicates strings in the application for faster lookup.
    fn internString(self: *Self, value: []const u8) !*GcObject {
        if (self.strings.get(value)) |v| {
            return v;
        }

        const owned = try self.gc_allocator.dupe(u8, value);
        const obj = try self.allocateObject(HeapAllocated{ .string = owned });
        try self.strings.put(owned, obj);
        return obj;
    }

    /// Get a string's content for debugging/printing
    pub fn getStringChars(obj: *const GcObject) ?[]const u8 {
        return if (obj.asString()) |str| str else null;
    }

    /// Compare two string objects for equality (fast path using interning)
    pub fn stringsEqual(a: *const GcObject, b: *const GcObject) bool {
        return a == b;
    }
};

test "GarbageCollector init and deinit works" {
    const allocator = std.testing.allocator;
    var gc = GarbageCollector.init(allocator);
    defer gc.deinit();

    try std.testing.expect(gc.objects == null);
    try std.testing.expect(gc.bytes_allocated == 0);
    try std.testing.expect(gc.next_gc == 1024 * 1024); // initial threshold
}

test "Allocate a string object and intern string" {
    const allocator = std.testing.allocator;
    var gc = GarbageCollector.init(allocator);
    defer gc.deinit();

    const obj = try gc.internString("test");
    const the_str = obj.asString();
    if (the_str) |exists| {
        try std.testing.expect(std.mem.eql(u8, exists, "test"));
    } else {
        try std.testing.expect(false); // The string should have existed.
    }

    // Interning the same string should return the same object
    const interned1 = try gc.internString("test");
    const interned2 = try gc.internString("test");
    try std.testing.expect(interned1 == interned2);
}

test "Mark and sweep removes unreachable objects" {
    const allocator = std.testing.allocator;
    var gc = GarbageCollector.init(allocator);
    defer gc.deinit();

    const str1 = try gc.allocateString("foo");
    const str2 = try gc.allocateString("bar");

    // Manually link objects to gc.objects
    gc.objects = str1;
    str1.next = str2;
    str2.next = null;

    // Mark only str1 as reachable
    try gc.tracer.markObject(str1);

    gc.sweep();

    // str1 should still be in the list
    var found_str1 = false;
    var current = gc.objects;
    while (current) |obj| {
        if (obj == str1) found_str1 = true;
        if (obj == str2) try std.testing.expect(false); // should be collected
        current = obj.next;
    }
    try std.testing.expect(found_str1);
}
