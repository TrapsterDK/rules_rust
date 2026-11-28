"""Analysis tests for `rust_analyzer_toolchain.rustc_lib`"""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("@bazel_skylib//rules:write_file.bzl", "write_file")
load("//rust:toolchain.bzl", "rust_analyzer_toolchain")

# buildifier: disable=bzl-visibility
load("//rust/private:rust_analyzer.bzl", "rust_analyzer_toolchain_alias")

def _rustc_lib_test_impl(ctx):
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)

    toolchain = target[platform_common.ToolchainInfo]
    toolchain_libs = [f.basename for f in toolchain.rustc_lib.to_list()]
    asserts.equals(env, ["libmock_driver.so"], toolchain_libs)

    runfiles = [f.basename for f in target[DefaultInfo].default_runfiles.files.to_list()]
    asserts.true(
        env,
        "libmock_driver.so" in runfiles,
        "Expected `rustc_lib` in the alias runfiles, got {}".format(runfiles),
    )

    return analysistest.end(env)

def _no_rustc_lib_test_impl(ctx):
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)

    asserts.equals(env, [], target[platform_common.ToolchainInfo].rustc_lib.to_list())
    asserts.equals(env, [], target[DefaultInfo].default_runfiles.files.to_list())

    return analysistest.end(env)

_rustc_lib_test = analysistest.make(
    _rustc_lib_test_impl,
    config_settings = {
        "//command_line_option:extra_toolchains": [str(Label(":with_rustc_lib_toolchain"))],
    },
)

_no_rustc_lib_test = analysistest.make(
    _no_rustc_lib_test_impl,
    config_settings = {
        "//command_line_option:extra_toolchains": [str(Label(":without_rustc_lib_toolchain"))],
    },
)

def _define_targets():
    write_file(
        name = "mock_rustc",
        out = "mock_rustc.exe",
        content = [],
        is_executable = True,
    )

    write_file(
        name = "mock_driver",
        out = "libmock_driver.so",
        content = [],
    )

    native.filegroup(
        name = "mock_rustc_lib",
        srcs = [":mock_driver"],
    )

    native.filegroup(
        name = "mock_rustc_srcs",
        srcs = [],
    )

    for name, rustc_lib in [("with_rustc_lib", ":mock_rustc_lib"), ("without_rustc_lib", None)]:
        rust_analyzer_toolchain(
            name = name + "_rust_analyzer_toolchain",
            rustc = ":mock_rustc",
            rustc_lib = rustc_lib,
            rustc_srcs = ":mock_rustc_srcs",
        )

        native.toolchain(
            name = name + "_toolchain",
            toolchain = ":{}_rust_analyzer_toolchain".format(name),
            toolchain_type = "//rust/rust_analyzer:toolchain_type",
        )

    rust_analyzer_toolchain_alias(
        name = "current_rust_analyzer_toolchain",
        tags = ["manual"],
    )

def rust_analyzer_toolchain_test_suite(name):
    """Entry-point macro called from the BUILD file.

    Args:
        name (str): The name of the test suite.
    """
    _define_targets()

    _rustc_lib_test(
        name = "rustc_lib_test",
        target_under_test = ":current_rust_analyzer_toolchain",
    )

    _no_rustc_lib_test(
        name = "no_rustc_lib_test",
        target_under_test = ":current_rust_analyzer_toolchain",
    )

    native.test_suite(
        name = name,
        tests = [
            ":no_rustc_lib_test",
            ":rustc_lib_test",
        ],
    )
