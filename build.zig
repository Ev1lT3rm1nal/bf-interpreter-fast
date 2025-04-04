const std = @import("std");

const ArrayBoundBehaviour = enum {
    None,
    Abort,
    Wrap,
    Block,
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});

    const optimize = b.standardOptimizeOption(.{});

    var options = b.addOptions();
    options.addOption(ArrayBoundBehaviour, "arraybounds", b.option(ArrayBoundBehaviour, "arraybounds", "Array bounds behaviour") orelse .None);

    const lib_mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        // .single_threaded = true,
        // .strip = true,
    });

    exe_mod.addOptions("options", options);

    exe_mod.addImport("bf_interpreter_lib", lib_mod);

    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "bf_interpreter",
        .root_module = lib_mod,
    });

    b.installArtifact(lib);

    const exe = b.addExecutable(.{
        .name = "bf",
        .root_module = exe_mod,
    });

    // exe.want_lto = true;
    exe.use_llvm = true;
    // exe.link_data_sections = true;
    // exe.link_function_sections = true;
    // exe.link_gc_sections = true;
    // exe.link_z_lazy = true;
    // exe.link_z_notext = true;

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const lib_unit_tests = b.addTest(.{
        .root_module = lib_mod,
    });

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const exe_unit_tests = b.addTest(.{
        .root_module = exe_mod,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
    test_step.dependOn(&run_exe_unit_tests.step);
}
