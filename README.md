# cnapp-demo

An intentionally insecure service used to demonstrate shift-left scanning with Qualys QScanner:
dependency vulnerabilities, hard-coded secrets, Infrastructure-as-Code misconfigurations, and
CIS Docker compliance, in the terminal, in GitHub pull requests, in VS Code, and in Devin.

**Do not deploy this anywhere real.** Every layer has planted weaknesses:

| Layer | File | Planted issue |
| --- | --- | --- |
| App | `app/package.json` | Old express, lodash, axios, jsonwebtoken, minimist |
| Container | `Dockerfile` | Runs as root, no HEALTHCHECK, uses ADD |
| Kubernetes | `helm/cnapp-demo/` | Privileged, runs as UID 0, docker.sock hostPath, no resource limits, AWS key in values.yaml |
| Cloud (Terraform) | `terraform/main.tf` | Public S3 ACL, SSH open to 0.0.0.0/0, IAM policy with `*` |
| Cloud (CloudFormation) | `cloudformation/rds.yaml` | Unencrypted, public RDS with a password in the template |
| Cloud (Azure ARM) | `azure/storage.json` | Storage account allowing HTTP, public blob access, TLS 1.0, open network ACL |
| Java | `java/pom.xml` | Log4Shell (CVE-2021-44228) and Spring4Shell (CVE-2022-22965), both CISA Known Exploited Vulnerabilities; Text4Shell |
| Sensitive data | `service/fixtures/customers.csv`, `service/config/payments.yaml` | Synthetic payment card numbers (Luhn-valid), SSNs, IBANs, a passport number and live-format Stripe keys |
| AI/ML | `models/huggingface/transformers/`, `service/requirements.txt`, `app/package.json` | A bundled DistilBERT-style checkpoint plus `transformers`, `torch` and `@tensorflow/tfjs` dependencies |
| Runtime identity | `helm/cnapp-demo/templates/serviceaccount.yaml` | IRSA-annotated service account bound to the wildcard IAM role, token auto-mounted, behind a public LoadBalancer |
| Service | `service/requirements.txt` | Pinned vulnerable Flask, Werkzeug, Requests, PyYAML, Jinja2, urllib3 |

`service/` is a minimal Flask app kept separate from `app/` because qscanner's automated-remediation
patcher supports `requirements.txt` but not `package.json`, so this manifest is what demonstrates the
automated-remediation flow.

See `RUNBOOK.md` for the demo flow and `docs/agent-prompts.md` for the VS Code and Devin prompts.

## What the scanner covers

| IaC type | Files | Engine | Check IDs |
| --- | --- | --- | --- |
| Terraform / OpenTofu | `*.tf` | Qualys IaC backend when `QUALYS_IAC_*` creds are set (else local) | `CID-<n>` (backend) or `AWS-*`/`AZU-*`/`GCP-*` (local) |
| CloudFormation | `*.yaml`/`*.json` templates | Qualys IaC backend (else local) | `CID-<n>` or `AWS-*` |
| Azure ARM | `*.json` templates | Qualys IaC backend (else local) | `CID-<n>` or `AZU-*` |
| Helm charts | `Chart.yaml` + templates | local | `KSV-*` |
| Kubernetes manifests | `*.yaml` | local | `KSV-*` |
| Dockerfile | `Dockerfile*` | local | `DS-*` |

Every finding carries a compliance column: CIS Docker / Kubernetes / AWS / Azure / GCP, Pod Security Standards, Kubescape, Qualys KSPM CIDs, and Qualys IaC CIDs. Dependencies (`--scan-types sca`) and secrets (`--scan-types secret`) run in the same invocation.

Findings also roll up the other way. `--report-format compliance` (and the `compliance_report`
MCP tool) turn the same scan into a control scorecard - which CIS Docker, CIS Kubernetes, CIS
AWS/Azure/GCP, Pod Security Standards, Kubescape, and Qualys KSPM controls this repository
fails, and which check IDs fail each one.

Two more MCP tools close the loop from a running artifact back to a person:

- `trace_finding` takes one QID, CVE, or IaC check ID and returns the image it ships in, the
  OCI provenance labels `build-and-gate.yml` stamps on that image (source repo, commit
  revision, Actions run, actor), the repository and branch, the commit and its author, the
  manifest line that pins the vulnerable version, the owner, and a one-paragraph narrative.
- `finding_owners` groups every finding by the team that owns the file, resolved from the
  `CODEOWNERS` file at the root of this repo, falling back to the last commit author. The
  `triage_to_owners` prompt turns that into one Jira-ready task list per owner.

Neither runs `git` or `gh`: the commit history comes from the scan report's own repository
metadata and the manifest lines come from reading the files in the checkout.

A third tool, `prioritize_findings`, turns a report into a fix queue ranked the way Qualys
ranks it. Each finding's base score is its QDS (or severity when QDS is absent), boosted by
threat intelligence (CISA KEV, active attacks, public exploit, malware, lateral movement,
privilege escalation, no patch) and multiplied by deployment context: asset criticality and
internet exposure from `.qualys/criticality.yaml`, privileged-workload and exposure signals
from the IaC report. The tool also fetches the asset's TruRisk score, max QDS and
customer-assigned criticality from the Container Security API with the MCP session's token
(read-only; a backend criticality overrides the file), and reports the Qualys risk value on
every finding. The result is P1 to P4 tiers with reasons, owners, and a `trurisk` block that
matches the number shown in TotalCloud.

## Sensitive-data detection rules

`config/qscanner-secret-rules.json` is the Qualys secret rule set for pod CA1 plus four sensitive-data
rules (payment card with Luhn validation, US SSN, IBAN with checksum validation, passport number).
Every scan in this repo passes `--secret-config-file config/qscanner-secret-rules.json` so the planted
PII in `service/` is detected alongside API keys. The file also carries the allow-rules that skip test,
example and placeholder content, which is why the canaries avoid those words.

## Getting the scanner

This repo publishes a custom QScanner build (with IaC scanning and MCP remediation tools) as
GitHub releases tagged `qscanner-<version>` on this repo. Two ways to fetch it:

- **Locally / in a script:** `scripts/get-qscanner.sh [dest_dir]` downloads the right binary for
  your OS/arch from the newest `qscanner-*` release (or `QSCANNER_RELEASE_TAG` if set), verifies
  its checksum, and prints the path to the binary.
- **In a GitHub Actions workflow:** use the composite action `.github/actions/setup-qscanner`,
  which wraps the same script:

  ```yaml
  - uses: ./.github/actions/setup-qscanner
    id: qs
  - run: "${{ steps.qs.outputs.path }}" --version
  ```

  Inputs: `dest` (download directory, default `${{ runner.temp }}/qscanner`) and `release_tag`
  (default: latest `qscanner-*` release). Output: `path` to the downloaded binary.

See `.github/workflows/pr-scan.yml` for a full example of the action driving a scan.

Maintainers publish new builds with `scripts/publish-qscanner.sh <version>`, which uploads a
release built from an internal branch - this stands in for a real release workflow until the
scanner build itself lives in a publishable pipeline.
