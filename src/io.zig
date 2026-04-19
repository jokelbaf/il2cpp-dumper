const std = @import("std");
const windows = std.os.windows;

const DWORD = windows.DWORD;
const HANDLE = windows.HANDLE;
const BOOL = windows.BOOL;
const INVALID_HANDLE_VALUE: HANDLE = @ptrFromInt(~@as(usize, 0));
const GENERIC_WRITE: DWORD = 0x40000000;
const CREATE_ALWAYS: DWORD = 2;
const FILE_ATTRIBUTE_NORMAL: DWORD = 0x00000080;

extern "kernel32" fn CreateDirectoryW(
    lpPathName: [*:0]const u16,
    lpSecurityAttributes: ?*anyopaque,
) callconv(.winapi) BOOL;

extern "kernel32" fn CreateFileW(
    lpFileName: [*:0]const u16,
    dwDesiredAccess: DWORD,
    dwShareMode: DWORD,
    lpSecurityAttributes: ?*anyopaque,
    dwCreationDisposition: DWORD,
    dwFlagsAndAttributes: DWORD,
    hTemplateFile: ?HANDLE,
) callconv(.winapi) HANDLE;

extern "kernel32" fn WriteFile(
    hFile: HANDLE,
    lpBuffer: [*]const u8,
    nNumberOfBytesToWrite: DWORD,
    lpNumberOfBytesWritten: ?*DWORD,
    lpOverlapped: ?*anyopaque,
) callconv(.winapi) BOOL;

extern "kernel32" fn CloseHandle(hObject: HANDLE) callconv(.winapi) BOOL;

pub fn buildPath16(out: []u16, base: []const u16, parts: []const []const u8) usize {
    var pos: usize = 0;
    @memcpy(out[0..base.len], base);
    pos += base.len;
    for (parts) |part| {
        out[pos] = '\\';
        pos += 1;
        const written = std.unicode.utf8ToUtf16Le(out[pos..], part) catch 0;
        pos += written;
    }
    out[pos] = 0;
    return pos;
}

pub fn createDir(tmp: *[512:0]u16, src: []const u16, end: usize) void {
    const len = @min(end, tmp.len - 1);
    @memcpy(tmp[0..len], src[0..len]);
    tmp[len] = 0;
    _ = CreateDirectoryW(tmp, null);
}

pub fn createDirAll16(path: []const u16) void {
    var tmp: [512:0]u16 = undefined;

    for (path, 0..) |ch, i| {
        if (ch == '\\' and i > 2) {
            createDir(&tmp, path, i);
        }
    }
    createDir(&tmp, path, path.len);
}

pub fn writeFileW(path: [:0]const u16, data: []const u8) !void {
    const handle = CreateFileW(path.ptr, GENERIC_WRITE, 0, null, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, null);
    if (handle == INVALID_HANDLE_VALUE) return error.CreateFileFailed;
    defer _ = CloseHandle(handle);

    var written: DWORD = 0;
    var offset: usize = 0;
    while (offset < data.len) {
        const chunk = @min(data.len - offset, 0x7FFF_FFFF);
        if (WriteFile(handle, data.ptr + offset, @intCast(chunk), &written, null) == .FALSE)
            return error.WriteFailed;
        offset += written;
    }
}

pub fn sanitize8(buf: []u8, name: []const u8) []u8 {
    const invalid = "<>:\"/\\|?*";
    const len = @min(name.len, buf.len - 1);
    for (name[0..len], 0..) |c, i| {
        buf[i] = if (std.mem.indexOfScalar(u8, invalid, c) != null) '_' else c;
    }
    return buf[0..len];
}

pub fn lastIndexOf16(slice: []const u16, scalar: u16) ?usize {
    var i = slice.len;
    while (i > 0) {
        i -= 1;
        if (slice[i] == scalar) return i;
    }
    return null;
}
