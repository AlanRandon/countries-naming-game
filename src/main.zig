const std = @import("std");
const vaxis = @import("vaxis");
const countries = @import("country.zig");
const Country = countries.Country;

const Event = union(enum) {
    key_press: vaxis.Key,
    winsize: vaxis.Winsize,
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

const State = struct {
    map: countries.ContinentMap,
    last_found: ?*const Country = null,
    hint: Hint,
    elapsed_ns: u64,

    pub fn check(state: *State, name: []const u8) !CheckResult {
        var buf: [1024]u8 = undefined;
        if (countries.find(name, &buf)) |country| {
            if (!state.map.contains(country)) {
                try state.map.add(country);
                state.last_found = country;
                return if (countries.countries.len == state.map.totalCount()) .finished else .{ .found = country };
            }
        }

        return .not_found;
    }

    pub fn fmtTime(elapsed_ns: u64, buf: []u8) []u8 {
        const secs = elapsed_ns / std.time.ns_per_s;
        const mins = elapsed_ns / std.time.ns_per_min;
        const hours = elapsed_ns / std.time.ns_per_hour;

        return (if (hours == 0)
            std.fmt.bufPrint(buf, "{:02}:{:02}", .{ mins % 60, secs % 60 })
        else
            std.fmt.bufPrint(buf, "{}:{:02}:{:02}", .{ hours, mins % 60, secs % 60 })) catch unreachable;
    }

    pub fn render(state: *const State, window: vaxis.Window, input: *vaxis.widgets.TextInput) void {
        window.clear();

        const line_count = 15;
        const center = vaxis.widgets.alignment.center(window, window.width, line_count);
        var lines: [line_count]vaxis.Window = undefined;
        inline for (0..line_count) |i| {
            lines[i] = center.child(.{ .y_off = i, .height = 1 });
        }

        const title = "Country Naming Game";
        _ = vaxis.widgets.alignment.center(lines[0], @intCast(title.len), 1).printSegment(.{ .text = title }, .{});

        {
            var buf: [10]u8 = undefined;
            const time = fmtTime(state.elapsed_ns, &buf);
            _ = vaxis.widgets.alignment.center(lines[1], @intCast(time.len), 1).printSegment(.{
                .text = time,
                .style = vaxis.Style{ .fg = .{ .index = 0 } },
            }, .{});
        }

        inline for (comptime std.enums.values(countries.Continent), 0..) |continent, i| {
            const name = comptime blk: {
                var buf: [17]u8 = undefined;
                const name = std.fmt.bufPrint(&buf, " {s:<16}", .{continent.name()}) catch unreachable;
                const buf_runtime = buf;
                break :blk buf_runtime[0..name.len];
            };

            const full = " " ** 1024;
            const empty = "\u{00B7}" ** 1024;

            const count = state.map.count(continent);
            const width = window.width -| 18;
            const cells = std.math.divCeil(usize, width * count.count, count.total) catch unreachable;

            const progess = @as(f32, @floatFromInt(count.count)) / @as(f32, @floatFromInt(count.total));
            const rgb: [3]u8 = if (progess < 0.25) .{
                0xdc, 0x26, 0x26,
            } else if (progess < 0.5) .{
                0xea, 0x58, 0x0c,
            } else if (progess < 0.75) .{
                0xea, 0xb3, 0x08,
            } else .{
                0x84, 0xcc, 0x16,
            };

            _ = lines[3 + i].print(&.{
                .{
                    .text = name,
                    .style = vaxis.Style{ .bold = true },
                },
                .{
                    .text = full[0..cells],
                    .style = vaxis.Style{ .bg = .{ .rgb = rgb } },
                },
                .{
                    .text = empty[0 .. (width - cells) * "\u{00B7}".len],
                    .style = vaxis.Style{ .fg = .{ .index = 0 } },
                },
            }, .{});
        }

        {
            const input_len: u16 = @truncate(input.buf.realLength() + 1);
            const win = vaxis.widgets.alignment.center(lines[11], input_len + 4, 1);
            _ = win.child(.{}).printSegment(.{ .text = "> " }, .{});
            input.draw(win.child(.{ .x_off = 2 }));
            _ = win.child(.{}).printSegment(.{ .text = " <" }, .{ .col_offset = input_len + 2 });
        }

        switch (state.hint) {
            .capital => |capital| {
                const country = capital.country;
                var buf: [64]u8 = undefined;

                const hint = if (country.capitals.len > capital.index)
                    std.fmt.bufPrint(
                        &buf,
                        "{s} is the capital of an unfound country",
                        .{country.capitals[capital.index]},
                    ) catch unreachable
                else
                    "an unfound country does not have a capital city";

                _ = lines[13].print(&.{
                    .{
                        .text = " Hint: ",
                        .style = vaxis.Style{ .bold = true },
                    },
                    .{
                        .text = hint,
                    },
                }, .{});
            },
        }

        if (state.last_found) |country| {
            var buf: [256]u8 = undefined;
            _ = lines[14].print(
                &.{.{
                    .text = std.fmt.bufPrint(
                        &buf,
                        " Found {s} ({}/{})",
                        .{ country.name, state.map.totalCount(), countries.countries.len },
                    ) catch unreachable,
                }},
                .{},
            );
        }
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var tty = try vaxis.Tty.init();
    defer tty.deinit();

    var vx = try vaxis.init(allocator, .{});
    defer vx.deinit(allocator, tty.anyWriter());

    var loop = vaxis.Loop(Event){
        .tty = &tty,
        .vaxis = &vx,
    };
    try loop.init();

    try loop.start();
    defer loop.stop();

    try vx.enterAltScreen(tty.anyWriter());
    try vx.queryTerminal(tty.anyWriter(), 1 * std.time.ns_per_s);

    vx.setTitle(tty.anyWriter(), "countries naming game") catch {};

    var rng = std.Random.DefaultPrng.init(@bitCast(std.time.milliTimestamp()));

    const map = countries.ContinentMap.init(allocator);

    var input: vaxis.widgets.TextInput = .init(allocator, &vx.unicode);
    defer input.deinit();

    var state = State{
        .map = map,
        .hint = .new(&map, rng.random()),
        .elapsed_ns = 0,
    };
    defer state.map.deinit();

    // for (countries.countries[0 .. countries.countries.len - 1]) |country| {
    //     try state.map.add(country);
    // }

    // state.hint = .new(&state.map, rng.random());

    var timer = try std.time.Timer.start();

    while (true) {
        const event = loop.nextEvent();
        switch (event) {
            .key_press => |key| if (key.matches('c', .{ .ctrl = true })) return,
            .winsize => |ws| {
                try vx.resize(allocator, tty.anyWriter(), ws);
                break;
            },
        }
    }

    var bw = tty.bufferedWriter();

    {
        const window = vx.window();
        state.render(window, &input);

        try vx.render(bw.writer().any());
        try bw.flush();
    }

    while (true) {
        const event = loop.nextEvent();
        state.elapsed_ns = timer.read();
        switch (event) {
            .key_press => |key| {
                if (key.matches('q', .{ .ctrl = true })) {
                    return;
                } else if (key.matches('c', .{ .ctrl = true })) {
                    input.clearAndFree();
                } else if (key.matches(vaxis.Key.enter, .{})) {
                    const first_half = input.buf.firstHalf();
                    const second_half = input.buf.secondHalf();
                    const name = try allocator.alloc(u8, first_half.len + second_half.len);
                    defer allocator.free(name);
                    @memcpy(name[0..first_half.len], first_half);
                    @memcpy(name[first_half.len..], second_half);

                    switch (try state.check(name)) {
                        .found => |country| {
                            input.clearAndFree();
                            switch (state.hint) {
                                .capital => |capital| if (capital.country == country) {
                                    state.hint = .new(&state.map, rng.random());
                                },
                            }
                        },
                        .not_found => {},
                        .finished => {
                            var buf: [2048]u8 = undefined;
                            while (true) {
                                const window = vx.window();
                                window.clear();
                                window.hideCursor();

                                var time_buf: [10]u8 = undefined;
                                const time = State.fmtTime(state.elapsed_ns, &time_buf);

                                _ = window.print(&.{.{
                                    .text = std.fmt.bufPrint(
                                        &buf,
                                        \\You won (press any key to exit)
                                        \\Time: {s}
                                    ,
                                        .{time},
                                    ) catch unreachable,
                                }}, .{});

                                try vx.render(bw.writer().any());
                                try bw.flush();

                                switch (loop.nextEvent()) {
                                    .winsize => |ws| {
                                        try vx.resize(allocator, tty.anyWriter(), ws);
                                    },
                                    .key_press => break,
                                }
                            }
                            break;
                        },
                    }
                } else {
                    try input.update(.{ .key_press = key });
                }
            },
            .winsize => |ws| {
                try vx.resize(allocator, tty.anyWriter(), ws);
            },
        }

        const window = vx.window();
        state.render(window, &input);

        try vx.render(bw.writer().any());
        try bw.flush();
    }
}
