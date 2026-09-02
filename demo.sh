#!/usr/bin/env bash
# Terminal walkthrough for the CNAPP demo. Six sections: IaC, secrets, SCA, container image,
# policy gate, and a hand-off pointer to the MCP prompts (docs/agent-prompts.md) and the live
# GitHub artifacts (RUNBOOK.md has the full table).
#
# Usage:
#   source ~/.config/cnapp-demo/iac.env   # QUALYS_ACCESS_TOKEN, QUALYS_IAC_USERNAME/PASSWORD
#   ./demo.sh [--fast]
#
# --fast skips section 4 (Docker build + image scan) and shortens the pauses between sections.
#
# The binary comes from scripts/get-qscanner.sh, downloaded into .qscanner/ (git-ignored):
#   scripts/get-qscanner.sh .qscanner
#
# Section 4 builds and scans a LOCAL image (cnapp-demo:local) only. This script never pulls
# from or pushes to ghcr.io/nelssec/cnapp-demo - the real "Build, scan image, gate, push"
# workflow (.github/workflows/build-and-gate.yml) blocks that push by design whenever the
# gate fails, which is the point of the demo (see run
# https://github.com/nelssec/cnapp-demo/actions/runs/33613303229). Building locally here
# means the script does not depend on GHCR auth or on that workflow having run recently.
#
# QUALYS_IAC_USERNAME/PASSWORD are optional: with them set, Terraform and CloudFormation are
# evaluated by the Qualys IaC backend (check IDs CID-<n>, visible on TotalCloud > Posture >
# IaC Posture for nelssec/cnapp-demo) alongside Helm/Kubernetes/Dockerfile, which are always
# evaluated locally (KSV-/DS-/AWS-<n> check IDs, no AVD- prefix in this qscanner build).
# Without them, section 1 falls back to --iac-engine local so Terraform/CloudFormation are
# still covered, just as AWS-<n> checks instead of CID-<n>.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
QSCANNER="${QSCANNER:-$HERE/.qscanner/qscanner}"
POD="${QUALYS_POD:-CA1}"
OUT="${OUT:-$HERE/demo-output}"
IMAGE="${IMAGE:-cnapp-demo:local}"
EXCLUDE='.superpowers/**'
FAST=0
PAUSE="${PAUSE:-8}"
[[ "${1:-}" == "--fast" ]] && { FAST=1; PAUSE=1; }

CYAN='\033[1;36m'; GREEN='\033[1;32m'; YELLOW='\033[1;33m'; RED='\033[1;31m'; DIM='\033[2m'; RESET='\033[0m'

header() { echo; echo -e "${CYAN}== $1 ==${RESET}"; echo -e "${DIM}$2${RESET}"; echo; }
show()   { echo -e "${DIM}\$ $1${RESET}"; echo; }
note()   { echo -e "${YELLOW}$1${RESET}"; }
pause()  { for ((i=PAUSE;i>0;i--)); do printf "\r${DIM}  next in %2d${RESET}" "$i"; sleep 1; done; printf "\r                \r"; }

[[ -x "$QSCANNER" ]] || { echo "qscanner not found at $QSCANNER. Run: scripts/get-qscanner.sh .qscanner"; exit 1; }
[[ -n "${QUALYS_ACCESS_TOKEN:-}" ]] || { echo "QUALYS_ACCESS_TOKEN is not set. source ~/.config/cnapp-demo/iac.env (or export it) first."; exit 1; }
if [[ -z "${QUALYS_IAC_USERNAME:-}" || -z "${QUALYS_IAC_PASSWORD:-}" ]]; then
  note "QUALYS_IAC_USERNAME/PASSWORD not set: section 1 will use --iac-engine local for Terraform/CloudFormation instead of the Qualys IaC backend."
fi

rm -rf "$OUT"; mkdir -p "$OUT"

clear
echo -e "${GREEN}Qualys QScanner${RESET} $("$QSCANNER" --version 2>&1 | tail -1)  pod=$POD"
echo -e "${DIM}One binary: dependencies, secrets, IaC, container compliance. Terminal, CI, IDE, agent.${RESET}"
pause

# ---------------------------------------------------------------------------
header "1. IaC misconfigurations (Terraform, CloudFormation, Helm, Kubernetes, Dockerfile)" \
       "Same repo a developer has open, before anything is deployed. Hybrid: Terraform and CloudFormation go to the Qualys IaC backend (CID-<n>) when creds are set; Helm, Kubernetes, and Dockerfile are always evaluated locally (KSV-/DS-/AWS-<n>)."
IAC_JSON="$OUT/iac"
mkdir -p "$IAC_JSON"
if [[ -n "${QUALYS_IAC_USERNAME:-}" && -n "${QUALYS_IAC_PASSWORD:-}" ]]; then
  show "qscanner --pod $POD --scan-types iac --exclude-dirs '$EXCLUDE' --report-format table,json code ."
  "$QSCANNER" --pod "$POD" --scan-types iac --exclude-dirs "$EXCLUDE" --report-format table,json -o "$IAC_JSON" code "$HERE"
  rc=$?
  echo -e "${YELLOW}exit code: $rc${RESET}"
  if ls "$IAC_JSON"/*Report.json >/dev/null 2>&1 && grep -Eq '"CheckID"[[:space:]]*:[[:space:]]*"CID-' "$IAC_JSON"/*Report.json 2>/dev/null; then
    echo -e "${GREEN}Backend engine returned CID-<n> checks for Terraform/CloudFormation - see TotalCloud > Posture > IaC Posture for nelssec/cnapp-demo.${RESET}"
  else
    note "No CID-<n> checks came back from the Qualys IaC backend this run (it has been intermittently returning HTTP 500 tonight; qscanner retries automatically). Falling back to --iac-engine local so Terraform/CloudFormation are still covered."
    show "qscanner --pod $POD --scan-types iac --iac-engine local --exclude-dirs '$EXCLUDE' --report-format table,json code ."
    "$QSCANNER" --pod "$POD" --scan-types iac --iac-engine local --exclude-dirs "$EXCLUDE" --report-format table,json -o "$IAC_JSON" code "$HERE"
    rc=$?
    echo -e "${YELLOW}exit code: $rc${RESET}"
  fi
else
  show "qscanner --pod $POD --scan-types iac --iac-engine local --exclude-dirs '$EXCLUDE' --report-format table,json code ."
  "$QSCANNER" --pod "$POD" --scan-types iac --iac-engine local --exclude-dirs "$EXCLUDE" --report-format table,json -o "$IAC_JSON" code "$HERE"
  rc=$?
  echo -e "${YELLOW}exit code: $rc${RESET}"
fi
echo -e "${DIM}The COMPLIANCE column maps each check to KSPM CIDs / CIS benchmarks / Pod Security Standards, e.g. the privileged container is KSV-0017 -> KSPM CID-45032; KSPM CID-45108; CIS K8s 5.2.2 +3.${RESET}"
pause

# ---------------------------------------------------------------------------
header "2. Secrets in the Helm chart" \
       "The AWS key pair in helm/cnapp-demo/values.yaml would ship inside every release of this chart. (The AWS EXAMPLE key pair from AWS docs is allow-listed by the engine and will not show - this is a synthetic canary key.)"
show "qscanner --pod $POD --scan-types secret --exclude-dirs '$EXCLUDE' --report-format table code ."
"$QSCANNER" --pod "$POD" --scan-types secret --exclude-dirs "$EXCLUDE" --report-format table -o "$OUT/secret" code "$HERE"
rc=$?
echo -e "${YELLOW}exit code: $rc${RESET}"
pause

# ---------------------------------------------------------------------------
header "3. Software composition analysis (dependency vulnerabilities)" \
       "app/package.json and service/requirements.txt, scored by QDS. This repo has a git remote, so the Qualys backend can produce the code-asset vulnerability report (expect ~78 findings); a repo without one would eventually time out with exit 40."
show "qscanner --pod $POD --scan-types sca --exclude-dirs '$EXCLUDE' --report-format table code ."
"$QSCANNER" --pod "$POD" --scan-types sca --exclude-dirs "$EXCLUDE" --report-format table -o "$OUT/sca" code "$HERE"
rc=$?
echo -e "${YELLOW}exit code: $rc${RESET}"
if [[ $rc -eq 40 ]]; then
  note "Exit 40: the Qualys backend did not return the SCA vulnerability report in time. This is a known, handled outcome (see .github/workflows/pr-scan.yml) - re-run, or check demo-output/sca for what was collected."
fi
pause

# ---------------------------------------------------------------------------
if [[ "$FAST" -eq 1 ]]; then
  header "4. Container image: vulnerabilities, secrets, CIS Docker benchmark [skipped, --fast]" \
         "Would build cnapp-demo:local from the Dockerfile and scan it before push. Skipped here to keep the run short."
else
  header "4. Container image: vulnerabilities, secrets, CIS Docker benchmark" \
         "Build the image from this Dockerfile and scan it before it is ever pushed. This is a LOCAL build (cnapp-demo:local) - the script does not pull ghcr.io/nelssec/cnapp-demo:latest, and the real CI push is blocked whenever the gate fails (build-and-gate.yml)."
  show "docker build -t $IMAGE ."
  if docker build -q -t "$IMAGE" "$HERE" >/dev/null; then
    show "qscanner --pod $POD --scan-types pkg,secret,compliance --compliance-benchmarks DOCKER_CIS --report-format table image $IMAGE"
    "$QSCANNER" --pod "$POD" --scan-types pkg,secret,compliance --compliance-benchmarks DOCKER_CIS --report-format table -o "$OUT/image" image "$IMAGE"
    rc=$?
    echo -e "${YELLOW}exit code: $rc${RESET}"
    echo -e "${DIM}Expect ~369 package vulnerabilities and Docker CIS PASS 1 / FAIL 4 (HEALTHCHECK 4.6, ADD 4.9, update-instruction 4.7, and one more) for this image.${RESET}"
  else
    note "Docker build failed or the daemon is not reachable. Re-run with --fast, or see the recorded build-and-gate run: https://github.com/nelssec/cnapp-demo/actions/runs/33613303229"
  fi
fi
pause

# ---------------------------------------------------------------------------
header "5. Policy enforcement: the same scan as a CI gate" \
       "--iac-fail-on high turns findings into a non-zero exit code. Exit 72 is the IaC gate failing - that is the expected result here, not a script error, and it's the same gate pull request #1 fails today."
show "qscanner --pod $POD --scan-types iac --iac-fail-on high --exclude-dirs '$EXCLUDE' --report-format table,sarif,json code ."
"$QSCANNER" --pod "$POD" --scan-types iac --iac-fail-on high --exclude-dirs "$EXCLUDE" --report-format table,sarif,json -o "$OUT/gate" code "$HERE"
rc=$?
case "$rc" in
  0)  echo -e "${GREEN}exit code: 0 - gate passed (no high/critical IaC findings).${RESET}" ;;
  72) echo -e "${RED}exit code: 72 - IaC gate failed (high/critical misconfigurations found). This is the expected, narrated outcome: it is exactly what blocks pull request #1 (demo/open-ingress) and what the 'Enforce gate' step in pr-scan.yml turns into a red check.${RESET}" ;;
  71) echo -e "${RED}exit code: 71 - the IaC scan itself failed (not the gate). Check the log above; the Qualys IaC backend may be unavailable - retry, or use --iac-engine local.${RESET}" ;;
  *)  echo -e "${YELLOW}exit code: $rc (unexpected)${RESET}" ;;
esac
echo -e "${DIM}SARIF written to $OUT/gate (this is what annotates the pull request in GitHub).${RESET}"
pause

# ---------------------------------------------------------------------------
header "6. Fixes, remediation PRs, and stakeholder views" \
       "Hand-off: switch to VS Code (Copilot agent, .vscode/mcp.json) or Devin (devin/). Prompts are numbered in docs/agent-prompts.md."
echo "  Prompt 1  IDE IaC scanning                    [4.1.1, 4.2.1-4.2.4]"
echo "  Prompt 2  Secrets and compliance view          [4.2.4, 4.2.6]"
echo "  Prompt 3  Generated code fixes                 [4.3.1, 4.3.4]"
echo "  Prompt 4  Automated remediation pull request   [4.3.2]"
echo "  Prompt 5  Automated recommendations            [4.3.4]"
echo "  Prompt 6  Policy enforcement in the IDE         [4.3.3]"
echo "  Prompt 7  Stakeholder views (5 audiences)       [4.4.1-4.4.5]"
echo
echo "  Live artifacts:"
echo "    gh pr view 1 --repo nelssec/cnapp-demo --web    # demo/open-ingress: gate-failing, annotated"
echo "    gh pr view 2 --repo nelssec/cnapp-demo --web    # qscanner/auto-remediation: six pins bumped"
echo "    gh run view 33613303229 --repo nelssec/cnapp-demo --web   # build-and-gate: gate failed, push skipped"
echo "    gh run view 33614398210 --repo nelssec/cnapp-demo --web   # auto-remediate: opened PR #2"
echo
echo -e "${GREEN}Done.${RESET} Reports: $OUT"
