# Contributing

Thank you for improving `aws.modules.cloudfront`. This guide covers the toolchain, the local quality gate, how features are tested and where they belong, commit and pull request conventions, and how releases are cut.

## Development setup

The module targets Terraform `>= 1.7.0, < 2.0.0` and is developed against 1.7.5, the version the consuming platform pins. Install the toolchain:

| Tool | Purpose | Install |
| --- | --- | --- |
| [tfenv](https://github.com/tfutils/tfenv) | Pin the Terraform version | `tfenv install 1.7.5 && tfenv use 1.7.5` |
| [tflint](https://github.com/terraform-linters/tflint) | Lint with the Terraform and AWS rulesets configured in `.tflint.hcl` | `brew install tflint && tflint --init` |
| [terraform-docs](https://terraform-docs.io) v0.20.0 | Generate the inputs and outputs tables in every README. Pinned to the version bundled by the CI docs action; newer releases change table formatting and fail the drift check (`make docs` refuses other versions). | Download the v0.20.0 binary from the [releases page](https://github.com/terraform-docs/terraform-docs/releases/tag/v0.20.0) |
| [checkov](https://www.checkov.io) | Static security policy | `pip install checkov` |
| [trivy](https://trivy.dev) | Misconfiguration scanning | `brew install trivy` |
| [pre-commit](https://pre-commit.com) | Run the gate on every commit | `pip install pre-commit && pre-commit install` |

Clone, initialise without a backend, and run the gate once to confirm the setup:

```sh
terraform init -backend=false -input=false
make check
```

## Integration suite

`tests/integration/` holds the credential-driven `smoke` suite that applies the module for real and destroys everything afterwards. It is never part of `make check` or the quality pipeline. Run it against your own account before a release that touches resource behaviour:

```bash
export AWS_PROFILE=<profile> AWS_REGION=<region>
make integration-smoke   # 15-25 minutes each way: a real CloudFront distribution waits for Deployed on both create and destroy
```

A new feature whose correctness depends on the AWS API rather than on rendering (for example a change to how the OAC or the distribution's `viewer_certificate` block is built) should extend `smoke` rather than add a new suite, unless it needs a genuinely different fixture. Keep every value derived from the environment or from `tests/integration/setup`'s disposable fixture, and never reference a real bucket, certificate, or account. `tests/integration/setup` creates its own plain S3 bucket (not through `aws.modules.s3`) because this module never creates or reaches into its origin bucket; the policy scans exclude that fixture.

## The local gate

`make check` is the default target and the same gate CI runs. It stops at the first failing target and must pass before you open a pull request.

| Target | What it runs |
| --- | --- |
| `make fmt` | `terraform fmt -check -recursive -diff` from the repository root. `make fmt-fix` rewrites the files instead. |
| `make validate` | `make init` (`terraform init -backend=false`) followed by `terraform validate` in the root, every example, and `tests/integration/setup`. |
| `make lint` | `tflint --init` and then `tflint` in every directory with the root `.tflint.hcl`: documented and typed variables, documented outputs, snake_case naming, no unused declarations, pinned required versions and providers. |
| `make test` | `terraform test` in the root. No credentials are needed. |
| `make lock` | Refresh the committed root `.terraform.lock.hcl` with hashes for linux and macOS on amd64 and arm64 after changing the provider constraint. |
| `make docs` | `terraform-docs -c .terraform-docs.yml` in every directory, regenerating the tables between the `BEGIN_TF_DOCS` and `END_TF_DOCS` markers. Run it after touching any variable or output. |
| `make docs-check` | The same in `--output-check` mode: fails when a README is out of date. This is the variant `make check` and CI run. |
| `make security` | `checkov -d . --framework terraform`, and `trivy config --severity HIGH,CRITICAL` when trivy is on the PATH. A skip needs an inline `checkov:skip=` comment with a reason on the resource it concerns, or an entry in `.checkov.yml` proven against a standalone scan first (see `tests/integration/setup`'s exclusion there). |
| `make check` | `fmt`, `validate`, `lint`, `test`, `docs-check`, `security`, in that order. |

## Test-first workflow

Every behaviour in this module is pinned by a test before it is implemented. Write the failing `run` block first, then the code, then run `make test`.

- Tests live in `tests/*.tftest.hcl`, one file per concern: `defaults`, `cache_behaviors`, `checks`, `custom_error_responses`, `geo_restriction`, `validation` (every variable validation and precondition), and `viewer_certificate`. Each file starts with `mock_provider "aws" {}` and a `variables` block holding a valid baseline; each `run` overrides only what it exercises.
- Use `command = plan` unless the assertion needs a value that is unknown at plan time. `required_bucket_policy_json` is rendered from `aws_cloudfront_distribution.this.arn`, unknown at plan time for a fresh create, so `tests/bucket_policy.tftest.hcl` alone uses `command = apply` with an explicit `mock_resource "aws_cloudfront_distribution" { defaults = { arn = "..." } }` override. Keep any future `apply`-based test in its own file: `run` blocks in one `.tftest.hcl` file share state, and an `apply` run's state leaking into a later `plan` run in the same file would make a value that run expects to be unknown appear unexpectedly known.
- Validations and preconditions are tested with `expect_failures`. Point it at the object that carries the check: `[var.aliases]` for a variable validation, `[aws_cloudfront_distribution.this]` for a resource precondition, `[check.web_acl_not_attached]` for a `check` block. A run with `expect_failures` passes only if exactly those objects fail; add a positive run alongside so the happy path is covered too.
- `||` and `&&` do not short-circuit in Terraform 1.7. Both operands are always evaluated, so `var.x == null || var.x.field > 0` fails when `x` is null. Guard with a conditional instead: `var.x == null ? true : var.x.field > 0`. This applies to validations, preconditions, and test assertions alike.
- Set-typed attributes need `toset()` in assertions to compare against a literal set; a block type that is itself a set (for example `ordered_cache_behavior`) cannot be indexed with `[0]`.
- Keep assertion `error_message` text a statement of the guaranteed behaviour. It becomes the documentation of the contract when a test fails.

## Where to add a feature

The module has no submodules; concerns are split by file, and each file has one reason to change.

| Concern | Lives in |
| --- | --- |
| A distribution argument (a new `aws_cloudfront_distribution` field) | `variables.tf` with a description, type, and validation; `main.tf` to render it; a test in the file for that concern. |
| Cache-behavior default resolution, the bucket policy statement, the fixed hosted zone ID, the partition fallback | `locals.tf`, pinned in `tests/cache_behaviors.tftest.hcl` or `tests/bucket_policy.tftest.hcl`. |
| Cross-input rules (the alias/certificate mutual requirement) | Resource preconditions in `main.tf`'s `lifecycle` block, or `checks.tf` when the situation is valid but usually unintended. |
| Outputs | `outputs.tf`; every output has a description, and one derived from a resource attribute is asserted in a test. |

Rules that apply everywhere: no data sources beyond the documented `partition` fallback, every variable has a description, a type, and a validation where a wrong value would otherwise fail at apply time, every output has a description, defaults are the secure choice, and this module never creates or reaches into the origin bucket, the viewer certificate, or the WAF Web ACL — only their identifiers are consumed.

## Commits

Use [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/). The scope is the file or concern the change touches.

```text
feat(cache_behaviors): accept a caller cache_policy_id per path pattern
fix(locals): scope required_bucket_policy_json's Resource to origin_path
docs: explain the us-east-1 constraint for web_acl_arn
test(geo_restriction): cover an empty locations set with blacklist
feat!: require geo_restriction.locations for whitelist and blacklist
```

Append `!` after the type or scope for a breaking change and add a `BREAKING CHANGE:` footer explaining what consumers must do. Breaking changes ship only in a major release with an entry in the upgrade guide.

## Pull request checklist

- [ ] `make check` passes locally.
- [ ] New behaviour has a test; changed validations have both a passing and an `expect_failures` run.
- [ ] Variables and outputs have descriptions; `make docs` regenerated the README tables.
- [ ] `CHANGELOG.md` has an entry under `## [Unreleased]` in the right category.
- [ ] Breaking changes carry `!`, a `BREAKING CHANGE:` footer, and an update to `docs/UPGRADE-<major>.md`.
- [ ] Examples still initialise and validate; a new feature worth showing has an example.
- [ ] No data sources beyond the documented `partition` fallback, no hard-coded account, region, or partition, no new defaults that weaken security.

## Release process

Releases are cut by maintainers.

1. Move the `## [Unreleased]` entries in `CHANGELOG.md` under a new `## [X.Y.Z] - YYYY-MM-DD` heading, add its compare link, and merge that change to `main`.
2. Create a signed annotated tag on the merge commit. The signing key must be registered with GitHub so the tag shows as Verified:

   ```sh
   git tag -s vX.Y.Z -m "aws.modules.cloudfront vX.Y.Z"
   git push origin vX.Y.Z
   ```

3. Dispatch the `module-release` workflow (`.github/workflows/module-release.yml`) from the tag with `release_tag = vX.Y.Z`: `gh workflow run module-release.yml --ref vX.Y.Z -f release_tag=vX.Y.Z`. It verifies the signed tag, formatting, validation, tests, and generated docs, then publishes the GitHub release. Never dispatch it from `main`: the workflow checks that the tag points at the revision it checked out, and a maintenance release of an older line is cut from that line's commit.
4. Announce the release with the commit SHA. Consumers pin that SHA, not the tag:

   ```hcl
   source = "git::https://github.com/hatan4ik/aws.modules.cloudfront.git?ref=<commit-sha>" # vX.Y.Z
   ```

Tags are never moved or deleted once published. A bad release is followed by a new patch release.
