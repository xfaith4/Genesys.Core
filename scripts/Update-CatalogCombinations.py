#!/usr/bin/env python3
"""
Update-CatalogCombinations.py

Adds 15 new dataset entries and 6 new combination recipes/playbooks to
catalog/genesys.catalog.json based on Genesys Cloud API research and
investigation of missing endpoint coverage.

Run from repo root:
    python3 scripts/Update-CatalogCombinations.py
"""

import json
import sys
from pathlib import Path

CATALOG_PATH = Path("catalog/genesys.catalog.json")


# ── New dataset entries ────────────────────────────────────────────────────────

NEW_DATASETS = {

    # ── Speech & Text Analytics ──────────────────────────────────────────────

    "speechandtextanalytics.get.conversation.categories": {
        "description": (
            "S&TA topic and category classification for a single conversation. "
            "Returns detected categories with scores — use to identify compliance "
            "triggers, intent labels, and quality programme matches."
        ),
        "endpoint": "getSpeechandtextanalyticsConversationCategories",
        "itemsPath": "$.entities",
        "paging": {"profile": "pageNumber_default"},
        "retry": {"profile": "rateLimitAware"},
        "redactionProfile": "standard",
        "validationStatus": "unvalidated"
    },

    "speechandtextanalytics.get.conversation.summaries.detail": {
        "description": (
            "S&TA-generated text summaries per communication leg for a single "
            "conversation. Provides brief narrative per call segment — faster to "
            "scan than transcripts for investigation triage."
        ),
        "endpoint": "getSpeechandtextanalyticsConversationSummaries",
        "itemsPath": "$.entities",
        "paging": {"profile": "pageNumber_default"},
        "retry": {"profile": "rateLimitAware"},
        "redactionProfile": "conversation-investigation-recordings",
        "validationStatus": "unvalidated"
    },

    "speechandtextanalytics.get.conversation.sentiments": {
        "description": (
            "Per-utterance sentiment timeline for a conversation — agent and customer "
            "scores at each turn. More granular than the top-level S&TA overview; "
            "used to pinpoint the moment sentiment shifted."
        ),
        "endpoint": "getSpeechandtextanalyticsConversationSentiments",
        "itemsPath": "$.entities",
        "paging": {"profile": "pageNumber_default"},
        "retry": {"profile": "rateLimitAware"},
        "redactionProfile": "standard",
        "validationStatus": "unvalidated"
    },

    # ── Conversation enrichment ──────────────────────────────────────────────

    "conversations.get.conversation.summaries": {
        "description": (
            "AI / Agent Assist copilot summaries for a conversation — reason for "
            "contact, resolution, and follow-up actions captured by the live-assist "
            "engine. Join to conversation-base on conversationId."
        ),
        "endpoint": "conversations.get.conversation.summaries",
        "itemsPath": "$.entities",
        "paging": {"profile": "none"},
        "retry": {"profile": "rateLimitAware"},
        "redactionProfile": "conversation-investigation-recordings",
        "validationStatus": "unvalidated"
    },

    "conversations.get.conversation.participant.wrapup": {
        "description": (
            "Wrapup code and notes for one participant in a conversation. "
            "Call once per agent participant extracted from the conversation roster; "
            "join on conversationId + participantId."
        ),
        "endpoint": "conversations.get.conversation.participant.wrapup",
        "itemsPath": "$",
        "paging": {"profile": "none"},
        "retry": {"profile": "rateLimitAware"},
        "redactionProfile": "standard",
        "validationStatus": "unvalidated"
    },

    "conversations.get.call.detail": {
        "description": (
            "Voice-channel call object for a single conversation — includes all "
            "hold/mute events, complete ANI/DNIS routing path, and per-participant "
            "call legs. Essential for voice engineers diagnosing routing or hold issues."
        ),
        "endpoint": "conversations.get.call.detail",
        "itemsPath": "$",
        "paging": {"profile": "none"},
        "retry": {"profile": "rateLimitAware"},
        "redactionProfile": "standard",
        "validationStatus": "unvalidated"
    },

    # ── Quality ──────────────────────────────────────────────────────────────

    "analytics.query.evaluations.aggregates": {
        "description": (
            "Aggregate quality evaluation metrics — evalCount, avgScore, "
            "criticalItemFailCount, highScore, lowScore. POST body supports "
            "groupBy userId, queueId, evaluatorId, and mediaType with daily/hourly "
            "granularity. Primary input for QM executive dashboards."
        ),
        "endpoint": "postAnalyticsEvaluationsAggregatesQuery",
        "itemsPath": "$.results",
        "paging": {"profile": "analytics_details_query"},
        "retry": {"profile": "rateLimitAware"},
        "redactionProfile": "standard",
        "validationStatus": "unvalidated"
    },

    "analytics.query.surveys.aggregates": {
        "description": (
            "Aggregate CSAT / NPS survey metrics — nSurveys, avgScore, "
            "promoterCount, detractorCount. POST body supports groupBy queueId, "
            "userId, and surveyFormId with daily granularity. Feeds the "
            "voice-of-customer section of executive reporting."
        ),
        "endpoint": "postAnalyticsSurveysAggregatesQuery",
        "itemsPath": "$.results",
        "paging": {"profile": "analytics_details_query"},
        "retry": {"profile": "rateLimitAware"},
        "redactionProfile": "standard",
        "validationStatus": "unvalidated"
    },

    # ── Routing — queue management ────────────────────────────────────────────

    "routing.get.queue.estimated.wait.time": {
        "description": (
            "Real-time Estimated Wait Time (EWT) for a queue, optionally filtered "
            "by mediaType. Returns estimatedWaitTimeSeconds — compare to SLA target "
            "to trigger staffing interventions in real-time operations monitoring."
        ),
        "endpoint": "routing.get.queue.estimated.wait.time",
        "itemsPath": "$",
        "paging": {"profile": "none"},
        "retry": {"profile": "rateLimitAware"},
        "redactionProfile": "standard",
        "validationStatus": "unvalidated"
    },

    # ── Authorization / Divisions ─────────────────────────────────────────────

    "authorization.search.division.objects": {
        "description": (
            "List all objects (queues, users, flows, etc.) assigned to a specific "
            "division. Filter by objectType=QUEUE to enumerate every queue in a "
            "division before fanning out queue-level analytics. The definitive "
            "source for division-to-queue mapping."
        ),
        "endpoint": "authorization.search.division.objects",
        "itemsPath": "$.entities",
        "paging": {"profile": "nextUri_default"},
        "retry": {"profile": "default"},
        "redactionProfile": "standard",
        "validationStatus": "unvalidated"
    },

    "authorization.get.division.grants": {
        "description": (
            "Access-control grants for a division — which subjects (users/roles) "
            "have which roles in this division. Used in division investigations to "
            "audit who has supervisory or admin access to a business unit's queues."
        ),
        "endpoint": "authorization.get.division.grants",
        "itemsPath": "$.entities",
        "paging": {"profile": "pageNumber_default"},
        "retry": {"profile": "default"},
        "redactionProfile": "standard",
        "validationStatus": "unvalidated"
    },

    # ── Workforce Management ──────────────────────────────────────────────────

    "workforce.get.agent.management.unit": {
        "description": (
            "Look up the WFM management unit for a specific agent by agentId. "
            "Returns managementUnitId and businessUnitId — used as the seed to "
            "retrieve schedule, adherence, and time-off data in the agent "
            "investigation WFM steps."
        ),
        "endpoint": "getWorkforcemanagementAgentManagementunit",
        "itemsPath": "$",
        "paging": {"profile": "none"},
        "retry": {"profile": "default"},
        "redactionProfile": "standard",
        "validationStatus": "unvalidated"
    },

    "workforce.get.adherence.bulk": {
        "description": (
            "Current schedule adherence state for one or more agents — "
            "adherenceState (In Adherence / Out of Adherence), adherencePct, "
            "impact (Positive / Negative), and scheduledActivityCategory. "
            "Accepts a list of userIds as query parameters; no window required."
        ),
        "endpoint": "getWorkforcemanagementAdherence",
        "itemsPath": "$",
        "paging": {"profile": "none"},
        "retry": {"profile": "default"},
        "redactionProfile": "standard",
        "validationStatus": "unvalidated"
    },

    # ── External Contacts (CRM enrichment) ───────────────────────────────────

    "externalcontacts.get.contact.details": {
        "description": (
            "External contact (CRM customer) profile — name, company, phone, email, "
            "and any custom schema fields. Join to a conversation via the "
            "externalContactId carried on the external participant in "
            "conversations.get.conversation.object."
        ),
        "endpoint": "getExternalcontactsContact",
        "itemsPath": "$",
        "paging": {"profile": "none"},
        "retry": {"profile": "rateLimitAware"},
        "redactionProfile": "agent-investigation-users",
        "validationStatus": "unvalidated"
    },

    "externalcontacts.get.contact.journey.sessions": {
        "description": (
            "All digital journey sessions associated with an external contact — "
            "web sessions, app sessions, and inbound events. Join on contactId "
            "from externalcontacts.get.contact.details; enriches conversation "
            "investigations with pre-contact web behaviour."
        ),
        "endpoint": "getExternalcontactsContactJourneySessions",
        "itemsPath": "$.entities",
        "paging": {"profile": "nextUri_default"},
        "retry": {"profile": "rateLimitAware"},
        "redactionProfile": "standard",
        "validationStatus": "unvalidated"
    },
}


# ── New investigation recipes ──────────────────────────────────────────────────

NEW_INVESTIGATION_RECIPES = {

    "campaign-investigation": {
        "description": (
            "End-to-end investigation of an outbound dialing campaign — configuration, "
            "contact list, diagnostics, dialer events, conversation analytics, and audit "
            "trail. Used by outbound operations managers to diagnose low reach rates, "
            "abandoned-call threshold violations, and campaign pacing issues."
        ),
        "subjectParam": "campaignId",
        "windowRequired": True,
        "steps": [
            {
                "step": "campaign-config",
                "dataset": "outbound.get.campaigns",
                "role": "seed",
                "filterBy": "campaignId",
                "joinKey": "id",
                "provides": "name, status, dialingMode, queueId, callerIdName, abandonRate threshold",
                "description": "Campaign configuration — dialing mode, queue, caller ID, and abandon threshold"
            },
            {
                "step": "contact-list",
                "dataset": "outbound.get.contact.lists",
                "filterBy": "contactListId (from campaign-config)",
                "joinKey": "contactListId",
                "provides": "contactList name, size, importStatus",
                "description": "Contact list identity and size — used to compute list penetration rate"
            },
            {
                "step": "queue-config",
                "dataset": "routing.get.single.queue.config",
                "filterBy": "queueId (from campaign-config)",
                "joinKey": "queueId",
                "provides": "queue name, mediaSettings, ACW settings",
                "description": "Inbound answer queue configuration for context on how calls are handled"
            },
            {
                "step": "diagnostics",
                "dataset": "outbound.get.campaign.diagnostics.summary",
                "filterBy": "campaignId",
                "joinKey": "campaignId",
                "provides": "abandonRate, dialingInProgress, numberOfCalls, progress",
                "description": "Live diagnostics snapshot — pacing health and real-time abandon rate"
            },
            {
                "step": "dialer-events",
                "dataset": "outbound.get.events",
                "filterBy": "campaignId",
                "joinKey": "campaignId",
                "provides": "contactDispositions, callAttempts, systemEvents",
                "description": "Dialer event stream — contact dispositions, call attempts, and system events"
            },
            {
                "step": "audit-changes",
                "dataset": "audit-logs",
                "filterBy": "EntityType=Campaign + EntityId=campaignId",
                "joinKey": "campaignId",
                "provides": "configChanges, startStop events, actor, timestamp",
                "description": "Audit trail for campaign changes — who started/stopped it and what was changed"
            },
            {
                "step": "conversation-analytics",
                "dataset": "analytics-conversation-details-query",
                "filterBy": "campaignId + investigation window",
                "joinKey": "campaignId",
                "provides": "conversationId, agentId, tTalk, tHandle, wrapUpCode, connectTime",
                "description": "Conversation analytics rows tied to this campaign in the window"
            }
        ],
        "joinSequence": "seed (campaign-config) → contact-list (contactListId) → queue-config (queueId) → diagnostics → dialer-events → conversation-analytics",
        "executiveMetrics": [
            "contactsDialed",
            "rightPartyContactRate%",
            "abandonRate%",
            "avgHandleTime",
            "listPenetration% = contactsDialed / totalContacts",
            "campaignProgress%",
            "dispositionBreakdown (by outcome)"
        ]
    },

    "real-time-operations-monitoring": {
        "description": (
            "Point-in-time snapshot of the entire contact centre — queue depths, "
            "agent availability, active call counts, IVR flow executions, and "
            "trunk utilisation. No historical window required; designed for polling "
            "at 10-30 second intervals for wall-board and NOC displays."
        ),
        "subjectParam": "none (organisation-wide)",
        "windowRequired": False,
        "steps": [
            {
                "step": "queue-observations",
                "dataset": "analytics.query.queue.observations.real.time.stats",
                "role": "seed",
                "joinKey": "queueId",
                "provides": "oInteracting, oWaiting, oOnQueueUsers, oOffQueueUsers, oAlerting per queue",
                "description": "Live queue counters for every active queue — the primary wall-board data source"
            },
            {
                "step": "conversation-activity",
                "dataset": "analytics.query.conversation.activity.real.time",
                "joinKey": "queueId",
                "provides": "oInteracting, oWaiting, oLongestWaiting, oAlerting per queue × mediaType",
                "description": "Real-time conversation activity with longest-wait indicator"
            },
            {
                "step": "user-observations",
                "dataset": "analytics.query.user.observations.real.time.status",
                "joinKey": "userId",
                "provides": "oUserPresence, oUserRoutingStatus per agent",
                "description": "Live presence and routing status for all agents"
            },
            {
                "step": "estimated-wait-times",
                "dataset": "routing.get.queue.estimated.wait.time",
                "filterBy": "queueId (iterate per queue)",
                "joinKey": "queueId",
                "provides": "estimatedWaitTimeSeconds by mediaType",
                "description": "EWT per queue — caller-facing wait forecast for real-time SLA alerting"
            },
            {
                "step": "flow-observations",
                "dataset": "analytics.query.flow.observations",
                "joinKey": "flowId",
                "provides": "oFlow (active flows in execution), oFlowDisconnect",
                "description": "Real-time IVR and bot flow execution counts"
            },
            {
                "step": "trunk-metrics",
                "dataset": "telephony.get.trunk.metrics.summary",
                "joinKey": "trunkId",
                "provides": "currentCalls, maxConcurrentCalls, inService, errors",
                "description": "SIP trunk utilisation and error counters — telephony NOC view"
            },
            {
                "step": "edge-status",
                "dataset": "telephony.get.edges",
                "joinKey": "edgeId",
                "provides": "statusCode, onlineStatus, name, site",
                "description": "Edge appliance registration and connectivity status"
            },
            {
                "step": "active-alerts",
                "dataset": "alerting.get.alerts",
                "joinKey": "alertId",
                "provides": "alertType, metricType, value, ruleId",
                "description": "Currently firing threshold alerts — confirms automated detection is working"
            },
            {
                "step": "agent-drilldown",
                "dataset": "analytics.get.agent.active.status",
                "filterBy": "userId (targeted — supervisor clicks on an agent)",
                "joinKey": "userId",
                "provides": "activeChannels, currentConversationIds, routingStatus",
                "description": "Detailed live session for one agent — triggered by supervisor drilldown"
            }
        ],
        "joinSequence": "seed (queue-observations) → conversation-activity (queueId) → user-observations → flow-observations → trunk-metrics → active-alerts",
        "pollingNote": (
            "All steps except agent-drilldown return point-in-time state. "
            "Poll the first five steps at 10-30 second intervals for wall-board. "
            "agent-drilldown is on-demand; trunk-metrics and edge-status can poll "
            "at 60-second intervals."
        ),
        "executiveMetrics": [
            "oWaiting (total across all queues)",
            "oInteracting (total active conversations)",
            "oOnQueueUsers (staffed agents)",
            "EWT vs SLA target (breach indicator)",
            "trunk utilisation% = currentCalls / maxConcurrentCalls",
            "activeAlertsCount",
            "longestWaiting seconds"
        ]
    }
}


# ── New voice engineer playbooks ──────────────────────────────────────────────

NEW_VOICE_ENGINEER_PLAYBOOKS = {

    "edge-log-extraction": {
        "description": (
            "Extract and download diagnostic logs from a specific Edge appliance for "
            "deep packet and signalling analysis. Used when SIP traces alone are "
            "insufficient and raw Edge logs (pcap, sys-log) are needed for trunk or "
            "codec issue forensics."
        ),
        "subjectParam": "edgeId",
        "datasetsInOrder": [
            "telephony.get.edges",
            "telephony.create.edge.logs.job",
            "telephony.get.edge.logs.job",
            "telephony.request.edge.logs.job.upload",
            "telephony.get.edge.performance.metrics"
        ],
        "workflowSteps": [
            "1. telephony.get.edges — confirm the target Edge is ACTIVE and identify its site",
            "2. telephony.create.edge.logs.job — POST to create a log job, specifying logLevel and time window",
            "3. telephony.get.edge.logs.job — poll until jobStatus = COMPLETE",
            "4. telephony.request.edge.logs.job.upload — trigger S3 upload of selected log files",
            "5. telephony.get.edge.performance.metrics — capture CPU/memory/call-count at extraction time"
        ],
        "diagnosticSignals": [
            "Edge statusCode != 'ACTIVE' before log job → Edge may be in failover; confirm peer Edge state",
            "Log job stays in PENDING > 5 min → Edge management-plane connectivity issue",
            "CPU > 80% in performance metrics → Edge under load during the incident window",
            "Pcap shows RTP stream gaps → one-way audio or media negotiation failure",
            "Sys-log shows 'TLS handshake failed' → certificate or cipher mismatch on PSTN trunk"
        ],
        "enrichWith": [
            "telephony.get.sip.messages.for.conversation (correlate Edge log timestamps to SIP trace)",
            "alerting.get.alerts (confirm whether Edge health alerts were firing during the incident)"
        ]
    },

    "byoi-conversation-injection-forensics": {
        "description": (
            "Investigate a BYOI-injected conversation — confirm injection metadata, "
            "provider-set custom attributes, and Genesys-side handling quality. "
            "Used when a conversation originated in an external system and was "
            "injected via POST /api/v2/conversations/providers/{providerId}/calls."
        ),
        "subjectParam": "conversationId",
        "datasetsInOrder": [
            "conversations.get.conversation.object",
            "conversations.get.conversation.customattributes",
            "conversations.search.participant.attributes",
            "analytics.get.single.conversation.analytics",
            "telephony.get.sip.messages.for.conversation",
            "conversations.get.recordings",
            "quality.get.evaluations.query"
        ],
        "identificationChecks": [
            "conversations.get.conversation.object: externalTag is non-null → BYOI confirmed",
            "conversations.get.conversation.object: participants[].purpose = 'external' and externalContactId set → CRM link present",
            "conversations.get.conversation.customattributes: provider-set keys (CRM case ID, external call ID) should be present"
        ],
        "diagnosticSignals": [
            "externalTag null but externalConversationId set → partial injection; provider did not set tag",
            "Custom attributes absent → provider call to POST /providers/{id}/calls did not include attributes payload",
            "SIP trace shows provider SIP-to-SIP handoff with wrong DNIS → IVR routing misconfiguration at provider",
            "analytics tTalk = 0 with originatingDirection = 'inbound' → conversation injected but never answered",
            "Recording absent → edge recording policy not applied to injected conversations; check recording rules",
            "Evaluation absent → QM programme not covering injected media type or queue"
        ],
        "enrichWith": [
            "externalcontacts.get.contact.details (retrieve full CRM contact if externalContactId is present)",
            "conversations.get.conversation.summaries (AI summary if Copilot is enabled for injected conversations)"
        ]
    }
}


# ── New executive reporting playbooks ─────────────────────────────────────────

NEW_EXECUTIVE_REPORTING_PLAYBOOKS = {

    "executive-csat-sentiment-rollup": {
        "description": (
            "Combined voice-of-customer executive rollup — CSAT/NPS survey scores, "
            "S&TA sentiment trends, and topic frequency. Answers: are customers "
            "satisfied, is sentiment improving or declining, and what topics are "
            "driving negative sentiment? Designed for weekly/monthly executive review."
        ),
        "datasetsInOrder": [
            "analytics.query.surveys.aggregates",
            "quality.get.agents.activity",
            "analytics.post.transcripts.aggregates.query",
            "speechandtextanalytics.get.topics"
        ],
        "joinOn": "queueId or userId",
        "groupBy": ["queueId", "userId", "topicId", "surveyFormId"],
        "granularity": "P1D (daily over reporting window)",
        "outputMetrics": [
            "nSurveys (response count)",
            "avgCsatScore (1-5 normalised)",
            "avgNpsScore (0-10)",
            "promoterRate% = promoterCount / nSurveys",
            "detractorRate% = detractorCount / nSurveys",
            "nAnalyzedConversations (STA coverage)",
            "avgCustomerSentimentScore (STA)",
            "sentimentTrend (week-over-week delta)",
            "topTopics by nConversations",
            "evalAvgScore (QM correlation with CSAT)"
        ],
        "executivePresentation": (
            "CSAT/NPS trend line + sentiment heatmap by queue; "
            "top-5 topics by volume with average sentiment score; "
            "flag queues where CSAT < threshold and sentiment declining week-over-week"
        ),
        "enrichWith": [
            "routing-queues (to resolve queueId to queue name and division)",
            "speechandtextanalytics.get.conversation.categories (for per-conversation category distribution)"
        ]
    },

    "external-contact-enrichment-analysis": {
        "description": (
            "Enrich conversation investigations with CRM external contact data — "
            "links Genesys conversations to customer profiles, company relationships, "
            "and prior journey sessions. Used when contact centre data needs to be "
            "correlated with CRM records for case management or repeat-contact analysis."
        ),
        "datasetsInOrder": [
            "analytics-conversation-details-query",
            "externalcontacts.get.contact.details",
            "externalcontacts.get.contact.journey.sessions",
            "conversations.get.conversation.object",
            "conversations.get.conversation.customattributes"
        ],
        "joinOn": "externalContactId (from conversation participants[].externalContactId)",
        "groupBy": ["externalContactId", "queueId"],
        "outputMetrics": [
            "contactName, company, primaryPhone",
            "conversationCount (repeat contacts)",
            "journeySessionCount (digital pre-contact events)",
            "totalHandleTime across all interactions",
            "customAttributeValues (IVR/flow-captured data)",
            "firstContactResolution% (derived: conversations with only one interaction)"
        ],
        "executivePresentation": (
            "Repeat-contact heat map by external contact; "
            "CRM company breakdown with conversation volumes; "
            "first-contact resolution rate by queue"
        ),
        "enrichWith": [
            "quality.get.evaluations.query (QM scores for this contact's conversations)",
            "quality.get.surveys (CSAT responses linked to this contact's conversations)"
        ]
    }
}


def main():
    print(f"Loading catalog from {CATALOG_PATH} …")
    with open(CATALOG_PATH, "r", encoding="utf-8") as f:
        catalog = json.load(f)

    existing_datasets = set(catalog["datasets"].keys())
    new_keys = set(NEW_DATASETS.keys())
    overlap = existing_datasets & new_keys
    if overlap:
        print(f"  WARNING: {len(overlap)} dataset key(s) already exist and will be skipped: {overlap}")
        for k in overlap:
            del NEW_DATASETS[k]

    print(f"  Adding {len(NEW_DATASETS)} new dataset entries …")
    catalog["datasets"].update(NEW_DATASETS)

    # ── investigationRecipes ────────────────────────────────────────────────
    existing_recipes = set(catalog["combinations"]["investigationRecipes"].keys())
    new_recipe_keys = set(NEW_INVESTIGATION_RECIPES.keys())
    recipe_overlap = existing_recipes & new_recipe_keys
    if recipe_overlap:
        print(f"  WARNING: {len(recipe_overlap)} recipe(s) already exist and will be skipped: {recipe_overlap}")
        for k in recipe_overlap:
            del NEW_INVESTIGATION_RECIPES[k]

    print(f"  Adding {len(NEW_INVESTIGATION_RECIPES)} new investigationRecipes …")
    catalog["combinations"]["investigationRecipes"].update(NEW_INVESTIGATION_RECIPES)

    # ── voiceEngineerPlaybooks ──────────────────────────────────────────────
    existing_ve = set(catalog["combinations"]["voiceEngineerPlaybooks"].keys())
    new_ve_keys = set(NEW_VOICE_ENGINEER_PLAYBOOKS.keys())
    ve_overlap = existing_ve & new_ve_keys
    if ve_overlap:
        print(f"  WARNING: {len(ve_overlap)} voice-engineer playbook(s) already exist and will be skipped: {ve_overlap}")
        for k in ve_overlap:
            del NEW_VOICE_ENGINEER_PLAYBOOKS[k]

    print(f"  Adding {len(NEW_VOICE_ENGINEER_PLAYBOOKS)} new voiceEngineerPlaybooks …")
    catalog["combinations"]["voiceEngineerPlaybooks"].update(NEW_VOICE_ENGINEER_PLAYBOOKS)

    # ── executiveReportingPlaybooks ─────────────────────────────────────────
    existing_exec = set(catalog["combinations"]["executiveReportingPlaybooks"].keys())
    new_exec_keys = set(NEW_EXECUTIVE_REPORTING_PLAYBOOKS.keys())
    exec_overlap = existing_exec & new_exec_keys
    if exec_overlap:
        print(f"  WARNING: {len(exec_overlap)} executive playbook(s) already exist and will be skipped: {exec_overlap}")
        for k in exec_overlap:
            del NEW_EXECUTIVE_REPORTING_PLAYBOOKS[k]

    print(f"  Adding {len(NEW_EXECUTIVE_REPORTING_PLAYBOOKS)} new executiveReportingPlaybooks …")
    catalog["combinations"]["executiveReportingPlaybooks"].update(NEW_EXECUTIVE_REPORTING_PLAYBOOKS)

    # ── Update metadata ─────────────────────────────────────────────────────
    catalog["version"] = "1.1.0"
    from datetime import datetime, timezone
    catalog["generatedAt"] = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.0000000Z")

    print(f"  Writing updated catalog …")
    with open(CATALOG_PATH, "w", encoding="utf-8") as f:
        json.dump(catalog, f, indent=2, ensure_ascii=False)
        f.write("\n")

    # ── Final counts ────────────────────────────────────────────────────────
    final_datasets = len(catalog["datasets"])
    final_recipes = len(catalog["combinations"]["investigationRecipes"])
    final_ve = len(catalog["combinations"]["voiceEngineerPlaybooks"])
    final_exec = len(catalog["combinations"]["executiveReportingPlaybooks"])

    print(f"\nDone.")
    print(f"  datasets:                  {final_datasets} total")
    print(f"  investigationRecipes:      {final_recipes} total")
    print(f"  voiceEngineerPlaybooks:    {final_ve} total")
    print(f"  executiveReportingPlaybooks: {final_exec} total")


if __name__ == "__main__":
    main()
