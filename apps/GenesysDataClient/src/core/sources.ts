/**
 * DataSource implementations - the only layer that understands Genesys payloads.
 *
 * Each source flattens a nested Genesys response into records the engine can filter, sort,
 * group and export generically. Adding an explorer to the application means adding a source
 * here, not building a screen.
 */

import type {
  DataRecord,
  DataSet,
  DataSource,
  FetchContext,
  FieldDefinition,
  QueryDefinition,
  RequestTrace,
} from './contracts';
import type { CoreClient } from './client';

// ─── Payload helpers ─────────────────────────────────────────────────────────

const asArray = (value: unknown): unknown[] => (Array.isArray(value) ? value : []);

const asObject = (value: unknown): Record<string, unknown> =>
  value !== null && typeof value === 'object' && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : {};

const str = (value: unknown): string =>
  value === null || value === undefined ? '' : typeof value === 'string' ? value : String(value);

const num = (value: unknown): number | null =>
  typeof value === 'number' && Number.isFinite(value) ? value : null;

const msBetween = (start: unknown, end: unknown): number | null => {
  const a = Date.parse(str(start));
  const b = Date.parse(str(end));
  if (Number.isNaN(a) || Number.isNaN(b)) return null;
  return b - a;
};

const unique = (values: string[]): string[] => [...new Set(values.filter((v) => v !== ''))];

/** Builds the DataSet envelope shared by every source. */
const makeDataSet = (
  sourceId: string,
  records: DataRecord[],
  fields: FieldDefinition[],
  traces: RequestTrace[],
  startedAt: number,
  warnings: string[] = [],
): DataSet => ({
  records,
  fields,
  meta: {
    sourceId,
    fetchedAt: new Date().toISOString(),
    durationMs: Math.round(performance.now() - startedAt),
    requests: traces,
    warnings,
  },
});

/**
 * Drives the Genesys async job lifecycle: submit, poll until FULFILLED, then read results.
 * The mock server reproduces the real QUEUED -> RUNNING -> FULFILLED progression.
 */
const runAsyncJob = async (
  client: CoreClient,
  options: {
    submitPath: string;
    submitBody: unknown;
    idProperty: string;
    statusPath: (id: string) => string;
    resultsPath: (id: string) => string;
    submitKey: string;
    pollKey: string;
    resultsKey: string;
    signal?: AbortSignal;
    maxPolls?: number;
  },
): Promise<{ jobId: string; traces: RequestTrace[]; results: unknown; warnings: string[] }> => {
  const traces: RequestTrace[] = [];
  const warnings: string[] = [];

  const submit = await client.post<Record<string, unknown>>(options.submitPath, options.submitBody, {
    signal: options.signal,
    endpointKey: options.submitKey,
  });
  traces.push({ ...submit.trace, note: 'submit job' });

  const jobId = str(submit.data?.[options.idProperty]);
  if (jobId === '') throw new Error(`Job submit did not return a '${options.idProperty}'.`);

  const maxPolls = options.maxPolls ?? 10;
  let state = '';
  for (let attempt = 0; attempt < maxPolls; attempt += 1) {
    const poll = await client.get<Record<string, unknown>>(options.statusPath(jobId), {
      signal: options.signal,
      endpointKey: options.pollKey,
    });
    state = str(poll.data?.state);
    traces.push({ ...poll.trace, note: `poll ${attempt + 1} -> ${state}` });
    if (state === 'FULFILLED') break;
    if (state === 'FAILED' || state === 'NOT_FOUND') {
      throw new Error(`Job ${jobId} ended in state ${state}.`);
    }
  }

  if (state !== 'FULFILLED') {
    warnings.push(`Job did not reach FULFILLED within ${maxPolls} polls (last state: ${state}).`);
  }

  const results = await client.get<unknown>(options.resultsPath(jobId), {
    signal: options.signal,
    endpointKey: options.resultsKey,
  });
  traces.push({ ...results.trace, note: 'results page 1' });

  return { jobId, traces, results: results.data, warnings };
};

// ─── Conversations ───────────────────────────────────────────────────────────

const CONVERSATION_FIELDS: FieldDefinition[] = [
  { key: 'conversationId', label: 'Conversation ID', type: 'string', width: 230 },
  { key: 'conversationStart', label: 'Start', type: 'date', width: 190 },
  { key: 'conversationEnd', label: 'End', type: 'date', width: 190, hiddenByDefault: true },
  { key: 'durationMs', label: 'Duration', type: 'duration', width: 110, align: 'right' },
  { key: 'direction', label: 'Direction', type: 'string', width: 100, facetable: true },
  { key: 'mediaTypes', label: 'Media', type: 'string', width: 110, facetable: true },
  { key: 'agentName', label: 'Agent', type: 'string', width: 160, facetable: true },
  { key: 'queueId', label: 'Queue', type: 'string', width: 200, facetable: true },
  { key: 'ani', label: 'ANI', type: 'string', width: 140 },
  { key: 'dnis', label: 'DNIS', type: 'string', width: 140 },
  { key: 'disconnectType', label: 'Disconnect', type: 'string', width: 120, facetable: true },
  { key: 'talkMs', label: 'Agent talk', type: 'duration', width: 110, align: 'right' },
  { key: 'participantCount', label: 'Participants', type: 'number', width: 110, align: 'right' },
  { key: 'segmentCount', label: 'Segments', type: 'number', width: 100, align: 'right' },
  { key: 'purposes', label: 'Purposes', type: 'string', width: 180, hiddenByDefault: true },
  { key: 'agentId', label: 'Agent ID', type: 'string', width: 200, hiddenByDefault: true },
  { key: 'divisionIds', label: 'Divisions', type: 'string', width: 200, hiddenByDefault: true },
  { key: 'raw', label: 'Raw payload', type: 'json', hiddenByDefault: true },
];

/** One row per conversation, with the nested participant tree summarized onto the row. */
const flattenConversation = (raw: unknown): DataRecord => {
  const conversation = asObject(raw);
  const participants = asArray(conversation.participants).map(asObject);

  const sessions = participants.flatMap((p) =>
    asArray(p.sessions).map((s) => ({ participant: p, session: asObject(s) })),
  );
  const segments = sessions.flatMap(({ participant, session }) =>
    asArray(session.segments).map((g) => ({ participant, session, segment: asObject(g) })),
  );

  const agent = participants.find((p) => str(p.purpose) === 'agent');
  const customerSession = sessions.find(({ participant }) => str(participant.purpose) === 'customer');

  const talkMs = segments
    .filter(({ participant, segment }) => str(participant.purpose) === 'agent' && str(segment.segmentType) === 'interact')
    .reduce((total, { segment }) => total + (num(segment.durationMs) ?? 0), 0);

  const disconnect = segments.map(({ segment }) => str(segment.disconnectType)).find((d) => d !== '');

  return {
    conversationId: str(conversation.conversationId),
    conversationStart: str(conversation.conversationStart),
    conversationEnd: str(conversation.conversationEnd),
    durationMs: msBetween(conversation.conversationStart, conversation.conversationEnd),
    direction: str(conversation.originatingDirection),
    mediaTypes: unique(sessions.map(({ session }) => str(session.mediaType))).join(', '),
    agentName: agent ? str(agent.participantName) : '',
    agentId: agent ? str(agent.userId) : '',
    queueId: unique(sessions.map(({ session }) => str(session.queueId)))[0] ?? '',
    ani: customerSession ? str(customerSession.session.ani) : '',
    dnis: customerSession ? str(customerSession.session.dnis) : '',
    disconnectType: disconnect ?? '',
    talkMs: talkMs > 0 ? talkMs : null,
    participantCount: participants.length,
    segmentCount: segments.length,
    purposes: unique(participants.map((p) => str(p.purpose))).join(', '),
    divisionIds: asArray(conversation.divisionIds).map(str).join(', '),
    raw: conversation,
  };
};

const conversationsSource: DataSource = {
  id: 'conversations',
  name: 'Conversations',
  group: 'Interactions',
  description:
    'Conversation details retrieved through the full async job lifecycle: submit, poll until FULFILLED, then read both cursor-paged result pages.',
  endpointKeys: ['analytics.create.conversation.details.job.large.query', 'analytics.conversation.details.query'],
  fields: CONVERSATION_FIELDS,
  defaultQuery: { sort: [{ field: 'conversationStart', direction: 'desc' }] },

  async fetch(ctx: FetchContext, _query: QueryDefinition): Promise<DataSet> {
    const startedAt = performance.now();
    const client = getClient();

    const job = await runAsyncJob(client, {
      submitPath: '/api/v2/analytics/conversations/details/jobs',
      submitBody: {
        interval: '2026-02-13T00:00:00.000Z/2026-02-20T23:59:59.999Z',
        order: 'asc',
        orderBy: 'conversationStart',
      },
      idProperty: 'jobId',
      statusPath: (id) => `/api/v2/analytics/conversations/details/jobs/${id}`,
      resultsPath: (id) => `/api/v2/analytics/conversations/details/jobs/${id}/results`,
      submitKey: 'analytics.create.conversation.details.job.large.query',
      pollKey: 'analytics.get.conversation.details.job.status',
      resultsKey: 'analytics.get.conversation.details.job.results',
      signal: ctx.signal,
    });

    const traces = [...job.traces];
    const firstPage = asObject(job.results);
    const conversations = [...asArray(firstPage.conversations)];

    // Follow the opaque cursor for as long as the server offers one.
    let cursor = str(firstPage.cursor);
    let guard = 0;
    while (cursor !== '' && guard < 10) {
      const next = await client.get<Record<string, unknown>>(
        `/api/v2/analytics/conversations/details/jobs/${job.jobId}/results`,
        {
          signal: ctx.signal,
          query: { cursor },
          endpointKey: 'analytics.get.conversation.details.job.results',
        },
      );
      traces.push({ ...next.trace, note: `results cursor page ${guard + 2}` });
      conversations.push(...asArray(next.data.conversations));
      const nextCursor = str(next.data.cursor);
      if (nextCursor === cursor) break; // defensive: never loop on a repeated cursor
      cursor = nextCursor;
      guard += 1;
    }

    return makeDataSet(
      'conversations',
      conversations.map(flattenConversation),
      CONVERSATION_FIELDS,
      traces,
      startedAt,
      job.warnings,
    );
  },
};

// ─── Conversation segments ───────────────────────────────────────────────────

const SEGMENT_FIELDS: FieldDefinition[] = [
  { key: 'conversationId', label: 'Conversation ID', type: 'string', width: 220 },
  { key: 'participantName', label: 'Participant', type: 'string', width: 150, facetable: true },
  { key: 'purpose', label: 'Purpose', type: 'string', width: 110, facetable: true },
  { key: 'mediaType', label: 'Media', type: 'string', width: 100, facetable: true },
  { key: 'segmentType', label: 'Segment type', type: 'string', width: 130, facetable: true },
  { key: 'segmentStart', label: 'Segment start', type: 'date', width: 190 },
  { key: 'segmentEnd', label: 'Segment end', type: 'date', width: 190, hiddenByDefault: true },
  { key: 'durationMs', label: 'Duration', type: 'duration', width: 110, align: 'right' },
  { key: 'disconnectType', label: 'Disconnect', type: 'string', width: 120, facetable: true },
  { key: 'direction', label: 'Direction', type: 'string', width: 100, facetable: true },
  { key: 'queueId', label: 'Queue', type: 'string', width: 200, facetable: true },
  { key: 'userId', label: 'User ID', type: 'string', width: 200, hiddenByDefault: true },
  { key: 'sessionId', label: 'Session ID', type: 'string', width: 180, hiddenByDefault: true },
  { key: 'ani', label: 'ANI', type: 'string', width: 140, hiddenByDefault: true },
  { key: 'dnis', label: 'DNIS', type: 'string', width: 140, hiddenByDefault: true },
];

const segmentsSource: DataSource = {
  id: 'conversation-segments',
  name: 'Conversation segments',
  group: 'Interactions',
  description:
    'The same conversations exploded to one row per participant, session and segment. This is the grain to group and aggregate for ad-hoc conversation reporting.',
  endpointKeys: ['analytics.conversation.details.query'],
  fields: SEGMENT_FIELDS,
  defaultQuery: { sort: [{ field: 'segmentStart', direction: 'asc' }] },

  async fetch(ctx: FetchContext, _query: QueryDefinition): Promise<DataSet> {
    const startedAt = performance.now();
    const client = getClient();

    const response = await client.post<Record<string, unknown>>(
      '/api/v2/analytics/conversations/details/query',
      {
        interval: '2026-02-13T00:00:00.000Z/2026-02-20T23:59:59.999Z',
        order: 'asc',
        orderBy: 'conversationStart',
        paging: { pageSize: 100, pageNumber: 1 },
      },
      { signal: ctx.signal, endpointKey: 'analytics.conversation.details.query' },
    );

    const records: DataRecord[] = [];
    for (const rawConversation of asArray(response.data.conversations)) {
      const conversation = asObject(rawConversation);
      for (const rawParticipant of asArray(conversation.participants)) {
        const participant = asObject(rawParticipant);
        for (const rawSession of asArray(participant.sessions)) {
          const session = asObject(rawSession);
          for (const rawSegment of asArray(session.segments)) {
            const segment = asObject(rawSegment);
            records.push({
              conversationId: str(conversation.conversationId),
              participantName: str(participant.participantName),
              purpose: str(participant.purpose),
              userId: str(participant.userId),
              sessionId: str(session.sessionId),
              mediaType: str(session.mediaType),
              direction: str(session.direction),
              queueId: str(session.queueId),
              ani: str(session.ani),
              dnis: str(session.dnis),
              segmentType: str(segment.segmentType),
              segmentStart: str(segment.segmentStart),
              segmentEnd: str(segment.segmentEnd),
              durationMs: num(segment.durationMs) ?? msBetween(segment.segmentStart, segment.segmentEnd),
              disconnectType: str(segment.disconnectType),
            });
          }
        }
      }
    }

    return makeDataSet('conversation-segments', records, SEGMENT_FIELDS, [response.trace], startedAt);
  },
};

// ─── Users ───────────────────────────────────────────────────────────────────

const USER_FIELDS: FieldDefinition[] = [
  { key: 'name', label: 'Name', type: 'string', width: 170 },
  { key: 'email', label: 'Email', type: 'string', width: 240 },
  { key: 'department', label: 'Department', type: 'string', width: 160, facetable: true },
  { key: 'title', label: 'Title', type: 'string', width: 180, facetable: true },
  { key: 'state', label: 'State', type: 'string', width: 90, facetable: true },
  { key: 'presence', label: 'Presence', type: 'string', width: 120, facetable: true },
  { key: 'routingStatus', label: 'Routing status', type: 'string', width: 130, facetable: true },
  { key: 'skills', label: 'Skills', type: 'string', width: 200 },
  { key: 'skillCount', label: 'Skills #', type: 'number', width: 90, align: 'right' },
  { key: 'acdAutoAnswer', label: 'Auto answer', type: 'boolean', width: 110 },
  { key: 'presenceMessage', label: 'Presence message', type: 'string', width: 180, hiddenByDefault: true },
  { key: 'routingSince', label: 'Routing since', type: 'date', width: 190, hiddenByDefault: true },
  { key: 'id', label: 'User ID', type: 'string', width: 220, hiddenByDefault: true },
];

const usersSource: DataSource = {
  id: 'users',
  name: 'Users',
  group: 'Directory',
  description:
    'Organization users with presence, routing status and skills. Follows nextUri across both demo pages.',
  endpointKeys: ['users'],
  fields: USER_FIELDS,
  defaultQuery: { sort: [{ field: 'name', direction: 'asc' }] },

  async fetch(ctx: FetchContext, _query: QueryDefinition): Promise<DataSet> {
    const startedAt = performance.now();
    const client = getClient();
    const { entities, traces } = await fetchAllPages(client, '/api/v2/users', 'users', ctx.signal);

    const records = entities.map((raw) => {
      const user = asObject(raw);
      const presence = asObject(user.presence);
      const definition = asObject(presence.presenceDefinition);
      const routing = asObject(user.routingStatus);
      const skills = asArray(user.skills).map(asObject);

      return {
        id: str(user.id),
        name: str(user.name),
        email: str(user.email),
        department: str(user.department),
        title: str(user.title),
        state: str(user.state),
        presence: str(definition.systemPresence),
        presenceMessage: str(presence.message),
        routingStatus: str(routing.status),
        routingSince: str(routing.startTime),
        skills: skills.map((s) => str(s.name)).join(', '),
        skillCount: skills.length,
        acdAutoAnswer: Boolean(user.acdAutoAnswer),
      } satisfies DataRecord;
    });

    return makeDataSet('users', records, USER_FIELDS, traces, startedAt);
  },
};

// ─── Queues ──────────────────────────────────────────────────────────────────

const QUEUE_FIELDS: FieldDefinition[] = [
  { key: 'name', label: 'Queue', type: 'string', width: 200 },
  { key: 'division', label: 'Division', type: 'string', width: 160, facetable: true },
  { key: 'memberCount', label: 'Members', type: 'number', width: 100, align: 'right' },
  { key: 'mediaTypes', label: 'Media settings', type: 'string', width: 180, facetable: true },
  { key: 'joined', label: 'Joined', type: 'boolean', width: 90 },
  { key: 'description', label: 'Description', type: 'string', width: 260 },
  { key: 'dateModified', label: 'Modified', type: 'date', width: 190 },
  { key: 'modifiedBy', label: 'Modified by', type: 'string', width: 160, hiddenByDefault: true },
  { key: 'dateCreated', label: 'Created', type: 'date', width: 190, hiddenByDefault: true },
  { key: 'id', label: 'Queue ID', type: 'string', width: 240, hiddenByDefault: true },
];

const queuesSource: DataSource = {
  id: 'queues',
  name: 'Routing queues',
  group: 'Routing',
  description: 'Routing queues with division, membership and per-media settings, across both demo pages.',
  endpointKeys: ['routing-queues'],
  fields: QUEUE_FIELDS,
  defaultQuery: { sort: [{ field: 'name', direction: 'asc' }] },

  async fetch(ctx: FetchContext, _query: QueryDefinition): Promise<DataSet> {
    const startedAt = performance.now();
    const client = getClient();
    const { entities, traces } = await fetchAllPages(client, '/api/v2/routing/queues', 'routing-queues', ctx.signal);

    const records = entities.map((raw) => {
      const queue = asObject(raw);
      return {
        id: str(queue.id),
        name: str(queue.name),
        division: str(asObject(queue.division).name),
        description: str(queue.description),
        memberCount: num(queue.memberCount) ?? 0,
        joined: Boolean(queue.joined),
        mediaTypes: Object.keys(asObject(queue.mediaSettings)).join(', '),
        dateCreated: str(queue.dateCreated),
        dateModified: str(queue.dateModified),
        modifiedBy: str(queue.modifiedBy),
      } satisfies DataRecord;
    });

    return makeDataSet('queues', records, QUEUE_FIELDS, traces, startedAt);
  },
};

// ─── Audit logs ──────────────────────────────────────────────────────────────

const AUDIT_FIELDS: FieldDefinition[] = [
  { key: 'timestamp', label: 'Timestamp', type: 'date', width: 190 },
  { key: 'serviceName', label: 'Service', type: 'string', width: 150, facetable: true },
  { key: 'action', label: 'Action', type: 'string', width: 120, facetable: true },
  { key: 'userName', label: 'User', type: 'string', width: 160, facetable: true },
  { key: 'userEmail', label: 'User email', type: 'string', width: 240 },
  { key: 'entityType', label: 'Entity type', type: 'string', width: 140, facetable: true },
  { key: 'entityName', label: 'Entity', type: 'string', width: 180 },
  { key: 'remoteIp', label: 'Remote IP', type: 'string', width: 130, facetable: true },
  { key: 'id', label: 'Audit ID', type: 'string', width: 220, hiddenByDefault: true },
  { key: 'userId', label: 'User ID', type: 'string', width: 220, hiddenByDefault: true },
  { key: 'context', label: 'Context', type: 'json', width: 260, hiddenByDefault: true },
];

const auditsSource: DataSource = {
  id: 'audits',
  name: 'Audit log',
  group: 'Governance',
  description:
    'Audit events retrieved through the async transaction lifecycle, then paged with nextUri across both demo pages.',
  endpointKeys: ['audits.get.audit.query.results'],
  fields: AUDIT_FIELDS,
  defaultQuery: { sort: [{ field: 'timestamp', direction: 'desc' }] },

  async fetch(ctx: FetchContext, _query: QueryDefinition): Promise<DataSet> {
    const startedAt = performance.now();
    const client = getClient();

    const job = await runAsyncJob(client, {
      submitPath: '/api/v2/audits/query',
      submitBody: {
        interval: '2026-02-13T00:00:00.000Z/2026-02-20T23:59:59.999Z',
        serviceName: 'ContactCenter',
      },
      idProperty: 'id',
      statusPath: (id) => `/api/v2/audits/query/${id}`,
      resultsPath: (id) => `/api/v2/audits/query/${id}/results`,
      submitKey: 'audits.post.audit.query',
      pollKey: 'audits.get.audit.query.status',
      resultsKey: 'audits.get.audit.query.results',
      signal: ctx.signal,
    });

    const traces = [...job.traces];
    const firstPage = asObject(job.results);
    const rows = [...asArray(firstPage.results)];

    // The demo server rewrites nextUri to an absolute URL on this server; page 2 ends the chain.
    if (str(firstPage.nextUri) !== '') {
      const second = await client.get<Record<string, unknown>>(
        `/api/v2/audits/query/${job.jobId}/results`,
        { signal: ctx.signal, query: { pageNumber: 2 }, endpointKey: 'audits.get.audit.query.results' },
      );
      traces.push({ ...second.trace, note: 'results page 2' });
      rows.push(...asArray(second.data.results));
    }

    const records = rows.map((raw) => {
      const audit = asObject(raw);
      const context = asObject(audit.context);
      return {
        id: str(audit.id),
        timestamp: str(audit.timestamp),
        serviceName: str(audit.serviceName),
        action: str(audit.action),
        userId: str(audit.userId),
        userName: str(audit.userName),
        userEmail: str(audit.userEmail),
        remoteIp: str(audit.remoteIp),
        entityType: str(context.entityType ?? context.type),
        entityName: str(context.entityName ?? context.name),
        context,
      } satisfies DataRecord;
    });

    return makeDataSet('audits', records, AUDIT_FIELDS, traces, startedAt, job.warnings);
  },
};

// ─── Active conversations ────────────────────────────────────────────────────

const ACTIVE_FIELDS: FieldDefinition[] = [
  { key: 'id', label: 'Conversation ID', type: 'string', width: 200 },
  { key: 'state', label: 'State', type: 'string', width: 110, facetable: true },
  { key: 'direction', label: 'Direction', type: 'string', width: 100, facetable: true },
  { key: 'address', label: 'Address', type: 'string', width: 150 },
  { key: 'startTime', label: 'Started', type: 'date', width: 190 },
  { key: 'elapsedMs', label: 'Elapsed', type: 'duration', width: 110, align: 'right' },
  { key: 'agents', label: 'Agents', type: 'string', width: 170 },
  { key: 'participantCount', label: 'Participants', type: 'number', width: 110, align: 'right' },
  { key: 'held', label: 'Held', type: 'boolean', width: 80 },
  { key: 'purposes', label: 'Purposes', type: 'string', width: 180, hiddenByDefault: true },
];

const activeConversationsSource: DataSource = {
  id: 'active-conversations',
  name: 'Active conversations',
  group: 'Interactions',
  description: 'Conversations currently in progress, with live participant state.',
  endpointKeys: ['conversations.get.active.conversations'],
  fields: ACTIVE_FIELDS,
  defaultQuery: { sort: [{ field: 'startTime', direction: 'desc' }] },

  async fetch(ctx: FetchContext, _query: QueryDefinition): Promise<DataSet> {
    const startedAt = performance.now();
    const client = getClient();
    const response = await client.get<Record<string, unknown>>('/api/v2/conversations', {
      signal: ctx.signal,
      endpointKey: 'conversations.get.active.conversations',
    });

    const records = asArray(response.data.entities).map((raw) => {
      const conversation = asObject(raw);
      const participants = asArray(conversation.participants).map(asObject);
      const agents = participants.filter((p) => str(p.purpose) === 'agent');
      return {
        id: str(conversation.id),
        state: str(conversation.state),
        direction: str(conversation.direction),
        address: str(conversation.address),
        startTime: str(conversation.startTime),
        elapsedMs: msBetween(conversation.startTime, new Date().toISOString()),
        agents: agents.map((a) => str(a.name)).join(', '),
        participantCount: participants.length,
        held: Boolean(conversation.held),
        purposes: unique(participants.map((p) => str(p.purpose))).join(', '),
      } satisfies DataRecord;
    });

    return makeDataSet('active-conversations', records, ACTIVE_FIELDS, [response.trace], startedAt);
  },
};

// ─── Roles, OAuth clients, topics ────────────────────────────────────────────

const ROLE_FIELDS: FieldDefinition[] = [
  { key: 'name', label: 'Role', type: 'string', width: 200 },
  { key: 'description', label: 'Description', type: 'string', width: 300 },
  { key: 'userCount', label: 'Users', type: 'number', width: 90, align: 'right' },
  { key: 'permissionCount', label: 'Permissions', type: 'number', width: 110, align: 'right' },
  { key: 'default', label: 'Default', type: 'boolean', width: 90 },
  { key: 'base', label: 'Base', type: 'boolean', width: 80 },
  { key: 'permissions', label: 'Permission list', type: 'string', width: 300, hiddenByDefault: true },
  { key: 'id', label: 'Role ID', type: 'string', width: 220, hiddenByDefault: true },
];

const rolesSource: DataSource = {
  id: 'roles',
  name: 'Authorization roles',
  group: 'Governance',
  description: 'Roles with their permission policies and user counts.',
  endpointKeys: ['authorization.get.roles'],
  fields: ROLE_FIELDS,
  defaultQuery: { sort: [{ field: 'userCount', direction: 'desc' }] },

  async fetch(ctx: FetchContext, _query: QueryDefinition): Promise<DataSet> {
    const startedAt = performance.now();
    const client = getClient();
    const response = await client.get<Record<string, unknown>>('/api/v2/authorization/roles', {
      signal: ctx.signal,
      endpointKey: 'authorization.get.roles',
    });

    const records = asArray(response.data.entities).map((raw) => {
      const role = asObject(raw);
      const permissions = asArray(role.permissions).map(str);
      return {
        id: str(role.id),
        name: str(role.name),
        description: str(role.description),
        userCount: num(role.userCount) ?? 0,
        permissionCount: permissions.length,
        permissions: permissions.join(', '),
        default: Boolean(role.default),
        base: Boolean(role.base),
      } satisfies DataRecord;
    });

    return makeDataSet('roles', records, ROLE_FIELDS, [response.trace], startedAt);
  },
};

const OAUTH_FIELDS: FieldDefinition[] = [
  { key: 'name', label: 'Client', type: 'string', width: 200 },
  { key: 'description', label: 'Description', type: 'string', width: 280 },
  { key: 'grantTypes', label: 'Grant types', type: 'string', width: 200, facetable: true },
  { key: 'tokenValiditySeconds', label: 'Token TTL', type: 'number', width: 110, align: 'right' },
  { key: 'dateCreated', label: 'Created', type: 'date', width: 190 },
  { key: 'createdBy', label: 'Created by', type: 'string', width: 160, hiddenByDefault: true },
  { key: 'id', label: 'Client ID', type: 'string', width: 240, hiddenByDefault: true },
];

const oauthClientsSource: DataSource = {
  id: 'oauth-clients',
  name: 'OAuth clients',
  group: 'Governance',
  description: 'OAuth clients registered in the demo organization.',
  endpointKeys: ['oauth.get.clients'],
  fields: OAUTH_FIELDS,
  defaultQuery: { sort: [{ field: 'name', direction: 'asc' }] },

  async fetch(ctx: FetchContext, _query: QueryDefinition): Promise<DataSet> {
    const startedAt = performance.now();
    const client = getClient();
    const response = await client.get<Record<string, unknown>>('/api/v2/oauth/clients', {
      signal: ctx.signal,
      endpointKey: 'oauth.get.clients',
    });

    const records = asArray(response.data.entities).map((raw) => {
      const oauthClient = asObject(raw);
      return {
        id: str(oauthClient.id),
        name: str(oauthClient.name),
        description: str(oauthClient.description),
        grantTypes: asArray(oauthClient.authorizedGrantTypes).map(str).join(', '),
        tokenValiditySeconds: num(oauthClient.accessTokenValiditySeconds) ?? 0,
        dateCreated: str(oauthClient.dateCreated),
        createdBy: str(oauthClient.createdBy),
      } satisfies DataRecord;
    });

    return makeDataSet('oauth-clients', records, OAUTH_FIELDS, [response.trace], startedAt);
  },
};

const TOPIC_FIELDS: FieldDefinition[] = [
  { key: 'name', label: 'Topic', type: 'string', width: 200 },
  { key: 'description', label: 'Description', type: 'string', width: 280 },
  { key: 'language', label: 'Language', type: 'string', width: 110, facetable: true },
  { key: 'published', label: 'Published', type: 'boolean', width: 100 },
  { key: 'strictness', label: 'Strictness', type: 'string', width: 110, facetable: true },
  { key: 'phraseCount', label: 'Phrases', type: 'number', width: 100, align: 'right' },
  { key: 'programsCount', label: 'Programs', type: 'number', width: 100, align: 'right' },
  { key: 'tags', label: 'Tags', type: 'string', width: 180, facetable: true },
  { key: 'phrases', label: 'Phrase list', type: 'string', width: 300, hiddenByDefault: true },
  { key: 'id', label: 'Topic ID', type: 'string', width: 220, hiddenByDefault: true },
];

const topicsSource: DataSource = {
  id: 'topics',
  name: 'Speech & text topics',
  group: 'Analytics',
  description: 'Speech and text analytics topics with their phrase definitions.',
  endpointKeys: ['speechandtextanalytics.get.topics'],
  fields: TOPIC_FIELDS,
  defaultQuery: { sort: [{ field: 'name', direction: 'asc' }] },

  async fetch(ctx: FetchContext, _query: QueryDefinition): Promise<DataSet> {
    const startedAt = performance.now();
    const client = getClient();
    const response = await client.get<Record<string, unknown>>('/api/v2/speechandtextanalytics/topics', {
      signal: ctx.signal,
      endpointKey: 'speechandtextanalytics.get.topics',
    });

    const records = asArray(response.data.entities).map((raw) => {
      const topic = asObject(raw);
      const phrases = asArray(topic.phrases).map((p) => str(asObject(p).text ?? p));
      return {
        id: str(topic.id),
        name: str(topic.name),
        description: str(topic.description),
        language: str(topic.language),
        published: Boolean(topic.published),
        strictness: str(topic.strictness),
        phraseCount: phrases.length,
        phrases: phrases.join(' | '),
        programsCount: num(topic.programsCount) ?? 0,
        tags: asArray(topic.tags).map(str).join(', '),
      } satisfies DataRecord;
    });

    return makeDataSet('topics', records, TOPIC_FIELDS, [response.trace], startedAt);
  },
};

// ─── Paging helper ───────────────────────────────────────────────────────────

/** Follows nextUri to the end, returning every entity plus a trace per request. */
const fetchAllPages = async (
  client: CoreClient,
  path: string,
  endpointKey: string,
  signal?: AbortSignal,
  maxPages = 10,
): Promise<{ entities: unknown[]; traces: RequestTrace[] }> => {
  const entities: unknown[] = [];
  const traces: RequestTrace[] = [];

  for (let page = 1; page <= maxPages; page += 1) {
    const response = await client.get<Record<string, unknown>>(path, {
      signal,
      endpointKey,
      query: page > 1 ? { pageNumber: page } : {},
    });
    traces.push({ ...response.trace, note: `page ${page}` });
    entities.push(...asArray(response.data.entities));
    if (str(response.data.nextUri) === '') break;
  }

  return { entities, traces };
};

// ─── Registry ────────────────────────────────────────────────────────────────

/**
 * Sources are constructed once and need the active client. Rather than threading it through
 * every call site, the provider installs it here at startup.
 */
let activeClient: CoreClient | null = null;

export const setSourceClient = (client: CoreClient): void => {
  activeClient = client;
};

const getClient = (): CoreClient => {
  if (!activeClient) throw new Error('Data source client has not been configured.');
  return activeClient;
};

export const DATA_SOURCES: DataSource[] = [
  conversationsSource,
  segmentsSource,
  activeConversationsSource,
  usersSource,
  queuesSource,
  auditsSource,
  rolesSource,
  oauthClientsSource,
  topicsSource,
];

export const sourceById = (id: string): DataSource | undefined =>
  DATA_SOURCES.find((source) => source.id === id);

/** Default visible column set for a source, honouring hiddenByDefault. */
export const defaultColumns = (source: DataSource) =>
  source.fields.map((field) => ({ key: field.key, visible: !field.hiddenByDefault, width: field.width }));

/**
 * Reconciles a stored column layout against the current field set.
 *
 * A saved view outlives the source it was taken from. Columns that no longer exist are dropped,
 * and fields added since the view was saved are appended at their default visibility rather than
 * being invisible forever.
 */
export const reconcileColumns = (
  stored: { key: string; visible: boolean; width?: number }[],
  fields: FieldDefinition[],
): { key: string; visible: boolean; width?: number }[] => {
  const known = new Set(fields.map((f) => f.key));
  const kept = stored.filter((column) => known.has(column.key));
  const seen = new Set(kept.map((column) => column.key));

  const added = fields
    .filter((field) => !seen.has(field.key))
    .map((field) => ({ key: field.key, visible: !field.hiddenByDefault, width: field.width }));

  return [...kept, ...added];
};
