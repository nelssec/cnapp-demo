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
does not go green: on PR #2's [run](https://github.com/nelssec/cnapp-demo/actions/runs/33622728123)
the summary comment shows the dependency vulnerability count dropping from 78 (main) to 64
while the IaC gate still fails on the untouched Terraform/Helm files - remediation of one
class of finding does not unblock the others. The six bumped `service/requirements.txt` pins
remove 14 findings; the remaining 64 are npm packages in `app/`, which `qscanner patch` does
not rewrite today (the `generate_fix` tool still returns guided fixes for them).

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

## 8. Compliance scorecard [6.2.5, 1.2.2]

> Run code_scan on this repository with scan_types ["iac"] and engine "local", then call
> compliance_report on that report_path and show me the CIS Kubernetes and CIS Docker
> controls this repo fails, with the check IDs that fail each one.

Expected: `compliance_report` returns a `frameworks` list - one entry per framework the
findings map to. On a whole-repo scan that is about 10 frameworks with roughly 89 failed
controls: `qualys-kspm` (e.g. `CID-45032` for the privileged container), `kubescape`,
`cis-k8s-1.9`, `pss-v1.31`, `cis-docker-1.7`, plus `qualys-iac`, `cis-aws-1.2`/`1.4`/`3.0`
and `cis-azure-2.1` from the Terraform, CloudFormation and ARM files -
each with `id`, `name`, `version`, `failed`, `passed`, a `coverage_note`, and a `controls`
list where every control is `fail` (with the check IDs in `findings`) or `not_evaluated`.
CIS K8s `5.2.2` fails on `KSV-0017` (privileged container); CIS Docker `4.1` fails on
`DS-0002` (root user). Plus a `summary` with `total_controls_failed` and `by_framework`.
Ask for `frameworks: ["cis-k8s-1.9"]` to scope it to one benchmark. Nothing here is
`pass`: the IaC engines report pass/fail per check, not per control, so only an image scan
(prompt 9's image report, or `demo.sh` section 4) contributes `pass` rows - for CIS Docker
those come from the image's own control evaluation.

The same scorecard is available in the terminal as `--report-format compliance`
(`demo.sh` section 6).

## 9. Trace a finding back to the developer [3.5.1 to 3.5.5, 3.2.4]

> Call trace_finding with finding_id "CVE-2023-30861", the image report path from the last
> container_image_scan, the code report path from the last code_scan, and repository_path set
> to this repository. Walk me through the story it returns.

Expected: one record tying the runtime finding to the commit that caused it - `finding`
(id, kind, severity, package, installed and fixed version), `image` (`reference` plus
`labels` with `source`, `revision`, `run_url`, and `actor` read from the OCI labels
`build-and-gate.yml` stamps on the image), `code` (`repository`, `branch`, `commit` with
hash/message/author, and `manifest` with the path and the line number that pins the
vulnerable version in `service/requirements.txt`), `owners` (from `CODEOWNERS`), and a
`story` paragraph that reads as one narrative. `run_url` is composed from the
`com.qualys.cnapp-demo.run-id` label and the source repository, so it links straight to the
Actions run. An IaC check id works too (`trace_finding` with `finding_id "KSV-0017"` and just
the code report) and comes back with the file, the line, and the compliance mapping.

No `git` or `gh` runs: the commit comes from the report's own repository metadata and the
manifest line comes from reading the file in the checkout.

## 10. Triage findings to their owners [5.1.1, 5.1.2, 3.5.5]

> Use the triage_to_owners prompt with the last scan report path and repository_path set to
> this repository.

Expected: one Markdown task list per owner, resolved from `CODEOWNERS` - Terraform,
CloudFormation, and Azure ARM findings to `@nelssec/cloud-security`; the Helm chart and the
`Dockerfile` to `@nelssec/platform-team`; `app/` and `service/` dependency findings to
`@nelssec/app-team` - each item carrying a ticket-ready title, the lowercase severity,
`file:line`, a fix hint from `generate_fix` (marked exact or guided), and why it landed with
that owner. Anything no rule claims falls back to the last commit author from the report, and
a closing "Unassigned" section proposes the `CODEOWNERS` lines that would claim those paths.
Calling `finding_owners` directly gives the same grouping as data (`owners`, each with
`source`, `findings`, and `counts.by_severity`).

## 11. Goal-only remediation, no steps given [4.3.2, 4.3.4]

> Get this repository's high-severity findings to zero and make the PR gate pass. Use the
> qscanner tools, decide the order yourself, and stop when the gate is green or explain what
> is left.

This one is deliberately just a goal. Prompts 4 and 5 tell the agent roughly what to do;
here it gets an outcome and has to plan the route itself. Run it in Devin or VS Code, same
as the others.

Expected: the agent picks its own sequence, and a good run looks something like scan first
to establish the baseline, `generate_fix` on the report, apply the exact-confidence diffs
as-is (the curated Terraform ACL/SG, Helm `privileged`/`runAsNonRoot`, and Dockerfile
checks), hand-edit the guided ones, bump the Python pins in `service/requirements.txt`,
re-scan, and compare counts before touching the gate. The order is the agent's; two runs
will not sequence identically, and that is the point.

On this repository the honest end state is not a green gate. The Python pins and the IaC
fixes land, the dependency count drops, and the remaining high-severity findings are npm
packages qscanner does not patch. A correct run finishes by saying exactly that: what it
fixed, what is left, why it cannot fix the remainder, and what a human should do next. An
agent that declares success here is wrong, and that failure mode is worth showing on
purpose. If it stops early or claims the gate passed, ask it to re-run the gate and
reconcile.

Watching it hit the failing gate, go back to `generate_fix` for the files it skipped, and
re-scan is the clearest live evidence that the sequencing comes from results, not from a
script. Keep the run log; the before and after counts and the agent's own stopping
explanation are the artifact.

## Finding the report path

If the agent asks for `scan_report_path`, tell it: "Use the `report_path` returned by the
most recent scan call (`iac_scan`, `code_scan`, `code_sca_scan`, or `container_image_scan`)."
Scan tools write reports as `*-Report.json` under a per-scan-ID subdirectory of
`~/qualys/qscanner/data/` (e.g. `~/qualys/qscanner/data/<scan_id>/<hash>-Report.json`), not a
flat `mcp-scans/` folder as an earlier draft of this doc said. The `report_path` field in the
tool's own output (a plain `report_path: <path>` line in the default `toon` output format) is
the reliable way to get this — do not guess the path from the scan ID alone.
