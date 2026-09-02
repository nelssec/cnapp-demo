# Agent prompts for the CNAPP demo

Type these verbatim in VS Code (Copilot Chat, Agent mode, with the `qscanner` MCP server from
`.vscode/mcp.json` enabled) or in a Devin session on this repository (see `devin/README.md`).
Each heading is numbered so other docs and the runbook can reference "prompt N". The sheet
item each prompt satisfies is in brackets.

Before the first run: fetch the binary with `scripts/get-qscanner.sh .qscanner` (VS Code) or
let the Devin startup command do it (Devin); VS Code will then prompt for the access token
and IaC credentials the first time the server starts, per the `inputs` in `.vscode/mcp.json`.

## 1. IDE IaC scanning [4.1.1, 4.2.1, 4.2.2, 4.2.3, 4.2.4]

> Use the qscanner iac_scan tool on this repository. Show me the HIGH and CRITICAL
> misconfigurations grouped by file, with the line numbers.

Expected: a list naming `terraform/main.tf` (`aws_s3_bucket.uploads` ACL `public-read`, SSH
open to `0.0.0.0/0` in `aws_security_group.app`, `aws_iam_policy.app_admin` with
`Action = "*"` / `Resource = "*"`), `helm/cnapp-demo/templates/deployment.yaml` (`privileged:
true`, `runAsUser: 0`, `hostPath` mount of `/var/run/docker.sock`), and
`cloudformation/rds.yaml` (`StorageEncrypted: false`, `PubliclyAccessible: true`, a plaintext
`MasterUserPassword`). Findings carry check IDs such as `KSV-0017` and `AWS-0107` alongside
compliance references (CIS AWS/Kubernetes, Pod Security Standards).

## 2. Secrets and compliance view [4.2.4, 4.2.6]

> Run code_scan on ./helm with scan_types ["secret", "iac"] and show me the compliance
> column for each finding, including any Qualys KSPM CIDs.

Expected: the AWS access key and secret in `helm/cnapp-demo/values.yaml` (lines 9-10) flagged
by the secret scan, and the deployment's privileged/root/hostPath misconfigurations from the
IaC scan shown with their compliance mappings — CIS Kubernetes Benchmark and Pod Security
Standards controls, the matching Kubescape check ID (for example `DS-0002` for a container
running as root), and the Qualys KSPM CID for the privileged container (`CID-45032`). Ask
the agent to render the findings as a table with an explicit "Compliance" column rather than
a flat list.

## 3. Generated code fixes [4.3.1, 4.3.4]

> Run code_scan on this repository with scan_types ["sca", "secret", "iac"] and engine
> "local", then call generate_fix on that report_path and apply the exact-confidence fixes
> to the files in this workspace. Do not commit yet. Show me the diff.

Running `code_scan` with `engine "local"` first matters: it makes Terraform get evaluated
locally too (so it shows up as `AWS-*` findings) instead of being sent to the Qualys IaC
backend, which is what `generate_fix` needs to be able to return an exact fix for it.

Expected: `generate_fix` returns one entry per finding (`finding_id`, `kind` `dependency` or
`iac`, `file_path`, `start_line`/`end_line`, `explanation`, `fix`, `fix_language`,
`confidence` `exact` or `guided`, `apply_hint`). `confidence: exact` only comes back for
findings in `generate_fix`'s curated table of local check IDs (`KSV-*`, `DS-*`, `AWS-*`), so
with the local engine this covers the Helm deployment (`privileged: false`,
`runAsNonRoot: true`), the `Dockerfile` (a non-root `USER`, a `HEALTHCHECK`, `COPY` instead
of `ADD`), and `terraform/main.tf` (private ACL plus an `aws_s3_bucket_public_access_block`,
the SSH `cidr_blocks` narrowed) - plus a unified diff for `service/requirements.txt`
dependency bumps. Anything evaluated by the Qualys backend (`CID-*` check IDs - which is what
you'd get for Terraform/CloudFormation without `engine "local"`) comes back `guided` with the
remediation text in `explanation`/`apply_hint` rather than an auto-applicable fix, same as any
other finding outside the curated table (for example the IAM policy's `Action`/`Resource`
scope). Leave `guided` entries for review, per `apply_hint`.

## 4. Automated remediation pull request [4.3.2]

> Use the qscanner prompt remediate_and_open_pr with repository_path set to this repo and
> base_branch main.

Expected: the agent scans, fixes, re-scans, creates a branch off `main` (default `fail_on`
is `high`), and opens a pull request against `nelssec/cnapp-demo` with a findings table —
similar in spirit to the existing `qscanner/auto-remediation` PR (#2), which bumps the
`service/requirements.txt` pins. The `PR security scan` workflow then runs on that PR, but it
does not go green: on PR #2's [run](https://github.com/nelssec/cnapp-demo/actions/runs/33614465983)
the summary comment shows the dependency vulnerability count dropping from 78 (main) to 0
while the IaC gate still fails on the untouched Terraform/Helm files - remediation of one
class of finding does not unblock the others. (That particular 0 also coincided with the
SCA backend's vulnerability-report fetch exhausting its retries with repeated 404s, so don't
read it as proof every dependency finding was fixed - only that the six bumped pins are no
longer the picture, and the gate cares about IaC regardless.)

## 5. Automated recommendations [4.3.4]

> Use get_remediation_suggestions on the last scan report, and summarize what to fix first.

Expected: remediation suggestions ordered by severity, including the IaC "reconfigure"
entries (with their compliance references) alongside dependency-upgrade suggestions, so the
agent's summary spans both misconfigurations and vulnerable packages.

## 6. Policy enforcement in the developer workflow [4.3.3]

> Run iac_scan on this repository with fail_on ["high"] and tell me whether it would pass
> the CI gate.

Expected: the agent reports the gate would fail because of the `terraform/main.tf` and
`helm/cnapp-demo/templates/deployment.yaml` findings above, citing the non-zero exit code
qscanner uses for a gate failure — the same check enforced by the `PR security scan` and
`build-and-gate` workflows, and the reason pull request #1 (`demo/open-ingress`) fails the
gate today.

## 7. Stakeholder views [4.4.1 to 4.4.5]

Run the same report through all five audiences, either by calling `stakeholder_report`
directly with each `audience` value, or via the `stakeholder_briefing` prompt:

> Use the stakeholder_briefing prompt with audience devops for the last scan report.
> Use the stakeholder_briefing prompt with audience cloud_security for the last scan report.
> Use the stakeholder_briefing prompt with audience secops for the last scan report.
> Use the stakeholder_briefing prompt with audience infra_ops for the last scan report.
> Use the stakeholder_briefing prompt with audience ciso for the last scan report.

Expected: five different briefings from one report, each with `audience`, `headline`, and
`counts` (including `by_framework`), plus per-audience `sections` — a "Compliance" section
appears for every audience — and `recommended_actions`. DevOps gets a per-file remediation
checklist; the CISO gets counts, plain-language top risks, and a short list of decisions to
make.

## Finding the report path

If the agent asks for `scan_report_path`, tell it: "Use the `report_path` returned by the
most recent scan call (`iac_scan`, `code_scan`, `code_sca_scan`, or `container_image_scan`)."
Scan tools write reports as `*-Report.json` under a per-scan-ID subdirectory of
`~/qualys/qscanner/data/` (e.g. `~/qualys/qscanner/data/<scan_id>/<hash>-Report.json`), not a
flat `mcp-scans/` folder as an earlier draft of this doc said. The `report_path` field in the
tool's own output (a plain `report_path: <path>` line in the default `toon` output format) is
the reliable way to get this — do not guess the path from the scan ID alone.
