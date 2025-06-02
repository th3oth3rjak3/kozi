//! garbage_collector contains all of the memory management for garbage collected
//! objects in the language.

const std = @import("std");
const builtin = @import("builtin");
const value_file = @import("value.zig");
const vm_file = @import("virtual_machine.zig");

const Object = value_file.Object;
const ObjectKind = value_file.ObjectKind;
const String = value_file.String;
const Value = value_file.Value;
const Allocator = std.mem.Allocator;
const VirtualMachine = vm_file.VirtualMachine;
const ArrayList = std.ArrayList;

const HEAP_GROW_FACTOR = 2;
const GC_HEAP_INIT_SIZE: comptime_int = 1024 * 1024; // 1MB
const GC_SLACK_PERCENT = 20;

/// GarbageCollector wraps an allocator and manages memory for the language runtime.
pub const GarbageCollector = struct {
    backing_allocator: Allocator,
    vm: ?*VirtualMachine,
    objects: ArrayList(*Object),
    bytes_allocated: usize = 0,
    next_gc: usize,
    globals: std.StringHashMap(Value),
    strings: std.StringHashMap(*String),

    const Self = @This();

    pub fn init(backing_allocator: Allocator) GarbageCollector {
        return GarbageCollector{
            .backing_allocator = backing_allocator,
            .vm = null,
            .objects = ArrayList(*Object).init(backing_allocator),
            .next_gc = GC_HEAP_INIT_SIZE,
            .strings = std.StringHashMap(*String).init(backing_allocator),
            .globals = std.StringHashMap(Value).init(backing_allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.freeAllObjects();
        self.strings.deinit();
        self.objects.deinit();
        self.globals.deinit();
    }

    pub fn addVirtualMachine(self: *Self, vm: *VirtualMachine) void {
        self.vm = vm;
    }

    pub fn newString(self: *Self, value: []const u8) !Value {
        if (self.strings.get(value)) |v| {
            return Value{ .String = v };
        }

        if (self.bytes_allocated > self.next_gc) {
            self.collect();
        }

        const owned = try self.backing_allocator.dupe(u8, value);
        self.bytes_allocated += owned.len;
        const str = try self.backing_allocator.create(String);
        str.* = .{
            .header = .{
                .marked = false,
                .kind = .String,
            },
            .data = owned,
        };

        self.bytes_allocated += @sizeOf(String);
        try self.objects.append(&str.header);

        try self.strings.put(value, str);
        return Value{ .String = str };
    }

    pub fn collect(self: *Self) void {
        const before = self.bytes_allocated;
        self.mark();
        self.sweep();
        self.resetMarks();

        const after = self.bytes_allocated;

        // Add 20% slack to avoid collecting again immediately
        const slack: usize = (after * @as(usize, GC_SLACK_PERCENT)) / 100;
        const adjusted = switch ((after + slack) > GC_HEAP_INIT_SIZE) {
            true => after * HEAP_GROW_FACTOR,
            false => after + slack,
        };

        self.next_gc = @max(adjusted, GC_HEAP_INIT_SIZE);

        if (builtin.mode == .Debug) {
            std.debug.print("GC collected {} bytes ({} -> {})\n", .{ before - after, before, after });
            std.debug.print("Next GC scheduled at: {}\n", .{self.next_gc});
        }
    }

    pub fn mark(self: *Self) void {
        if (self.vm == null) {
            return;
        }

        for (self.vm.?.stack.items) |*value| {
            self.markObject(value);
        }

        var iterator = self.globals.iterator();
        while (iterator.next()) |entry| {
            self.markObject(entry.value_ptr);
        }
    }

    pub fn markObjectRecursive(self: *Self, obj: *Object) void {
        _ = self;
        if (obj.marked) return;
        obj.*.marked = true;

        switch (obj.kind) {
            .String => {},
            // else => {
            //     // Here you would call self.markObject on the inner types.
            //     _ = self;
            // }
        }
    }

    pub fn markObject(self: *Self, value: *Value) void {
        switch (value.*) {
            .String => |str| {
                self.markObjectRecursive(&str.header);
            },
            else => {},
        }
    }

    pub fn sweep(self: *Self) void {
        var i: usize = 0;
        while (i < self.objects.items.len) {
            const obj = self.objects.items[i];
            if (!obj.marked) {
                // Remove from objects list first
                _ = self.objects.swapRemove(i);
                // Then free the object (this will also remove from strings hashmap)
                self.freeObjectMemory(obj);
                // Don't increment i since we removed an element
            } else {
                i += 1;
            }
        }
    }

    pub fn resetMarks(self: *Self) void {
        for (self.objects.items) |obj| {
            switch (obj.kind) {
                .String => {
                    const str: *String = @ptrCast(@alignCast(obj));
                    str.*.header.marked = false;
                },
            }
        }
    }

    pub fn freeAllObjects(self: *Self) void {
        // Free all remaining objects
        while (self.objects.items.len > 0) {
            const obj = self.objects.items[0];
            _ = self.objects.swapRemove(0);
            self.freeObjectMemory(obj);
        }

        // Clear the hashmaps (should be empty at this point)
        self.strings.clearAndFree();
    }

    pub fn freeValue(self: *Self, value: *Value) void {
        switch (value.*) {
            .String => |str| {
                self.freeObject(&str.header);
            },
            else => {},
        }
    }

    pub fn freeObject(self: *Self, obj: *Object) void {
        // Find and remove from objects list
        for (self.objects.items, 0..) |existing, i| {
            if (obj == existing) {
                _ = self.objects.swapRemove(i);
                break;
            }
        }

        // Free the memory
        self.freeObjectMemory(obj);
    }

    fn freeObjectMemory(self: *Self, obj: *Object) void {
        switch (obj.kind) {
            .String => {
                const ptr: *String = @ptrCast(@alignCast(obj));

                // Remove from strings hashmap if present
                if (self.strings.contains(ptr.data)) {
                    _ = self.strings.remove(ptr.data);
                }

                // Free the string data
                self.bytes_allocated -= ptr.data.len;
                self.backing_allocator.free(ptr.data);

                // Free the String struct
                self.backing_allocator.destroy(ptr);
                self.bytes_allocated -= @sizeOf(String);
            },
        }
    }
};

test "GarbageCollector basic string allocation and GC" {
    const expect = std.testing.expect;

    const gpa = std.testing.allocator;
    var gc = GarbageCollector.init(gpa);
    defer gc.deinit();

    var vm = VirtualMachine.init(&gc);
    defer vm.deinit();

    gc.addVirtualMachine(&vm);

    // Allocate a string
    const val1 = try gc.newString("hello");
    try expect(std.mem.eql(u8, val1.String.data, "hello"));

    // Allocate the same string again, should be interned
    const val2 = try gc.newString("hello");
    try expect(val1.String == val2.String); // same pointer = interned

    // Allocate a different string
    const val3 = try gc.newString("world");
    try expect(std.mem.eql(u8, val3.String.data, "world"));
    try expect(val1.String != val3.String);

    // Put val1 and val3 on the stack so they’re reachable
    try vm.push(val1);
    try vm.push(val3);

    // Force a GC cycle
    gc.collect();

    // They should still be there
    const val1_again = try gc.newString("hello");
    try expect(val1_again.String == val1.String);

    const val3_again = try gc.newString("world");
    try expect(val3_again.String == val3.String);
}

test "GarbageCollector drops unreferenced string after GC" {
    const expect = std.testing.expect;

    const gpa = std.testing.allocator;
    var gc = GarbageCollector.init(gpa);
    defer gc.deinit();

    // Add a string and don't retain it
    _ = try gc.newString("temp");

    // Ensure it's in the string table
    try expect(gc.strings.get("temp") != null);

    // No references on stack or globals, so it should be collected
    gc.collect();

    // The string should be gone
    try expect(gc.strings.get("temp") == null);
}
