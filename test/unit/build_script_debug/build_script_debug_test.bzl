"""Starlark tests for the `DEBUG` and `PROFILE` environment of `cargo_build_script`"""

load("@bazel_skylib//lib:unittest.bzl", "analysistest")
load("@bazel_skylib//rules:write_file.bzl", "write_file")
load("//cargo:defs.bzl", "cargo_build_script")
load(
    "//test/unit:common.bzl",
    "assert_action_mnemonic",
    "assert_env_value",
)

def _build_script_env_test_impl(ctx):
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)

    action = [a for a in target.actions if a.mnemonic == "CargoBuildScriptRun"][0]
    assert_action_mnemonic(env, action, "CargoBuildScriptRun")
    assert_env_value(env, action, "DEBUG", ctx.attr.expected_debug)
    assert_env_value(env, action, "PROFILE", ctx.attr.expected_profile)
    return analysistest.end(env)

def _make_build_script_env_test(compilation_mode):
    return analysistest.make(
        _build_script_env_test_impl,
        attrs = {
            "expected_debug": attr.string(mandatory = True),
            "expected_profile": attr.string(mandatory = True),
        },
        config_settings = {
            "//command_line_option:compilation_mode": compilation_mode,
        },
    )

_build_script_env_dbg_test = _make_build_script_env_test("dbg")
_build_script_env_fastbuild_test = _make_build_script_env_test("fastbuild")
_build_script_env_opt_test = _make_build_script_env_test("opt")

def build_script_debug_test_suite(name):
    """Entry-point macro called from the BUILD file.

    Args:
        name (str): The name of the test suite.
    """
    write_file(
        name = "build_rs",
        out = "build.rs",
        content = [
            "fn main() {}",
            "",
        ],
    )

    cargo_build_script(
        name = "script",
        srcs = [":build.rs"],
        edition = "2021",
    )

    # The default toolchain uses `debuginfo=2` for `dbg` and `debuginfo=0` otherwise.
    _build_script_env_dbg_test(
        name = "build_script_env_dbg_test",
        target_under_test = ":script",
        expected_debug = "true",
        expected_profile = "debug",
    )

    _build_script_env_fastbuild_test(
        name = "build_script_env_fastbuild_test",
        target_under_test = ":script",
        expected_debug = "false",
        expected_profile = "debug",
    )

    _build_script_env_opt_test(
        name = "build_script_env_opt_test",
        target_under_test = ":script",
        expected_debug = "false",
        expected_profile = "release",
    )

    native.test_suite(
        name = name,
        tests = [
            ":build_script_env_dbg_test",
            ":build_script_env_fastbuild_test",
            ":build_script_env_opt_test",
        ],
    )
