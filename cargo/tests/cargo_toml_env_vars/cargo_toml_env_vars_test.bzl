"""Analysis tests for the `//cargo/settings:cargo_toml_env_vars` flag."""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("@bazel_skylib//rules:write_file.bzl", "write_file")
load("//cargo:defs.bzl", "cargo_toml_env_vars")

_CARGO_TOML_ENV_VARS_FLAG = str(Label("//cargo/settings:cargo_toml_env_vars"))

_EXTRACT_MNEMONIC = "ExtractCargoTomlEnvVars"

def _extract_actions(target):
    return [a for a in target.actions if a.mnemonic == _EXTRACT_MNEMONIC]

def _enabled_runs_extractor_test_impl(ctx):
    env = analysistest.begin(ctx)
    actions = _extract_actions(analysistest.target_under_test(env))
    asserts.equals(env, 1, len(actions), "expected one {} action".format(_EXTRACT_MNEMONIC))
    if actions:
        asserts.true(
            env,
            "cargo_toml_variable_extractor" in actions[0].argv[0],
            "expected the action to run the extractor, got: {}".format(actions[0].argv[0]),
        )
    return analysistest.end(env)

_enabled_runs_extractor_test = analysistest.make(
    impl = _enabled_runs_extractor_test_impl,
)

def _disabled_writes_empty_env_file_test_impl(ctx):
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)
    asserts.equals(env, [], _extract_actions(target))

    writes = []
    for action in target.actions:
        outputs = [f.basename for f in action.outputs.to_list()]
        if action.mnemonic == "FileWrite" and outputs == ["env_vars.env"]:
            writes.append(action)
    asserts.equals(env, 1, len(writes), "expected env_vars.env to be written directly")
    if writes:
        asserts.equals(env, "", writes[0].content)
    return analysistest.end(env)

_disabled_writes_empty_env_file_test = analysistest.make(
    impl = _disabled_writes_empty_env_file_test_impl,
    config_settings = {_CARGO_TOML_ENV_VARS_FLAG: False},
)

def _disabled_extractor_is_placeholder_test_impl(ctx):
    env = analysistest.begin(ctx)
    executable = analysistest.target_under_test(env)[DefaultInfo].files_to_run.executable
    asserts.true(
        env,
        executable.basename.startswith("no_binary"),
        "expected the extractor alias to resolve to no_binary, got: {}".format(executable.short_path),
    )
    return analysistest.end(env)

_disabled_extractor_is_placeholder_test = analysistest.make(
    impl = _disabled_extractor_is_placeholder_test_impl,
    config_settings = {_CARGO_TOML_ENV_VARS_FLAG: False},
)

def cargo_toml_env_vars_test_suite(name):
    """Instantiates analysis tests covering `//cargo/settings:cargo_toml_env_vars`.

    Args:
        name (str): The name of the test suite.
    """
    write_file(
        name = "cargo_toml",
        out = "Cargo.toml",
        content = [
            "[package]",
            "name = \"env_vars\"",
            "version = \"0.1.0\"",
            "",
        ],
        tags = ["manual"],
    )

    cargo_toml_env_vars(
        name = "env_vars",
        src = ":cargo_toml",
        tags = ["manual"],
    )

    _enabled_runs_extractor_test(
        name = "enabled_runs_extractor_test",
        target_under_test = ":env_vars",
    )

    _disabled_writes_empty_env_file_test(
        name = "disabled_writes_empty_env_file_test",
        target_under_test = ":env_vars",
    )

    # `cargo_toml_env_vars` depends on this alias, so with the flag off the
    # real extractor and its crates drop out of the build graph.
    _disabled_extractor_is_placeholder_test(
        name = "disabled_extractor_is_placeholder_test",
        target_under_test = "//cargo/private:cargo_toml_variable_extractor",
    )

    native.test_suite(
        name = name,
        tests = [
            ":disabled_extractor_is_placeholder_test",
            ":disabled_writes_empty_env_file_test",
            ":enabled_runs_extractor_test",
        ],
    )
