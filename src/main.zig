const std = @import("std");
const RawTerm = @import("RawTerm");
const ansi = RawTerm.ansi;

const Continent = enum {
    africa,
    asia,
    europe,
    north_america,
    oceania,
    insular_oceania,
    south_america,

    pub fn name(continent: Continent) []const u8 {
        return switch (continent) {
            .africa => "Africa",
            .asia => "Asia",
            .europe => "Europe",
            .north_america => "North America",
            .oceania => "Oceania",
            .insular_oceania => "Insular Oceania",
            .south_america => "South America",
        };
    }

    const by_name = blk: {
        var kvs: []const struct { []const u8, Continent } = &.{};
        for (std.enums.values(Continent)) |variant| {
            kvs = kvs ++ .{.{ variant.name(), variant }};
        }
        break :blk std.StaticStringMap(Continent).initComptime(kvs);
    };
};

const Country = struct {
    name: []const u8,
    capitals: []const []const u8,
    continents: []const Continent,
};

const countries = blk: {
    const raw_countries = @import("countries");

    @setEvalBranchQuota(100_000);

    const Entry = struct { []const u8, *const Country };
    var by_name_kv_list: []const Entry = &.{};
    var all: []const *const Country = &.{};

    for (raw_countries.countries) |raw_country| {
        var continents: []const Continent = &.{};
        for (raw_country.continents) |continent| {
            continents = continents ++ .{Continent.by_name.get(continent).?};
        }

        const country = Country{
            .name = raw_country.primary_name,
            .capitals = raw_country.capitals,
            .continents = continents,
        };

        all = all ++ .{&country};

        for (raw_country.alt_names ++ .{raw_country.primary_name}) |name| {
            var lower: [name.len]u8 = undefined;
            _ = std.ascii.lowerString(&lower, name);
            const key: [name.len]u8 = lower;
            by_name_kv_list = by_name_kv_list ++ @as([]const Entry, &.{Entry{ &key, &country }});
        }
    }

    const Result = struct {
        pub const countries = all;
        pub const by_name = std.StaticStringMap(*const Country).initComptime(by_name_kv_list);

        pub fn find(name: []const u8, buf: []u8) ?*const Country {
            return by_name.get(std.ascii.lowerString(buf, name));
        }

        pub const ContinentMap = struct {
            const Self = @This();

            map: std.AutoHashMap(*const Country, void),

            fn init(allocator: std.mem.Allocator) Self {
                return .{ .map = .init(allocator) };
            }

            pub fn deinit(map: *Self) void {
                map.map.deinit();
            }

            pub fn totalCount(map: *const Self) usize {
                var total_count: usize = 0;

                inline for (all) |country| {
                    if (map.contains(country)) {
                        total_count += 1;
                    }
                }

                return total_count;
            }

            pub fn count(map: *const Self, comptime continent: Continent) struct { count: usize, total: usize } {
                comptime var total_count: usize = 0;
                var continent_count: usize = 0;

                inline for (all) |country| {
                    inline for (country.continents) |country_continent| {
                        if (country_continent == continent) {
                            total_count += 1;

                            if (map.contains(country)) {
                                continent_count += 1;
                            }
                        }
                    }
                }

                return .{
                    .count = continent_count,
                    .total = total_count,
                };
            }

            fn add(map: *Self, country: *const Country) !void {
                try map.map.put(country, {});
            }

            fn contains(map: *const Self, country: *const Country) bool {
                return map.map.contains(country);
            }
        };
    };

    break :blk Result;
};

const Input = struct {
    buf: std.ArrayList(u8),
    position: usize,

    fn init(allocator: std.mem.Allocator) Input {
        return .{
            .buf = .init(allocator),
            .position = 0,
        };
    }

    fn deinit(input: *Input) void {
        input.buf.deinit();
    }

    fn handleEvent(input: *Input, event: RawTerm.Event) !void {
        input.position = @min(input.position, input.buf.items.len);
        switch (event) {
            .char => |char| if (char.ctrl) switch (char.value) {
                'c' => input.buf.clearAndFree(),
                'h' => {
                    input.position -|= 1;
                },
                'l' => {
                    input.position = @min(input.position + 1, input.buf.items.len);
                },
                else => {},
            } else {
                var buf: [4]u8 = undefined;
                const len = try std.unicode.utf8Encode(char.value, &buf);
                for (buf[0..len]) |byte| {
                    try input.buf.insert(input.position, byte);
                }
                input.position += len;
            },
            .special => |key| switch (key.key) {
                .backspace => {
                    if (input.position >= 1) {
                        _ = input.buf.orderedRemove(input.position - 1);
                        input.position -= 1;
                    }
                },
                .right => {
                    input.position -|= 1;
                },
                .left => {
                    input.position = @min(input.position + 1, input.buf.items.len);
                },
                else => {},
            },
            else => {},
        }
    }

    pub fn format(
        input: Input,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = options;
        _ = fmt;

        const position = @min(input.position, input.buf.items.len);

        if (position == input.buf.items.len) {
            try std.fmt.format(
                writer,
                "{s}" ++ ansi.style.reverse.enable ++ " " ++ ansi.style.reverse.disable,
                .{input.buf.items},
            );
        } else {
            const ch = input.buf.items[input.position];
            try std.fmt.format(
                writer,
                "{s}" ++ ansi.style.reverse.enable ++ "{c}" ++ ansi.style.reverse.disable ++ "{s}",
                .{ input.buf.items[0..position], ch, input.buf.items[position + 1 .. input.buf.items.len] },
            );
        }
    }
};

const Hint = union(enum) {
    capital: struct { country: *const Country, index: usize },

    fn new(map: *const countries.ContinentMap, rng: std.Random) Hint {
        const total_remaining = countries.countries.len - map.totalCount();
        var remaining = rng.intRangeLessThan(usize, 0, total_remaining);

        for (countries.countries) |country| {
            if (!map.contains(country)) {
                if (remaining == 0) {
                    return .{
                        .capital = .{
                            .country = country,
                            .index = if (country.capitals.len == 0) 0 else rng.intRangeLessThan(usize, 0, country.capitals.len),
                        },
                    };
                } else {
                    remaining -= 1;
                }
            }
        }

        std.debug.panic("Tried to get hint when all countries were found", .{});
    }
};

const CheckResult = union(enum) {
    found: *const Country,
    not_found,
    finished,
};

fn hsvToRgb(h: f32, s: f32, v: f32) @Vector(3, f32) {
    if (s == 0) {
        return .{ v, v, v };
    } else {
        var var_h = h * 6;
        if (var_h == 6) var_h = 0;
        const var_i = std.math.floor(var_h);
        const v1 = v * (1 - s);
        const v2 = v * (1 - s * (var_h - var_i));
        const v3 = v * (1 - s * (1 - var_h + var_i));

        switch (@as(usize, @intFromFloat(var_i))) {
            0 => return .{ v, v3, v1 },
            1 => return .{ v2, v, v1 },
            2 => return .{ v1, v, v3 },
            3 => return .{ v1, v2, v },
            4 => return .{ v3, v1, v },
            5 => return .{ v, v1, v2 },
            else => unreachable,
        }
    }
}

const State = struct {
    size: RawTerm.Size,
    map: countries.ContinentMap,
    input: Input,
    last_found: ?*const Country = null,
    hint: Hint,

    pub fn check(state: *State) !CheckResult {
        var buf: [1024]u8 = undefined;
        if (countries.find(state.input.buf.items, &buf)) |country| {
            if (!state.map.contains(country)) {
                state.input.buf.clearAndFree();
                try state.map.add(country);
                state.last_found = country;
                return if (countries.countries.len == state.map.totalCount()) .finished else .{ .found = country };
            }
        }

        return .not_found;
    }

    pub fn render(state: *const State, raw_term: *RawTerm) !void {
        try raw_term.out.writer().print(
            ansi.clear.screen ++ ansi.cursor.goto_top_left ++ "\x1b[{}H",
            .{(state.size.height -| 14) / 2 + 1},
        );

        try raw_term.out.writer().print("{s:^[1]}\n\r", .{ "Country Naming Game", state.size.width });

        inline for (comptime std.enums.values(Continent)) |continent| {
            try raw_term.out.writer().print("\n\r {s:<16}", .{continent.name()});

            const count = state.map.count(continent);
            const width = state.size.width -| 18;
            const cells = try std.math.divCeil(usize, width * count.count, count.total);

            const progess = @as(f32, @floatFromInt(count.count)) / @as(f32, @floatFromInt(count.total));
            const rgb: struct { u8, u8, u8 } = if (progess < 0.25) .{
                0xdc, 0x26, 0x26,
            } else if (progess < 0.5) .{
                0xea, 0x58, 0x0c,
            } else if (progess < 0.75) .{
                0xea, 0xb3, 0x08,
            } else .{
                0x84, 0xcc, 0x16,
            };

            try raw_term.out.writer().print(ansi.style.bold.enable ++ "\x1B[48;2;{};{};{}m", .{ rgb[0], rgb[1], rgb[2] });

            for (0..cells) |_| {
                try raw_term.out.writeAll(" ");
            }

            try raw_term.out.writeAll(ansi.style.reset ++ "\x1b[30m");

            for (0..width - cells) |_| {
                try raw_term.out.writeAll("\u{00B7}");
            }

            try raw_term.out.writeAll(ansi.style.reset);
        }

        try raw_term.out.writer().print(
            "\n\n\r{s:<[1]}> {2} <\n\r",
            .{ "", (state.size.width -| state.input.buf.items.len) / 2 -| 2, state.input },
        );

        if (state.last_found) |country| {
            try raw_term.out.writer().print("\n\r Found {s} ({}/{})", .{ country.name, state.map.totalCount(), countries.countries.len });
        }

        switch (state.hint) {
            .capital => |capital| {
                const country = capital.country;
                if (country.capitals.len > capital.index) {
                    try raw_term.out.writer().print("\n\r Hint: {s} is the capital of a country which hasn't been found", .{country.capitals[capital.index]});
                } else {
                    try raw_term.out.writeAll("\n\r Hint: a country without a capital city has not been found");
                }
            },
        }
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var raw_term = try RawTerm.enable(std.io.getStdIn(), std.io.getStdOut(), false);
    defer raw_term.disable() catch {};

    var listener = try raw_term.eventListener(allocator);
    defer listener.deinit();

    try raw_term.out.writeAll(ansi.alternate_screen.enable ++ ansi.cursor.hide);
    defer raw_term.out.writeAll(ansi.alternate_screen.disable ++ ansi.cursor.show) catch {};

    var rng = std.Random.DefaultPrng.init(@bitCast(std.time.milliTimestamp()));

    const map = countries.ContinentMap.init(allocator);

    var state = State{
        .size = try raw_term.size(),
        .map = map,
        .input = .init(allocator),
        .hint = .new(&map, rng.random()),
    };
    defer state.map.deinit();
    defer state.input.deinit();

    try state.render(&raw_term);

    while (true) {
        const event = try listener.queue.wait();
        switch (event) {
            .special => |special| switch (special.key) {
                .esc => break,
                else => {
                    try state.input.handleEvent(event);
                    try state.render(&raw_term);
                },
            },
            .resize => {
                state.size = try raw_term.size();
                try state.render(&raw_term);
            },
            .char => |char| switch (char.value) {
                '\r' => {
                    switch (try state.check()) {
                        .found => |country| switch (state.hint) {
                            .capital => |capital| if (capital.country == country) {
                                state.hint = .new(&state.map, rng.random());
                            },
                        },
                        .not_found => {},
                        .finished => {
                            while (true) {
                                try raw_term.out.writeAll(ansi.clear.screen ++ ansi.cursor.goto_top_left ++ "You won (press any key to exit)");
                                const ev = try listener.queue.wait();
                                switch (ev) {
                                    .resize => {},
                                    else => break,
                                }
                            }
                            break;
                        },
                    }
                    try state.render(&raw_term);
                },
                else => {
                    try state.input.handleEvent(event);
                    try state.render(&raw_term);
                },
            },
            else => {},
        }
    }
}
