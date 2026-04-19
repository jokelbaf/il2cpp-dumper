const std = @import("std");
const Il2cpp = @import("Il2cpp.zig");
const io = @import("io.zig");

const Allocator = std.mem.Allocator;

pub const ImageInfo = struct {
    name: []const u8,
    index: u32,
    first_type: u32,
    last_type: u32,
};

pub fn stripDllSuffix(name: []const u8) []const u8 {
    if (std.mem.endsWith(u8, name, ".dll")) return name[0 .. name.len - 4];
    return name;
}

pub fn writeClassFile(
    out_root: []const u16,
    il: *const Il2cpp,
    class: Il2cpp.Class,
    image_name: []const u8,
    content: []const u8,
) !void {
    const namespace = std.mem.span(il.class_get_namespace(class));
    const class_name = std.mem.span(il.class_get_name(class));

    var parts_buf: [32][]const u8 = undefined;
    var n_parts: usize = 0;

    var safe_image_buf: [256]u8 = undefined;
    parts_buf[n_parts] = io.sanitize8(&safe_image_buf, stripDllSuffix(image_name));
    n_parts += 1;

    var ns_parts_buf: [16][128]u8 = undefined;
    if (namespace.len > 0) {
        var it = std.mem.splitScalar(u8, namespace, '.');
        while (it.next()) |part| {
            if (n_parts >= parts_buf.len - 1) break;
            parts_buf[n_parts] = io.sanitize8(&ns_parts_buf[n_parts - 1], part);
            n_parts += 1;
        }
    }

    var safe_class_buf: [256]u8 = undefined;
    parts_buf[n_parts] = io.sanitize8(&safe_class_buf, class_name);
    n_parts += 1;

    var dir_path: [600:0]u16 = undefined;
    const dir_len = io.buildPath16(&dir_path, out_root, parts_buf[0 .. n_parts - 1]);
    io.createDirAll16(dir_path[0..dir_len]);

    var cs_name_buf: [260]u8 = undefined;
    const cs_name = std.fmt.bufPrint(&cs_name_buf, "{s}.cs", .{parts_buf[n_parts - 1]}) catch
        return error.NameTooLong;
    parts_buf[n_parts - 1] = cs_name;

    var file_path: [600:0]u16 = undefined;
    const file_len = io.buildPath16(&file_path, out_root, parts_buf[0..n_parts]);
    try io.writeFileW(file_path[0..file_len :0], content);
}

pub fn writeClass(
    buf: *std.ArrayList(u8),
    allocator: Allocator,
    il: *const Il2cpp,
    class: Il2cpp.Class,
    img: ImageInfo,
) !void {
    var usings: std.ArrayList([]const u8) = .empty;
    defer usings.deinit(allocator);
    try usingsAdd(&usings, allocator, "System");
    try usingsAdd(&usings, allocator, "System.Diagnostics");
    try usingsAdd(&usings, allocator, "System.Runtime.CompilerServices");
    try collectUsings(&usings, allocator, il, class);
    std.mem.sort([]const u8, usings.items, {}, lessThanStr);

    const asm_name = stripDllSuffix(img.name);

    try buf.appendSlice(
        allocator,
        "\xef\xbb\xbf/*\n" ++
            " * Generated with il2cpp-dumper - https://github.com/jokelbaf/il2cpp-dumper\n" ++
            " */\n\n",
    );
    for (usings.items) |ns| {
        try buf.print(allocator, "using {s};\n", .{ns});
    }
    try buf.append(allocator, '\n');
    try buf.print(
        allocator,
        "// Image {d}: {s} - Assembly: {s} - Types {d}-{d}\n\n",
        .{ img.index, img.name, asm_name, img.first_type, img.last_type },
    );

    const namespace = std.mem.span(il.class_get_namespace(class));
    if (namespace.len > 0) {
        try buf.print(allocator, "namespace {s}\n{{\n", .{namespace});
        try writeTypeDecl(buf, allocator, il, class, img, usings.items, 1);
        try buf.appendSlice(allocator, "}\n");
    } else {
        try writeTypeDecl(buf, allocator, il, class, img, usings.items, 0);
    }
}

fn lessThanStr(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.lessThan(u8, a, b);
}

fn indent(buf: *std.ArrayList(u8), allocator: Allocator, depth: u32) !void {
    var i: u32 = 0;
    while (i < depth) : (i += 1) try buf.append(allocator, '\t');
}

fn typedefIndex(il: *const Il2cpp, class: Il2cpp.Class, img: ImageInfo) u32 {
    const token = il.class_get_type_token(class);
    if (token == 0) return 0;
    return img.first_type + (token & 0x00FFFFFF) - 1;
}

fn usingsAdd(usings: *std.ArrayList([]const u8), allocator: Allocator, ns: []const u8) !void {
    if (ns.len == 0) return;
    for (usings.items) |existing| {
        if (std.mem.eql(u8, existing, ns)) return;
    }
    try usings.append(allocator, ns);
}

fn addTypeUsing(usings: *std.ArrayList([]const u8), allocator: Allocator, type_name: []const u8) !void {
    const translated = translateType(type_name);
    if (!std.mem.eql(u8, translated, type_name)) return;
    const base = if (std.mem.indexOfScalar(u8, type_name, '[')) |bi| type_name[0..bi] else type_name;
    const clean = if (std.mem.indexOfScalar(u8, base, '`')) |gi| base[0..gi] else base;
    const last_dot = std.mem.lastIndexOfScalar(u8, clean, '.') orelse return;
    try usingsAdd(usings, allocator, clean[0..last_dot]);
}

fn collectUsings(usings: *std.ArrayList([]const u8), allocator: Allocator, il: *const Il2cpp, class: Il2cpp.Class) !void {
    var field_iter: ?Il2cpp.Iter = null;
    while (il.class_get_fields(class, &field_iter)) |field| {
        const fattrs = il.field_get_flags(field);
        if (fattrs & Il2cpp.FieldAttr.special_name != 0) continue;
        try addTypeUsing(usings, allocator, std.mem.span(il.type_get_name(il.field_get_type(field))));
    }
    var method_iter: ?Il2cpp.Iter = null;
    while (il.class_get_methods(class, &method_iter)) |method| {
        try addTypeUsing(usings, allocator, std.mem.span(il.type_get_name(il.method_get_return_type(method))));
        const pc = il.method_get_param_count(method);
        var pi: u32 = 0;
        while (pi < pc) : (pi += 1) {
            try addTypeUsing(usings, allocator, std.mem.span(il.type_get_name(il.method_get_param(method, pi))));
        }
    }
    var prop_iter: ?Il2cpp.Iter = null;
    while (il.class_get_properties(class, &prop_iter)) |prop| {
        const m = il.property_get_get_method(prop) orelse il.property_get_set_method(prop) orelse continue;
        try addTypeUsing(usings, allocator, std.mem.span(il.type_get_name(il.method_get_return_type(m))));
    }
    if (il.class_get_parent(class)) |parent| {
        try usingsAdd(usings, allocator, std.mem.span(il.class_get_namespace(parent)));
    }
    var iface_iter: ?Il2cpp.Iter = null;
    while (il.class_get_interfaces(class, &iface_iter)) |iface| {
        try usingsAdd(usings, allocator, std.mem.span(il.class_get_namespace(iface)));
    }
}

fn translateType(name: []const u8) []const u8 {
    if (std.mem.eql(u8, name, "System.Boolean")) return "bool";
    if (std.mem.eql(u8, name, "System.Byte")) return "byte";
    if (std.mem.eql(u8, name, "System.SByte")) return "sbyte";
    if (std.mem.eql(u8, name, "System.Char")) return "char";
    if (std.mem.eql(u8, name, "System.Int16")) return "short";
    if (std.mem.eql(u8, name, "System.UInt16")) return "ushort";
    if (std.mem.eql(u8, name, "System.Int32")) return "int";
    if (std.mem.eql(u8, name, "System.UInt32")) return "uint";
    if (std.mem.eql(u8, name, "System.Int64")) return "long";
    if (std.mem.eql(u8, name, "System.UInt64")) return "ulong";
    if (std.mem.eql(u8, name, "System.Single")) return "float";
    if (std.mem.eql(u8, name, "System.Double")) return "double";
    if (std.mem.eql(u8, name, "System.Decimal")) return "decimal";
    if (std.mem.eql(u8, name, "System.Object")) return "object";
    if (std.mem.eql(u8, name, "System.String")) return "string";
    if (std.mem.eql(u8, name, "System.Void")) return "void";
    return name;
}

fn resolveType(type_name: []const u8, usings: []const []const u8) []const u8 {
    const translated = translateType(type_name);
    if (!std.mem.eql(u8, translated, type_name)) return translated;
    var best_len: usize = 0;
    for (usings) |ns| {
        if (type_name.len > ns.len + 1 and
            std.mem.startsWith(u8, type_name, ns) and
            type_name[ns.len] == '.' and
            ns.len > best_len)
        {
            best_len = ns.len;
        }
    }
    if (best_len > 0) return type_name[best_len + 1 ..];
    return type_name;
}

fn typeAccess(flags: u32) []const u8 {
    return switch (flags & Il2cpp.TypeAttr.vis_mask) {
        Il2cpp.TypeAttr.public, Il2cpp.TypeAttr.nested_public => "public",
        Il2cpp.TypeAttr.nested_private => "private",
        Il2cpp.TypeAttr.nested_family => "protected",
        Il2cpp.TypeAttr.nested_assembly => "internal",
        Il2cpp.TypeAttr.nested_fam_or_assem => "protected internal",
        Il2cpp.TypeAttr.nested_fam_and_assem => "private protected",
        else => "internal",
    };
}

fn methodAccess(flags: u32) []const u8 {
    return switch (flags & Il2cpp.MethodAttr.access_mask) {
        Il2cpp.MethodAttr.public => "public",
        Il2cpp.MethodAttr.private => "private",
        Il2cpp.MethodAttr.family => "protected",
        Il2cpp.MethodAttr.assem => "internal",
        Il2cpp.MethodAttr.fam_or_assem => "protected internal",
        Il2cpp.MethodAttr.fam_and_assem => "private protected",
        else => "private",
    };
}

fn fieldAccess(flags: u32) []const u8 {
    return switch (flags & Il2cpp.FieldAttr.access_mask) {
        Il2cpp.FieldAttr.public => "public",
        Il2cpp.FieldAttr.private => "private",
        Il2cpp.FieldAttr.family => "protected",
        Il2cpp.FieldAttr.assem => "internal",
        Il2cpp.FieldAttr.fam_or_assem => "protected internal",
        Il2cpp.FieldAttr.fam_and_assem => "private protected",
        else => "private",
    };
}

fn writeTypeDecl(
    buf: *std.ArrayList(u8),
    allocator: Allocator,
    il: *const Il2cpp,
    class: Il2cpp.Class,
    img: ImageInfo,
    usings: []const []const u8,
    depth: u32,
) anyerror!void {
    if (il.class_is_enum(class)) {
        try writeEnum(buf, allocator, il, class, img, usings, depth);
    } else {
        try writeClassOrStruct(buf, allocator, il, class, img, usings, depth);
    }
}

fn enumBaseType(il: *const Il2cpp, class: Il2cpp.Class) ?[]const u8 {
    var iter: ?Il2cpp.Iter = null;
    while (il.class_get_fields(class, &iter)) |field| {
        if (!std.mem.eql(u8, std.mem.span(il.field_get_name(field)), "value__")) continue;
        const translated = translateType(std.mem.span(il.type_get_name(il.field_get_type(field))));
        if (std.mem.eql(u8, translated, "int")) return null;
        return translated;
    }
    return null;
}

fn writeEnum(
    buf: *std.ArrayList(u8),
    allocator: Allocator,
    il: *const Il2cpp,
    class: Il2cpp.Class,
    img: ImageInfo,
    usings: []const []const u8,
    depth: u32,
) !void {
    _ = usings;
    const flags = il.class_get_flags(class);
    const class_name = std.mem.span(il.class_get_name(class));
    const base_type = enumBaseType(il, class);

    try indent(buf, allocator, depth);
    if (base_type) |bt| {
        try buf.print(allocator, "{s} enum {s} : {s} // TypeDefIndex: {d}\n", .{ typeAccess(flags), class_name, bt, typedefIndex(il, class, img) });
    } else {
        try buf.print(allocator, "{s} enum {s} // TypeDefIndex: {d}\n", .{ typeAccess(flags), class_name, typedefIndex(il, class, img) });
    }
    try indent(buf, allocator, depth);
    try buf.appendSlice(allocator, "{\n");

    var iter: ?Il2cpp.Iter = null;
    var first = true;
    while (il.class_get_fields(class, &iter)) |field| {
        const fattrs = il.field_get_flags(field);
        if (fattrs & Il2cpp.FieldAttr.special_name != 0) continue;
        var val: usize = 0;
        il.field_static_get_value(field, &val);
        const int_val: i64 = @as(i32, @truncate(@as(isize, @bitCast(val))));
        if (!first) try buf.appendSlice(allocator, ",\n");
        try indent(buf, allocator, depth + 1);
        try buf.print(allocator, "{s} = {d}", .{ std.mem.span(il.field_get_name(field)), int_val });
        first = false;
    }

    if (!first) try buf.append(allocator, '\n');
    try indent(buf, allocator, depth);
    try buf.appendSlice(allocator, "}\n");
}

fn writeClassOrStruct(
    buf: *std.ArrayList(u8),
    allocator: Allocator,
    il: *const Il2cpp,
    class: Il2cpp.Class,
    img: ImageInfo,
    usings: []const []const u8,
    depth: u32,
) anyerror!void {
    const flags = il.class_get_flags(class);
    const class_name = std.mem.span(il.class_get_name(class));
    const is_interface = il.class_is_interface(class);
    const is_valuetype = il.class_is_valuetype(class);
    const is_abstract = (flags & Il2cpp.TypeAttr.abstract_bit) != 0;
    const is_sealed = (flags & Il2cpp.TypeAttr.sealed_bit) != 0;
    const kind: []const u8 = if (is_interface) "interface" else if (is_valuetype) "struct" else "class";

    if (!is_interface and !is_valuetype and (flags & Il2cpp.TypeAttr.serializable != 0)) {
        try indent(buf, allocator, depth);
        try buf.appendSlice(allocator, "[Serializable]\n");
    }

    try indent(buf, allocator, depth);
    const access = typeAccess(flags);
    if (is_abstract and is_sealed and !is_interface) {
        try buf.print(allocator, "{s} static {s} {s}", .{ access, kind, class_name });
    } else if (is_abstract and !is_interface) {
        try buf.print(allocator, "{s} abstract {s} {s}", .{ access, kind, class_name });
    } else if (is_sealed and !is_valuetype and !is_interface) {
        try buf.print(allocator, "{s} sealed {s} {s}", .{ access, kind, class_name });
    } else {
        try buf.print(allocator, "{s} {s} {s}", .{ access, kind, class_name });
    }

    var wrote_colon = false;
    if (!is_interface and !is_valuetype) {
        if (il.class_get_parent(class)) |parent| {
            const parent_name = std.mem.span(il.class_get_name(parent));
            if (!std.mem.eql(u8, parent_name, "Object") and
                !std.mem.eql(u8, parent_name, "ValueType") and
                !std.mem.eql(u8, parent_name, "Enum"))
            {
                try buf.print(allocator, " : {s}", .{parent_name});
                wrote_colon = true;
            }
        }
    }

    var iface_iter: ?Il2cpp.Iter = null;
    while (il.class_get_interfaces(class, &iface_iter)) |iface| {
        if (!wrote_colon) {
            try buf.appendSlice(allocator, " : ");
            wrote_colon = true;
        } else {
            try buf.appendSlice(allocator, ", ");
        }
        try buf.appendSlice(allocator, std.mem.span(il.class_get_name(iface)));
    }

    try buf.print(allocator, " // TypeDefIndex: {d}\n", .{typedefIndex(il, class, img)});
    try indent(buf, allocator, depth);
    try buf.appendSlice(allocator, "{\n");

    try writeFields(buf, allocator, il, class, usings, depth + 1);
    try writeProperties(buf, allocator, il, class, usings, depth + 1);
    try writeNestedTypes(buf, allocator, il, class, img, usings, depth + 1);
    try writeConstructors(buf, allocator, il, class, class_name, usings, depth + 1);
    try writeMethods(buf, allocator, il, class, class_name, usings, depth + 1);

    try indent(buf, allocator, depth);
    try buf.appendSlice(allocator, "}\n");
}

fn writeFields(
    buf: *std.ArrayList(u8),
    allocator: Allocator,
    il: *const Il2cpp,
    class: Il2cpp.Class,
    usings: []const []const u8,
    depth: u32,
) !void {
    var iter: ?Il2cpp.Iter = null;
    var count: usize = 0;
    while (il.class_get_fields(class, &iter)) |field| {
        const fattrs = il.field_get_flags(field);
        if (fattrs & Il2cpp.FieldAttr.special_name != 0) continue;
        if (count == 0) {
            try indent(buf, allocator, depth);
            try buf.appendSlice(allocator, "// Fields\n");
        }
        count += 1;
        try writeField(buf, allocator, il, field, usings, depth);
    }
    if (count > 0) try buf.append(allocator, '\n');
}

fn writeField(
    buf: *std.ArrayList(u8),
    allocator: Allocator,
    il: *const Il2cpp,
    field: Il2cpp.Field,
    usings: []const []const u8,
    depth: u32,
) !void {
    const fattrs = il.field_get_flags(field);
    const type_name = resolveType(std.mem.span(il.type_get_name(il.field_get_type(field))), usings);
    const is_static = (fattrs & Il2cpp.FieldAttr.static) != 0;
    const is_readonly = (fattrs & Il2cpp.FieldAttr.init_only) != 0;
    const is_const = (fattrs & Il2cpp.FieldAttr.literal) != 0;

    if (fattrs & Il2cpp.FieldAttr.not_serialized != 0) {
        try indent(buf, allocator, depth);
        try buf.appendSlice(allocator, "[NonSerialized]\n");
    }
    try indent(buf, allocator, depth);
    try buf.appendSlice(allocator, fieldAccess(fattrs));
    if (is_const) {
        try buf.appendSlice(allocator, " const ");
    } else {
        if (is_static) try buf.appendSlice(allocator, " static");
        if (is_readonly) try buf.appendSlice(allocator, " readonly");
        try buf.append(allocator, ' ');
    }
    try buf.print(allocator, "{s} {s}; // 0x{X:0>2}\n", .{ type_name, std.mem.span(il.field_get_name(field)), il.field_get_offset(field) });
}

fn writeProperties(
    buf: *std.ArrayList(u8),
    allocator: Allocator,
    il: *const Il2cpp,
    class: Il2cpp.Class,
    usings: []const []const u8,
    depth: u32,
) !void {
    var iter: ?Il2cpp.Iter = null;
    var count: usize = 0;
    while (il.class_get_properties(class, &iter)) |prop| {
        if (count == 0) {
            try indent(buf, allocator, depth);
            try buf.appendSlice(allocator, "// Properties\n");
        }
        count += 1;
        try writeProperty(buf, allocator, il, prop, usings, depth);
    }
    if (count > 0) try buf.append(allocator, '\n');
}

fn writeProperty(
    buf: *std.ArrayList(u8),
    allocator: Allocator,
    il: *const Il2cpp,
    prop: Il2cpp.Property,
    usings: []const []const u8,
    depth: u32,
) !void {
    const getter = il.property_get_get_method(prop);
    const setter = il.property_get_set_method(prop);
    const representative = getter orelse setter orelse return;

    const mflags = il.method_get_flags(representative, null);
    const is_virtual = (mflags & Il2cpp.MethodAttr.virtual_bit) != 0;
    const is_final = (mflags & Il2cpp.MethodAttr.final) != 0;
    const is_abstract = (mflags & Il2cpp.MethodAttr.abstract_bit) != 0;
    const is_new_slot = (mflags & Il2cpp.MethodAttr.new_slot) != 0;

    const prop_method = getter orelse setter.?;
    const type_name = resolveType(std.mem.span(il.type_get_name(il.method_get_return_type(prop_method))), usings);

    try indent(buf, allocator, depth);
    try buf.appendSlice(allocator, methodAccess(mflags));
    if (mflags & Il2cpp.MethodAttr.static != 0) try buf.appendSlice(allocator, " static");
    if (is_abstract) {
        try buf.appendSlice(allocator, " abstract");
    } else if (is_virtual and !is_final) {
        try buf.appendSlice(allocator, if (is_new_slot) " virtual" else " override");
    }
    try buf.print(allocator, " {s} {s} {{", .{ type_name, std.mem.span(il.property_get_name(prop)) });
    if (getter != null) try buf.appendSlice(allocator, " get;");
    if (setter != null) try buf.appendSlice(allocator, " set;");
    try buf.appendSlice(allocator, " }");
    if (getter) |g| try buf.print(allocator, " // 0x{X:0>16}", .{g.address});
    if (setter) |s| {
        if (getter != null) {
            try buf.print(allocator, " 0x{X:0>16}", .{s.address});
        } else {
            try buf.print(allocator, " // 0x{X:0>16}", .{s.address});
        }
    }
    try buf.append(allocator, '\n');
}

fn writeNestedTypes(
    buf: *std.ArrayList(u8),
    allocator: Allocator,
    il: *const Il2cpp,
    class: Il2cpp.Class,
    img: ImageInfo,
    usings: []const []const u8,
    depth: u32,
) anyerror!void {
    var iter: ?Il2cpp.Iter = null;
    var count: usize = 0;
    while (il.class_get_nested_types(class, &iter)) |nested| {
        if (count == 0) {
            try indent(buf, allocator, depth);
            try buf.appendSlice(allocator, "// Nested Types\n");
        }
        count += 1;
        try writeTypeDecl(buf, allocator, il, nested, img, usings, depth);
    }
    if (count > 0) try buf.append(allocator, '\n');
}

fn writeConstructors(
    buf: *std.ArrayList(u8),
    allocator: Allocator,
    il: *const Il2cpp,
    class: Il2cpp.Class,
    class_name: []const u8,
    usings: []const []const u8,
    depth: u32,
) !void {
    var iter: ?Il2cpp.Iter = null;
    var count: usize = 0;
    while (il.class_get_methods(class, &iter)) |method| {
        const mflags = il.method_get_flags(method, null);
        if (mflags & Il2cpp.MethodAttr.rt_special_name == 0) continue;
        if (!std.mem.eql(u8, std.mem.span(il.method_get_name(method)), ".ctor")) continue;

        if (count == 0) {
            try indent(buf, allocator, depth);
            try buf.appendSlice(allocator, "// Constructors\n");
        }
        count += 1;
        try indent(buf, allocator, depth);
        try buf.appendSlice(allocator, methodAccess(mflags));
        try buf.append(allocator, ' ');
        try buf.appendSlice(allocator, class_name);
        try buf.append(allocator, '(');
        try writeMethodParams(buf, allocator, il, method, usings);
        try buf.print(allocator, "); // 0x{X:0>16}\n", .{method.address});
    }
    if (count > 0) try buf.append(allocator, '\n');
}

fn writeMethods(
    buf: *std.ArrayList(u8),
    allocator: Allocator,
    il: *const Il2cpp,
    class: Il2cpp.Class,
    class_name: []const u8,
    usings: []const []const u8,
    depth: u32,
) !void {
    var iter: ?Il2cpp.Iter = null;
    var count: usize = 0;
    while (il.class_get_methods(class, &iter)) |method| {
        const mflags = il.method_get_flags(method, null);
        if (mflags & Il2cpp.MethodAttr.rt_special_name != 0) continue;
        if (mflags & Il2cpp.MethodAttr.special_name != 0) continue;

        if (count == 0) {
            try indent(buf, allocator, depth);
            try buf.appendSlice(allocator, "// Methods\n");
        }
        count += 1;
        try writeMethod(buf, allocator, il, method, class_name, usings, depth);
    }
}

fn writeMethod(
    buf: *std.ArrayList(u8),
    allocator: Allocator,
    il: *const Il2cpp,
    method: Il2cpp.Method,
    class_name: []const u8,
    usings: []const []const u8,
    depth: u32,
) !void {
    const mflags = il.method_get_flags(method, null);
    const mname = std.mem.span(il.method_get_name(method));
    const is_virtual = (mflags & Il2cpp.MethodAttr.virtual_bit) != 0;
    const is_final = (mflags & Il2cpp.MethodAttr.final) != 0;
    const is_abstract = (mflags & Il2cpp.MethodAttr.abstract_bit) != 0;
    const is_new_slot = (mflags & Il2cpp.MethodAttr.new_slot) != 0;

    if (std.mem.eql(u8, mname, "Finalize") and il.method_get_param_count(method) == 0 and is_virtual) {
        try indent(buf, allocator, depth);
        try buf.print(allocator, "~{s}(); // 0x{X:0>16}\n", .{ class_name, method.address });
        return;
    }

    const ret_name = resolveType(std.mem.span(il.type_get_name(il.method_get_return_type(method))), usings);

    try indent(buf, allocator, depth);
    try buf.appendSlice(allocator, methodAccess(mflags));
    if (mflags & Il2cpp.MethodAttr.static != 0) try buf.appendSlice(allocator, " static");
    if (is_abstract) {
        try buf.appendSlice(allocator, " abstract");
    } else if (is_virtual and !is_final) {
        try buf.appendSlice(allocator, if (is_new_slot) " virtual" else " override");
    }
    try buf.print(allocator, " {s} {s}(", .{ ret_name, mname });
    try writeMethodParams(buf, allocator, il, method, usings);
    try buf.print(allocator, "); // 0x{X:0>16}\n", .{method.address});
}

fn writeMethodParams(
    buf: *std.ArrayList(u8),
    allocator: Allocator,
    il: *const Il2cpp,
    method: Il2cpp.Method,
    usings: []const []const u8,
) !void {
    const count = il.method_get_param_count(method);
    var i: u32 = 0;
    while (i < count) : (i += 1) {
        if (i > 0) try buf.appendSlice(allocator, ", ");
        const ptype_name = resolveType(std.mem.span(il.type_get_name(il.method_get_param(method, i))), usings);
        const pname = std.mem.span(il.method_get_param_name(method, i));
        try buf.print(allocator, "{s} {s}", .{ ptype_name, pname });
    }
}
