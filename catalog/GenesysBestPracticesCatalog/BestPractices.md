# Genesys Cloud Best Practices Reference
Version: 0.1.0  
Status: First-pass starter package

## Purpose

This package provides a **human-readable guide** and a **machine-readable index** of Genesys Cloud best practices that an application can reference by stable key.

It is designed for:

- audit and hygiene tooling
- operator guidance
- executive-ready reporting with consistent language
- mapping findings to recommended actions
- future rule automation and drift detection

## Package contents

- `BestPractices.md` — readable reference guide
- `best-practices.catalog.json` — machine-readable catalog of best-practice entries
- `best-practices.schema.json` — JSON Schema for validating catalog entries
- `best-practices-map.json` — starter mapping from finding types to best-practice keys
- `README.md` — implementation notes and adoption guidance

## Design goals

1. **Stable keys for code**
2. **Readable titles for humans**
3. **Short summaries for UI cards**
4. **Recommended state and anti-pattern fields for findings**
5. **Severity and auditability fields for prioritization**
6. **Extensible taxonomy for future domains**

---

# Catalog model

Each best-practice entry uses the following conceptual model:

- `key` — stable dotted identifier for application lookup
- `domain` — major object family or operational area
- `subcategory` — narrower grouping inside the domain
- `title` — short human-readable label
- `summary` — concise statement of the guidance
- `why_it_matters` — operational or governance reason
- `recommended_state` — condition that should be true
- `anti_pattern` — configuration or behavior to avoid
- `severity` — Low / Medium / High / Critical
- `auditability` — Config / Runtime / Config+Runtime / Manual
- `tags` — search/filter tags
- `object_types` — Genesys object types or logical scopes
- `source_basis` — what source family the rule came from
- `notes` — optional implementation notes

---

# Domain taxonomy

## Queue
ACD behavior, scoring methods, skills, members, work routing, wrap-up codes.

## API
Rate limiting, notifications vs polling, bulk usage, OAuth scope discipline, retry behavior.

## EdgeSite
Edge resilience, primary/secondary behavior, compatibility, network quality, multi-site redundancy.

## Architect
Flow lifecycle, naming, schedule groups, validation, deployment discipline.

## Security
Least privilege, role scoping, custom roles, divisions, access boundaries.

## Telephony
DIDs, extensions, stations, resource limits, group ring prerequisites.

## DevOps
CX as Code, Terraform, CI/CD promotion, automated deployment, change control.

---

# Best practices

## Queue

### queue.routing.method.explicit
**Title:** Define queue routing method intentionally  
**Summary:** Each queue should use a routing method chosen for the interaction model rather than inherited by accident.  
**Why it matters:** Routing method determines how arrival time, priority, and skills influence assignment.  
**Recommended state:** Routing method is explicitly chosen and documented for each queue.  
**Anti-pattern:** Using a queue with default routing behavior that no one has reviewed.  
**Severity:** High  
**Auditability:** Config

### queue.routing.scoring.change_only_when_empty
**Title:** Change queue scoring only when backlog is clear  
**Summary:** Set or change scoring during queue creation or while no interactions are waiting.  
**Why it matters:** Midstream scoring changes can produce unexpected assignment order for waiting interactions.  
**Recommended state:** Scoring changes occur only during planned maintenance windows or at creation time.  
**Anti-pattern:** Changing scoring while interactions are already waiting in the queue.  
**Severity:** High  
**Auditability:** Config+Runtime

### queue.skills.taxonomy.intentional
**Title:** Keep the skills taxonomy deliberate and current  
**Summary:** Skills should represent meaningful expertise and be assigned with discipline.  
**Why it matters:** Bloated or stale skill taxonomies reduce routing precision and raise maintenance cost.  
**Recommended state:** Skills are narrow, meaningful, reviewed, and tied to real routing use cases.  
**Anti-pattern:** Accumulating dozens of overlapping or unused skills.  
**Severity:** Medium  
**Auditability:** Config

### queue.skills.rating.meaningful
**Title:** Use skill ratings only where they drive actual routing decisions  
**Summary:** Skill ratings should reflect real proficiency and should not be decorative.  
**Why it matters:** Ratings imply ordering logic; inaccurate ratings distort routing outcomes.  
**Recommended state:** Ratings are periodically reviewed and used only where the routing method benefits from them.  
**Anti-pattern:** Uniform or arbitrary ratings that create false precision.  
**Severity:** Medium  
**Auditability:** Config

### queue.wrapup.division_aligned
**Title:** Align wrap-up codes to the queue division  
**Summary:** Wrap-up codes assigned to a queue should belong to the same division when possible.  
**Why it matters:** Division-aligned codes produce clearer reporting and reduce ambiguity across business units.  
**Recommended state:** Queue wrap-up codes are governed by the owning division.  
**Anti-pattern:** Cross-division wrap-up catalogs without a reporting reason.  
**Severity:** Medium  
**Auditability:** Config

### queue.wrapup.catalog.concise
**Title:** Keep the wrap-up catalog concise and semantically clear  
**Summary:** Wrap-up codes should describe outcomes distinctly, without synonym sprawl.  
**Why it matters:** Overlapping codes weaken reporting and make agent selection inconsistent.  
**Recommended state:** Each wrap-up code has a unique purpose and plain-language meaning.  
**Anti-pattern:** Multiple codes that mean nearly the same thing.  
**Severity:** Medium  
**Auditability:** Config

### queue.workitem.media.separate_when_possible
**Title:** Separate workitem queues by media type where practical  
**Summary:** Dedicated queues reduce routing contention between workitems and other interaction types.  
**Why it matters:** Mixed media can create priority side effects that starve other work.  
**Recommended state:** Workitems and real-time media are isolated when operationally appropriate.  
**Anti-pattern:** Mixed-media queues that are difficult to tune.  
**Severity:** Medium  
**Auditability:** Config

### queue.membership.multi_queue.caution
**Title:** Add agents to multiple queues cautiously  
**Summary:** Multi-queue membership should be deliberate and capacity-aware.  
**Why it matters:** Heavy multi-queue membership can affect backlog evaluation and routing behavior.  
**Recommended state:** Membership is minimal, purposeful, and tied to staffing strategy.  
**Anti-pattern:** Broad “add everyone everywhere” queue membership.  
**Severity:** Medium  
**Auditability:** Config

---

## API

### api.rate_limit.retry.backoff
**Title:** Implement explicit retry backoff for rate-limited requests  
**Summary:** Clients should handle rate limits using deliberate retry intervals and limit metadata inspection.  
**Why it matters:** This reduces repeated throttling and improves stability under load.  
**Recommended state:** Integrations inspect limit information and back off rather than retrying aggressively.  
**Anti-pattern:** Immediate repeated retries after 429 responses.  
**Severity:** High  
**Auditability:** Runtime

### api.state_change.notifications_over_polling
**Title:** Prefer notifications over polling for asynchronous state changes  
**Summary:** Use event subscriptions where available instead of repeated status polling.  
**Why it matters:** Notification-based patterns reduce request volume and improve responsiveness.  
**Recommended state:** State-change monitoring is event-driven where the platform supports it.  
**Anti-pattern:** Tight-loop polling for campaign or resource state.  
**Severity:** High  
**Auditability:** Runtime

### api.bulk.use_for_scale
**Title:** Use bulk endpoints for multi-record operations  
**Summary:** For large sets of records, bulk APIs should be preferred over repeated single-item requests.  
**Why it matters:** Bulk operations usually deliver better throughput and lower API overhead.  
**Recommended state:** Bulk APIs are used whenever available for batch tasks.  
**Anti-pattern:** Loops of one-by-one mutations where a bulk endpoint exists.  
**Severity:** Medium  
**Auditability:** Runtime

### api.oauth.scope.minimum_required
**Title:** Request the minimum OAuth scopes required  
**Summary:** Applications and automations should only request scopes they truly need.  
**Why it matters:** Least-privilege design reduces blast radius and eases governance review.  
**Recommended state:** Each app has a documented scope set tied to a business purpose.  
**Anti-pattern:** Broad “just in case” scope grants.  
**Severity:** High  
**Auditability:** Config

---

## EdgeSite

### edgesite.redundancy.n_plus_one
**Title:** Design BYOC Premises Edge resiliency as N+1  
**Summary:** Capacity planning should tolerate the loss of one active Edge while preserving service continuity.  
**Why it matters:** A design that only works at full inventory is fragile.  
**Recommended state:** Expected concurrent load remains supportable after single-Edge failure.  
**Anti-pattern:** Sizing that requires every Edge to stay healthy.  
**Severity:** Critical  
**Auditability:** Manual

### edgesite.phone.primary_secondary
**Title:** Ensure phones have primary and secondary Edge paths  
**Summary:** Phones should benefit from redundant registration paths rather than a single attachment point.  
**Why it matters:** Redundant assignment shortens service disruption during Edge failure.  
**Recommended state:** Managed phones participate in primary/secondary redundancy design.  
**Anti-pattern:** Single-path phone dependencies in a supposedly redundant site.  
**Severity:** High  
**Auditability:** Config

### edgesite.capacity.compatible_classes
**Title:** Keep redundant Edge pools within compatible capacity classes  
**Summary:** Combine like-for-like or supported capacity classes within redundancy groups.  
**Why it matters:** Unsupported or uneven combinations can distort failover assumptions.  
**Recommended state:** Redundant pools are composed of compatible Edge types and sizes.  
**Anti-pattern:** Mixing incompatible capacity classes without a supported design.  
**Severity:** High  
**Auditability:** Config

### edgesite.network.low_latency_low_jitter
**Title:** Maintain low latency and low jitter between dependent Edge components  
**Summary:** Network quality between Edges should stay within tight tolerances.  
**Why it matters:** Failover reliability and telephony quality both degrade under poor inter-Edge conditions.  
**Recommended state:** Inter-Edge latency and jitter remain within recommended thresholds.  
**Anti-pattern:** Treating redundancy as valid while the underlying network is unstable.  
**Severity:** Critical  
**Auditability:** Runtime

### edgesite.multisite.primary_secondary.defined
**Title:** Define primary and secondary sites explicitly for multi-site resiliency  
**Summary:** Multi-site configurations should declare the intended primary and secondary topology.  
**Why it matters:** Ambiguous multi-site design complicates failover expectations and operations.  
**Recommended state:** Primary/secondary site relationships are explicit, documented, and tested.  
**Anti-pattern:** Multi-site deployments with no validated failover narrative.  
**Severity:** High  
**Auditability:** Config

---

## Architect

### architect.flow.build_for_org
**Title:** Build flows for the organization, not by cloning examples blindly  
**Summary:** Examples should be references, not production designs copied without adaptation.  
**Why it matters:** Real routing, prompts, schedules, and failover logic are organization-specific.  
**Recommended state:** Production flows are intentionally tailored and reviewed.  
**Anti-pattern:** Publishing example flows with minimal local design work.  
**Severity:** Medium  
**Auditability:** Manual

### architect.flow.naming.descriptive_unique
**Title:** Use descriptive and unique names for flows and prompts  
**Summary:** Names should be specific enough to support maintenance, reporting, and promotion.  
**Why it matters:** Weak names make troubleshooting and environment comparison harder.  
**Recommended state:** Names encode business purpose and remain unique within the relevant type.  
**Anti-pattern:** Generic labels like Main, Test, Final2, or Copy.  
**Severity:** Medium  
**Auditability:** Config

### architect.state.labels.distinct
**Title:** Give Architect states distinct labels  
**Summary:** State labels should clearly describe the action or branch they represent.  
**Why it matters:** Architect readability and supportability depend on state clarity.  
**Recommended state:** Sequence labels are explicit and non-duplicative.  
**Anti-pattern:** Reusing vague labels across many states.  
**Severity:** Medium  
**Auditability:** Config

### architect.schedule_groups.timezone_explicit
**Title:** Keep schedule groups timezone-explicit  
**Summary:** Schedule groups should make timezone behavior obvious and intentional.  
**Why it matters:** Hidden timezone assumptions create open/closed routing defects.  
**Recommended state:** Timezone and holiday/emergency logic are documented and tested.  
**Anti-pattern:** Implicit timezone handling or copied schedule groups without review.  
**Severity:** High  
**Auditability:** Config

### architect.lifecycle.validation_versioning
**Title:** Use validation, versioning, and check-in/check-out discipline  
**Summary:** Flow changes should follow a controlled lifecycle before publication.  
**Why it matters:** This reduces accidental release errors and helps preserve change history.  
**Recommended state:** Validation and version management are part of the deployment routine.  
**Anti-pattern:** Direct ad hoc publishing with no review or lifecycle control.  
**Severity:** High  
**Auditability:** Manual

---

## Security

### security.access.least_privilege
**Title:** Default to least privilege  
**Summary:** Users, groups, and integrations should have only the permissions necessary for their purpose.  
**Why it matters:** Broad permissions increase blast radius and complicate governance.  
**Recommended state:** Access is role-based, purposeful, and periodically reviewed.  
**Anti-pattern:** Blanket admin assignment for convenience.  
**Severity:** Critical  
**Auditability:** Config

### security.roles.custom_over_broad_admin
**Title:** Prefer custom roles over broad administrative grants  
**Summary:** Use narrower custom roles where they satisfy the need.  
**Why it matters:** This limits overexposure while preserving operational effectiveness.  
**Recommended state:** Broad admin roles are rare and justified.  
**Anti-pattern:** Using Master Admin as a shortcut.  
**Severity:** High  
**Auditability:** Config

### security.roles.sprawl.minimize
**Title:** Keep the role catalog lean  
**Summary:** Avoid uncontrolled growth in role count and permission overlap.  
**Why it matters:** Role sprawl obscures intent and increases maintenance burden.  
**Recommended state:** Roles are curated, named clearly, and periodically rationalized.  
**Anti-pattern:** Creating one-off roles for every exception.  
**Severity:** Medium  
**Auditability:** Config

### security.divisions.boundaries_explicit
**Title:** Use divisions as explicit administrative boundaries  
**Summary:** Division design should reflect actual operational or business boundaries.  
**Why it matters:** Division scoping is a core containment and governance mechanism.  
**Recommended state:** Division assignments are intentional and auditable.  
**Anti-pattern:** Cross-division access that exists only because “it was easier.”  
**Severity:** High  
**Auditability:** Config

---

## Telephony

### telephony.capacity.monitor_limits
**Title:** Monitor telephony resource limits before warning thresholds become operational blockers  
**Summary:** Capacity should be reviewed before the environment approaches hard limits.  
**Why it matters:** Resource exhaustion often creates last-minute provisioning failures.  
**Recommended state:** Limit utilization is tracked and actioned before it becomes critical.  
**Anti-pattern:** Discovering object-limit exhaustion during an urgent change.  
**Severity:** High  
**Auditability:** Config

### telephony.did_extension.assignment_controlled
**Title:** Manage DID and extension assignment with clear ownership  
**Summary:** DIDs and extensions should be allocated from controlled ranges with documented stewardship.  
**Why it matters:** Ad hoc numbering plans create confusion and slow incident response.  
**Recommended state:** Number assignment follows a maintained plan.  
**Anti-pattern:** One-off assignments with no ownership model.  
**Severity:** Medium  
**Auditability:** Config

### telephony.group_ring.addressing_required
**Title:** Ensure users are properly addressable for group ring scenarios  
**Summary:** Group ring behavior depends on user telephony addressing being complete.  
**Why it matters:** Missing DID or extension coverage can lead to inconsistent alerting.  
**Recommended state:** Group ring participants have the required telephony configuration.  
**Anti-pattern:** Assuming group ring will work without endpoint addressing prerequisites.  
**Severity:** Medium  
**Auditability:** Config

---

## DevOps

### devops.cx_as_code.prefer_for_repeatability
**Title:** Prefer CX as Code for repeatable configuration management  
**Summary:** Supported Genesys Cloud configuration should be represented as managed text artifacts where practical.  
**Why it matters:** Text-defined configuration improves repeatability, review, and promotion between orgs.  
**Recommended state:** Core configuration is source-controlled and deployable.  
**Anti-pattern:** Treating production configuration as manual-only tribal knowledge.  
**Severity:** High  
**Auditability:** Manual

### devops.cicd.pipeline.automated_promotion
**Title:** Promote changes through automated CI/CD pipelines  
**Summary:** Changes should advance through environments with validation and minimal manual handling.  
**Why it matters:** Automation reduces drift and improves consistency across orgs.  
**Recommended state:** Dev, test, and production promotion is pipeline-driven.  
**Anti-pattern:** Manual copy/paste promotion across orgs.  
**Severity:** High  
**Auditability:** Manual

### devops.terraform.state_managed
**Title:** Use managed Terraform state and locking  
**Summary:** Terraform-based Genesys workflows should use controlled remote state and locking mechanisms.  
**Why it matters:** Shared state without governance creates deployment risk.  
**Recommended state:** State storage, locking, and promotion strategy are documented and enforced.  
**Anti-pattern:** Ad hoc local state files for shared environments.  
**Severity:** High  
**Auditability:** Manual

### devops.deployments.automated_and_tested
**Title:** Deploy through an automated, test-backed process  
**Summary:** Production changes should be the output of a repeatable deployment pipeline with validation steps.  
**Why it matters:** This improves consistency and supports change control.  
**Recommended state:** Commit-driven deployment with validation gates.  
**Anti-pattern:** Direct human-driven production changes with no reproducible deployment path.  
**Severity:** High  
**Auditability:** Manual

---

# Implementation guidance

## Stable key convention

Use dotted keys in the format:

`<domain>.<subcategory>.<rule_name>`

Examples:

- `queue.routing.scoring.change_only_when_empty`
- `security.roles.custom_over_broad_admin`
- `devops.cicd.pipeline.automated_promotion`

## Severity convention

- **Low** — improvement opportunity
- **Medium** — notable hygiene issue
- **High** — material operational or governance risk
- **Critical** — direct availability, security, or major governance risk

## Auditability convention

- **Config** — detectable from static configuration or metadata
- **Runtime** — detectable from live behavior, logs, or telemetry
- **Config+Runtime** — best judged with both
- **Manual** — requires human review or architectural confirmation

## Recommended next steps

1. Add `evidence_examples` to each catalog entry
2. Add `finding_templates` to support report output
3. Add `detection_strategy` for rules you can automate
4. Add `remediation_steps` with short and long forms
5. Add `owner_role` to clarify operational accountability

## Opinionated note

This first pass intentionally favors **stable structure over maximal completeness**.  
The right next evolution is to connect your analyzer outputs directly to `best-practices-map.json` so every finding can point to one or more catalog keys, a rationale, and a recommended action.
