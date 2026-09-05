# SereneHarmony Site Starter Roadmap

## Status
![Build Status](https://img.shields.io/badge/build-passing-brightgreen) ![Coverage](https://img.shields.io/badge/coverage-95%25-success)

## Release Index

### v1.0: Initial Release
- [x] Setup basic UI framework
- [x] Finalize homepage design
- [x] Implement primary navigation
- [x] Test responsive layout

### v1.1: User Engagement
- [x] Enable user login/authentication
- [x] Implement user profile management
- [x] Set up email notification system
- [x] Integrate basic user analytics

## Active Release: v1.2

**Goal:** Enhance Accessibility and Performance

- [x] Attain WCAG 2.1 compliance — 2026-09-02
- [ ] Reduce image load times by 30%
- [ ] Integrate lazy loading for offscreen assets
- [ ] Conduct comprehensive performance audit

**Acceptance Criteria:**

- WCAG 2.1 compliance verified with automated tests.
- Image load reduction measured via Lighthouse.
- Lazy load functionality confirmed through network inspection.
- Performance audit results: all critical issues resolved.

### WCAG 2.1 compliance — delivered 2026-09-02

All seven shipped HTML surfaces conform to **WCAG 2.1 Level AA** under the
repository's automated gate. 175 violations were remediated.

| Deliverable | Location |
| --- | --- |
| Static analyzer (25 rules, no Node/npm dependency) | `tools/Genesys.Accessibility/` |
| Audit CLI (non-zero exit on violations) | `scripts/Invoke-AccessibilityAudit.ps1` |
| Surface manifest | `config/accessibility-surfaces.json` |
| Test suite (17 tests) | `tests/unit/Accessibility.Wcag21.Tests.ps1` |
| CI gate | `.github/workflows/ci.yml` → `accessibility` job |
| Conformance statement + manual checklist | `docs/ACCESSIBILITY.md` |

**Verification:**

```powershell
pwsh -NoProfile -File ./scripts/Invoke-AccessibilityAudit.ps1
# PASS - 7 surface(s) conform to WCAG 2.1 Level AA under static analysis.

pwsh -NoProfile -File ./scripts/Invoke-Tests.ps1
# Tests Passed: 203, Failed: 0, Skipped: 1
```

Surfaces were also driven in a real browser to confirm no functional regression:
demo-data load, tab keyboard navigation, filter toggles, table sorting, row
expansion, and diagram rendering.

**Non-blockers carried forward:**

- [non-blocker] Reflow (1.4.10), text spacing (1.4.12), and rendered chart
  contrast (1.4.11) are on the manual checklist in `docs/ACCESSIBILITY.md`;
  they require a rendered viewport that static analysis cannot evaluate.
- [non-blocker] Translucent (`rgba` alpha < 1) backgrounds are skipped by the
  contrast rules because the composited colour depends on an unresolvable
  ancestor. The affected rules were verified by hand and are listed in
  `docs/ACCESSIBILITY.md`.
- [non-blocker] No screen-reader pass has been run; add one NVDA/Narrator pass
  per console before claiming certified conformance.
- [non-blocker] **Pre-existing, unrelated to this work:**
  `tests/integration/MockServer.Integration.Tests.ps1` fails with
  `The term 'Start-MockServer' is not recognized` (13 failures). Verified
  against a clean tree at `77f6c53`: 0 passed / 13 failed before any
  accessibility change. `tests/PesterConfiguration.ps1` sets
  `Run.Path = './tests'`, so the `pester` CI job runs these and is red for this
  reason. The mock-server helper functions are not exported where the test
  expects them.

## Future Releases

### v1.3: Community Features
- [ ] Develop user forums
- [ ] Implement article comment sections
- [ ] Create like/dislike interaction system

### v1.4: Content Library Expansion
- [ ] Add 50 diverse articles
- [ ] Implement content recommendation system
- [ ] Include multimedia content with transcription

### v1.5: Mobile App Launch
- [ ] Develop iOS/Android mobile app
- [ ] Integrate real-time web synchronization
- [ ] Ensure seamless user session transition between app and web.