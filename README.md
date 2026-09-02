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
