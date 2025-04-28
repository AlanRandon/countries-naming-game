const std = @import("std");

pub const Country = struct {
    id: []const u8,
    name: []const u8,
    alt_names: []const []const u8,
    continents: []const []const u8,
    capitals: []const []const u8,
};

pub fn main() !void {
    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const json_src = @embedFile("countries.json");
    const json = try std.json.parseFromSlice([]const Country, arena, json_src, .{});

    const stdout = std.io.getStdOut();

    try stdout.writer().writeAll(
        \\pub const RawCountry = struct {
        \\  primary_name: []const u8,
        \\  alt_names: []const []const u8,
        \\  continents: []const []const u8,
        \\  capitals: []const []const u8,
        \\};
    );

    for (json.value) |country| {
        try stdout.writer().print(
            \\pub const @"{0s}" = RawCountry{{
            \\  .primary_name = "{0s}",
            \\
        , .{
            country.name,
        });

        try stdout.writer().print(".alt_names = &.{{\"{s}\",", .{country.name});
        for (country.alt_names) |name| {
            try stdout.writer().print("\"{s}\",", .{name});
        }
        try stdout.writer().writeAll("},\n");

        try stdout.writeAll(".continents = &.{");
        for (country.continents) |continent| {
            try stdout.writer().print("\"{s}\",", .{continent});
        }
        try stdout.writeAll("},\n");

        try stdout.writeAll(".capitals = &.{");
        for (country.capitals) |capital| {
            try stdout.writer().print("\"{s}\",", .{capital});
        }
        try stdout.writeAll("},\n");

        try stdout.writer().writeAll("};\n");
    }

    try stdout.writeAll("pub const countries = .{");
    for (json.value) |country| {
        try stdout.writer().print(
            \\@"{s}",
        , .{country.name});
    }
    try stdout.writeAll("};");
}
