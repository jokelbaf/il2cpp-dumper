const std = @import("std");
const Il2cpp = @import("Il2cpp.zig");
const dumper = @import("dumper.zig");

const windows = std.os.windows;
const unicode = std.unicode;
const Io = std.Io;

const DLL_PROCESS_ATTACH = 1;

extern "kernel32" fn AllocConsole() callconv(.winapi) void;
extern "kernel32" fn FreeConsole() callconv(.winapi) void;
extern "kernel32" fn GetModuleHandleW(lpModuleName: ?[*:0]const u16) callconv(.winapi) ?windows.HMODULE;
extern "kernel32" fn CreateThread(
    lpThreadAttributes: ?*anyopaque,
    dwStackSize: usize,
    lpStartAddress: *const fn (?*anyopaque) callconv(.winapi) windows.DWORD,
    lpParameter: ?*anyopaque,
    dwCreationFlags: windows.DWORD,
    lpThreadId: ?*windows.DWORD,
) callconv(.winapi) ?windows.HANDLE;

const gameassembly_name = unicode.utf8ToUtf16LeStringLiteral("GameAssembly.dll");
var base: usize = 0;
var il2cpp: Il2cpp = undefined;

fn init(_: ?*anyopaque) callconv(.winapi) windows.DWORD {
    const log = std.log.scoped(.init);

    FreeConsole();
    AllocConsole();

    var threaded: Io.Threaded = .init_single_threaded;
    defer threaded.deinit();
    const io = threaded.io();

    log.info("Waiting for the game startup...", .{});

    while (base == 0) : (base = @intFromPtr(GetModuleHandleW(gameassembly_name))) {
        io.sleep(.fromNanoseconds(200 * std.time.ns_per_ms), .awake) catch {};
    } else {
        io.sleep(.fromSeconds(2), .awake) catch {};
    }

    log.info("GameAssembly addr: 0x{X}", .{base});

    il2cpp = Il2cpp.link(@ptrFromInt(base)) catch |err| {
        log.err("failed to link il2cpp symbols: {t}", .{err});
        return 1;
    };

    log.info("Starting IL2CPP dump...", .{});

    dumper.dump(&il2cpp, std.heap.c_allocator) catch |err| {
        log.err("dump failed: {t}", .{err});
        return 1;
    };

    return 0;
}

pub export fn DllMain(_: windows.HINSTANCE, reason: windows.DWORD, _: windows.LPVOID) callconv(.winapi) windows.BOOL {
    if (reason == DLL_PROCESS_ATTACH) {
        _ = CreateThread(null, 0, init, null, 0, null);
    }

    return .TRUE;
}
