# Devin setup

This repo ships a custom QScanner build with an MCP server (`qscanner mcp --pod CA1`) that
exposes SCA, secret, IaC, and container scanning, plus fix-generation and stakeholder-report
prompts, to a Devin session on this repository.

## Devin desktop app (runs on your machine)

The Devin desktop app runs its MCP servers locally and reads them from
`~/.config/devin/mcp_config.json`. Point it at a wrapper script that sources the Qualys credentials
and runs the binary from this checkout, so no secret values sit in the config:

    {
      "mcpServers": {
        "qscanner": {
          "command": "/Users/<you>/.config/cnapp-demo/qscanner-mcp.sh",
          "args": [],
          "env": { "QUALYS_POD": "CA1" }
        }
      }
    }

The wrapper (`~/.config/cnapp-demo/qscanner-mcp.sh`) is three lines: source
`~/.config/cnapp-demo/iac.env` (exports `QUALYS_ACCESS_TOKEN`, `QUALYS_IAC_USERNAME`,
`QUALYS_IAC_PASSWORD`, `QUALYS_IAC_AUTH_TYPE`), export
`QSCANNER_SECRET_CONFIG_FILE=<checkout>/config/qscanner-secret-rules.json`, then
`exec <checkout>/.qscanner/qscanner mcp --pod CA1`. Put the binary at `.qscanner/qscanner`
(gitignored) with `scripts/get-qscanner.sh .qscanner` or a local build. After saving the
config, restart the app (or reload its MCP servers) and confirm 15 tools and 9 prompts are
listed. The prompts in `docs/agent-prompts.md` then run from the chat with the repository open.

## Devin cloud sessions (app.devin.ai)

1. **Machine setup (once per repo).** In app.devin.ai open **Settings > Environment > Blueprints**, pick this repository, and add
   these setup commands to the `initialize` step (or start a session and ask Devin to "set up
   your environment for this repo", then approve the cards) so the binary and `gh` are ready when a session starts (Devin clones
   the repo to `/home/ubuntu/repos/cnapp-demo`; if yours differs, change the path in
   `devin/mcp-config.json` too):

       cd /home/ubuntu/repos/cnapp-demo
       gh auth status || gh auth login --with-token <<< "$GH_TOKEN"
       ./scripts/get-qscanner.sh .qscanner

   `GH_TOKEN` is a GitHub token with read access to `nelssec/cnapp-demo` releases, stored as a
   Devin secret (the repository is public, but `gh` itself still needs a login to download releases). `devin/run-qscanner-mcp.sh` also downloads
   the binary on first use if the setup step was skipped.

2. **Add the custom MCP server.** In app.devin.ai open **Customize > MCPs**, **Add MCP**, **Add custom MCP**, and paste the contents of `devin/mcp-config.json`. The server command is the
   wrapper script `devin/run-qscanner-mcp.sh`, which reads the Qualys credentials from the
   VM environment, so no secret values appear in the config.

3. **Set secrets.** In app.devin.ai open the Secrets page (https://app.devin.ai/secrets, or the **Secrets**
   tab in the repository blueprint for repo-scoped values) and add:
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
