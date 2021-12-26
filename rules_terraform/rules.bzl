TerraformModuleInfo = provider(
    "Provider for the terraform_module rule",
    fields={
        "source_files": "depset of source Terraform files",
        "providers": "depset of providers",
    })

def _terraform_module_impl(ctx):
    # TODO: Once we have dependencies, we need to resolve transitive
    # dependencies. Same with plugins.
    return [
        TerraformModuleInfo(
            source_files = depset(ctx.files.srcs),
            providers = depset(ctx.files.providers),
        )
    ]

terraform_module = rule(
    implementation = _terraform_module_impl,
    attrs = {
        "srcs": attr.label_list(
            mandatory = True,
            allow_files = True,
        ),
        "providers": attr.label_list(
            mandatory = True,
        ),
    },
)

TerraformRootModuleInfo = provider(
    "Provider for the terraform_root_module rule",
    fields={
        "terraform_wrapper": "Terraform wrapper script to run terraform in this rule's output directory",
        "runfiles": "depset of collected files needed to run",
    })

def _terraform_root_module_impl(ctx):
    module = ctx.attr.module[TerraformModuleInfo]

    # Create a wrapper script that runs terraform in a bazel run directory with
    # all of the necessary files symlinked.
    wrapper = ctx.actions.declare_file(ctx.label.name + "_run_wrapper")
    ctx.actions.write(
        output = wrapper,
        is_executable = True,
        content = """
set -eu

terraform="$(realpath {terraform})"

cd "{package}"

exec "$terraform" $@
        """.format(
            package = ctx.label.package,
            terraform = ctx.executable.terraform.path,
        ),
    )

    source_files_list = module.source_files.to_list()
    providers_list = module.providers.to_list()

    args = ctx.actions.args()
    args.add("init")
    args.add("-backend=false")
    args.add_all(
        module.providers,
        before_each = "-plugin-dir",
    )
    dot_terraform = ctx.actions.declare_directory(".terraform")
    ctx.actions.run(
        executable = ctx.executable.terraform,
        inputs = source_files_list + providers_list,
        outputs = [dot_terraform],
        mnemonic = "TerraformInitialize",
        arguments = [args],
    )

    runfiles = ctx.runfiles(
        files = [ctx.executable.terraform, dot_terraform, wrapper] +
                source_files_list + providers_list,
    )
    return [
        DefaultInfo(
            runfiles = runfiles,
            executable = wrapper,
        ),
        TerraformRootModuleInfo(
            terraform_wrapper = wrapper,
            runfiles = runfiles,
        )
    ]

terraform_root_module = rule(
    implementation = _terraform_root_module_impl,
    attrs = {
        "module": attr.label(
            mandatory = True,
            providers = [TerraformModuleInfo],
        ),
        "terraform": attr.label(
            allow_files = True,
            executable = True,
            cfg = "host",
        ),
    },
    executable = True,
)

def _terraform_validate_test_impl(ctx):
    root = ctx.attr.root_module[TerraformRootModuleInfo]

    # Call the wrapper script from the root module and just run validate
    exe = ctx.actions.declare_file(ctx.label.name + "_validate_test_wrapper")
    ctx.actions.write(
        output = exe,
        is_executable = True,
        content = """exec "{terraform}" validate""".format(
            terraform = root.terraform_wrapper.short_path,
        ),
    )

    return [DefaultInfo(
        runfiles = root.runfiles,
        executable = exe,
    )]

terraform_validate_test = rule(
    implementation = _terraform_validate_test_impl,
    attrs = {
        "root_module": attr.label(
            mandatory = True,
            providers = [TerraformRootModuleInfo],
        ),
    },
    test = True,
)
