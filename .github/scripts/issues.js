// Turns a QScanner JSON report into GitHub Issues, one per CODEOWNERS owner, so the
// Issues tab shows who owns which findings. Idempotent: each owner's issue carries a
// marker and is updated in place on later runs (and closed when the owner has no
// findings left). Findings below the severity floor are ignored.
const fs = require('fs');
const path = require('path');

const ORDER = { critical: 5, high: 4, medium: 3, low: 2, info: 1, unknown: 0 };

function sevLabel(v) {
  if (typeof v === 'number') return v >= 5 ? 'critical' : v === 4 ? 'high' : v === 3 ? 'medium' : v === 2 ? 'low' : 'info';
  const s = String(v || '').toLowerCase();
  return ORDER[s] !== undefined ? s : 'unknown';
}

// Minimal CODEOWNERS matcher: comments/blank lines ignored, last matching rule wins,
// `dir/` matches everything under dir, a bare name matches at any depth, `*` is a
// catch-all, leading `/` anchors to the root, `**` spans directories.
function loadCodeowners(root) {
  for (const rel of ['.github/CODEOWNERS', 'CODEOWNERS', 'docs/CODEOWNERS']) {
    const p = path.join(root, rel);
    if (fs.existsSync(p)) {
      return fs.readFileSync(p, 'utf8').split('\n')
        .map((l) => l.replace(/#.*$/, '').trim()).filter(Boolean)
        .map((l) => { const [pattern, ...owners] = l.split(/\s+/); return { pattern, owners }; });
    }
  }
  return [];
}

function globToRegex(pattern) {
  let p = pattern;
  let anchored = false;
  if (p.startsWith('/')) { anchored = true; p = p.slice(1); }
  const dirOnly = p.endsWith('/');
  if (dirOnly) p = p.slice(0, -1);
  if (p === '*' || p === '**') return /.*/;
  const anyDepth = !anchored && !p.includes('/');
  const DOUBLE = '__DOUBLESTAR__';
  let re = p.replace(/[.+^${}()|[\]\\]/g, '\\$&').replace(/\*\*/g, DOUBLE).replace(/\*/g, '[^/]*').replace(new RegExp(DOUBLE, 'g'), '.*').replace(/\?/g, '[^/]');
  re = (anyDepth ? '(^|.*/)' : '^') + re + '(/.*)?$';
  return new RegExp(re);
}

function ownersFor(rules, file) {
  let owners = [];
  for (const r of rules) if (globToRegex(r.pattern).test(file)) owners = r.owners;
  return owners.length ? owners : ['unassigned'];
}

function collect(report) {
  const out = [];
  const inv = report.Inventory || {};
  for (const m of inv.Misconfigurations || []) {
    out.push({ id: m.CheckID, kind: 'iac', file: m.FilePath, line: m.StartLine || 0, severity: sevLabel(m.Severity), title: m.Title, fix: m.Resolution, compliance: (m.Compliance || []).slice(0, 3).map((c) => `${c.Framework} ${c.Control}`) });
  }
  for (const s of inv.SecretResults || inv.Secrets || []) {
    const file = s.Target || s.target || '';
    for (const d of s.Details || s.details || []) {
      out.push({ id: d.RuleID || d.ruleId || 'secret', kind: 'secret', file, line: d.StartLine || d.startLine || 0, severity: sevLabel(d.Severity || d.severity || 'high'), title: d.Title || d.title || 'Secret detected', fix: 'Remove the secret from the repository and rotate it.' });
    }
  }
  const vr = report.VulnerabilityReport || {};
  for (const v of vr.Vulnerabilities || vr.vulnerabilities || []) {
    const sw = (v.software || v.Softwares || [])[0] || {};
    const file = sw.packagePath || sw.Path || 'app/package-lock.json';
    const fixed = sw.fixVersion || sw.FixedVersion;
    out.push({ id: `QID-${v.qid || v.QID}`, kind: 'dependency', file, line: 0, severity: sevLabel(v.severity ?? v.Severity), title: `${sw.name || sw.Name || 'package'} ${sw.version || sw.InstalledVersion || ''}: ${v.title || v.Title || ''}`.trim(), fix: fixed ? `Upgrade to ${fixed}` : 'No fixed version published yet' });
  }
  return out;
}

function cell(s) {
  return String(s || '').replace(/\|/g, '\\|').replace(/\r?\n/g, ' ');
}

module.exports = async ({ github, context, core, reportPath, repoRoot, severityFloor = 'high', maxPerIssue = 40 }) => {
  const report = JSON.parse(fs.readFileSync(reportPath, 'utf8'));
  const rules = loadCodeowners(repoRoot);
  const floor = ORDER[severityFloor] || ORDER.high;
  const findings = collect(report).filter((f) => ORDER[f.severity] >= floor);
  const byOwner = new Map();
  for (const f of findings) for (const o of ownersFor(rules, f.file)) { if (!byOwner.has(o)) byOwner.set(o, []); byOwner.get(o).push(f); }

  const { owner, repo } = context.repo;
  const existing = await github.paginate(github.rest.issues.listForRepo, { owner, repo, state: 'all', labels: 'qscanner', per_page: 100 });
  const markerOf = (o) => `<!-- qscanner-owner:${o} -->`;
  const runUrl = `${context.serverUrl}/${owner}/${repo}/actions/runs/${context.runId}`;
  const branch = String(context.ref || '').replace('refs/heads/', '');
  const created = [];
  const updated = [];
  const closed = [];

  for (const [o, list] of [...byOwner.entries()].sort()) {
    list.sort((a, b) => ORDER[b.severity] - ORDER[a.severity] || a.id.localeCompare(b.id));
    const rows = list.slice(0, maxPerIssue).map((f) => {
      const where = f.line ? `${f.file}:${f.line}` : f.file;
      const comp = f.compliance && f.compliance.length ? ` (${f.compliance.join('; ')})` : '';
      return `| ${f.severity} | ${f.kind} | \`${cell(f.id)}\` | \`${cell(where)}\` | ${cell(f.title)} | ${cell(f.fix)}${cell(comp)} |`;
    });
    const more = list.length > maxPerIssue ? `\n... and ${list.length - maxPerIssue} more.` : '';
    const body = [
      markerOf(o),
      `## QScanner findings owned by ${o}`,
      '',
      `${list.length} finding(s) at or above **${severityFloor}** from the latest scan of \`${branch}\` ([run](${runUrl})).`,
      '',
      '| Severity | Kind | Finding | Location | Title | Fix (compliance) |',
      '| --- | --- | --- | --- | --- | --- |',
      ...rows,
      more,
      '',
      'Ownership comes from `CODEOWNERS`; fixes come from QScanner (`generate_fix` / `qscanner patch`). This issue is updated automatically on every scan of the default branch.',
    ].join('\n');
    const title = `QScanner: ${list.length} ${severityFloor}+ finding(s) for ${o}`;
    const labels = ['qscanner', 'security', ...new Set(list.map((f) => `severity:${f.severity}`))];
    const match = existing.find((i) => i.body && i.body.includes(markerOf(o)));
    if (match) {
      await github.rest.issues.update({ owner, repo, issue_number: match.number, title, body, labels, state: 'open' });
      updated.push(match.number);
    } else {
      const res = await github.rest.issues.create({ owner, repo, title, body, labels });
      created.push(res.data.number);
    }
  }
  for (const i of existing) {
    if (i.state !== 'open' || !i.body) continue;
    const m = i.body.match(/<!-- qscanner-owner:(.+?) -->/);
    if (m && !byOwner.has(m[1])) {
      await github.rest.issues.createComment({ owner, repo, issue_number: i.number, body: `All findings for ${m[1]} at or above ${severityFloor} are resolved as of [this run](${runUrl}). Closing.` });
      await github.rest.issues.update({ owner, repo, issue_number: i.number, state: 'closed' });
      closed.push(i.number);
    }
  }
  await core.summary
    .addHeading('QScanner triage issues')
    .addTable([[{ data: 'Owner', header: true }, { data: 'Findings', header: true }], ...[...byOwner.entries()].map(([o, l]) => [o, String(l.length)])])
    .write();
  core.setOutput('created', created.join(','));
  core.setOutput('updated', updated.join(','));
  core.setOutput('closed', closed.join(','));
  core.info(`issues created=${created} updated=${updated} closed=${closed}`);
};
