const std = @import("std");

pub const Continent = enum {
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

pub const Country = struct {
    name: []const u8,
    capitals: []const []const u8,
    continents: []const Continent,
};

pub usingnamespace blk: {
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

    break :blk struct {
        pub const countries = all;
        pub const by_name = std.StaticStringMap(*const Country).initComptime(by_name_kv_list);

        pub fn find(name: []const u8, buf: []u8) ?*const Country {
            return by_name.get(std.ascii.lowerString(buf, name));
        }

        pub const ContinentMap = struct {
            const Self = @This();

            map: std.AutoHashMap(*const Country, void),

            pub fn init(allocator: std.mem.Allocator) Self {
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

            pub fn add(map: *Self, country: *const Country) !void {
                try map.map.put(country, {});
            }

            pub fn contains(map: *const Self, country: *const Country) bool {
                return map.map.contains(country);
            }
        };
    };
};
