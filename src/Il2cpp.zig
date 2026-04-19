const Il2cpp = @This();
const std = @import("std");
const windows = std.os.windows;

const log = std.log.scoped(.il2cpp);

pub const Domain = *anyopaque;
pub const Assembly = *anyopaque;
pub const Image = *anyopaque;
pub const Class = *anyopaque;
pub const Method = *extern struct { address: usize };
pub const Field = *anyopaque;
pub const Type = *anyopaque;
pub const Property = *anyopaque;
pub const Iter = *anyopaque;

pub const TypeAttr = struct {
    pub const vis_mask: u32 = 0x00000007;
    pub const not_public: u32 = 0x00000000;
    pub const public: u32 = 0x00000001;
    pub const nested_public: u32 = 0x00000002;
    pub const nested_private: u32 = 0x00000003;
    pub const nested_family: u32 = 0x00000004;
    pub const nested_assembly: u32 = 0x00000005;
    pub const nested_fam_and_assem: u32 = 0x00000006;
    pub const nested_fam_or_assem: u32 = 0x00000007;
    pub const interface_bit: u32 = 0x00000020;
    pub const abstract_bit: u32 = 0x00000080;
    pub const sealed_bit: u32 = 0x00000100;
    pub const serializable: u32 = 0x00002000;
};

pub const MethodAttr = struct {
    pub const access_mask: u32 = 0x00000007;
    pub const compiler_controlled: u32 = 0x00000000;
    pub const private: u32 = 0x00000001;
    pub const fam_and_assem: u32 = 0x00000002;
    pub const assem: u32 = 0x00000003;
    pub const family: u32 = 0x00000004;
    pub const fam_or_assem: u32 = 0x00000005;
    pub const public: u32 = 0x00000006;
    pub const static: u32 = 0x00000010;
    pub const final: u32 = 0x00000020;
    pub const virtual_bit: u32 = 0x00000040;
    pub const new_slot: u32 = 0x00000100;
    pub const abstract_bit: u32 = 0x00000400;
    pub const special_name: u32 = 0x00000800;
    pub const rt_special_name: u32 = 0x00001000;
};

pub const FieldAttr = struct {
    pub const access_mask: u32 = 0x00000007;
    pub const compiler_controlled: u32 = 0x00000000;
    pub const private: u32 = 0x00000001;
    pub const fam_and_assem: u32 = 0x00000002;
    pub const assem: u32 = 0x00000003;
    pub const family: u32 = 0x00000004;
    pub const fam_or_assem: u32 = 0x00000005;
    pub const public: u32 = 0x00000006;
    pub const static: u32 = 0x00000010;
    pub const init_only: u32 = 0x00000020;
    pub const literal: u32 = 0x00000040;
    pub const not_serialized: u32 = 0x00000080;
    pub const special_name: u32 = 0x00000200;
};

array_new: *const fn (element_class: Class, length: usize) callconv(.c) *anyopaque,
domain_get: *const fn () callconv(.c) Domain,
domain_get_assemblies: *const fn (domain: Domain, size: *usize) callconv(.c) [*]Assembly,
domain_assembly_open: *const fn (domain: Domain, name: [*:0]const u8) callconv(.c) ?Assembly,
thread_attach: *const fn (domain: Domain) callconv(.c) void,
gc_disable: *const fn () callconv(.c) void,
assembly_get_image: *const fn (assembly: Assembly) callconv(.c) Image,
image_get_name: *const fn (image: Image) callconv(.c) [*:0]const u8,
image_get_class_count: *const fn (image: Image) callconv(.c) usize,
image_get_class: *const fn (image: Image, index: usize) callconv(.c) Class,
class_from_name: *const fn (image: Image, namespace: [*:0]const u8, name: [*:0]const u8) callconv(.c) ?Class,
class_get_name: *const fn (class: Class) callconv(.c) [*:0]const u8,
class_get_namespace: *const fn (class: Class) callconv(.c) [*:0]const u8,
class_get_type: *const fn (class: Class) callconv(.c) Type,
class_get_parent: *const fn (class: Class) callconv(.c) ?Class,
class_get_interfaces: *const fn (class: Class, iter: *?Iter) callconv(.c) ?Class,
class_get_fields: *const fn (class: Class, iter: *?Iter) callconv(.c) ?Field,
class_get_methods: *const fn (class: Class, iter: *?Iter) callconv(.c) ?Method,
class_get_method_from_name: *const fn (class: Class, name: [*:0]const u8, argc: i32) callconv(.c) ?Method,
class_get_properties: *const fn (class: Class, iter: *?Iter) callconv(.c) ?Property,
class_get_nested_types: *const fn (class: Class, iter: *?Iter) callconv(.c) ?Class,
class_get_declaring_type: *const fn (class: Class) callconv(.c) ?Class,
class_get_type_token: *const fn (class: Class) callconv(.c) u32,
class_get_flags: *const fn (class: Class) callconv(.c) u32,
class_is_enum: *const fn (class: Class) callconv(.c) bool,
class_is_interface: *const fn (class: Class) callconv(.c) bool,
class_is_valuetype: *const fn (class: Class) callconv(.c) bool,
type_get_name: *const fn (t: Type) callconv(.c) [*:0]const u8,
type_get_attrs: *const fn (t: Type) callconv(.c) u32,
field_get_name: *const fn (f: Field) callconv(.c) [*:0]const u8,
field_get_type: *const fn (f: Field) callconv(.c) Type,
field_get_offset: *const fn (f: Field) callconv(.c) usize,
field_get_flags: *const fn (f: Field) callconv(.c) u32,
field_static_get_value: *const fn (f: Field, value: *usize) callconv(.c) void,
method_get_name: *const fn (m: Method) callconv(.c) [*:0]const u8,
method_get_return_type: *const fn (m: Method) callconv(.c) Type,
method_get_flags: *const fn (m: Method, iflags: ?*u32) callconv(.c) u32,
method_get_param_count: *const fn (m: Method) callconv(.c) u32,
method_get_param: *const fn (m: Method, index: u32) callconv(.c) Type,
method_get_param_name: *const fn (m: Method, index: u32) callconv(.c) [*:0]u8,
method_get_class: *const fn (m: Method) callconv(.c) Class,
property_get_name: *const fn (prop: Property) callconv(.c) [*:0]const u8,
property_get_get_method: *const fn (prop: Property) callconv(.c) ?Method,
property_get_set_method: *const fn (prop: Property) callconv(.c) ?Method,

extern "kernel32" fn GetProcAddress(hModule: windows.HMODULE, lpProcName: [*:0]const u8) callconv(.winapi) ?*anyopaque;

const LinkageError = error{SymbolNotFound};

pub fn link(against: windows.HMODULE) LinkageError!Il2cpp {
    var result: Il2cpp = undefined;
    inline for (@typeInfo(Il2cpp).@"struct".fields) |field| {
        @field(result, field.name) = @ptrCast(GetProcAddress(against, "il2cpp_" ++ field.name) orelse {
            log.err("symbol not found: '" ++ field.name ++ "'", .{});
            return error.SymbolNotFound;
        });
    }

    return result;
}
