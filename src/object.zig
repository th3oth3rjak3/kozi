//! object contains the runtime objects used in the language.

const garbage_collector = @import("garbage_collector.zig");

const GcObject = garbage_collector.GcObject;

pub const Object = union(enum) {
    Bool: bool,
    Number: f64,
    Nil,
    String: *GcObject,
};
