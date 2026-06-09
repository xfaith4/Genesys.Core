#!/usr/bin/env python3
"""
update-catalog-additions.py
Adds new dataset entries and combination entries to genesys.catalog.json.
"""

import json

CATALOG_PATH = "/home/user/Genesys.Core/catalog/genesys.catalog.json"

# ---------------------------------------------------------------------------
# New dataset entries
# ---------------------------------------------------------------------------
NEW_DATASETS = {
    "speechandtextanalytics.get.conversation.categories": {
        "description": "S&TA topic and category classifications for a single conversation — category names, scores, and matched phrase evidence.",
        "endpoint": "speechandtextanalytics.get.conversation.categories",
        "itemsPath": "$.categories",
        "paging": {"profile": "none"},
        "retry": {"profile": "rateLimitAware"},
        "redactionProfile": "conversation-sentiment",
        "validationStatus": "unvalidated"
    },
    "speechandtextanalytics.get.conversation.summaries.detail": {
        "description": "AI-generated conversation summaries per communication leg — used for rapid content review without listening to the recording.",
        "endpoint": "speechandtextanalytics.get.conversation.summaries.detail",
        "itemsPath": "$.summaries",
        "paging": {"profile": "none"},
        "retry": {"profile": "rateLimitAware"},
        "redactionProfile": "conversation-sentiment",
        "validationStatus": "unvalidated"
    },
    "conversations.get.conversation.summaries": {
        "description": "Conversation-level AI summaries — structured summary with resolution status, follow-up items, and reason codes.",
        "endpoint": "conversations.get.conversation.summaries",
        "itemsPath": "$.summaries",
        "paging": {"profile": "none"},
        "retry": {"profile": "rateLimitAware"},
        "redactionProfile": "conversation-sentiment",
        "validationStatus": "unvalidated"
    },
    "conversations.get.conversation.participant.wrapup": {
        "description": "Wrapup code and notes for a single participant in a conversation — use to retrieve per-agent wrapup without reloading the full conversation object.",
        "endpoint": "conversations.get.conversation.participant.wrapup",
        "itemsPath": "$",
        "paging": {"profile": "none"},
        "retry": {"profile": "rateLimitAware"},
        "redactionProfile": "standard",
        "validationStatus": "unvalidated"
    },
    "conversations.get.call.detail": {
        "description": "Voice-specific call detail for a conversation — hold events, mute events, ANI/DNIS routing path, and call leg duration. Complements analytics.get.single.conversation.analytics for voice deep-dive.",
        "endpoint": "conversations.get.call.detail",
        "itemsPath": "$",
        "paging": {"profile": "none"},
        "retry": {"profile": "rateLimitAware"},
        "redactionProfile": "agent-investigation-conversations",
        "validationStatus": "unvalidated"
    },
    "authorization.get.division.grants": {
        "description": "Access control grants for a division — who has what role in this division. Used in division investigation to understand permission scope.",
        "endpoint": "authorization.get.division.grants",
        "itemsPath": "$.entities",
        "paging": {"profile": "nextUri_default"},
        "retry": {"profile": "default"},
        "validationStatus": "unvalidated"
    },
    "externalcontacts.get.contact": {
        "description": "Single external contact record — name, phone, email, external organization linkage, and custom schema fields. Join on externalContactId from conversation participants.",
        "endpoint": "getExternalcontactsContact",
        "itemsPath": "$",
        "paging": {"profile": "none"},
        "retry": {"profile": "rateLimitAware"},
        "redactionProfile": "agent-investigation-users",
        "validationStatus": "unvalidated"
    },
    "externalcontacts.get.contact.journey.sessions": {
        "description": "Journey sessions for an external contact — web and app sessions the customer had before and after a conversation. Provides cross-channel context: pages visited, actions taken, outcomes scored.",
        "endpoint": "getExternalcontactsContactJourneySessions",
        "itemsPath": "$.entities",
        "paging": {"profile": "nextUri_default"},
        "retry": {"profile": "rateLimitAware"},
        "redactionProfile": "standard",
        "validationStatus": "unvalidated"
    },
    "externalcontacts.get.organization": {
        "description": "External organization record — company name, industry, address, and linked contacts. Use when conversation participant is linked to an externalOrganizationId.",
        "endpoint": "getExternalcontactsOrganization",
        "itemsPath": "$",
        "paging": {"profile": "none"},
        "retry": {"profile": "rateLimitAware"},
        "redactionProfile": "standard",
        "validationStatus": "unvalidated"
    },
    "recording.post.batch.request": {
        "description": "Submit a batch recording download request — provide a list of conversationId/recordingId pairs and receive a jobId for polling. Required for bulk QM recording retrieval workflows.",
        "endpoint": "postRecordingBatchrequests",
        "itemsPath": "$",
        "paging": {"profile": "none"},
        "retry": {"profile": "rateLimitAware"},
        "transaction": {"profile": "recording_batch"},
        "validationStatus": "unvalidated"
    },
    "recording.get.batch.request": {
        "description": "Poll a batch recording request job and retrieve signed download URLs — returns per-recording status and time-limited download URLs once the job completes.",
        "endpoint": "getRecordingBatchrequest",
        "itemsPath": "$.results",
        "paging": {"profile": "none"},
        "retry": {"profile": "rateLimitAware"},
        "validationStatus": "unvalidated"
    },
    "journey.get.session": {
        "description": "Full journey session detail — session type (web, app, BYOI), customer identity, duration, channel, outcome scores, and originating app/site. Seed step for customer journey investigation.",
        "endpoint": "getJourneySession",
        "itemsPath": "$",
        "paging": {"profile": "none"},
        "retry": {"profile": "rateLimitAware"},
        "redactionProfile": "standard",
        "validationStatus": "unvalidated"
    },
    "journey.get.session.events": {
        "description": "Ordered event timeline for a journey session — page views, clicks, form submissions, segment qualifications, and action-map triggers. Use to reconstruct the customer journey before a call.",
        "endpoint": "getJourneySessionEvents",
        "itemsPath": "$.entities",
        "paging": {"profile": "nextUri_default"},
        "retry": {"profile": "rateLimitAware"},
        "redactionProfile": "standard",
        "validationStatus": "unvalidated"
    },
    "routing.get.queue.estimated.wait.time": {
        "description": "Current estimated wait time for a queue — what the system is telling customers the expected wait is. Use to correlate EWT accuracy against actual tAbandon and oLongestWaiting.",
        "endpoint": "routing.get.queue.estimated.wait.time",
        "itemsPath": "$",
        "paging": {"profile": "none"},
        "retry": {"profile": "rateLimitAware"},
        "validationStatus": "unvalidated"
    },
    "routing.get.predictors": {
        "description": "Predictive routing predictor configurations — the ML models and KPIs used to score and match agents to conversations. Use to understand the routing logic applied to a conversation.",
        "endpoint": "getRoutingPredictors",
        "itemsPath": "$.entities",
        "paging": {"profile": "pageNumber_default"},
        "retry": {"profile": "default"},
        "validationStatus": "unvalidated"
    },
    "workforce.post.historical.adherence.query": {
        "description": "Historical schedule adherence for agents in a WFM management unit — actual vs. scheduled state per agent over a time window. Use to determine whether an agent was on schedule during a conversation.",
        "endpoint": "postWorkforcemanagementManagementunitHistoricaladherencequery",
        "itemsPath": "$.userScheduleAdherenceList",
        "paging": {"profile": "none"},
        "retry": {"profile": "rateLimitAware"},
        "redactionProfile": "agent-investigation-activity",
        "validationStatus": "unvalidated"
    },
    "workforce.search.agent.schedules": {
        "description": "Search scheduled shifts for agents in a WFM management unit — returns shift start/end times, activity codes, and meeting events. Join on userId to overlay schedule against conversation handle times.",
        "endpoint": "postWorkforcemanagementManagementunitAgentschedulesSearch",
        "itemsPath": "$.userSchedules",
        "paging": {"profile": "none"},
        "retry": {"profile": "rateLimitAware"},
        "redactionProfile": "agent-investigation-activity",
        "validationStatus": "unvalidated"
    },
}

# ---------------------------------------------------------------------------
# New investigationRecipes entries
# ---------------------------------------------------------------------------
NEW_INVESTIGATION_RECIPES = {
    "customer-journey-investigation": {
        "description": "Cross-channel investigation of a single customer — enriches a conversation with the customer's external contact record, pre-call web/app journey, conversation history, analytics detail, and evaluations. Answers: who is this customer, what did they do before calling, and how was this interaction handled?",
        "subjectParam": "conversationId (with externalContactId resolved from participants)",
        "windowRequired": False,
        "steps": [
            {
                "step": "conversation-base",
                "dataset": "conversations.get.conversation.object",
                "role": "seed",
                "joinKey": "conversationId",
                "provides": "participants[].externalContactId, externalOrganizationId, ANI, DNIS, mediaType",
                "description": "Seed step — retrieves the conversation and extracts externalContactId from participants"
            },
            {
                "step": "external-contact",
                "dataset": "externalcontacts.get.contact",
                "filterBy": "externalContactId (from participants)",
                "joinKey": "externalContactId",
                "provides": "name, phone, email, externalOrganizationId, customFields",
                "description": "Customer identity from CRM — confirms who the customer is and links to their organisation"
            },
            {
                "step": "external-organization",
                "dataset": "externalcontacts.get.organization",
                "filterBy": "externalOrganizationId (from external-contact)",
                "joinKey": "externalOrganizationId",
                "provides": "companyName, industry, address",
                "description": "Organisation record — context for B2B interactions. Optional; skip if contact has no org linkage.",
                "optional": True
            },
            {
                "step": "journey-sessions",
                "dataset": "externalcontacts.get.contact.journey.sessions",
                "filterBy": "externalContactId",
                "joinKey": "externalContactId",
                "provides": "sessionId list, sessionType, channel, duration, outcomeScores",
                "description": "All journey sessions for this contact — select sessions close to conversation start time"
            },
            {
                "step": "journey-events",
                "dataset": "journey.get.session.events",
                "filterBy": "sessionId (from pre-call journey sessions)",
                "joinKey": "sessionId",
                "provides": "pageViews, clicks, formSubmissions, actionMapTriggers",
                "description": "Event timeline for the most-recent pre-call journey session — what the customer did on the website before calling"
            },
            {
                "step": "analytics-detail",
                "dataset": "analytics.get.single.conversation.analytics",
                "filterBy": "conversationId",
                "joinKey": "conversationId",
                "provides": "tIvr, tAcd, tTalk, tHeld, tAcw, tHandle, segments",
                "description": "Full timing breakdown for the conversation"
            },
            {
                "step": "evaluation",
                "dataset": "quality.get.evaluations.query",
                "filterBy": "conversationId",
                "joinKey": "conversationId",
                "provides": "evaluationScore, formName, evaluator, criticalItemFailed",
                "description": "QM evaluation if the conversation was scored. Optional; not all conversations are evaluated.",
                "optional": True
            },
            {
                "step": "survey",
                "dataset": "quality.get.surveys",
                "filterBy": "conversationId",
                "joinKey": "conversationId",
                "provides": "csatScore, npsScore, surveyStatus",
                "description": "Post-call survey result if a survey was triggered. Optional.",
                "optional": True
            }
        ],
        "joinSequence": "conversation-base (conversationId) → external-contact (externalContactId) → external-organization (externalOrganizationId) → journey-sessions (externalContactId) → journey-events (sessionId) → analytics-detail (conversationId) → evaluation (conversationId) → survey (conversationId)",
        "executiveMetrics": [
            "customerName", "organizationName", "preCallSessionCount", "preCallPageViews",
            "tHandle", "evaluationScore", "csatScore"
        ],
        "diagnosticSignals": [
            "externalContactId null in all participants → BYOI or anonymous contact; use ANI reverse-lookup via getExternalcontactsReversewhitepageslookup",
            "journey-sessions empty but externalContactId present → customer has no web journey or Genesys Journey is not deployed",
            "actionMapTrigger in journey events → predictive engagement fired; check if queue and timing matched what the customer reached",
            "multiple journey sessions in 24h before call → repeated self-service attempts before escalating; high-effort customer"
        ]
    },
    "recording-access-workflow": {
        "description": "QM and compliance recording retrieval workflow — from conversation identification to bulk signed-URL download. Use when you need the actual audio/video content, not just recording metadata.",
        "subjectParam": "queueId, agentUserId, or conversationId list",
        "windowRequired": True,
        "steps": [
            {
                "step": "conversation-list",
                "dataset": "analytics-conversation-details-query",
                "role": "seed",
                "joinKey": "conversationId",
                "provides": "conversationId list with mediaType filter",
                "description": "Retrieve conversation IDs for the target queue/agent/window — source of the recording request list"
            },
            {
                "step": "recording-metadata",
                "dataset": "conversations.get.conversation.recording.metadata",
                "filterBy": "conversationId (per conversation from seed)",
                "joinKey": "conversationId",
                "provides": "recordingId, mediaType, duration, archivalStatus, policyName, deleteDate",
                "description": "Recording metadata — confirms recordings exist and are not yet archived/deleted. Filter out conversations with no recordings or ERROR fileState before building the batch request."
            },
            {
                "step": "batch-request",
                "dataset": "recording.post.batch.request",
                "filterBy": "conversationId + recordingId pairs from recording-metadata",
                "joinKey": "jobId",
                "provides": "jobId for polling",
                "description": "Submit batch recording download request with conversationId/recordingId pairs. Returns jobId."
            },
            {
                "step": "batch-results",
                "dataset": "recording.get.batch.request",
                "filterBy": "jobId from batch-request",
                "joinKey": "jobId",
                "provides": "signedDownloadUrl, fileSize, recordingId per result",
                "description": "Poll batch job until FULFILLED. Returns time-limited signed download URLs (15-second validity window — initiate download immediately)."
            }
        ],
        "joinSequence": "conversation-list → recording-metadata (conversationId) → batch-request (conversationId + recordingId list) → batch-results (jobId)",
        "operationalNotes": [
            "Signed URLs expire 15 seconds after generation — the download must START within that window, not complete",
            "Maximum batch size is 100 recordings per request; fan out for larger sets",
            "Recordings in DELETED or PURGED state will not return a signed URL",
            "ARCHIVED recordings require a restore request before batch download is possible"
        ],
        "diagnosticSignals": [
            "recording-metadata returns empty for a conversationId → recording policy not configured for the queue or consent was declined",
            "recording.fileState = ERROR → edge storage issue; check audit-logs (service=Recording) for policy errors",
            "batch-results shows recordingId MISSING status → recording was deleted or purged after the conversation ended"
        ]
    },
    "wfm-adherence-investigation": {
        "description": "Workforce schedule adherence investigation for an agent — overlays scheduled shifts against actual presence and conversation activity to determine whether schedule gaps explain performance issues. Answers: was the agent on schedule, and if not, when and by how much?",
        "subjectParam": "userId + managementUnitId",
        "windowRequired": True,
        "steps": [
            {
                "step": "identity",
                "dataset": "users.get.user.details.with.full.expansion",
                "role": "seed",
                "joinKey": "userId",
                "provides": "name, email, department, manager",
                "description": "Agent identity — confirms the agent and retrieves their management unit assignment"
            },
            {
                "step": "management-unit",
                "dataset": "workforce.get.management.units",
                "filterBy": "managementUnitId (from agent's WFM assignment)",
                "joinKey": "managementUnitId",
                "provides": "managementUnitName, timeZone",
                "description": "WFM management unit metadata — timezone is critical for schedule alignment"
            },
            {
                "step": "scheduled-shifts",
                "dataset": "workforce.search.agent.schedules",
                "filterBy": "managementUnitId + userId + window",
                "joinKey": "userId",
                "provides": "scheduledStart, scheduledEnd, activityCode, mealBreaks, meetings",
                "description": "Planned schedule for the agent in the window — what shifts were they supposed to work"
            },
            {
                "step": "historical-adherence",
                "dataset": "workforce.post.historical.adherence.query",
                "filterBy": "managementUnitId + userId + window",
                "joinKey": "userId",
                "provides": "adherencePct, onTimePercent, scheduledSeconds, actualSeconds, activityExceptions",
                "description": "Actual vs. scheduled adherence — the delta between planned and actual presence states"
            },
            {
                "step": "presence-activity",
                "dataset": "analytics.query.user.details.activity.report",
                "filterBy": "userId + window",
                "joinKey": "userId",
                "provides": "presenceSegments, routingStatusSegments, tOnQueue, tOffQueue",
                "description": "Actual presence and routing-status timeline — reconcile with scheduled-shifts to identify off-schedule gaps"
            },
            {
                "step": "conversation-performance",
                "dataset": "analytics-conversation-details-query",
                "filterBy": "participantUserId + window",
                "joinKey": "userId",
                "provides": "conversationId, queueId, wrapUpCode, tHandle, tTalk, tAcw, mediaType",
                "description": "All conversations the agent handled in the window — overlay against scheduled-shifts to confirm on-queue time was productive"
            }
        ],
        "joinSequence": "identity (userId) → management-unit (managementUnitId) → scheduled-shifts (userId) → historical-adherence (userId) → presence-activity (userId) → conversation-performance (userId)",
        "derivedMetrics": [
            "adherencePct = scheduledSeconds with matching actual state / totalScheduledSeconds",
            "onQueuePercent = tOnQueue / totalScheduledSeconds",
            "offScheduleGapMinutes = sum of presence-activity gaps not in scheduled-shifts",
            "productiveOnQueuePercent = nConnected * avgTHandle / tOnQueue"
        ],
        "executiveMetrics": ["adherencePct", "onQueuePercent", "nConnected", "tHandle (avg)", "evalAvgScore"],
        "diagnosticSignals": [
            "adherencePct < 85% → agent is frequently off schedule; check presence-activity for off-queue patterns",
            "large gap between scheduled-shifts and presence-activity → unplanned absence or late login; check audit-logs",
            "high nConnected but low adherencePct → agent is handling calls but going off-queue between interactions",
            "presence-activity shows BUSY during a scheduled break → break timing is misaligned with WFM schedule"
        ]
    },
    "byoi-provider-conversation-investigation": {
        "description": "Enriched investigation for conversations injected via BYOI (Bring Your Own Integration) — identifies provider origin, retrieves injected context attributes, and reconciles the SIP handoff with Genesys analytics. Use when a conversation has a non-null externalTag.",
        "subjectParam": "conversationId",
        "windowRequired": False,
        "steps": [
            {
                "step": "conversation-base",
                "dataset": "conversations.get.conversation.object",
                "role": "seed",
                "joinKey": "conversationId",
                "provides": "externalTag, externalConversationId, participants[].externalContactId, participants[].purpose='external'",
                "description": "Base conversation — externalTag and externalConversationId confirm BYOI origin. Non-null externalTag is the definitive indicator."
            },
            {
                "step": "custom-attributes",
                "dataset": "conversations.get.conversation.customattributes",
                "filterBy": "conversationId",
                "joinKey": "conversationId",
                "provides": "provider-set custom attributes: CRM case ID, intent label, external call ID, priority score",
                "description": "Provider-injected attributes set at conversation creation — the CRM context the provider passed in"
            },
            {
                "step": "participant-attributes",
                "dataset": "conversations.search.participant.attributes",
                "filterBy": "conversationId",
                "joinKey": "conversationId",
                "provides": "IVR/Architect flow variables set during the injected conversation",
                "description": "Architect flow variables set after BYOI injection — data actions, intent parsing, routing decisions"
            },
            {
                "step": "analytics-detail",
                "dataset": "analytics.get.single.conversation.analytics",
                "filterBy": "conversationId",
                "joinKey": "conversationId",
                "provides": "tIvr, tAcd, tTalk, tHeld, tAcw, segments with originatingDirection",
                "description": "Segment timing — same as any conversation; originatingDirection='inbound' or 'outbound' confirms injection direction"
            },
            {
                "step": "sip-trace",
                "dataset": "telephony.get.sip.messages.for.conversation",
                "filterBy": "conversationId",
                "joinKey": "conversationId",
                "provides": "SIP INVITE/200 OK/BYE — reflects SIP-to-SIP handoff not PSTN leg",
                "description": "SIP signalling for BYOI — confirms the SIP handoff from the provider. The INVITE From/To headers will show the provider SIP URI, not a PSTN number."
            },
            {
                "step": "external-contact",
                "dataset": "externalcontacts.get.contact",
                "filterBy": "externalContactId (from participants)",
                "joinKey": "externalContactId",
                "provides": "customer name, org, contact history",
                "description": "External contact enrichment — available when the provider linked the contact to a Genesys external contact record",
                "optional": True
            },
            {
                "step": "recording-metadata",
                "dataset": "conversations.get.conversation.recording.metadata",
                "filterBy": "conversationId",
                "joinKey": "conversationId",
                "provides": "recordingId, mediaType, duration",
                "description": "Recording confirmation — BYOI conversations record identically to native conversations if the recording policy applies"
            }
        ],
        "joinSequence": "conversation-base → custom-attributes (conversationId) → participant-attributes (conversationId) → analytics-detail (conversationId) → sip-trace (conversationId) → external-contact (externalContactId) → recording-metadata (conversationId)",
        "byoiIndicators": [
            "conversations.get.conversation.object.externalTag non-null → BYOI conversation",
            "participants[].purpose='external' → provider-injected participant",
            "sip-trace INVITE From header contains provider SIP URI (not PSTN E.164) → confirms SIP handoff path",
            "custom-attributes contains CRM fields (caseId, customerId) set by provider at injection"
        ],
        "executiveMetrics": ["tHandle", "externalTag (provider ID)", "wrapUpCode", "evaluationScore"]
    },
}

# ---------------------------------------------------------------------------
# New executiveReportingPlaybooks entries
# ---------------------------------------------------------------------------
NEW_EXECUTIVE_REPORTING_PLAYBOOKS = {
    "workforce-efficiency-and-adherence": {
        "description": "WFM efficiency rollup — occupancy, adherence, and schedule utilisation across all agents in a management unit for a reporting period. Feeds workforce operations dashboards and WFM effectiveness reviews.",
        "datasetsInOrder": [
            "workforce.get.management.units",
            "workforce.get.management.unit.users",
            "workforce.post.historical.adherence.query",
            "analytics.query.user.aggregates.login.activity",
            "analytics.query.user.aggregates.performance.metrics"
        ],
        "joinOn": "userId",
        "groupBy": ["userId", "managementUnitId"],
        "granularity": "P1D or P1W",
        "outputMetrics": [
            "adherencePct (avg per agent)",
            "scheduledSeconds",
            "actualOnQueueSeconds",
            "onQueuePercent = tOnQueue / scheduledSeconds",
            "occupancyPct = nConnected * avgTHandle / tOnQueue",
            "nConnected",
            "avgHandleTime = tHandle / nConnected"
        ],
        "executivePresentation": "Workforce efficiency scorecard: adherence %, occupancy %, AHT by agent with management unit filter"
    },
    "digital-channel-volume-trends": {
        "description": "Multi-channel volume and efficiency trends — breaks down offered/connected/abandoned volume by media type (voice, chat, email, message) across queues. Used for channel strategy reviews and capacity planning.",
        "datasetsInOrder": [
            "routing-queues",
            "analytics.query.conversation.aggregates.digital.channels",
            "analytics.query.conversation.aggregates.queue.performance",
            "analytics.query.conversation.aggregates.abandon.metrics"
        ],
        "joinOn": "queueId + mediaType",
        "groupBy": ["queueId", "mediaType", "divisionId"],
        "granularity": "PT1H or P1D",
        "outputMetrics": [
            "nOffered by mediaType",
            "nConnected by mediaType",
            "nAbandoned by mediaType",
            "abandonRate% by mediaType = nAbandoned / nOffered",
            "avgHandleTime by mediaType = tHandle / nConnected",
            "channelMix% = nOffered[mediaType] / nOffered[total]"
        ],
        "executivePresentation": "Channel mix stacked bar (offered volume by mediaType, daily) + AHT comparison by channel"
    },
    "customer-experience-voice-of-customer": {
        "description": "CSAT, NPS, and sentiment rollup — surveys, quality scores, and speech analytics combined to give a single voice-of-customer view across queues and agents. The executive-level measure of customer experience quality.",
        "datasetsInOrder": [
            "quality.get.surveys",
            "quality.get.evaluations.query",
            "quality.get.agents.activity",
            "analytics.post.transcripts.aggregates.query",
            "speechandtextanalytics.get.topics"
        ],
        "joinOn": "agentUserId or queueId",
        "groupBy": ["agentUserId", "queueId"],
        "granularity": "P1W or P1M",
        "outputMetrics": [
            "avgCsatScore (1-5)",
            "avgNpsScore (0-10)",
            "surveyCompletionRate% = surveysCompleted / nConnected",
            "avgEvaluationScore%",
            "criticalItemFailRate%",
            "avgCustomerSentimentScore (from STA)",
            "topNegativeTopic (most frequent topic with negative sentiment)"
        ],
        "executivePresentation": "VoC scorecard: CSAT trend line + NPS bar + eval score by queue; sentiment heatmap by topic"
    },
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main():
    with open(CATALOG_PATH, "r", encoding="utf-8") as f:
        cat = json.load(f)

    # --- datasets ---
    datasets_before = len(cat["datasets"])
    for key, value in NEW_DATASETS.items():
        if key in cat["datasets"]:
            print(f"  [SKIP] dataset already exists: {key}")
        else:
            cat["datasets"][key] = value
    datasets_after = len(cat["datasets"])
    datasets_added = datasets_after - datasets_before

    # --- investigationRecipes ---
    recipes_before = len(cat["combinations"]["investigationRecipes"])
    for key, value in NEW_INVESTIGATION_RECIPES.items():
        if key in cat["combinations"]["investigationRecipes"]:
            print(f"  [SKIP] investigationRecipe already exists: {key}")
        else:
            cat["combinations"]["investigationRecipes"][key] = value
    recipes_after = len(cat["combinations"]["investigationRecipes"])
    recipes_added = recipes_after - recipes_before

    # --- executiveReportingPlaybooks ---
    playbooks_before = len(cat["combinations"]["executiveReportingPlaybooks"])
    for key, value in NEW_EXECUTIVE_REPORTING_PLAYBOOKS.items():
        if key in cat["combinations"]["executiveReportingPlaybooks"]:
            print(f"  [SKIP] executiveReportingPlaybook already exists: {key}")
        else:
            cat["combinations"]["executiveReportingPlaybooks"][key] = value
    playbooks_after = len(cat["combinations"]["executiveReportingPlaybooks"])
    playbooks_added = playbooks_after - playbooks_before

    # --- write ---
    with open(CATALOG_PATH, "w", encoding="utf-8") as f:
        f.write(json.dumps(cat, indent=2, ensure_ascii=False))
        f.write("\n")

    print(f"\nDone.")
    print(f"  datasets:                  {datasets_before} -> {datasets_after} (+{datasets_added})")
    print(f"  investigationRecipes:      {recipes_before} -> {recipes_after} (+{recipes_added})")
    print(f"  executiveReportingPlaybooks: {playbooks_before} -> {playbooks_after} (+{playbooks_added})")

if __name__ == "__main__":
    main()
