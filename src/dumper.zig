const std = @import("std");
const Il2cpp = @import("Il2cpp.zig");
const cs = @import("cs.zig");
const io = @import("io.zig");
const windows = std.os.windows;

const log = std.log.scoped(.dumper);

extern "kernel32" fn GetModuleFileNameW(
    hModule: ?windows.HANDLE,
    lpFilename: [*]u16,
    nSize: windows.DWORD,
) callconv(.winapi) windows.DWORD;

pub fn dump(il2cpp: *const Il2cpp, allocator: std.mem.Allocator) !void {
    var path_w: [260]u16 = undefined;
    const path_len = GetModuleFileNameW(null, &path_w, 260);
    if (path_len == 0) return error.GetExePathFailed;

    const dir_end = io.lastIndexOf16(path_w[0..path_len], '\\') orelse path_len;
    const exe_dir_w = path_w[0..dir_end];

    var path_u8: [1024]u8 = undefined;
    const utf8_len = try std.unicode.utf16LeToUtf8(&path_u8, exe_dir_w);
    log.info("Output directory: {s}\\cs", .{path_u8[0..utf8_len]});

    var cs_root: [600:0]u16 = undefined;
    const cs_root_len = io.buildPath16(&cs_root, exe_dir_w, &[_][]const u8{"cs"});
    io.createDirAll16(cs_root[0..cs_root_len]);

    const domain = il2cpp.domain_get();
    il2cpp.thread_attach(domain);

    var size: usize = 0;
    const assemblies = il2cpp.domain_get_assemblies(domain, &size);
    log.info("Found {d} assemblies.", .{size});

    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(allocator);

    var image_idx: u32 = 0;
    var global_type_idx: u32 = 0;

    for (assemblies[0..size]) |assembly| {
        const image = il2cpp.assembly_get_image(assembly);
        const image_name = std.mem.span(il2cpp.image_get_name(image));
        const class_count = il2cpp.image_get_class_count(image);
        if (class_count == 0) continue;

        image_idx += 1;
        const img_first = global_type_idx;
        global_type_idx += @intCast(class_count);

        const img = cs.ImageInfo{
            .name = image_name,
            .index = image_idx,
            .first_type = img_first,
            .last_type = global_type_idx - 1,
        };

        log.info("Dumping image {d}/{d}: {s} ({d} types)", .{ image_idx, size, image_name, class_count });

        for (0..class_count) |i| {
            const class = il2cpp.image_get_class(image, i);
            if (il2cpp.class_get_declaring_type(class) != null) continue;
            if (std.mem.eql(u8, std.mem.span(il2cpp.class_get_name(class)), "<Module>")) continue;

            buf.clearRetainingCapacity();
            cs.writeClass(&buf, allocator, il2cpp, class, img) catch |err| {
                log.warn("[{s}] class {d}: writeClass failed: {}", .{ image_name, i, err });
                continue;
            };

            cs.writeClassFile(cs_root[0..cs_root_len], il2cpp, class, image_name, buf.items) catch |err| {
                log.warn("[{s}] class {d}: writeClassFile failed: {}", .{ image_name, i, err });
            };
        }
    }

    log.info("Dump complete: {d} images, {d} types", .{ image_idx, global_type_idx });
}
