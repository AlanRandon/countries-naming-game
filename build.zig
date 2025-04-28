const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const run_query = b.addSystemCommand(&.{
        "curl",
        "-s",
        "https://query.wikidata.org/sparql",
        "-H",
        "Accept: application/sparql-results+json",
        "--data-urlencode",
    });

    run_query.addPrefixedFileArg("query@", b.path("tools/query.sparql"));

    const process_query = b.addSystemCommand(&.{ "jq", "-f" });
    process_query.addFileArg(b.path("tools/query.jq"));

    process_query.setStdIn(.{ .lazy_path = run_query.captureStdOut() });

    const update_src = b.addUpdateSourceFiles();
    update_src.addCopyFileToSource(process_query.captureStdOut(), "countries.json");

    const generated = b.addExecutable(.{
        .name = "generate_countries",
        .root_source_file = b.path("tools/generate_countries.zig"),
        .target = b.graph.host,
    });

    generated.root_module.addAnonymousImport("countries.json", .{ .root_source_file = b.path("countries.json") });

    const fetch_step = b.step("fetch", "Run wikidata queries to update countries.json");
    fetch_step.dependOn(&update_src.step);

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const ansio = b.dependency("ansio", .{});

    exe_mod.addImport("RawTerm", ansio.module("RawTerm"));
    exe_mod.addAnonymousImport("countries", .{
        .root_source_file = b.addRunArtifact(generated).captureStdOut(),
    });

    const exe = b.addExecutable(.{
        .name = "lua_test",
        .root_module = exe_mod,
    });

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_unit_tests = b.addTest(.{
        .root_module = exe_mod,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}
