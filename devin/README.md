# Devin setup

This repo ships a custom QScanner build with an MCP server (`qscanner mcp --pod CA1`) that
exposes SCA, secret, IaC, and container scanning, plus fix-generation and stakeholder-report
prompts, to a Devin session on this repository.

1. **Fetch the binary.** In the Devin machine setup for this repo, add to the startup
   commands so the binary exists where `devin/mcp-config.json` expects it:

       export GH_TOKEN=<github token with repo scope>
       ./scripts/get-qscanner.sh .qscanner

   This downloads the release into `.qscanner/` (already git-ignored). If the workspace root
   in your Devin session is not `/home/ubuntu/cnapp-demo`, update the `command` path in
   `devin/mcp-config.json` to match.

2. **Add the custom MCP server.** In Devin, open Settings, Integrations, MCP Marketplace, and
   add a custom server using the contents of `devin/mcp-config.json`.

3. **Set secrets.** In Devin, open Settings, Secrets, and add:
   - `QUALYS_ACCESS_TOKEN` — the CS access token for pod CA1.
   - `QUALYS_IAC_USERNAME` and `QUALYS_IAC_PASSWORD` — credentials for backend evaluation of
     Terraform and CloudFormation (used only when a scan needs the backend engine).

   These resolve into the server's environment via the `${QUALYS_ACCESS_TOKEN}`,
   `${QUALYS_IAC_USERNAME}`, and `${QUALYS_IAC_PASSWORD}` placeholders in
   `devin/mcp-config.json`. Never write the real values into any file in this repo.

4. **Confirm the server.** Ask Devin "list the qscanner MCP tools and prompts" and confirm it
   can see the server before running anything else.

5. **Run the prompts.** Use the prompts in `docs/agent-prompts.md` in a Devin session on this
   repository, for example the automated remediation pull request prompt (prompt 4). Devin
   needs `gh` authenticated (it is in the default image) to open pull requests against
   `nelssec/cnapp-demo`.
