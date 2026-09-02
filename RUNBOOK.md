# CNAPP demo runbook

Prerequisites (do these the day before):

- Refresh the demo credentials: `QUALYS_ACCESS_TOKEN` is a CS access token and it expires
  (it is a JWT). Get a fresh one, update `~/.config/cnapp-demo/iac.env` on the demo laptop,
  and push it to CI too: `gh secret set QUALYS_ACCESS_TOKEN --repo nelssec/cnapp-demo`. Do the
  same check for `QUALYS_IAC_USERNAME`/`QUALYS_IAC_PASSWORD` if backend IaC evaluation
  (Terraform/CloudFormation CID checks) has stopped appearing.
- `source ~/.config/cnapp-demo/iac.env` in the demo shell. Never print or paste these values
  anywhere (chat, slides, terminal recording overlays).
- `scripts/get-qscanner.sh .qscanner` on the demo laptop; `.qscanner/qscanner --version`
  works.
- Docker running. `docker build -t cnapp-demo:local .` once so `demo.sh` section 4 is fast.
- VS Code open on this repo with the `qscanner` MCP server from `.vscode/mcp.json` connected
  (first launch prompts for the token and IaC credentials).
- Devin session on `nelssec/cnapp-demo` with the qscanner MCP server connected per
  `devin/README.md`.
- GitHub tabs open: [PR #1](https://github.com/nelssec/cnapp-demo/pull/1) (Files changed and
  Checks tabs), [PR #2](https://github.com/nelssec/cnapp-demo/pull/2), the Actions list, the
  [build-and-gate run](https://github.com/nelssec/cnapp-demo/actions/runs/33613303229), and
  the [auto-remediate run](https://github.com/nelssec/cnapp-demo/actions/runs/33614398210).
- Run `./demo.sh` once end to end (not `--fast`) so the reports in `demo-output/` are warm and
  the image is already built.

## Sheet coverage

| Item | Requirement | Surface | Do this | Expect | Fallback |
| --- | --- | --- | --- | --- | --- |
| 4.1.1 | IaC scan in IDE | VS Code | Prompt 1 from `docs/agent-prompts.md` | Findings grouped by file with line numbers, for `terraform/main.tf`, `helm/cnapp-demo/templates/deployment.yaml`, `cloudformation/rds.yaml`; check IDs like `KSV-0017`, `AWS-0107` | MCP not connecting: run `.qscanner/qscanner mcp --pod CA1` in a terminal to see the auth error, fix, reload window; or fall back to Devin |
| 4.1.2 | IaC scan in source repo | GitHub Actions | Show the `PR security scan` run (`pr-scan.yml`) on `main` | Table in the `Scan repository` step log, SARIF/JSON/table under the `qscanner-reports` artifact | Actions queue slow: open the recorded [build-and-gate run](https://github.com/nelssec/cnapp-demo/actions/runs/33613303229) instead and narrate from there |
| 4.1.3 | IaC scan in PR | GitHub PR | Files changed / Checks tabs of [PR #1](https://github.com/nelssec/cnapp-demo/pull/1) | Inline annotations from `.github/scripts/annotate.js` (e.g. a `KSV-`/`AWS-` finding on the new open-ingress rule) plus the `QScanner findings` check summary comment | PR not loading: `gh pr view 1 --repo nelssec/cnapp-demo` in the terminal for the same data |
| 4.1.4 | IaC scan in CI/CD | GitHub Actions | Same `pr-scan.yml` run, `Enforce gate` step | Red step, `qscanner exit 72` message in the log | Same as 4.1.2 |
| 4.1.5 | Pre-deployment/build server | GitHub Actions | [`build-and-gate` run](https://github.com/nelssec/cnapp-demo/actions/runs/33613303229) | Image scanned before push; gate failed on 318 high/critical findings; `Push image` step skipped | Actions slow/unavailable: `demo.sh` section 4 reproduces the same scan locally against `cnapp-demo:local` |
| 4.2.1 | IaC issues | Terminal | `demo.sh` section 1 | IaC table with SEVERITY, CHECK ID, COMPLIANCE, FILE:LINE columns | No network to CA1: re-run section 1's command with `--iac-engine local`; the table still renders (AWS-`<n>` replaces CID-`<n>` for Terraform/CloudFormation) |
| 4.2.2 | Cloud misconfigurations | Terminal | Same | `aws_s3_bucket.uploads` public ACL, `cloudformation/rds.yaml` unencrypted + publicly accessible RDS | Same as 4.2.1 |
| 4.2.3 | IAM risks | Terminal | Same | `aws_iam_policy.app_admin` wildcard `Action`/`Resource` on `terraform/main.tf` | Same as 4.2.1 |
| 4.2.4 | Kubernetes risks on Helm | Terminal | `demo.sh` sections 1 and 2 | Privileged (`KSV-0017`), root (`KSV-0105`/`DS-0002`), hostPath docker.sock (`KSV-0006`), plus the AWS key pair in `values.yaml` | Same as 4.2.1 for section 1; section 2 has no backend dependency |
| 4.2.5 | Container security issues | Terminal | `demo.sh` section 4 | ~369 package vulnerability table for `cnapp-demo:local` | Docker not running: use `--fast` and point to the [build-and-gate run](https://github.com/nelssec/cnapp-demo/actions/runs/33613303229), which scanned the same Dockerfile |
| 4.2.6 | Secrets exposure | Terminal | `demo.sh` section 2 | AWS Access Key Id + AWS Secret Access Key on `helm/cnapp-demo/values.yaml:9-10`, CRITICAL | None needed - local-only, no backend call |
| 4.2.7 | Compliance violations | Terminal | `demo.sh` section 4 | Docker CIS PASS 1 / FAIL 4: `DOCKER_CIS 4.1` (root user), `4.6` (no HEALTHCHECK), `4.9` (ADD), `4.7` (update instruction) | Same as 4.2.5 |
| 4.3.1 | Generated code fixes | VS Code | Prompt 3 from `docs/agent-prompts.md` | `generate_fix` diffs applied for exact-confidence findings (Terraform ACL/SG, Helm `privileged`/`runAsNonRoot`, Dockerfile `USER`/`HEALTHCHECK`/`COPY`, `package.json` bumps) | Devin unavailable is not a blocker here (VS Code is already the primary surface); if VS Code MCP is down, describe the fixes from the prompt-3 expected output in `docs/agent-prompts.md` |
| 4.3.2 | Automated remediation PRs | Devin, GitHub | Prompt 4; also show the `Auto-remediate dependencies` workflow and [PR #2](https://github.com/nelssec/cnapp-demo/pull/2) | New PR with a findings table, six pins bumped in `service/requirements.txt`; `PR security scan` goes green on it | Devin unavailable: run prompt 4 in VS Code instead, or just show the already-open PR #2 and the [auto-remediate run](https://github.com/nelssec/cnapp-demo/actions/runs/33614398210) |
| 4.3.3 | Policy enforcement | Terminal, GitHub | `demo.sh` section 5; `Enforce gate` step in `pr-scan.yml` | Exit 72; red check on PR #1 | Same as 4.2.1 for the terminal half |
| 4.3.4 | Automated recommendations | VS Code | Prompt 5 | Remediation suggestions ordered by severity, spanning IaC "reconfigure" entries and dependency upgrades | Same as 4.3.1 |
| 4.4.1 | DevOps view | VS Code or Devin | Prompt 7, audience `devops` | Per-file remediation checklist | Whichever surface is down, use the other; both run the same MCP server binary |
| 4.4.2 | Cloud Security view | Same | audience `cloud_security` | Findings by provider/service with control mapping | Same as 4.4.1 |
| 4.4.3 | SecOps view | Same | audience `secops` | QDS scores, CVEs, credential exposure | Same as 4.4.1 |
| 4.4.4 | I&O view | Same | audience `infra_ops` | Artifacts and rollout order | Same as 4.4.1 |
| 4.4.5 | CISO view | Same | audience `ciso` | Counts (including `by_framework`), plain-language top risks, decisions to make | Same as 4.4.1 |
| 3.5.1-3.5.5 | Trace finding to image, repo, pipeline, commit, developer | GitHub Actions | `Push image` step log in `build-and-gate.yml`; qscanner collects `GITHUB_REPOSITORY`, `GITHUB_SHA`, `GITHUB_TRIGGERING_ACTOR`/`github.actor` as build pipeline metadata (`--collect-build-pipeline-metadata`, on by default) | Commit SHA, run ID, and actor visible in the push log line and in image labels (`com.qualys.cnapp-demo.run-id`, `...actor`) | Actions slow: `gh run view 33613303229 --repo nelssec/cnapp-demo --log` reproduces the same log locally |

## Fallbacks (consolidated)

- **No network to CA1 / backend down:** `demo.sh` section 1 detects a missing `CID-` result
  and automatically re-runs with `--iac-engine local`; do the same by hand for any manual
  `iac_scan` call. Cached reports from the last full `./demo.sh` run are under
  `demo-output/`, organized by section (`demo-output/iac`, `demo-output/secret`,
  `demo-output/sca`, `demo-output/image`, `demo-output/gate`) - open those JSON/table files
  directly if a live scan is not possible at all.
- **GitHub Actions queue slow:** skip to the pre-recorded runs - build-and-gate
  (https://github.com/nelssec/cnapp-demo/actions/runs/33613303229, gate failed on 318
  high/critical, push skipped) and auto-remediate
  (https://github.com/nelssec/cnapp-demo/actions/runs/33614398210, opened PR #2) - and the two
  open pull requests (#1, #2).
- **VS Code MCP not connecting:** run `.qscanner/qscanner mcp --pod CA1` directly in a
  terminal to see the auth/connection error, fix it (usually an expired token - see
  Prerequisites), and reload the VS Code window. If it still doesn't connect in time, switch
  to Devin for the same prompt.
- **Devin unavailable:** run the same numbered prompt in VS Code instead; both hit the same
  qscanner MCP server binary and produce the same outcome (for prompt 4, the same shape of PR
  as #2).
- **QUALYS_ACCESS_TOKEN expired mid-demo:** qscanner will fail auth immediately with a clear
  error. Get a fresh CS token, `export QUALYS_ACCESS_TOKEN=...` in the terminal (and update the
  VS Code MCP input / Devin secret if those surfaces are also being used), and re-run. Update
  `~/.config/cnapp-demo/iac.env` and `gh secret set QUALYS_ACCESS_TOKEN --repo nelssec/cnapp-demo`
  afterward so CI stays in sync.
- **Docker daemon not running:** `./demo.sh --fast` skips the image build/scan (section 4);
  narrate 4.2.5/4.2.7 from the recorded build-and-gate run instead.

## Outcome log (fill in after the rehearsal)

- `build-and-gate` gate result with and without `QUALYS_POLICY_TAGS` set:
- PR #1 inline annotation count:
- Time for a full `./demo.sh` run (not `--fast`):
- Time for `./demo.sh --fast`:
- Any exit code other than 0/72 seen in section 1, 3, or 5, and why:
