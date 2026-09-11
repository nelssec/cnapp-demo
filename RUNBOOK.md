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
| 4.1.1 | IaC scan in IDE (Terraform/OpenTofu, CloudFormation, Helm, Kubernetes, Dockerfile, Azure ARM) | VS Code | Prompt 1 from `docs/agent-prompts.md` | Findings grouped by file with line numbers, for `terraform/main.tf`, `helm/cnapp-demo/templates/deployment.yaml`, `cloudformation/rds.yaml`; check IDs like `KSV-0017`, `AWS-0107` | MCP not connecting: run `.qscanner/qscanner mcp --pod CA1` in a terminal to see the auth error, fix, reload window; or fall back to Devin |
| 4.1.2 | IaC scan in source repo | GitHub Actions | Show the `PR security scan` run (`pr-scan.yml`) on `main` | Table in the `Scan repository` step log, SARIF/JSON/table under the `qscanner-reports` artifact; TotalCloud > Posture > IaC Posture lists the scan for `nelssec/cnapp-demo` (CID-<n> controls); CS > Assets > Code lists the repo with TruRisk score and vulnerabilities | Actions queue slow: open the recorded [build-and-gate run](https://github.com/nelssec/cnapp-demo/actions/runs/33613303229) instead and narrate from there |
| 4.1.3 | IaC scan in PR | GitHub PR | Files changed / Checks tabs of [PR #1](https://github.com/nelssec/cnapp-demo/pull/1) | Inline annotations from `.github/scripts/annotate.js` (e.g. the new RDP rule, port 3389 open to `0.0.0.0/0`, annotated `CID-42` since `pr-scan.yml` evaluates Terraform against the Qualys backend by default) plus the `QScanner findings` check summary comment; an `AWS-0107`-family id only shows up here if the run instead evaluates Terraform with the local engine (`--iac-engine local`) | PR not loading: `gh pr view 1 --repo nelssec/cnapp-demo` in the terminal for the same data |
| 4.1.3b | IaC scan results in GitHub code scanning | GitHub Security tab | Security > Code scanning (repo is public so code scanning is on): alerts uploaded from the SARIF of each PR/main scan, rule ids `KSV-0017`, `DS-0002`, `CID-<n>`, with compliance tags on each rule | Alert list filterable by branch/PR; each alert opens on the offending line | Checks-API annotations on the PR show the same findings if the Security tab has not refreshed yet |
| 4.1.4 | IaC scan in CI/CD | GitHub Actions | Same `pr-scan.yml` run, `Enforce gate` step | Red step, `qscanner exit 72` message in the log | Same as 4.1.2 |
| 4.1.5 | Pre-deployment/build server | GitHub Actions | [`build-and-gate` run](https://github.com/nelssec/cnapp-demo/actions/runs/33613303229) | Image scanned before push; gate failed on 318 high/critical findings; `Push image` step skipped | Actions slow/unavailable: `demo.sh` section 4 reproduces the same scan locally against `cnapp-demo:local` |
| 4.2.1 | IaC issues | Terminal | `demo.sh` section 1 | IaC table with SEVERITY, CHECK ID, COMPLIANCE, FILE:LINE columns | No network to CA1: re-run section 1's command with `--iac-engine local`; the table still renders (AWS-`<n>` replaces CID-`<n>` for Terraform/CloudFormation) |
| 4.2.2 | Cloud misconfigurations | Terminal | Same; also `azure/storage.json` (ARM) → `CID-50011` secure transfer, `CID-50052` open network ACL, `CID-50181` TLS 1.0 with CIS Azure mappings | `aws_s3_bucket.uploads` public ACL, `cloudformation/rds.yaml` unencrypted + publicly accessible RDS | Same as 4.2.1 |
| 4.2.3 | IAM risks | Terminal | Same | `aws_iam_policy.app_admin` wildcard `Action`/`Resource` on `terraform/main.tf` | Same as 4.2.1 |
| 4.2.4 | Kubernetes risks on Helm | Terminal | `demo.sh` sections 1 and 2 | Privileged (`KSV-0017`), root (`KSV-0105`/`DS-0002`), hostPath docker.sock (`KSV-0006`), plus the AWS key pair in `values.yaml` | Same as 4.2.1 for section 1; section 2 has no backend dependency |
| 4.2.5 | Container security issues | Terminal | `demo.sh` section 4 | ~369 package vulnerability table for `cnapp-demo:local` | Docker not running: use `--fast` and point to the [build-and-gate run](https://github.com/nelssec/cnapp-demo/actions/runs/33613303229), which scanned the same Dockerfile |
| 4.2.6 | Secrets exposure | Terminal | `demo.sh` section 2 | AWS Access Key Id + AWS Secret Access Key on `helm/cnapp-demo/values.yaml:9-10`, CRITICAL | None needed - local-only, no backend call |
| 4.2.7 | Compliance violations | Terminal | `demo.sh` section 4 | Docker CIS PASS 1 / FAIL 4: `DOCKER_CIS 4.1` (root user), `4.6` (no HEALTHCHECK), `4.9` (ADD), `4.7` (update instruction) | Same as 4.2.5 |
| 4.3.1 | Generated code fixes | VS Code | Prompt 3 from `docs/agent-prompts.md`: `code_scan` with `engine "local"` (so Terraform gets local `AWS-*` ids) then `generate_fix` on that report | Exact-confidence diffs applied for the curated local check IDs (Terraform ACL/SG, Helm `privileged`/`runAsNonRoot`, Dockerfile `USER`/`HEALTHCHECK`/`COPY`), plus a unified diff for `service/requirements.txt`; findings the Qualys backend evaluates (`CID-*`) come back `guided`, not `exact` | Devin unavailable is not a blocker here (VS Code is already the primary surface); if VS Code MCP is down, describe the fixes from the prompt-3 expected output in `docs/agent-prompts.md` |
| 4.3.2 | Automated remediation PRs | Devin, GitHub | Prompt 4; also show the `Auto-remediate dependencies` workflow, [PR #2](https://github.com/nelssec/cnapp-demo/pull/2), and its [`PR security scan` run](https://github.com/nelssec/cnapp-demo/actions/runs/33622728123) | New PR with a findings table, six pins bumped in `service/requirements.txt`; the summary comment shows the dependency vulnerability count dropping from 122 (main) to 108 (the six Python pins remove 14 findings; the remaining 108 are npm and Java packages qscanner does not patch) while the IaC gate still fails (`exit 72`) on the untouched Terraform/Helm files - remediation of one class of finding does not unblock the others | Devin unavailable: run prompt 4 in VS Code instead, or just show the already-open PR #2 and the [auto-remediate run](https://github.com/nelssec/cnapp-demo/actions/runs/33614398210) |
| 4.3.3 | Policy enforcement | Terminal, GitHub | `demo.sh` section 5; `Enforce gate` step in `pr-scan.yml` | Exit 72; red check on PR #1 | Same as 4.2.1 for the terminal half |
| 4.3.4 | Automated recommendations | VS Code | Prompt 5 | Remediation suggestions ordered by severity, spanning IaC "reconfigure" entries and dependency upgrades | Same as 4.3.1 |
| 4.3.2, 4.3.4 (goal-only) | Dynamic multi-step remediation from a goal, no steps given | Devin (VS Code works too) | Prompt 11 from `docs/agent-prompts.md` | Agent plans its own order: baseline scan, `generate_fix`, exact diffs applied, guided ones hand-edited, Python pins bumped, re-scan, gate re-run; ends by explaining the leftover npm high-severity findings it cannot patch rather than claiming green | If the agent claims the gate passed, have it re-run the gate and reconcile; if Devin is down, VS Code runs the same prompt |
| 4.4.1 | DevOps view | VS Code or Devin | Prompt 7, audience `devops` | Per-file remediation checklist | Whichever surface is down, use the other; both run the same MCP server binary |
| 4.4.2 | Cloud Security view | Same | audience `cloud_security` | Findings by provider/service with control mapping | Same as 4.4.1 |
| 4.4.3 | SecOps view | Same | audience `secops` | QDS scores, CVEs, credential exposure | Same as 4.4.1 |
| 4.4.4 | I&O view | Same | audience `infra_ops` | Artifacts and rollout order | Same as 4.4.1 |
| 4.4.5 | CISO view | Same | audience `ciso` | Counts (including `by_framework`), plain-language top risks, decisions to make | Same as 4.4.1 |
| 3.5.1-3.5.5 | Trace finding to image, repo, pipeline, commit, developer | GitHub Actions | `Push image` step log in `build-and-gate.yml`; qscanner collects `GITHUB_REPOSITORY`, `GITHUB_SHA`, `GITHUB_TRIGGERING_ACTOR`/`github.actor` as build pipeline metadata (`--collect-build-pipeline-metadata`, on by default) | Commit SHA, run ID, and actor visible in the push log line and in image labels (`com.qualys.cnapp-demo.run-id`, `...actor`) | Actions slow: `gh run view 33613303229 --repo nelssec/cnapp-demo --log` reproduces the same log locally |
| 6.2.5 | Compliance reporting against benchmarks | Terminal, Devin/VS Code | `demo.sh` section 6 (`--report-format compliance`), or prompt 8 from `docs/agent-prompts.md` | `Compliance Scorecard` table: FRAMEWORK, CONTROL, STATUS, FINDINGS across about 10 frameworks / 89 failed controls on the whole repo (`qualys-kspm` incl. `CID-45032`, `kubescape`, `cis-k8s-1.9`, `pss-v1.31`, `cis-docker-1.7`, `qualys-iac`, `cis-aws-1.2`/`1.4`/`3.0`, `cis-azure-2.1`); CIS K8s 5.2.2 FAIL on `KSV-0017`, CIS Docker 4.1 FAIL on `DS-0002` | Terminal only needs the local engine, so no backend dependency; if VS Code MCP is down, `demo.sh` section 6 shows the same scorecard |
| 1.2.2 | Map findings to compliance controls | VS Code | Prompt 8, scoped with `frameworks: ["cis-k8s-1.9"]` | One framework entry with `failed`, `passed`, `coverage_note`, and every control as `fail` or `not_evaluated` | Read the `COMPLIANCE` column of `demo.sh` section 1's IaC table instead - same crosswalk, per finding rather than per control |
| 3.5.1-3.5.5 (MCP) | Trace a production finding to image, repo, pipeline, commit, developer | VS Code or Devin | Prompt 9 (`trace_finding`) with the image report from `demo.sh` section 4 and the code report from section 3 | One record plus a `story` paragraph: image reference, OCI labels (`source`, `revision`, `run_url` composed from `com.qualys.cnapp-demo.run-id`, `actor`), repository, branch, commit hash/message/author, the `service/requirements.txt` line that pins the vulnerable version, and the `CODEOWNERS` owner | No image report to hand (`--fast` run): call `trace_finding` with only `code_report_path` and `finding_id "KSV-0017"` - the repo, commit, and owner half of the trace still resolves |
| 3.2.4 | Correlate runtime artifact to source | Same | Same | The `package_match` block confirms the same package and version is in both the image and the repo | Same as 3.5.1-3.5.5 (MCP) |
| 5.1.1 | Assign findings to an owner | VS Code or Devin | Prompt 10 (`triage_to_owners`), or `finding_owners` directly | One task list per `CODEOWNERS` alias: `@nelssec/cloud-security` for `terraform/`, `cloudformation/`, `azure/`; `@nelssec/platform-team` for `helm/` and `Dockerfile`; `@nelssec/app-team` for `app/` and `service/`; `counts.by_severity` per owner | MCP down: `cat CODEOWNERS` and narrate the mapping against `demo.sh` section 1's FILE:LINE column |
| 5.1.2 | Route unowned findings | Same | Same | Findings no rule claims fall back to the last commit author from the report (`source: commit_author`); anything with neither lands under `unassigned`, with proposed `CODEOWNERS` lines | Same as 5.1.1 |
| 5.1.3 | Remediation status tracked in the developer's tool | GitHub Issues | Issues tab, label `qscanner`: one issue per CODEOWNERS owner, filed by the `Triage findings into issues` workflow on every scan of `main` (or run it from Actions with a severity floor) | Issues titled "QScanner: N high+ finding(s) for @nelssec/<team>" with a table of findings, locations, fixes and compliance refs; an issue closes itself when its owner's findings are gone | Show an existing issue; if the workflow is queued, the issues from the last run are already there |

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


## Section 3.4 and 3.5 answers (container prioritization and code-to-cloud trace)

The demo container (`ghcr.io/nelssec/cnapp-demo:latest` deployed by `helm/cnapp-demo`) is built so every prioritization
dimension in the sheet has a concrete signal. Rows 3.4.x are shown in TotalCloud > Container Security on the running
asset (Aman/Shrikant drive the UI); QScanner provides the same answer from the developer side so the story starts
before deploy. Exact QQL tokens: confirm in the CS UI filter builder.

| Item | Requirement | TotalCloud CS surface | QScanner evidence (this repo) |
| --- | --- | --- | --- |
| 3.4.1 | Business impact assessment | Assets > Containers: asset criticality score and dynamic tag on the cnapp-demo container (tag rule on image repo `nelssec/cnapp-demo` or namespace `cnapp-demo`); vulnerabilities re-ranked by TruRisk | `.qualys/criticality.yaml` in the repo (criticality, internet exposure) feeds the `prioritize_findings` MCP tool; owners from CODEOWNERS |
| 3.4.2 | Exploitability analysis | Vulnerabilities on the container filtered by threat intel: CISA KEV, public exploit, active attacks, exploit kit; software in use (npm, Java jar, Debian packages) | Image report: 4 KEV (Log4Shell), 83 public-exploit, 6 active-attack flags; `prioritize_findings` boosts and lists the reasons; `demo.sh` section 3/4 |
| 3.4.3 | Misconfiguration analysis | Containers filtered to privileged / running as root, then their vulnerabilities | The deployment is privileged, runs as UID 0 and mounts the Docker socket (KSV-0017, KSV-0012, KSV-0006); `prioritize_findings` applies the privileged-workload multiplier when given the IaC report as context |
| 3.4.4 | Exposure analysis | Containers filtered to internet-exposed (LoadBalancer service, public IP), then their vulnerabilities | Service type LoadBalancer in the chart; security group 0.0.0.0/0 on 22 and 3389 in Terraform (CID-41/42); exposure multiplier in `prioritize_findings` |
| 3.4.5 | Vulnerability analysis (QDS) | Open one QID on the asset, show QDS vs CVSS and the TruRisk contribution | Every vulnerability entry in the QScanner report carries `qdsScore`, CVSS and threat-intel flags; the Log4Shell QID shows QDS 95 with KEV |
| 3.4.6 | Runtime context (drift) | Runtime sensor on the cluster: drift between image and running container, runtime alerts | Not from QScanner; needs the sensor (Aman). The RUNBOOK insight table marks 5151/5154/5156 the same way |
| 3.4.7 | Prioritization methodology | Same QDS/TruRisk view: severity, exploitability, asset criticality, exposure combined | `prioritize_findings` prints its methodology paragraph and per-finding reasons (QDS base, threat-intel boosts, privileged/exposure/criticality multipliers, P1-P4 tiers) |
| 3.5.1 | Trace to container image | Attack path view (Anuj) from the running container to its image digest | `trace_finding` on the image report: image reference and digest, OCI labels |
| 3.5.2 | Trace to source repository | Same | `org.opencontainers.image.source` label -> `nelssec/cnapp-demo`; CS > Assets > Code lists the repo |
| 3.5.3 | Trace to pipeline | Same | `com.qualys.cnapp-demo.run-id` label -> the GitHub Actions run URL |
| 3.5.4 | Trace to commit | Same | `org.opencontainers.image.revision` -> commit; `trace_finding` joins it to the code report's commit (hash, message, author) and the manifest line (`java/pom.xml`, `app/package-lock.json`) |
| 3.5.5 | Trace to developer ownership | Same | `trace_finding` and `finding_owners` resolve CODEOWNERS (`@nelssec/app-team`, `@nelssec/platform-team`, `@nelssec/cloud-security`), falling back to the last commit author |

Demo path for 3.4: open the container in TotalCloud, show criticality tag and QDS ranking, filter privileged + internet-exposed + KEV, then switch to Devin/terminal and run `prioritize_findings` on the same image report to show the identical ranking with reasons, before the image was ever deployed.

## TruRisk Insights coverage

TotalCloud insights fire when the deployed container carries the signals below and is reachable from
the internet. The image built by `build-and-gate.yml` (`ghcr.io/nelssec/cnapp-demo`, or `cnapp-demo:local`)
and the Helm chart plant every signal except malware; deploying the chart to the demo EKS cluster with
the LoadBalancer service is what makes the container "publicly exposed".

| Signal the insight keys on | Where it is planted | Insight IDs it satisfies |
| --- | --- | --- |
| Secrets / sensitive data on the image | `/app/config/payments.yaml` (Stripe keys, SSN, card), `/app/data/customers.csv` (cards, IBANs, passport), `values.yaml` AWS key pair | 5113, 5114, 5117, 5120, 5126, 5183 |
| Critical exploitable vulnerability (CISA KEV) | `/app/lib/log4j-core-2.14.1.jar` (CVE-2021-44228), `java/pom.xml` (Log4Shell, Spring4Shell), plus the Debian git KEV already on the base image | 5113, 5118, 5119, 5121, 5129, 5136, 5137, 5182 |
| Public exploit / lateral movement flags | Same KEV packages carry threat-intel flags (public exploit, lateral movement) in the Qualys vuln report | 5119, 5120, 5121, 5136; vulnerabilities carrying the "associated with malware" threat-intel flag also satisfy 5116, 5123, 5139 |
| End-of-Life software | Base image `node:16-buster` (Debian 10 and Node 16 are both EOL) | 5180, 5182, 5183 |
| AI models / AI packages | `/root/.cache/huggingface/transformers/` (config.json, tokenizer.json, pytorch_model.bin), `@tensorflow/tfjs`, `transformers`, `torch` | 5189, 5191, 5193, 5194, 5195 |
| Excessive / wildcard cloud permissions | ServiceAccount with IRSA role `cnapp-demo-app` bound to the `Action:*`/`Resource:*` policy in `terraform/main.tf`, token auto-mounted | 5126, 5127, 5129, 5131, 5132, 5136, 5137, 5140, 5194, 5195 |
| Root privilege | `runAsUser: 0`, `privileged: true` in the deployment | 5131, 5140 |
| Public exposure | `Service` type `LoadBalancer` on port 80 | every "publicly exposed / public container" insight above |
| Runtime alert | Not planted; needs the runtime sensor on the cluster (Aman) | 5151, 5154, 5156 |
| Malware | Not planted: QScanner's malware analysis classifies ELF binaries with a backend ML model and there is no benign test sample that triggers it; do not add real malware to a public repository | 5115, 5118, 5122, 5124, 5130, 5133, 5141 |

Verified 2026-09-10 with the local build: repo SCA 122 vulnerabilities with 3 CISA KEV QIDs (Log4Shell 984157/986972, Spring4Shell 984158); image 127 vulnerabilities with 4 KEV, threat-intel flags on 100 (lateral movement) / 83 (public exploit) / 6 (active attacks); 3 AI model files under `/root/.cache/huggingface/transformers/`; 9 sensitive-data and key findings in 2 image files (Payment Card Number, SSN, IBAN, Stripe keys); CIS Docker PASS 1 / FAIL 4.

Verify locally before the demo: `./demo.sh` section 2 lists the PII findings (Payment Card Number, Social Security Number, IBAN, Stripe keys); section 3 shows the KEV flag on the Log4Shell QID; section 4 shows the image with the AI model files and the same secrets.

## Outcome log (rehearsed 2026-09-02)

- 2026-09-10 update (after planting the TruRisk insight signals; supersedes the counts below): main scan 122 dependency vulnerabilities (3 CISA KEV: Log4Shell, Spring4Shell), 11 secrets/sensitive-data findings in 3 files, 49-50 IaC misconfigurations, 3 AI model files; PR #1 `QScanner findings` 183 annotations, summary 122 / 11 / 50; PR #2 dependency count 122 -> 108; owner issues app-team 43, platform-team 12, cloud-security 14; image 127 vulnerabilities (4 KEV), 9 sensitive-data findings, 3 AI models, CIS Docker FAIL 4, GHCR push blocked.

Release used: `qscanner-5.3.0-cnapp5` (latest at rehearsal time; `scripts/get-qscanner.sh
.qscanner` fetched it without issue - `qscanner-5.3.0-cnapp5.linux-amd64.tar.gz` and
`...darwin-arm64.tar.gz` were both present and matched their SHA256SUMS entries).

### Terminal (`./demo.sh`)

- `build-and-gate` gate result: no `QUALYS_POLICY_TAGS` is set for this demo, so the gate
  (both in `./demo.sh` section 5 and in `build-and-gate.yml`) always blocks on report content
  (high/critical findings), not a policy verdict - see the "Gate reason" note under GitHub
  below for the exact wording.
- PR #1 inline annotation count: 124 (see GitHub section below).
- Time for a full `./demo.sh` run (Docker running, not `--fast`): **3m 19s** (`3:19.19 total`
  per `time`; wall clock 03:16:29-03:19:49 PDT).
- Time for `./demo.sh --fast`: **2m 52s** (`2:51.67 total`; section 4 skipped).
- Per-section exit codes (full run): section 1 (IaC) - first pass with
  `QUALYS_IAC_USERNAME`/`PASSWORD` set exited 0 but the Qualys IaC backend scan itself ended
  in `ERROR` (see below), so no `CID-` checks came back; `demo.sh` auto-retried with
  `--iac-engine local` per its detection logic, also exit 0 (162 checks passed / 26 failed
  the first pass, 251 passed / 42 failed after the local-only fallback covered
  Terraform/CloudFormation too). Section 2 (secrets): exit 0. Section 3 (SCA): exit 0 (see
  backend retry note below - no 40 seen). Section 4 (image): exit 0. Section 5 (gate): exit
  72, as expected (IaC gate failing on high/critical misconfigurations - the same gate PR #1
  fails). No exit 71 or 40 was seen in this rehearsal.
- IaC backend behaviour observed: the Qualys IaC backend scan (`2a6cbf5f-adad-...`) was
  `SUBMITTED` then came back `ended in ERROR` (not the 500 the code comment anticipates, but
  the same effective outcome - no `CID-` results). `demo.sh` detected the absence of
  `CID-` checks in the report and transparently re-ran with `--iac-engine local`, which is
  the documented, expected fallback; the visible table still covered Terraform and
  CloudFormation, just with `AWS-<n>` check IDs instead of `CID-<n>`. Nothing in the demo
  narration needs to change for this - it is exactly the fallback path `demo.sh` and the
  Runbook already describe - but presenters should expect `AWS-<n>` IDs on the night unless
  the backend has recovered.
- SCA count: **78** dependency vulnerabilities (after 4 retries on `404 Not Found` fetching
  the vulnerability report, ~50s total backend latency - well within the exit-40 timeout).
- Secret count: **2** (AWS Access Key Id + AWS Secret Access Key in
  `helm/cnapp-demo/values.yaml:9-10`, both CRITICAL).
- Image vuln count: **321** package vulnerabilities for `cnapp-demo:local` (comment in
  `demo.sh` says "~369" - actual count drifts run to run with the upstream Debian/npm
  advisory feed; 321 is normal and does not need a `demo.sh` update).
- Docker CIS: **PASS 1 / FAIL 4** - `DOCKER_CIS 4.1` (no non-root `USER`, HIGH), `4.6` (no
  `HEALTHCHECK`, MEDIUM), `4.7` (update instruction alone in a layer, MEDIUM), `4.9` (`ADD`
  instead of `COPY`, MEDIUM); `4.10` (no secrets in the Dockerfile) PASSED.

### GitHub (read-only, via `gh`)

- PR #1 (https://github.com/nelssec/cnapp-demo/pull/1, `demo/open-ingress`, head
  `c79440c`): check-runs on the head commit show `QScanner findings` -
  **failure, 124 annotations** and `QScanner code scan (SCA, secrets, IaC)` - failure, 7
  annotations. The `<!-- qscanner-summary -->` PR comment is present: 78 dependency
  vulnerabilities, 2 secrets, 44 IaC misconfigurations, 0 compliance, **Gate: FAILED
  (qscanner exit 72)**. PR is still open.
- PR #2 (https://github.com/nelssec/cnapp-demo/pull/2, `qscanner/auto-remediation`, head
  `c954e75`): still open; diff is exactly `service/requirements.txt`, 6 lines changed
  (flask 2.0.1->2.2.5, werkzeug 2.0.1->2.3.8, requests 2.25.1->2.33.0, pyyaml 5.3.1->5.4,
  jinja2 2.11.2->2.11.3, urllib3 1.26.4->1.26.19).
- Latest `PR security scan` run for PR #1 itself: **failure** (124 annotations, expected -
  this is the gate working as designed). Latest `PR security scan` run overall (push to
  `main`, run 33618217040): also failure, for the same reason `main` itself carries the
  baseline misconfigurations.
- Latest `Build, scan image, gate, push` run (33618216985, push to `main`): **failure**, but
  for an unexpected reason unrelated to the security gate - it failed at the "Setup
  qscanner" step with `no assets match the file pattern` (a transient race between
  publishing release assets and the very next workflow run picking up that release; a
  `gh release download` for the same tag succeeded seconds later from this machine). The
  actual gate mechanism was last exercised cleanly on run 33616565172 (push to `main`,
  slightly earlier): image built, qscanner scanned it, **Gate step failed with 318
  high/critical findings** ("No CA1 policy is configured for this demo, so the gate blocks
  on report content instead of a policy verdict... Image will not be pushed."), `Push image`
  skipped, job failed via the deliberate "Fail job when gate failed" step. This is the
  behavior to narrate; if the flaky asset-fetch failure recurs on demo night, re-running the
  workflow (`gh run rerun <id> --repo nelssec/cnapp-demo`) should clear it since the release
  itself is intact.

### MCP surface rehearsed headlessly

Per the controller ruling, VS Code and Devin sessions need a human, so the MCP surface itself
was rehearsed by driving `qscanner mcp --pod CA1` directly over stdio with raw JSON-RPC
(`initialize` -> `notifications/initialized` -> `tools/list` -> `tools/call`), from the fresh
`.qscanner/qscanner` binary, `QUALYS_ACCESS_TOKEN`/`QUALYS_IAC_USERNAME`/`PASSWORD` sourced
from `~/.config/cnapp-demo/iac.env`.

- `tools/list`: 14 tools registered (`code_sca_scan`, `code_scan`, `compare_scans`,
  `compliance_report`, `container_image_scan`, `evaluate_security_policy`, `finding_owners`,
  `generate_fix`, `get_remediation_suggestions`, `get_scan_summary`, `get_vulnerability_details`,
  `iac_scan`, `stakeholder_report`, `trace_finding`) - the 11 above plus the three analyst
  tools - plus 9 MCP prompts (the 8 below plus `triage_to_owners`) and 1 static + 3 template
  resources per the server's own startup log. Schemas matched `docs/agent-prompts.md`
  (`iac_scan` takes `target`/`iac_types`/`engine`/`fail_on`;
  `generate_fix`/`stakeholder_report`/`get_scan_summary` take `scan_report_path`, not
  `report_path`). Re-verified against release `qscanner-5.3.0-cnapp6` on 2026-09-02.
- `iac_scan` (`target=<repo path>`, `iac_types=[helm,kubernetes,dockerfile]`,
  `engine=local`): completed in ~1s (no backend call). Headline: 26 misconfigurations, 162
  checks passed, risk driven by 5 HIGH findings (root user, hostPath docker.sock mount,
  default security context, non-read-only rootfs, privileged). Counts by severity - high 5,
  medium 6, low 15. Counts `by_framework` - `qualys-kspm` 19, `kubescape` 20, `cis-k8s-1.9`
  12, `pss-v1.31` 11, `cis-docker-1.7` 4 (a finding can map to more than one framework).
- `generate_fix` on that report: 26 fixes returned. First two: `DS-0002` (Dockerfile root
  user, **confidence: exact**, fix adds a non-root `USER`) and `KSV-0006` (hostPath
  `docker.sock` mount, **confidence: guided** - a suggested manifest edit for review, not an
  auto-apply).
- `stakeholder_report` audience `ciso`: headline "0 vulnerabilities, 0 exposed secrets, 26
  misconfigurations. Highest severity: high. All have known fixes." with a "Top risks in
  plain language" section and 3 recommended actions (approve the CI gate policy, fund
  credential rotation, request a monthly trend report).
- `stakeholder_report` audience `devops`: headline "2 file(s) need changes: 0 dependency
  vulnerabilities, 0 exposed secrets, 26 IaC misconfigurations", with a per-file checklist
  (`Dockerfile`, `helm/cnapp-demo/templates/deployment.yaml`) giving line numbers and fixes.
- `get_scan_summary`: `risk_level: high`, `total_misconfigurations: 26`,
  `iac_checks_passed: 162`, `total_secrets: 0`, `total_vulnerabilities: 0` (scope was IaC
  only, so no SCA/secret counts here - that matches `code_scan` being the tool for a
  combined view).
- Doc fix: `docs/agent-prompts.md` ("Finding the report path") said reports land under
  `~/qualys/qscanner/data/mcp-scans/`; the actual path observed in every one of the calls
  above was a per-scan-ID subdirectory of `~/qualys/qscanner/data/` (e.g.
  `~/qualys/qscanner/data/<scan_id>/<hash>-Report.json`) with no `mcp-scans/` folder at all.
  Updated the doc to say so and to point agents at the tool's own `report_path` field rather
  than guessing the path.
- **Analyst tools rehearsed (release `qscanner-5.3.0-cnapp6`, 2026-09-02).** `scripts/get-qscanner.sh
  .qscanner` fetched it without issue; `.qscanner/qscanner --version` reports
  `5.3.0-cnapp6-0`. `./demo.sh --fast` (sections 1-3, 5-7) ran clean, exit 0 overall, in
  **2m 11s**; per-section exit codes matched the earlier cnapp5 rehearsal (sections 1/2/3/6/7:
  0; section 5 gate: 72, expected). Section 6's scorecard caption:
  `Compliance Scorecard (10 framework(s), 89 control(s) failed, 0 passed)` - first three rows
  all fall under `qualys-kspm`: `CID-45005 Non-root containers` (`KSV-0012, KSV-0105`),
  `CID-45008 Allow privilege escalation` (`KSV-0001`), `CID-45009 Immutable container
  filesystem` (`KSV-0014`). This matches `docs/agent-prompts.md` prompt 8's documented
  "roughly 89 failed controls" almost exactly, so no rewording was needed there.
  - MCP calls were driven against a broader code report than Task 7's (`.qscanner/qscanner
    --pod CA1 --scan-types sca,secret,iac --report-format json -o demo-output/rehearsal code
    .` - whole repo, default engine, no `--exclude-dirs`), not the narrower
    helm/kubernetes/dockerfile-only `iac_scan` report from Task 7, so its own
    `compliance_report` numbers (12 frameworks, 98 controls failed total) are a separate,
    larger figure from `demo.sh` section 6's 89/10 above - both are correct for their own
    scope, this is a deviation worth remembering, not a bug.
  - `compliance_report` (default frameworks) on that code report: 12 frameworks, `summary.
    total_controls_failed: 98`, `by_framework`: `qualys-kspm` 20, `qualys-iac` 20, `kubescape`
    23, `cis-k8s-1.9` 8, `pss-v1.31` 6, `cis-docker-1.7` 3, `cis-azure` 6, `cis-azure-2.1` 3,
    `cis-aws-3.0` 3, `cis-aws` 2, `cis-aws-1.2` 2, `cis-aws-1.4` 2.
  - `compliance_report` with `frameworks: ["cis-k8s-1.9","cis-docker-1.7"]`: `summary.
    total_controls_failed: 11` (`cis-k8s-1.9` 8, `cis-docker-1.7` 3). Confirmed: CIS
    Kubernetes `5.2.2` fails on `KSV-0017` (privileged container); CIS Docker `4.1` fails on
    `DS-0002` (root user).
  - `trace_finding` on `KSV-0017` (code report + `repository_path` only, no image path):
    returns `code.repository: https://github.com/nelssec/cnapp-demo.git`, `branch: main`,
    commit `049e2567461e23adeb6421dd5df9c1d689cbbdd3` by `Andrew Nelson <andrew@nelssec.com>`,
    the compliance mapping (incl. `5.2.2`/`cis-k8s-1.9`), `owners: [@nelssec/platform-team]`
    (from `CODEOWNERS`), an empty `image` section (no image path given, as expected), and a
    `story` paragraph.
  - `trace_finding` on a dependency finding (`QID-990887`, `moment` `CVE-2022-24785`, code
    report + a locally built `cnapp-demo:local` image report + `repository_path`): the local
    image was built with `docker build --label org.opencontainers.image.source=... --label
    org.opencontainers.image.revision=$(git rev-parse HEAD) --label
    com.qualys.cnapp-demo.run-id=local --label com.qualys.cnapp-demo.actor=andrew` mirroring
    `build-and-gate.yml`'s label keys, so unlike an unlabeled local build the trace record did
    carry an `image` section: `reference: cnapp-demo:local`, `labels`: `source`,
    `revision: 049e2567461e23adeb6421dd5df9c1d689cbbdd3`, `actor: andrew`, and
    `run_url: https://github.com/nelssec/cnapp-demo/actions/runs/local` (composed from
    `com.qualys.cnapp-demo.run-id=local` per the spec-ambiguity ruling). `owners:
    [@nelssec/app-team]`. Deviation: the image's own dependency scan did not itself report
    `moment` (its `npm ci --omit=dev` layer differs from the full lockfile the code scan
    reads), so this record demonstrates the labels/reference path rather than an
    installed-version cross-reference; the GHCR image from an actual `build-and-gate` run
    remains the path that would show both.
  - `finding_owners` on the code report: `codeowners_file: CODEOWNERS`, `total_findings: 126`,
    three buckets, all `source: codeowners`: `@nelssec/app-team` - 78 findings
    (`counts.by_severity`: critical 4, high 28, medium 40, low 6); `@nelssec/cloud-security` -
    20 findings (high 14, medium 6); `@nelssec/platform-team` - 28 findings (critical 2,
    high 5, medium 6, low 15).
  - `prompts/get` for `triage_to_owners` (with `scan_report_path`/`repository_path` filled
    in): returns description "Findings grouped by owner as Jira-ready task lists" and a user
    message opening "Triage the QScanner findings in ... to the teams that own them ...
    1. Resolve ownership. Call finding_owners ... 2. Get fix content. Call generate_fix ...
    3. Write one Markdown section per owner ...", matching `docs/agent-prompts.md` prompt 10
    - no rewording needed there either, or for prompt 9 (the OCI-label and `run_url`
    behaviour matched what prompt 9 already documents).

### VS Code and Devin (not rehearsed unattended)

- **VS Code - PRESENTER: not rehearsed unattended.** Run Prompt 1 (IDE IaC scanning), Prompt
  3 (generated code fixes), Prompt 5 (automated recommendations), and Prompt 6 (policy
  enforcement) from `docs/agent-prompts.md` in Copilot Chat agent mode with the `qscanner`
  MCP server connected. Expect the same findings and fix content shown in the headless MCP
  rehearsal above (grouped by file with line numbers for Prompt 1; the `DS-0002` exact-fix
  and `KSV-0006` guided-fix pattern for Prompt 3; severity-ordered suggestions spanning IaC
  and dependency fixes for Prompt 5; a reported gate failure citing `terraform/main.tf` and
  the Helm deployment for Prompt 6).
- **Devin - PRESENTER: not rehearsed unattended.** Run Prompt 4 (automated remediation pull
  request: `remediate_and_open_pr` with `repository_path` set to this repo and `base_branch
  main`) in a Devin session per `devin/README.md`, then wait for the `PR security scan`
  workflow to complete on the new PR. Expect a new PR shaped like the existing
  `qscanner/auto-remediation` PR #2 (a findings table plus dependency pins bumped), and the
  `QScanner findings` check on it to go green or show only sub-`fail_on` findings. Prompt 7
  (stakeholder views, all five audiences) can run in either VS Code or Devin; expect the same
  shape of output as the `ciso`/`devops` results captured in the headless rehearsal above,
  plus `cloud_security`, `secops`, and `infra_ops` briefings.

### Before the demo (do the day before)

- [ ] Refresh `QUALYS_ACCESS_TOKEN` (it is a JWT and expires): get a fresh CS token, update
      `~/.config/cnapp-demo/iac.env`, and push it to CI: `gh secret set QUALYS_ACCESS_TOKEN
      --repo nelssec/cnapp-demo`.
- [ ] Confirm PR #1 and PR #2 are still open: `gh pr view 1 --repo nelssec/cnapp-demo` and
      `gh pr view 2 --repo nelssec/cnapp-demo`.
- [ ] Run `./demo.sh` once end to end (not `--fast`) so the binary, credentials, and network
      path are all warm, and so `demo-output/image` exists as a fallback for 4.2.5/4.2.7 (a
      `--fast` run skips section 4 and never creates it).
- [ ] Open TotalCloud > Posture > IaC Posture, filtered to `nelssec/cnapp-demo`, in a browser
      tab (this is where the Qualys IaC backend's `CID-<n>` results for
      Terraform/CloudFormation show up when the backend is healthy).
- [ ] Confirm VS Code is open on this repo with the `qscanner` MCP server from
      `.vscode/mcp.json` connected (first launch prompts for the token and IaC credentials).

- Re-check after the rehearsal (2026-09-02, main @ fb5aaff): a full `qscanner --scan-types iac code .` against CA1 finished normally — Qualys IaC scan 849e3a55-dd61-48d0-a8c3-c4eecf6ce5c8 FINISHED, PASS 169 / FAIL 43 (backend: terraform, cloudformation, azurearm; local: helm, kubernetes, dockerfile). The ERROR seen during the rehearsal was transient; demo.sh falls back to the local engine automatically when it recurs.
