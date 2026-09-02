# Devin setup

This repo ships a custom QScanner build with an MCP server (`qscanner mcp --pod CA1`) that
exposes SCA, secret, IaC, and container scanning, plus fix-generation and stakeholder-report
prompts, to a Devin session on this repository.

1. **Machine setup (once per repo).** In Devin, open the repository's machine settings and add
   these setup commands so the binary and `gh` are ready when a session starts (Devin clones
   the repo to `/home/ubuntu/repos/cnapp-demo`; if yours differs, change the path in
   `devin/mcp-config.json` too):

       cd /home/ubuntu/repos/cnapp-demo
       gh auth status || gh auth login --with-token <<< "$GH_TOKEN"
       ./scripts/get-qscanner.sh .qscanner

   `GH_TOKEN` is a GitHub token with read access to `nelssec/cnapp-demo` releases, stored as a
   Devin secret (the release is on a private repo). `devin/run-qscanner-mcp.sh` also downloads
   the binary on first use if the setup step was skipped.

2. **Add the custom MCP server.** In Devin, open Settings, MCP Marketplace, Add custom MCP
   server, and paste the contents of `devin/mcp-config.json`. The server command is the
   wrapper script `devin/run-qscanner-mcp.sh`, which reads the Qualys credentials from the
   VM environment, so no secret values appear in the config.

3. **Set secrets.** In Devin, open Settings, Secrets, and add:
   - `QUALYS_ACCESS_TOKEN` — the CS access token for pod CA1.
   - `QUALYS_IAC_USERNAME` and `QUALYS_IAC_PASSWORD` — credentials for backend evaluation of
     Terraform, CloudFormation, and ARM (Helm/Kubernetes/Dockerfile are evaluated locally).
   - `GH_TOKEN` — for the release download above.

   Devin exports secrets into the VM environment; the wrapper script passes them straight to
   `qscanner mcp`. Never write the real values into any file in this repo.

4. **Confirm the server.** Ask Devin "list the qscanner MCP tools and prompts" and confirm it
   can see the server before running anything else.

5. **Run the prompts.** Use the prompts in `docs/agent-prompts.md` in a Devin session on this
   repository, for example the automated remediation pull request prompt (prompt 4). Devin
   needs `gh` authenticated (it is in the default image) to open pull requests against
   `nelssec/cnapp-demo`.
