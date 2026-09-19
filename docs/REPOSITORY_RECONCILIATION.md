# Repository reconciliation — 2026-09-15

## Outcome

The interrupted local merge is resolved and local main includes GitHub main at
`65e39c5` (fetched during this review). The modern React Data Client, latest Core/Ops
code, accessibility tooling, and mock OAuth/metadata server are present. Repository
validation is recorded below; live Genesys tenant acceptance remains separate.

## Recovery and history

Before changing files, a recovery branch preserved original HEAD `705a1d6`, and an
external archive saved tracked files, nonignored untracked files, the Git index and
merge metadata, staged/unstaged binary patches, and status. The archive intentionally
contains local editor settings and should remain local.

Local recovery directory:
`../Genesys.Core-recovery-20260915T045511Z/`

Recovery branch: `recovery/pre-cleanup-20260915T045511Z`.
To inspect the original checkout, extract `worktree-and-git.tar.gz` into a separate
empty directory; do not extract it over this reconciled checkout.

Original state: one local commit ahead and 191 behind the cached remote, an unfinished
merge of `77b1ad9`, two unresolved conflicts, and hundreds of staged/unstaged entries.
Ignoring CRLF differences, local application source matched that merge target. Unique
changes were conflicted README/editor settings and generated .NET metadata. The local
README change incorrectly used a module file as `Set-Location`; current upstream already
preserved the desired `usw2.pure.cloud` region and a correct repository-directory setup.

Merge commits `53f453f` and `79f486a` preserve history; no reset or force push was used.

## Accepted and cleaned up

- Accepted all current GitHub main changes, including the React/TypeScript Data Client,
  mock server improvements, and upstream deletion of duplicated embedded Core sources
  and tracked `bin/obj` outputs.
- Consolidated dependency-update intent from open PRs #65/#68 using Node 24, Vite 8,
  Vitest 5 and the compatible React plugin; regenerated the lock without peer overrides.
- Adapted the open PR #60 temp-directory correction to the current Pester lifecycle
  and removed Windows-only `Start-Process -WindowStyle` from the cross-platform test.
- Consolidated 25 reference-recipe updates from recent branches, with explicit
  `reference-only` status. These are design records, not newly exported runtime features.
- Held nine recipe updates that reference missing catalog entries. Preserved proposed
  runtime additions rather than enabling untested paging/retry/redaction behavior.
  For example, the work-item proposal requests `rateLimitAware`, while the current
  catalog defines only the `default` retry profile.
  **2026-09-19 update:** `rateLimitAware` already resolves — `Resolve-CatalogProfile`
  matches a retry profile name against a candidate's `mode` field when no profile of
  that exact name exists, and the `default` retry profile's `mode` is `rateLimitAware`;
  dozens of already-merged datasets (e.g. `users.get.user.routing.skills`) use this
  exact pattern and pass `Assert-Catalog`. With that clarified, eight of the nine held
  recipes have been registered: the missing curated `datasets` entries (wrapping
  already-catalogued swagger operations for External Contacts, Groups, Voicemail, Task
  Management, and Bot Flow) were added, and `division-access-security-audit`'s two
  genuinely nonexistent endpoint references were corrected to the equivalent entries
  `division-investigation` already uses. See
  [endpoint combinations](ENDPOINT_COMBINATIONS.md#september-2026-reconciliation-part-2--held-recipes-promoted)
  and the updated [proposal decisions](reconciliation/proposal-decisions.json). Only the
  unrelated `agent-investigation` / `(derived)` entry remains held.
- Corrected unverified generic provider-call injection guidance, externalTag origin
  assumptions, and Open Messaging deprecation guidance using the official source linked
  from [endpoint combinations](ENDPOINT_COMBINATIONS.md#open-messaging-correction).
- Removed the tracked agent temp-file duplicate. Stopped tracking personal editor and
  Claude settings while leaving those settings on disk. Moved comparison scratch files
  into the recovery directory.
- Replaced unrelated SereneHarmony roadmap content, removed a nonexistent GUI entry,
  corrected Analyzer paths and the SQLite ignore exception, and qualified accessibility
  claims to distinguish automated checks from full conformance.

## Remote branch disposition

126 branches were not ancestors of GitHub main at inspection. Many independently repeat
catalog proposals; their timestamps are not evidence of correctness or completeness.
The four open PRs were #60, #61, #65 and #68. Public API inspection worked; the GitHub CLI
had no authenticated session. No PR was closed or marked merged by this reconciliation.

- [Every unmerged branch, commit, changed paths and disposition](reconciliation/remote-branches.json)
- [Original recent catalog proposal deltas](reconciliation/recent-proposals.json)
- [Accepted recipe updates and held references](reconciliation/proposal-decisions.json)

Older independent branches remain available remotely. They were inventoried, not blindly
merged. In particular, a Division design recipe is not proof that a Division composer ships.
The supported runtime module exports and passing tests remain the authority.

## Architecture retained

`modules/Genesys.Core` is the shared execution engine, `Genesys.Ops` composes investigations,
and `Genesys.Auth` supplies authentication. The Data Client owns its isolated frontend
build. AuditLogsConsole, ConversationAnalyzer, standalone artifact viewers and operational
scripts remain where they provide distinct workflows. Removing them before feature parity
would discard case storage, desktop/reporting or offline investigation functionality.

## Validation

| Check | Result |
| --- | --- |
| Core unit suite, including recipe integrity | 206 passed, 0 failed, 1 skipped (local Swagger snapshot absent) |
| PowerShell integrations against fixtures/HTTP mock | 74 passed, 0 failed, 1 skipped (live tenant credentials absent) |
| .NET mock-server tests | 38 passed, 0 failed |
| ConversationAnalyzer checks | 272 passed, 0 failed, 2 skipped (SQLite native runtime unavailable) |
| Data Client clean lockfile install (`npm ci`), Node 24 | Passed; npm audit reported zero vulnerabilities |
| Data Client typecheck and production build, Node 24 | Passed |
| Data Client tests against HTTP mock | 75 passed, 0 failed, 0 skipped |
| Rendered accessibility audit | 15 surfaces, 0 detected violations |
| Strict catalog validation | Passed |
| Unresolved Git index conflicts | None |

Logs are retained in the local recovery directory under `validation/`. No production credentials, tenant runs, deployment, Windows
WPF interaction, or manual accessibility certification are implied by local fixture tests.


## Publication

Local changes are committed on main. GitHub publication is blocked by missing HTTPS
credentials: `git push --dry-run origin main` failed with `could not read Username`.
No remote branch or PR was modified. Once Git authentication is available, publish with
`git push origin main` (normal fast-forward push; fetch/review again if upstream advanced).

## Execution note

An initial npm install issued from the repository root resolved the parent directory's
package manifest. The resulting parent dependency directory and lockfile were preserved
in the recovery directory under `parent-npm-artifacts/`; the parent package.json was not
edited. All application installs and checks subsequently used its explicit directory.
