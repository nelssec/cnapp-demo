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
