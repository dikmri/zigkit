//! zigkit-test: Test helper utilities supplementing std.testing.
//!
//! Ownership: All allocation functions return caller-owned memory
//! unless documented otherwise.

const std = @import("std");
const builtin = @import("builtin");
const internal_json = @import("internal/json.zig");

/// Asserts that haystack contains needle.
pub fn expectContains(haystack: []const u8, needle: []const u8) !void {
    if (std.mem.indexOf(u8, haystack, needle) == null) {
        std.debug.print(
            "\nexpected to find:\n  {s}\nin:\n  {s}\n",
            .{ needle, haystack },
        );
        return error.TestUnexpectedResult;
    }
}

/// Asserts that actual starts with prefix.
pub fn expectStartsWith(actual: []const u8, prefix: []const u8) !void {
    if (!std.mem.startsWith(u8, actual, prefix)) {
        std.debug.print(
            "\nexpected to start with:\n  {s}\ngot:\n  {s}\n",
            .{ prefix, actual },
        );
        return error.TestUnexpectedResult;
    }
}

/// Asserts that actual ends with suffix.
pub fn expectEndsWith(actual: []const u8, suffix: []const u8) !void {
    if (!std.mem.endsWith(u8, actual, suffix)) {
        std.debug.print(
            "\nexpected to end with:\n  {s}\ngot:\n  {s}\n",
            .{ suffix, actual },
        );
        return error.TestUnexpectedResult;
    }
}

/// Asserts that expected == actual, with a pretty diff on failure.
pub fn expectEqualStringPretty(expected: []const u8, actual: []const u8) !void {
    if (!std.mem.eql(u8, expected, actual)) {
        std.debug.print(
            "\nstring mismatch:\nexpected:\n  {s}\nactual:\n  {s}\n",
            .{ expected, actual },
        );
        return error.TestExpectedEqual;
    }
}

/// Asserts that two JSON strings are semantically equal (key order ignored).
pub fn expectJsonEqual(
    allocator: std.mem.Allocator,
    expected: []const u8,
    actual: []const u8,
) !void {
    const equal = try internal_json.jsonEqual(allocator, expected, actual);
    if (!equal) {
        std.debug.print(
            "\nJSON mismatch:\nexpected:\n  {s}\nactual:\n  {s}\n",
            .{ expected, actual },
        );
        return error.TestExpectedEqual;
    }
}

/// Temporary directory that is deleted on deinit.
pub const TempDir = struct {
    allocator: std.mem.Allocator,
    path: []const u8,

    /// Creates a unique temporary directory under the OS temp dir.
    /// Caller must call deinit() to clean up.
    pub fn init(allocator: std.mem.Allocator) !TempDir {
        const tmp_base = try getTmpBase(allocator);
        defer allocator.free(tmp_base);

        const tid = std.Thread.getCurrentId();
        const io = std.Io.Threaded.global_single_threaded.io();
        const ts = std.Io.Clock.real.now(io).toMilliseconds();
        const dir_name = try std.fmt.allocPrint(allocator, "zigkit-test-{d}-{d}", .{ tid, ts });
        defer allocator.free(dir_name);

        const full_path = try std.fs.path.join(allocator, &.{ tmp_base, dir_name });
        errdefer allocator.free(full_path);

        try std.Io.Dir.cwd().createDirPath(io, full_path);

        return TempDir{
            .allocator = allocator,
            .path = full_path,
        };
    }

    fn getTmpBase(allocator: std.mem.Allocator) ![]u8 {
        // Use std.c.getenv (requires libc to be linked, which is done in build.zig)
        if (std.c.getenv("TEMP")) |val| {
            return allocator.dupe(u8, std.mem.sliceTo(val, 0));
        }
        if (std.c.getenv("TMP")) |val| {
            return allocator.dupe(u8, std.mem.sliceTo(val, 0));
        }
        if (builtin.os.tag == .windows) {
            return allocator.dupe(u8, "C:\\Temp");
        } else {
            return allocator.dupe(u8, "/tmp");
        }
    }

    /// Deletes the temporary directory and frees path memory.
    pub fn deinit(self: *TempDir) void {
        const io = std.Io.Threaded.global_single_threaded.io();
        std.Io.Dir.cwd().deleteTree(io, self.path) catch {};
        self.allocator.free(self.path);
        self.* = undefined;
    }

    /// Writes content to a named file inside the temp dir.
    pub fn writeFile(self: *TempDir, name: []const u8, content: []const u8) !void {
        const file_path = try std.fs.path.join(self.allocator, &.{ self.path, name });
        defer self.allocator.free(file_path);
        const io = std.Io.Threaded.global_single_threaded.io();
        const file = try std.Io.Dir.cwd().createFile(io, file_path, .{});
        defer file.close(io);
        try file.writeStreamingAll(io, content);
    }

    /// Reads a named file from the temp dir. Caller owns returned slice.
    pub fn readFile(self: *TempDir, name: []const u8, allocator: std.mem.Allocator) ![]u8 {
        const file_path = try std.fs.path.join(self.allocator, &.{ self.path, name });
        defer self.allocator.free(file_path);
        const io = std.Io.Threaded.global_single_threaded.io();
        const file = try std.Io.Dir.cwd().openFile(io, file_path, .{});
        defer file.close(io);
        const stat = try file.stat(io);
        const buf = try allocator.alloc(u8, stat.size);
        errdefer allocator.free(buf);
        const n = try file.readPositionalAll(io, buf, 0);
        return buf[0..n];
    }

    /// Returns the full path to a named file in the temp dir. Caller owns returned slice.
    pub fn pathJoinAlloc(self: *TempDir, allocator: std.mem.Allocator, name: []const u8) ![]u8 {
        return std.fs.path.join(allocator, &.{ self.path, name });
    }
};

/// Reads a fixture file. Caller owns the returned slice.
/// `path` is relative to the current working directory (typically the project root during tests).
pub fn fixtureAlloc(
    allocator: std.mem.Allocator,
    path: []const u8,
) ![]u8 {
    const io = std.Io.Threaded.global_single_threaded.io();
    const file = try std.Io.Dir.cwd().openFile(io, path, .{});
    defer file.close(io);
    const stat = try file.stat(io);
    const buf = try allocator.alloc(u8, stat.size);
    errdefer allocator.free(buf);
    const n = try file.readPositionalAll(io, buf, 0);
    return buf[0..n];
}

/// Snapshot path base directory.
const snapshot_dir = "tests/snapshots";

/// Tests `actual` against a stored snapshot.
///
/// If `ZIGKIT_UPDATE_SNAPSHOTS=1`, creates or updates the snapshot.
/// Otherwise, fails if the snapshot doesn't exist or doesn't match.
pub fn expectSnapshot(
    allocator: std.mem.Allocator,
    name: []const u8,
    actual: []const u8,
) !void {
    const snap_path = try std.fmt.allocPrint(
        allocator,
        "{s}/{s}.snap",
        .{ snapshot_dir, name },
    );
    defer allocator.free(snap_path);

    const io = std.Io.Threaded.global_single_threaded.io();

    if (shouldUpdateSnapshots()) {
        // Ensure directory exists
        std.Io.Dir.cwd().createDirPath(io, snapshot_dir) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };
        // Write snapshot
        const file = try std.Io.Dir.cwd().createFile(io, snap_path, .{});
        defer file.close(io);
        try file.writeStreamingAll(io, actual);
        return;
    }

    // Read existing snapshot
    const existing = std.Io.Dir.cwd().openFile(io, snap_path, .{}) catch |err| switch (err) {
        error.FileNotFound => {
            std.debug.print(
                "\nsnapshot not found: {s}\nrun with ZIGKIT_UPDATE_SNAPSHOTS=1 to create it\n",
                .{snap_path},
            );
            return error.TestUnexpectedResult;
        },
        else => return err,
    };
    defer existing.close(io);

    const stat = try existing.stat(io);
    const expected = try allocator.alloc(u8, stat.size);
    defer allocator.free(expected);
    _ = try existing.readPositionalAll(io, expected, 0);

    if (!std.mem.eql(u8, expected, actual)) {
        std.debug.print(
            "\nsnapshot mismatch for '{s}':\nexpected:\n{s}\nactual:\n{s}\n",
            .{ name, expected, actual },
        );
        return error.TestExpectedEqual;
    }
}

fn shouldUpdateSnapshots() bool {
    const val = std.c.getenv("ZIGKIT_UPDATE_SNAPSHOTS") orelse return false;
    const s = std.mem.sliceTo(val, 0);
    return s.len > 0 and !std.mem.eql(u8, s, "0");
}
