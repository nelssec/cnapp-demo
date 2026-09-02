// Reads a QScanner SARIF report and (1) creates a check run with inline annotations,
// (2) upserts a PR comment with a summary table.
//
// Robust to a SARIF with no runs or no results at all (e.g. when the SCA vulnerability
// report could not be fetched from the backend but IaC/secret findings were still
// written) - in that case counts stay at 0 and no annotations/crash occur.
module.exports = async ({ github, context, core, sarifPath, gateExitCode }) => {
  const fs = require('fs');
  const sarif = JSON.parse(fs.readFileSync(sarifPath, 'utf8'));
  const run = (sarif.runs || [])[0] || {};
  const driver = (run.tool && run.tool.driver) || {};
  const rules = new Map((driver.rules || []).map((r) => [r.id, r]));

  const levelMap = { error: 'failure', warning: 'warning', note: 'notice', none: 'notice' };
  const annotations = [];
  const counts = { vulnerability: 0, secret: 0, iac: 0, compliance: 0 };

  for (const result of run.results || []) {
    const rule = rules.get(result.ruleId) || {};
    const name = rule.name || '';
    const kind = name === 'IaCMisconfiguration' ? 'iac' : name === 'Secret' ? 'secret' : name === 'Compliance' ? 'compliance' : 'vulnerability';
    counts[kind]++;

    const loc = (result.locations || [])[0];
    const phys = loc && loc.physicalLocation;
    if (!phys || !phys.artifactLocation || !phys.artifactLocation.uri) continue;
    let path = phys.artifactLocation.uri.replace(/^\.\//, '');
    if (path.startsWith('/')) continue; // absolute paths cannot be annotated
    const region = phys.region || {};
    const start = Math.max(1, region.startLine || 1);
    const end = Math.max(start, region.endLine || start);
    const title = `${result.ruleId}: ${(rule.shortDescription && rule.shortDescription.text) || name}`;
    const help = (rule.help && rule.help.text) || '';
    annotations.push({
      path,
      start_line: start,
      end_line: end,
      annotation_level: levelMap[result.level] || 'warning',
      title: title.slice(0, 255),
      message: `${(result.message && result.message.text) || ''}\n\n${help}`.trim().slice(0, 64000),
    });
  }

  // 72 = qscanner IaC gate. Any other non-zero exit is treated as a scan error upstream
  // (see the "Scan repository" step) and never reaches this script with gateExitCode set,
  // so the only gating exit code handled here is 72.
  const gateFailed = gateExitCode === 72;
  const conclusion = gateFailed ? 'failure' : annotations.length ? 'neutral' : 'success';
  const summary = [
    `| Type | Count |`, `| --- | --- |`,
    `| Dependency vulnerabilities | ${counts.vulnerability} |`,
    `| Secrets | ${counts.secret} |`,
    `| IaC misconfigurations | ${counts.iac} |`,
    `| Compliance | ${counts.compliance} |`,
    ``,
    gateFailed ? `**Gate: FAILED** (qscanner exit ${gateExitCode})` : `**Gate: passed**`,
  ].join('\n');

  // Checks API accepts 50 annotations per request
  const headSha = context.payload.pull_request ? context.payload.pull_request.head.sha : context.sha;
  const check = await github.rest.checks.create({
    owner: context.repo.owner, repo: context.repo.repo,
    name: 'QScanner findings', head_sha: headSha, status: 'completed', conclusion,
    output: { title: `QScanner: ${annotations.length} finding(s)`, summary, annotations: annotations.slice(0, 50) },
  });
  for (let i = 50; i < annotations.length; i += 50) {
    await github.rest.checks.update({
      owner: context.repo.owner, repo: context.repo.repo, check_run_id: check.data.id,
      output: { title: `QScanner: ${annotations.length} finding(s)`, summary, annotations: annotations.slice(i, i + 50) },
    });
  }

  if (context.payload.pull_request) {
    const marker = '<!-- qscanner-summary -->';
    const body = `${marker}\n## QScanner scan summary\n\n${summary}\n\nFull SARIF and JSON reports are attached to the workflow run as artifacts.`;
    const { data: comments } = await github.rest.issues.listComments({
      owner: context.repo.owner, repo: context.repo.repo, issue_number: context.payload.pull_request.number,
    });
    const existing = comments.find((c) => c.body && c.body.startsWith(marker));
    if (existing) {
      await github.rest.issues.updateComment({ owner: context.repo.owner, repo: context.repo.repo, comment_id: existing.id, body });
    } else {
      await github.rest.issues.createComment({ owner: context.repo.owner, repo: context.repo.repo, issue_number: context.payload.pull_request.number, body });
    }
  }

  core.setOutput('finding_count', String(annotations.length));
  core.setOutput('gate_failed', String(gateFailed));
};
