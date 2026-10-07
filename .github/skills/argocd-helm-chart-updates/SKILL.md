---
name: argocd-helm-chart-updates
description: Checks whether Helm charts used by Argo CD Application manifests have newer versions available, and optionally bumps targetRevision. Use when asked to check, audit, or upgrade Helm chart versions in environments/.
---

# Check Argo CD Helm chart updates

## Workflow

1. Run the checker from the repository root (requires `helm` and `python3`):

   ```bash
   python3 .github/skills/argocd-helm-chart-updates/scripts/check_updates.py
   ```

   It scans `environments/**/*.yaml` for `kind: Application` manifests, reads each Helm source (`chart`, `repoURL`, `targetRevision`), queries the repo for the latest stable version, and prints a table with `OK`, `UPDATE`, or `ERROR` per chart. Pass another directory as an argument to scan elsewhere.

2. Report the table. For each `UPDATE`, flag major version jumps (first version component changes) as potentially breaking.

3. Only if the user asks to upgrade, re-run with `--apply` to rewrite `targetRevision` in the manifests, then show `git diff`.

4. Before recommending a major bump, read the chart's release notes or changelog and check the Application's inline `helm.values` for keys that may have been renamed or removed.

## Notes

- Prerelease versions are ignored; only the latest stable chart is compared.
- Non-Helm sources (Git repos with no `chart:` field) are skipped.
- `ERROR` usually means the repo is unreachable or the chart name is wrong; verify with `helm show chart --repo <repoURL> <chart>`.
