# Genesys.Core - Product & Engineering Roadmap

> Status: Active
>
> Last updated: 2026-04-29

## 1. Product Intent

Genesys.Core is a catalog-driven PowerShell execution engine for governed,
reproducible data collection from the Genesys Cloud REST API. It produces
deterministic run artifacts (`manifest.json`, `events.jsonl`, `summary.json`,
`data/*.jsonl`) suitable for compliance review, CI automation, and downstream
analysis.

The next product step is **investigation composition**: combining the
existing per-dataset queries into joined, subject-centred records — for example,
matching an agent's identity, division, location, skills, and queue
assignments to the conversations on which they were alerted or engaged.
The raw datasets exist; the composition layer does not.

Audience: contact-centre operators, platform admins, compliance reviewers, and
the engineering teams that automate against them.

---

## 2. Recently Completed

- [x] Critical hardening (2026-03-30): catalog-path resolution, schema-path
      computation, and Genesys.Ops module-init ordering. Queries now succeed
      from any working directory and on first import.
- [x] Session 19 — Quality and Voice-of-Customer overlay (joins
      survey/evaluation/sentiment data on top of existing Core datasets).
- [x] Track A — Workflow auth wiring: `dataset.on-demand.yml` with
      `GENESYS_CLIENT_ID` / `GENESYS_CLIENT_SECRET` / `GENESYS_REGION` secrets
      contract, token bootstrap step, and end-to-end dataset execution.
- [x] Track A — Redaction baseline coverage: five named redaction profiles added
      to `catalog/genesys.catalog.json`; `Protect-RecordData` extended with
      profile-driven `removeFields` support; all seven Agent Investigation
      datasets carry a `redactionProfile` reference.
- [x] Track A — Formal production-readiness gate: `READINESS_REVIEW.md`
      rewritten as a verifiable per-criterion checklist covering auth, paging,
      retry, redaction, artifact contract, workflow/CI, live validation, and
      the Track B gate.
- [x] Release 1.1 — Conversation Investigation flagship: `Get-GenesysConversationInvestigation`
      implemented with derived-participants step, `RecordDeriver`/`SubjectUpdater`
      extension to `Invoke-Investigation`, redaction profiles for recordings and
      evaluations datasets, and full fixture-driven integration test suite.
- [x] Release 1.2 — Queue Investigation flagship: `Get-GenesysQueueInvestigation`
      implemented over six steps (queue, members, observations, sla, abandons,
      activeAgents); new `routing-queue-members` dataset and
      `queue-investigation-members` redaction profile added to the catalog;
      `Get-GenesysQueueHealthSnapshot` and `Invoke-GenesysOperationsReport`
      retained with cross-references to the new investigation; full
      fixture-driven integration test suite under
      `tests/integration/QueueInvestigation.Tests.ps1`.

---

## 3. Release Roadmap

The composition pivot is preserved across the 1.x series. To keep each release
shippable, only **one flagship investigation** lands per release. Agent
Investigation is the first flagship and proves the composition model end-to-end;
Conversation and Queue investigations follow once the model is in production.

| Release | Theme |
| --- | --- |
| 1.0 | Trust foundation + Agent Investigation |
| 1.1 | Conversation Investigation + redaction hardening |
| 1.2 | Queue Investigation + reporting-contract cleanup |
| 1.3 | Visibility extensions, edge alarms, temporal trends |

---

## Release 1.0 — Trust foundation + Agent Investigation

**Goal:** Establish a trustworthy data layer (Track A) and prove the
investigation composition model with a single flagship: Agent Investigation
(Track B). Plumbing alone does not mark this release complete; the release
ships when an operator can run `Get-GenesysAgentInvestigation` end-to-end
against verified datasets and the joined output is deterministic.

### Product outcomes

- Operators can run any catalog dataset against live Genesys Cloud and trust
  the output (paging, retry, redaction verified per endpoint).
- Operators can run **Agent Investigation** end-to-end and receive a joined
  record set covering identity, division, location, skills, queue
  memberships, conversations the agent touched, and presence/login activity
  in the chosen window — all under the standard run-artifact contract.
- The product intent in section 1 is reflected in `README.md`, training
  material, and onboarding — investigations are described as a first-class
  capability, not an appendix.

### Track A — Trust (preconditions)

These items gate Track B. Joining unverified data amplifies any silent error
in a single dataset.

- [ ] Live validation of each remaining Phase 4 endpoint against Genesys Cloud
      (confirm `itemsPath`, paging strategy/profile, retry behaviour; update
      catalog entries where live behaviour differs from initial wiring).
- [x] Mirror-catalog consolidation / canonical cutover (remove the deprecated
      `genesys-core.catalog.json` stub, retire the legacy fallback in
      `Resolve-Catalog`, update tests and agent/app docs to reference only
      `catalog/genesys.catalog.json`).
- [x] Workflow auth wiring and examples (GitHub Actions secrets contract,
      token bootstrap step, end-to-end example workflow distinct from the CI
      mock run). See `.github/workflows/dataset.on-demand.yml`.
- [x] Resolve OAuth usage async orchestration behind curated handler(s) if the
      submit → results chain requires it in production. **Decision: deferred.**
      The `oauth.post.client.usage.query` / `oauth.get.client.usage.query.results`
      two-step pattern is adequately served by the existing generic catalog
      dataset pair — operators sequence them in Genesys.Ops. No curated handler
      is needed for 1.0; the submit → results gap is bridged by the `usage_query`
      transaction profile already defined in the catalog. Revisit if a composed
      investigation step requires it in-process.
- [x] Redaction baseline coverage for the Agent Investigation dataset set
      (allow/deny rules verified for `users`, division-info, skills,
      `routing-queues`, bulk presences, user activity report, and
      `analytics-conversation-details-query`). Named redaction profiles added
      to `catalog/genesys.catalog.json`; `Protect-RecordData` extended with
      profile-driven `removeFields` support; all three dataset execution paths
      now resolve and pass the catalog profile.
- [x] Formal production-readiness gate definition (single checklist of
      verifiable exit criteria for "broad automation" in
      [READINESS_REVIEW.md](READINESS_REVIEW.md)).
- [ ] Any Ops-layer endpoint/cmdlet hardening identified during live
      validation (itemsPath corrections, paging profile swaps, async chain
      wrapping).

### Track B — Composition (the value step)

Design contract: [INVESTIGATIONS.md](INVESTIGATIONS.md). Track B reuses the
existing dataset run-artifact contract — investigations are not a new file
format, they are datasets that join other datasets. No new module, no new
artifact format, no broad abstraction layer.

- [x] **Investigation composer contract.** A single private helper
      (`Invoke-Investigation`) in `Genesys.Ops` that takes a subject + window,
      runs N registered datasets via existing `Genesys.Core` plumbing, joins
      on declared keys, and emits the standard artifact set under
      `out/<investigationKey>/<runId>/`. No new abstractions beyond the join
      helper.
- [x] **Investigation Manifest Contract.** The investigation's `manifest.json`
      records a fixed shape so downstream tooling (CI, audit, reporting) can
      consume any investigation uniformly. Required fields:
      `investigationKey`, `subjectType`, `subjectId`, `window` (`since`,
      `until`), `datasetsInvoked` (array of `{ datasetKey, runId,
      validationStatus, recordCount }`), `joinPlan` (array of
      `{ stepName, leftSource, rightSource, joinKind }`), `redactionProfile`
      (per-dataset profile name + composer-level overrides), and
      `outputArtifacts` (`manifestPath`, `eventsPath`, `summaryPath`,
      `dataPaths`). See
      [INVESTIGATIONS.md § Manifest contract](INVESTIGATIONS.md#manifest-contract).
- [x] **Flagship investigation — Agent.**
      `Get-GenesysAgentInvestigation -UserId <x> -Since <window>` →
      identity + division + location + skills + queue memberships +
      conversations the agent touched + presence/login activity in the
      window. Emits the standard artifact set with the manifest above.
- [x] **Integration test contract for investigations.** Feed Agent
      Investigation a known subject ID against a fixture and assert (a) the
      manifest shape, (b) the `summary.json` join shape, and (c)
      determinism — two consecutive runs over the same fixture produce
      byte-equivalent `summary.json` and `data/*.jsonl` (timestamps and
      `runId` excluded). Mirrors how dataset tests work today.
- [x] **Docs as first-class capability.** Update `README.md`, `ONBOARDING.md`,
      and training material to describe investigations alongside datasets.
      Cross-link `INVESTIGATIONS.md`. No "manages repositories" boilerplate
      anywhere.

### Dependencies and ordering

- Agent Investigation depends on these Track A datasets having
  `Live Invoke-Dataset acceptance passed`: `users`, division-info, skills,
  `routing-queues`, bulk presences, user activity report,
  `analytics-conversation-details-query`.
  The flagship cannot be marked done until each of these reports a green
  validation status in its catalog entry.
- Mirror-catalog consolidation has landed; Agent Investigation may reference
  catalog keys without risk of a double rename.
- Redaction baseline coverage (Track A) is the floor; per-dataset profile
  hardening rides with the Conversation flagship in 1.1.

### Acceptance criteria

Release 1.0 is complete when **all** of the following hold:

- [ ] All Track A items are implemented and the readiness checklist in
      `READINESS_REVIEW.md` reports green.
- [ ] `Get-GenesysAgentInvestigation -UserId <known-id> -Since 7d` runs
      end-to-end against live Genesys Cloud and exits 0.
- [ ] Every dataset Agent Investigation invokes has
      `Live Invoke-Dataset acceptance passed` and `validationStatus =
      'live-validated'` recorded in its catalog entry as of release tag.
- [x] Fixture-driven integration test for Agent Investigation passes,
      asserting manifest shape, join shape, and determinism (see
      [§ Acceptance tests for Agent Investigation](#acceptance-tests-for-agent-investigation)
      below).
- [x] Agent Investigation produces the full standard artifact set
      (`manifest.json`, `events.jsonl`, `summary.json`, `data/*.jsonl`) under
      `out/agent-investigation/<runId>/`, and `manifest.json` conforms to the
      Investigation Manifest Contract.
- [x] `README.md` and `ONBOARDING.md` describe investigations as first-class;
      `INVESTIGATIONS.md` is cross-linked from both.
- [ ] No placeholder stubs or TODO comments remain in modified code.

### Acceptance tests for Agent Investigation

These are the integration tests that gate release. They live under
`tests/integration/` alongside existing dataset integration tests.

1. **Happy path, full window.** Given a known agent ID and a 7-day window
   against the recorded fixture, the run produces:
   - exit code 0
   - `manifest.json` containing every required field listed in the
     Manifest Contract, with `datasetsInvoked.length == 7`
   - `summary.json` with sections `agent`, `division`, `skills`, `queues`,
     `presence`, `activity`, `conversations` and an inner-join row count
     ≥ 1 for the seed identity step
   - one JSONL per step under `data/`, line counts matching
     `datasetsInvoked[i].recordCount`
2. **Determinism.** Two consecutive runs over the same fixture produce
   byte-equivalent `summary.json` and byte-equivalent `data/*.jsonl`, after
   stripping `runId` and ISO-8601 timestamps.
3. **Missing optional step.** With a fixture where the user has no
   conversations in the window, the run still exits 0; `summary.json`
   contains an empty `conversations` array; `manifest.json` records
   `recordCount: 0` for that step. Required vs. optional step semantics are
   honoured — no missing step is silently swallowed.
4. **Required step failure aborts.** With a fixture that returns 4xx for the
   identity dataset, the run exits non-zero and `events.jsonl` records the
   failure with the dataset's `runId`. No `summary.json` is written.
5. **Redaction.** Authorization headers and any token-shaped query params do
   not appear in `events.jsonl`; PII fields covered by the redaction baseline
   for each invoked dataset do not appear in `summary.json` or `data/*.jsonl`.
6. **Manifest validity.** `manifest.json` validates against the
   Investigation Manifest schema (added under
   `catalog/schema/investigation.manifest.schema.json`).
7. **Subject-by-name resolution boundary.** When the cmdlet is called with
   `-UserName 'Jane Doe'`, the wrapper resolves to a `UserId` before invoking
   `Invoke-Investigation`; the composer never sees the name. Asserted by
   inspecting the manifest's `subjectId` field.

### Out of scope (deferred to 1.1+)

- Conversation Investigation (moved to 1.1).
- Queue Investigation (moved to 1.2).
- Profile-by-dataset redaction sweep beyond the Agent baseline (moved to 1.1
  with the Conversation flagship, where free-text content makes it
  load-bearing).
- Reporting-contract cleanup of `Get-GenesysQueueHealthSnapshot` and
  `Invoke-GenesysOperationsReport` (moved to 1.2 with the Queue flagship,
  whose join logic overlaps).
- Edge Alarms & Event Feed (Idea 5), Session 20 temporal trends (1.3).
- Any composition that introduces a new artifact format, a new module, or a
  cross-module reference beyond Genesys.Ops → Genesys.Core. Investigations
  must live within the existing three-module structure.

---

## Release 1.1 — Conversation Investigation + redaction hardening

**Goal:** Add the second flagship and harden redaction for the free-text
content it surfaces.

- [x] **Flagship investigation — Conversation.**
      `Get-GenesysConversationInvestigation -ConversationId <x>` →
      conversation detail + every agent involved (with their division/skills/
      queues at time of contact, current-state attribution acceptable for
      1.1) + recordings/evaluations/sentiment when present.
- [x] **Profile-by-dataset redaction sweep.** Explicit allow/deny rules for
      `conversations.get.recordings` and `quality.get.evaluations.query`
      added to `catalog/genesys.catalog.json` as
      `conversation-investigation-recordings` and
      `conversation-investigation-evaluations` profiles. Conversation
      Investigation inherits dataset-level redaction without bypass.
- [x] **Acceptance tests for Conversation Investigation** mirroring the Agent
      pattern: happy path, determinism, missing recordings, required-step
      failure, redaction (no auth headers), manifest validity, and no-participant
      edge case. All tests under `tests/integration/ConversationInvestigation.Tests.ps1`.
- [ ] Live validation of any Conversation-only datasets not covered in 1.0
      (`analytics-conversation-details`, recordings, evaluations).

---

## Release 1.2 — Queue Investigation + reporting-contract cleanup

**Goal:** Add the third flagship and reconcile pre-existing ad-hoc composers
with the composition contract.

- [x] **Flagship investigation — Queue.**
      `Get-GenesysQueueInvestigation -QueueId <x> -Since <window>` →
      queue config + members + observations + SLA + abandons + agents
      currently active on the queue. Six steps composed via
      `Invoke-Investigation`; new `routing-queue-members` dataset wraps
      `routing.get.queue.members.with.status`. Emits the standard run-artifact
      set under `out/queue-investigation/<runId>/`.
- [x] **Reporting-contract cleanup.** `Get-GenesysQueueHealthSnapshot` and
      `Invoke-GenesysOperationsReport` are retained as-is and now carry
      one-line cross-references in their source `.SYNOPSIS`/`.DESCRIPTION`
      pointing operators to `Get-GenesysQueueInvestigation` for the
      single-queue case under the run-artifact contract. They differ in
      shape (multi-queue snapshot / multi-section daily report vs. a
      subject-centred investigation) so a re-implementation on top of
      `Invoke-Investigation` would have been pure churn.
- [x] **Acceptance tests for Queue Investigation** mirroring the Agent and
      Conversation patterns. All seven contexts (happy path, determinism,
      missing optional step, required-step failure, redaction, manifest
      validity, empty aggregates) pass under
      `tests/integration/QueueInvestigation.Tests.ps1`.
- [ ] Live validation of any Queue-only datasets not covered in 1.0/1.1
      (queue members, queue observations, queue performance, abandon
      aggregates, user observations) — gated on live Genesys Cloud access.

---

## Release 1.3 — Visibility extensions (tentative)

**Goal:** Add deferred visibility features once the composition layer is
established and proven across all three flagships.

- [ ] Idea 5 — Edge Alarms & Event Feed (catalog endpoint
      `telephony.get.edge.logs`, `Get-GenesysEdgeEvent` Ops cmdlet, NOC feed
      contract).
- [ ] Session 20 — Temporal Trend and Comparative Reporting
      (period-over-period comparisons on Core aggregate outputs and on
      investigation outputs).
- [ ] Additional flagship investigations identified during 1.0–1.2
      (candidates: Division, Flow, Outbound Campaign) — only if a stakeholder
      names a concrete use case.

---

## 4. Definition of Done

A release is not complete unless:

- All checklist items for that release are implemented or explicitly deferred
  with a written rationale in this file.
- UI elements are connected to real behaviour rather than placeholders.
- Affected docs (`README.md`, `ONBOARDING.md`, `INVESTIGATIONS.md`,
  `READINESS_REVIEW.md`, training material) are updated where workflow or
  product behaviour changed.
- Logging and error handling are sufficient to diagnose failures without
  reaching for source code.
- New cross-module references have been justified in the relevant design doc;
  by default, prefer fewer abstractions, fewer files, and fewer cross-module
  calls.
