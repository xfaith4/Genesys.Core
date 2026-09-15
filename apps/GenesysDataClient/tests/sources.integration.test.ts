/**
 * Integration tests against a running Genesys.MockServer.
 *
 * These exercise the real Genesys-facing layer: every data source is fetched over HTTP and its
 * flattening is checked against the demo fixtures. They are skipped automatically when the demo
 * server is not running, so the suite stays runnable offline.
 *
 *   dotnet run --project tools/Genesys.MockServer
 *   npm test
 */

import { describe, expect, it } from 'vitest';
import { CoreClient, DiscoveryApi, DEMO_TOKEN } from '../src/core/client';
import { DATA_SOURCES, setSourceClient, sourceById } from '../src/core/sources';
import { emptyQuery, type DataSet } from '../src/core/contracts';
import { applyQuery, buildReport } from '../src/engine/query';

const BASE_URL = process.env.GDC_MOCK_SERVER ?? 'http://localhost:7777';

// Probed at module load so an unreachable server shows as a visible SKIP in the reporter,
// rather than as tests that pass without asserting anything.
const serverUp = await (async () => {
  try {
    const response = await fetch(`${BASE_URL}/health`, { signal: AbortSignal.timeout(2500) });
    return response.ok;
  } catch {
    return false;
  }
})();

if (serverUp) {
  setSourceClient(new CoreClient({ baseUrl: BASE_URL, token: DEMO_TOKEN }));
} else {
  console.warn(`\n  SKIPPING integration tests: no demo server at ${BASE_URL}\n`);
}

const load = (sourceId: string): Promise<DataSet> => {
  const source = sourceById(sourceId);
  if (!source) throw new Error(`No source ${sourceId}`);
  return source.fetch({}, { ...emptyQuery(sourceId), ...source.defaultQuery });
};

describe.skipIf(!serverUp)('data sources against the demo server', () => {
  it('every registered source returns records', async () => {

    for (const source of DATA_SOURCES) {
      const dataSet = await source.fetch({}, { ...emptyQuery(source.id), ...source.defaultQuery });
      expect(dataSet.records.length, `${source.id} returned no records`).toBeGreaterThan(0);
      expect(dataSet.meta.requests.length, `${source.id} recorded no requests`).toBeGreaterThan(0);
      // Every request must have succeeded, or the flattening below is meaningless.
      for (const trace of dataSet.meta.requests) {
        expect(trace.status, `${source.id}: ${trace.method} ${trace.url}`).toBeLessThan(400);
      }
    }
  }, 30_000);

  it('conversations drive the full async job lifecycle and follow the cursor', async () => {
    const dataSet = await load('conversations');

    const notes = dataSet.meta.requests.map((r) => r.note ?? '');
    expect(notes.some((n) => n.includes('submit'))).toBe(true);
    expect(notes.some((n) => n.includes('FULFILLED'))).toBe(true);
    expect(notes.some((n) => n.includes('cursor page'))).toBe(true);

    // Both fixture pages: 3 on page one, 2 on page two.
    expect(dataSet.records).toHaveLength(5);
    expect(dataSet.meta.warnings).toHaveLength(0);
  }, 20_000);

  it('flattens the nested participant tree onto conversation rows', async () => {
    const dataSet = await load('conversations');

    const inbound = dataSet.records.find((r) => r.conversationId === 'conv-v001-voice-inbound');
    expect(inbound).toBeDefined();
    expect(inbound!.agentName).toBe('Alice Support');
    expect(inbound!.direction).toBe('inbound');
    expect(inbound!.mediaTypes).toBe('voice');
    expect(inbound!.ani).toBe('+14155550101');
    expect(inbound!.dnis).toBe('+18005551000');
    // 09:00:00 to 09:14:27 is 867 seconds.
    expect(inbound!.durationMs).toBe(867_000);
    expect(inbound!.participantCount).toBe(3);
  }, 20_000);

  it('explodes conversations to one row per segment', async () => {
    const dataSet = await load('conversation-segments');

    expect(dataSet.records.length).toBeGreaterThan(dataSet.records.map((r) => r.conversationId).filter(
      (id, index, all) => all.indexOf(id) === index,
    ).length);

    for (const record of dataSet.records) {
      expect(record.conversationId).toBeTruthy();
      expect(record.segmentType).toBeTruthy();
    }
  }, 20_000);

  it('audits complete the transaction lifecycle and page with nextUri', async () => {
    const dataSet = await load('audits');

    const notes = dataSet.meta.requests.map((r) => r.note ?? '');
    expect(notes.some((n) => n.includes('results page 2'))).toBe(true);
    // 10 rows per fixture page across two pages.
    expect(dataSet.records).toHaveLength(20);
    expect(dataSet.records[0]!.serviceName).toBeTruthy();
  }, 20_000);

  it('users follow nextUri across both pages', async () => {
    const dataSet = await load('users');

    expect(dataSet.records).toHaveLength(10);
    expect(dataSet.meta.requests).toHaveLength(2);

    const alice = dataSet.records.find((r) => r.email === 'alice.support@corp.example.com');
    expect(alice?.presence).toBe('AVAILABLE');
    expect(alice?.skillCount).toBe(1);
  }, 20_000);

  it('supports an end-to-end filter, sort and report over live data', async () => {
    const dataSet = await load('conversation-segments');

    const filtered = applyQuery(dataSet.records, dataSet.fields, {
      ...emptyQuery('conversation-segments'),
      filters: [{ id: 'f1', field: 'purpose', operator: 'eq', value: 'agent', enabled: true }],
      sort: [{ field: 'durationMs', direction: 'desc' }],
    });

    expect(filtered.records.length).toBeGreaterThan(0);
    expect(filtered.records.every((r) => r.purpose === 'agent')).toBe(true);

    const durations = filtered.records.map((r) => Number(r.durationMs ?? 0));
    expect([...durations].sort((a, b) => b - a)).toEqual(durations);

    const report = buildReport(filtered.records, dataSet.fields, {
      groupBy: ['segmentType'],
      metrics: [{ id: 'm1', field: 'durationMs', fn: 'sum' }],
    });
    expect(report.rows.length).toBeGreaterThan(0);
    expect(report.rows.reduce((total, row) => total + row.count, 0)).toBe(filtered.records.length);
  }, 20_000);
});

describe.skipIf(!serverUp)('discovery API', () => {
  it('reports coverage that matches the endpoints it lists', async () => {
    const discovery = new DiscoveryApi(new CoreClient({ baseUrl: BASE_URL, token: DEMO_TOKEN }));

    const overview = await discovery.overview();
    expect(overview.counts.endpoints).toBeGreaterThan(0);
    expect(overview.counts.withDemoData).toBeGreaterThan(0);

    const withData = await discovery.endpoints({ demoData: true, limit: 500 });
    expect(withData.items.length).toBe(overview.counts.withDemoData);
    expect(withData.items.every((e) => e.coverage !== 'generated')).toBe(true);

    const rules = await discovery.coverage();
    expect(rules.length).toBe(overview.counts.coverageRules);
    // Every fixture a rule names must exist on disk, or the outline is lying.
    expect(rules.every((rule) => rule.fixtures.every((f) => f.present))).toBe(true);
  }, 20_000);
});
