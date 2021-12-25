def _terraform_download_impl(ctx):
    os, arch = _detect_os_arch(ctx)
    version = ctx.attr.version

    # First get SHA256SUMS file so we can get all of the individual zip SHAs
    ctx.report_progress("Downloading and extracting SHA256SUMS file")
    sha256sums_url = "https://releases.hashicorp.com/terraform/{version}/terraform_{version}_SHA256SUMS".format(
        version = version,
    )
    ctx.download(
        url = sha256sums_url,
        sha256 = ctx.attr.sha256,
        output = "terraform_sha256sums",
    )
    sha_content = ctx.read("terraform_sha256sums")
    sha_by_zip = _parse_sha_file(sha_content)
    zip = "terraform_{version}_{os}_{arch}.zip".format(
        version = version,
        os = os,
        arch = arch,
    )
    url = "https://releases.hashicorp.com/terraform/{version}/{zip}".format(
        version = version,
        zip = zip,
    )
    sha256 = sha_by_zip[zip]

    # Now download actual Terraform zip
    ctx.report_progress("Downloading and extracting Terraform")
    ctx.download_and_extract(
        url = url,
        sha256 = sha256,
        output = "terraform",
        type = "zip",
    )

    # Put a BUILD file here so we can use the resulting binary in other bazel
    # rules.
    ctx.file("BUILD.bazel",
        """
filegroup(
    name = "terraform_executable",
    srcs = ["terraform/terraform"],
    visibility = ["//visibility:public"]
)
""",
        executable=False
    )

def _detect_os_arch(ctx):
    if ctx.os.name == "linux":
        return "linux", "amd64"
    elif ctx.os.name == "mac os x":
        return "darwin", "amd64"
    else:
        fail("Unsupported operating system: " + ctx.os.name)

def _parse_sha_file(file_content):
    """Parses terraform SHA256SUMS file and returns map from zip to SHA.

    Args:
        file_content: Content of a SHA256SUMS file (see example below)

    Returns:
        A dict from a TF zip (e.g. terraform_1.1.2_darwin_amd64.zip) to zip SHA

    Here is an example couple lines from a SHA256SUMS file:

    214da2e97f95389ba7557b8fcb11fe05a23d877e0fd67cd97fcbc160560078f1  terraform_1.1.2_darwin_amd64.zip
    734efa82e2d0d3df8f239ce17f7370dabd38e535d21e64d35c73e45f35dfa95c  terraform_1.1.2_linux_amd64.zip
    """

    sha_by_zip = {}
    for line in file_content.splitlines():
        sha, _, zip = line.partition("  ")
        sha_by_zip[zip] = sha

    return sha_by_zip

terraform_download = repository_rule(
    implementation = _terraform_download_impl,
    attrs = {
        "sha256": attr.string(
            mandatory = True,
            doc = "Expected SHA-256 sum of the downloaded archive",
        ),
        "version": attr.string(
            mandatory = True,
            doc = "Version of Terraform",
        ),
    },
    doc = "Downloads a Terraform binary",
)

TerraformInitInfo = provider(
    "Files produced by terraform init",
    fields={
        "source_files": "depset of source Terraform files",
        "dot_terraform": ".terraform directory from terraform init",
    })

def _terraform_init(ctx):
    srcs = depset(ctx.files.srcs)
    output = ctx.actions.declare_directory(".terraform")
    ctx.actions.run(
        executable = ctx.executable._exec,
        inputs = srcs.to_list(),
        outputs = [output],
        mnemonic = "TerraformInitialize",
        arguments = [
            "init",
            "-out={0}".format(output.path),
            srcs.to_list()[0].dirname, # TODO: Better way to get this?
        ],
    )
    return [
        DefaultInfo(files = srcs),
        TerraformInitInfo(
            source_files = srcs,
            dot_terraform = output
        )
    ]

terraform_init = rule(
    implementation = _terraform_init,
    attrs = {
        "srcs": attr.label_list(
            mandatory = True,
            allow_files = True,
        ),
        "_exec": attr.label(
            default = Label("@terraform//:terraform_executable"),
            allow_files = True,
            executable = True,
            cfg = "host",
        ),
    },
    #outputs = {"out": "%{name}.out"},
)
