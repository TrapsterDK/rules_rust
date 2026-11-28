"""Analysis tests for the linker and library search paths of MSVC Rust targets."""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("@bazel_skylib//rules:write_file.bzl", "write_file")
load("@rules_cc//cc:cc_toolchain_config_lib.bzl", "feature", "flag_group", "flag_set", "tool_path")
load("@rules_cc//cc:defs.bzl", "cc_toolchain")
load("@rules_cc//cc/common:cc_common.bzl", "cc_common")
load("@rules_cc//cc/toolchains:cc_toolchain_config_info.bzl", "CcToolchainConfigInfo")
load("//rust:defs.bzl", "rust_binary")
load("//rust:toolchain.bzl", "rust_stdlib_filegroup", "rust_toolchain")

def _cc_config_impl(ctx):
    return cc_common.create_cc_toolchain_config_info(
        ctx = ctx,
        tool_paths = [
            tool_path(name = name, path = ctx.attr.link_tool if name == "gcc" else "bin/" + name)
            for name in ["ar", "cpp", "gcc", "ld", "nm", "objdump", "strip"]
        ] if ctx.attr.link_tool else [],
        toolchain_identifier = "test-clang-cl",
        host_system_name = "unknown",
        target_system_name = "unknown",
        target_cpu = "unknown",
        target_libc = "unknown",
        compiler = "unknown",
        abi_version = "unknown",
        abi_libc_version = "unknown",
        features = [
            feature(
                name = "libpath",
                enabled = True,
                flag_sets = [flag_set(
                    actions = ["c++-link-executable"],
                    flag_groups = [flag_group(flags = [
                        "/clang:/LIBPATH:sdk/um",
                        "-LIBPATH:crt/lib",
                        "/LIBPATH:sdk/ucrt",
                        "/DEFAULTLIB:ignored.lib",
                    ])],
                )],
            ),
        ],
    )

_cc_config = rule(
    implementation = _cc_config_impl,
    attrs = {
        "link_tool": attr.string(),
    },
    provides = [CcToolchainConfigInfo],
)

def _libpath_test_impl(ctx):
    env = analysistest.begin(ctx)
    actions = [a for a in analysistest.target_actions(env) if a.mnemonic == "Rustc"]
    asserts.equals(env, 1, len(actions))
    if actions:
        argv = actions[0].argv
        for expected in ["sdk/um", "crt/lib", "sdk/ucrt"]:
            asserts.true(
                env,
                "--codegen=link-arg=-LIBPATH:" + expected in argv,
                "Expected -LIBPATH:{} in {}".format(expected, argv),
            )
        asserts.false(env, any(["DEFAULTLIB" in arg for arg in argv]), "Unexpected link flag in {}".format(argv))
    return analysistest.end(env)

libpath_test = analysistest.make(
    _libpath_test_impl,
    config_settings = {
        # The mock toolchain cannot execute, so coverage must not build :bin.
        "//command_line_option:collect_code_coverage": False,
        "//command_line_option:extra_toolchains": [
            str(Label(":rust_toolchain")),
            str(Label(":cc_toolchain")),
        ],
        "//command_line_option:platforms": str(Label(":windows_msvc")),
    },
)

def _linker_test_impl(ctx):
    env = analysistest.begin(ctx)
    actions = [a for a in analysistest.target_actions(env) if a.mnemonic == "Rustc"]
    asserts.equals(env, 1, len(actions))
    if actions:
        linkers = [arg for arg in actions[0].argv if arg.startswith("--codegen=linker=")]
        asserts.equals(env, 1, len(linkers))
        if linkers:
            asserts.true(
                env,
                linkers[0].endswith("/" + ctx.attr.expected_linker),
                "Expected {} as the linker, got {}".format(ctx.attr.expected_linker, linkers[0]),
            )
    return analysistest.end(env)

def _make_linker_test(cc_toolchain):
    return analysistest.make(
        _linker_test_impl,
        attrs = {
            "expected_linker": attr.string(mandatory = True),
        },
        config_settings = {
            "//command_line_option:collect_code_coverage": False,
            "//command_line_option:extra_toolchains": [
                str(Label(":rust_toolchain_no_preference")),
                str(Label(cc_toolchain)),
            ],
            "//command_line_option:platforms": str(Label(":windows_msvc")),
        },
    )

clang_cl_linker_test = _make_linker_test(":cc_toolchain_clang_cl")
link_exe_linker_test = _make_linker_test(":cc_toolchain_link_exe")

def msvc_libpath_test_suite(name):
    """Entry-point macro for the MSVC library search path tests.

    Args:
        name: test suite name
    """
    native.constraint_setting(name = "abi")
    native.constraint_value(name = "msvc", constraint_setting = ":abi")
    native.platform(
        name = "windows_msvc",
        constraint_values = [
            "@platforms//cpu:x86_64",
            "@platforms//os:windows",
            ":msvc",
        ],
    )

    _cc_config(name = "cc_config")
    cc_toolchain(
        name = "cc_toolchain_impl",
        all_files = ":empty",
        compiler_files = ":empty",
        dwp_files = ":empty",
        linker_files = ":empty",
        objcopy_files = ":empty",
        strip_files = ":empty",
        supports_param_files = 0,
        toolchain_config = ":cc_config",
        toolchain_identifier = "test-clang-cl",
    )
    native.filegroup(name = "empty")
    native.toolchain(
        name = "cc_toolchain",
        target_compatible_with = [":msvc"],
        toolchain = ":cc_toolchain_impl",
        toolchain_type = "@rules_cc//cc:toolchain_type",
    )
    for link_name, link_tool in [("clang_cl", "bin/clang-cl.exe"), ("link_exe", "bin/link.exe")]:
        _cc_config(name = "cc_config_" + link_name, link_tool = link_tool)
        cc_toolchain(
            name = "cc_toolchain_{}_impl".format(link_name),
            all_files = ":empty",
            compiler_files = ":empty",
            dwp_files = ":empty",
            linker_files = ":empty",
            objcopy_files = ":empty",
            strip_files = ":empty",
            supports_param_files = 0,
            toolchain_config = ":cc_config_" + link_name,
            toolchain_identifier = "test-" + link_name,
        )
        native.toolchain(
            name = "cc_toolchain_" + link_name,
            target_compatible_with = [":msvc"],
            toolchain = ":cc_toolchain_{}_impl".format(link_name),
            toolchain_type = "@rules_cc//cc:toolchain_type",
        )

    rust_toolchain(
        name = "rust_toolchain_impl",
        binary_ext = ".exe",
        dylib_ext = ".dll",
        exec_triple = "x86_64-unknown-linux-gnu",
        linker = ":mock_linker",
        linker_preference = "rust",
        linker_type = "direct",
        rust_doc = ":mock_rustdoc",
        rust_std = ":std_libs",
        rustc = ":mock_rustc",
        staticlib_ext = ".lib",
        stdlib_linkflags = [],
        target_triple = "x86_64-pc-windows-msvc",
    )
    native.toolchain(
        name = "rust_toolchain",
        target_compatible_with = [":msvc"],
        toolchain = ":rust_toolchain_impl",
        toolchain_type = "@rules_rust//rust:toolchain",
    )
    rust_toolchain(
        name = "rust_toolchain_no_preference_impl",
        binary_ext = ".exe",
        dylib_ext = ".dll",
        exec_triple = "x86_64-unknown-linux-gnu",
        linker = ":mock_linker",
        linker_type = "direct",
        rust_doc = ":mock_rustdoc",
        rust_std = ":std_libs",
        rustc = ":mock_rustc",
        staticlib_ext = ".lib",
        stdlib_linkflags = [],
        target_triple = "x86_64-pc-windows-msvc",
    )
    native.toolchain(
        name = "rust_toolchain_no_preference",
        target_compatible_with = [":msvc"],
        toolchain = ":rust_toolchain_no_preference_impl",
        toolchain_type = "@rules_rust//rust:toolchain",
    )
    rust_stdlib_filegroup(name = "std_libs", srcs = [])
    for tool in ["mock_linker", "mock_rustc", "mock_rustdoc"]:
        write_file(name = tool, out = tool + ".exe", content = [], is_executable = True)

    rust_binary(
        name = "bin",
        srcs = ["lib.rs"],
        edition = "2021",
        tags = ["manual"],
    )

    libpath_test(
        name = "libpath_test",
        target_under_test = ":bin",
    )

    clang_cl_linker_test(
        name = "clang_cl_linker_test",
        expected_linker = "mock_linker.exe",
        target_under_test = ":bin",
    )

    link_exe_linker_test(
        name = "link_exe_linker_test",
        expected_linker = "link.exe",
        target_under_test = ":bin",
    )

    native.test_suite(name = name, tests = [
        ":clang_cl_linker_test",
        ":libpath_test",
        ":link_exe_linker_test",
    ])
