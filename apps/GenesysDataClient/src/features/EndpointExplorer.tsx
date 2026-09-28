/**
 * Endpoint Explorer.
 *
 * Renders the outline of everything the connected server can exercise, straight from its own
 * /__meta discovery API, and lets any endpoint be run in place. Because the outline and the
 * dispatcher are driven by the same coverage table on the server, this can never claim demo data
 * that the server would not actually return.
 */

import { useCallback, useEffect, useMemo, useState } from 'react';
import type {
  CoverageRuleInfo,
  EndpointDetail,
  EndpointSummary,
  GroupSummary,
  ServerOverview,
} from '../core/client';
import { ApiError, DiscoveryApi } from '../core/client';
import { useWorkspace } from '../engine/workspace';
import { PanelBoard, type PanelSpec } from '../components/Panel';
import {
  Badge,
  Button,
  CoverageBadge,
  DetailRow,
  EmptyState,
  ErrorState,
  JsonBlock,
  MethodBadge,
  Select,
  Spinner,
  TextInput,
} from '../components/primitives';
import type { SkinCapabilities } from '../skins';

const COVERAGE_OPTIONS = [
  { value: '', label: 'Any coverage' },
  { value: 'fixture', label: 'Demo data' },
  { value: 'paged-fixture', label: 'Demo data, paged' },
  { value: 'cursor-fixture', label: 'Demo data, cursor' },
  { value: 'async-submit', label: 'Async submit' },
  { value: 'async-poll', label: 'Async poll' },
  { value: 'inline', label: 'Synthesized' },
  { value: 'generated', label: 'Empty skeleton' },
];

interface RunResult {
  status: number;
  durationMs: number;
  body: unknown;
  url: string;
  error?: string;
}

/** Extracts {placeholders} from a catalog path template. */
const routeParamsOf = (path: string): string[] =>
  [...path.matchAll(/\{([^}]+)\}/g)].map((match) => match[1] ?? '').filter((name) => name !== '');

const EndpointRunner = ({ detail }: { detail: EndpointDetail }) => {
  const { client } = useWorkspace();
  const [routeValues, setRouteValues] = useState<Record<string, string>>({});
  const [body, setBody] = useState('');
  const [running, setRunning] = useState(false);
  const [result, setResult] = useState<RunResult | null>(null);

  const params = useMemo(() => routeParamsOf(detail.path), [detail.path]);

  // Prefill route values and body from whatever the catalog suggests.
  useEffect(() => {
    const defaults: Record<string, string> = {};
    for (const name of params) {
      defaults[name] =
        detail.defaultRouteValues?.[name] ?? detail.defaultQueryParams?.[name] ?? `demo-${name}`;
    }
    setRouteValues(defaults);
    setBody(detail.defaultBody ? JSON.stringify(detail.defaultBody, null, 2) : '');
    setResult(null);
  }, [detail, params]);

  const resolvedPath = useMemo(() => {
    let path = detail.path;
    for (const [name, value] of Object.entries(routeValues)) {
      path = path.replace(`{${name}}`, encodeURIComponent(value || `demo-${name}`));
    }
    return path;
  }, [detail.path, routeValues]);

  const hasBody = ['POST', 'PUT', 'PATCH'].includes(detail.method);

  const run = useCallback(async () => {
    setRunning(true);
    setResult(null);
    const started = performance.now();

    let parsedBody: unknown = undefined;
    if (hasBody && body.trim() !== '') {
      try {
        parsedBody = JSON.parse(body);
      } catch (cause) {
        setRunning(false);
        setResult({
          status: 0,
          durationMs: 0,
          body: null,
          url: resolvedPath,
          error: `Request body is not valid JSON: ${String(cause)}`,
        });
        return;
      }
    }

    try {
      const response = await client.request(resolvedPath, {
        method: detail.method,
        body: parsedBody,
        endpointKey: detail.key,
      });
      setResult({
        status: response.trace.status,
        durationMs: response.trace.durationMs,
        body: response.data,
        url: response.trace.url,
      });
    } catch (cause) {
      const apiError = cause instanceof ApiError ? cause : null;
      setResult({
        status: apiError?.status ?? 0,
        durationMs: Math.round(performance.now() - started),
        body: apiError?.body ?? null,
        url: resolvedPath,
        error: cause instanceof Error ? cause.message : String(cause),
      });
    } finally {
      setRunning(false);
    }
  }, [client, detail, resolvedPath, body, hasBody]);

  return (
    <div className="runner">
      <div className="runner__line">
        <MethodBadge method={detail.method} />
        <code className="runner__path">{resolvedPath}</code>
        <Button variant="primary" onClick={run} disabled={running}>
          {running ? 'Running…' : 'Run request'}
        </Button>
      </div>

      {params.length > 0 ? (
        <div className="runner__params">
          {params.map((name) => (
            <TextInput
              key={name}
              id={`param-${name}`}
              label={name}
              value={routeValues[name] ?? ''}
              onChange={(value) => setRouteValues({ ...routeValues, [name]: value })}
            />
          ))}
        </div>
      ) : null}

      {hasBody ? (
        <label className="field runner__body">
          <span className="field__label">Request body</span>
          <textarea
            className="field__control field__control--area"
            value={body}
            onChange={(event) => setBody(event.target.value)}
            rows={body.split('\n').length > 14 ? 14 : Math.max(4, body.split('\n').length)}
            spellCheck={false}
            placeholder="{}"
          />
        </label>
      ) : null}

      {result ? (
        <div className="runner__result">
          <div className="runner__result-head">
            <Badge tone={result.error ? 'bad' : result.status < 400 ? 'good' : 'bad'}>
              {result.status === 0 ? 'error' : result.status}
            </Badge>
            <span className="runner__timing">{result.durationMs} ms</span>
            <code className="runner__url">{result.url.replace(/^https?:\/\/[^/]+/, '')}</code>
          </div>
          {result.error ? <p className="runner__error">{result.error}</p> : null}
          {result.body !== null && result.body !== undefined ? <JsonBlock value={result.body} maxHeight={380} /> : null}
        </div>
      ) : null}
    </div>
  );
};

export const EndpointExplorer = ({ capabilities }: { capabilities: SkinCapabilities }) => {
  const { client } = useWorkspace();
  const discovery = useMemo(() => new DiscoveryApi(client), [client]);

  const [overview, setOverview] = useState<ServerOverview | null>(null);
  const [groups, setGroups] = useState<GroupSummary[]>([]);
  const [rules, setRules] = useState<CoverageRuleInfo[]>([]);
  const [endpoints, setEndpoints] = useState<EndpointSummary[]>([]);
  const [total, setTotal] = useState(0);
  const [detail, setDetail] = useState<EndpointDetail | null>(null);

  const [group, setGroup] = useState('');
  const [coverage, setCoverage] = useState('');
  const [search, setSearch] = useState('');
  const [onlyDemoData, setOnlyDemoData] = useState(true);

  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  // Bootstrap: the server describes itself.
  useEffect(() => {
    const controller = new AbortController();
    setLoading(true);
    Promise.all([
      discovery.overview(controller.signal),
      discovery.groups(controller.signal),
      discovery.coverage(controller.signal),
    ])
      .then(([serverOverview, groupList, ruleList]) => {
        if (controller.signal.aborted) return;
        setOverview(serverOverview);
        setGroups(groupList);
        setRules(ruleList);
        setError(null);
      })
      .catch((cause: unknown) => {
        if (controller.signal.aborted) return;
        setError(cause instanceof Error ? cause.message : String(cause));
      })
      .finally(() => {
        if (!controller.signal.aborted) setLoading(false);
      });
    return () => controller.abort();
  }, [discovery]);

  // Endpoint list reacts to the filters.
  useEffect(() => {
    const controller = new AbortController();
    const handle = setTimeout(() => {
      discovery
        .endpoints(
          {
            group: group || undefined,
            coverage: coverage || undefined,
            q: search || undefined,
            demoData: onlyDemoData ? true : undefined,
            limit: 300,
          },
          controller.signal,
        )
        .then((response) => {
          if (controller.signal.aborted) return;
          setEndpoints(response.items);
          setTotal(response.total);
        })
        .catch(() => {
          /* transient filter errors are not worth interrupting the page for */
        });
    }, 180); // debounce the search box

    return () => {
      clearTimeout(handle);
      controller.abort();
    };
  }, [discovery, group, coverage, search, onlyDemoData]);

  const openDetail = useCallback(
    (key: string) => {
      discovery
        .endpoint(key)
        .then(setDetail)
        .catch((cause: unknown) => setError(cause instanceof Error ? cause.message : String(cause)));
    },
    [discovery],
  );

  if (loading) {
    return (
      <div className="page-state">
        <Spinner label="Asking the server what it can do…" />
      </div>
    );
  }

  if (error && !overview) {
    return (
      <ErrorState
        message={`${error} — start the demo server with: dotnet run --project tools/Genesys.MockServer`}
      />
    );
  }

  const overviewPanel: PanelSpec = {
    id: 'overview',
    title: 'Connected server',
    render: () =>
      overview ? (
        <div className="overview">
          <div className="stat-row">
            <Stat label="Endpoints" value={overview.counts.endpoints.toLocaleString()} />
            <Stat label="With demo data" value={overview.counts.withDemoData.toLocaleString()} tone="accent" />
            <Stat label="Groups" value={overview.counts.groups.toLocaleString()} />
            <Stat label="Coverage rules" value={overview.counts.coverageRules.toLocaleString()} />
          </div>
          <DetailRow label="Server">
            {overview.server} v{overview.version}
          </DetailRow>
          <DetailRow label="Catalog">
            v{overview.catalog.version} · generated {new Date(overview.catalog.generatedAt).toLocaleString()}
          </DetailRow>
          <DetailRow label="Demo token">
            <code className="inline-code">{overview.demoToken}</code>
          </DetailRow>
          <p className="overview__note">
            Of {overview.counts.endpoints.toLocaleString()} catalog endpoints, {overview.counts.withDemoData} return
            real demo data. The rest are registered and will answer with a shape-correct empty envelope.
          </p>
        </div>
      ) : (
        <EmptyState title="No server metadata" />
      ),
  };

  const listPanel: PanelSpec = {
    id: 'endpoints',
    title: 'Endpoints',
    wide: true,
    actions: (
      <Badge tone="accent">
        {endpoints.length} of {total}
      </Badge>
    ),
    render: () => (
      <div className="endpoints">
        <div className="endpoints__filters">
          <TextInput
            id="endpoint-search"
            label="Search"
            value={search}
            onChange={setSearch}
            placeholder="path, key or operation id"
          />
          <Select
            id="endpoint-group"
            label="Group"
            value={group}
            onChange={setGroup}
            options={[
              { value: '', label: `All groups (${groups.length})` },
              ...groups.map((g) => ({
                value: g.group,
                label: `${g.group} (${g.endpoints}${g.withDemoData > 0 ? `, ${g.withDemoData} live` : ''})`,
              })),
            ]}
          />
          <Select
            id="endpoint-coverage"
            label="Coverage"
            value={coverage}
            onChange={setCoverage}
            options={COVERAGE_OPTIONS}
          />
          <label className="toggle">
            <input
              type="checkbox"
              checked={onlyDemoData}
              onChange={(event) => setOnlyDemoData(event.target.checked)}
            />
            <span>Only endpoints with demo data</span>
          </label>
        </div>

        {endpoints.length === 0 ? (
          <EmptyState
            title="No endpoints match"
            hint="Clear the demo-data filter to browse the full catalog surface."
          />
        ) : (
          <ul className="endpoint-list">
            {endpoints.map((endpoint) => (
              <li key={endpoint.key}>
                <button
                  type="button"
                  className={`endpoint${detail?.key === endpoint.key ? ' endpoint--active' : ''}`}
                  onClick={() => openDetail(endpoint.key)}
                >
                  <MethodBadge method={endpoint.method} />
                  <code className="endpoint__path">{endpoint.path}</code>
                  <span className="endpoint__title">{endpoint.title}</span>
                  <CoverageBadge coverage={endpoint.coverage} title={endpoint.coverageSummary ?? undefined} />
                </button>
              </li>
            ))}
          </ul>
        )}
      </div>
    ),
  };

  const detailPanel: PanelSpec = {
    id: 'detail',
    title: detail ? detail.title : 'Endpoint detail',
    wide: true,
    render: () =>
      detail ? (
        <div className="endpoint-detail">
          <div className="endpoint-detail__head">
            <MethodBadge method={detail.method} />
            <code className="endpoint-detail__path">{detail.path}</code>
            <CoverageBadge coverage={detail.coverage} />
          </div>

          {detail.coverageSummary ? <p className="endpoint-detail__summary">{detail.coverageSummary}</p> : null}
          {detail.description ? <p className="endpoint-detail__desc">{detail.description}</p> : null}

          <DetailRow label="Catalog key">
            <code className="inline-code">{detail.key}</code>
          </DetailRow>
          <DetailRow label="Group">{detail.group}</DetailRow>
          <DetailRow label="Paging">{detail.pagingProfile}</DetailRow>
          <DetailRow label="Retry">{detail.retryProfile}</DetailRow>
          <DetailRow label="Items path">
            <code className="inline-code">{detail.itemsPath}</code>
          </DetailRow>

          {detail.fixtures.length > 0 ? (
            <DetailRow label="Fixtures">
              {detail.fixtures.map((fixture) => (
                <Badge key={fixture.file} tone={fixture.present ? 'good' : 'bad'}>
                  {fixture.file}
                </Badge>
              ))}
            </DetailRow>
          ) : null}

          {!detail.hasDemoData ? (
            <p className="endpoint-detail__warning">
              This endpoint is registered but has no fixture. It answers with a shape-correct empty envelope, which
              is still useful for exercising paging and error handling.
            </p>
          ) : null}

          <EndpointRunner detail={detail} />
        </div>
      ) : (
        <EmptyState
          title="Select an endpoint"
          hint="Pick one from the list to see its catalog metadata and run it against the demo server."
        />
      ),
  };

  const rulesPanel: PanelSpec = {
    id: 'rules',
    title: 'Demo data coverage',
    wide: true,
    render: () => (
      <div className="rules">
        <p className="rules__intro">
          These are the route families the server backs with real demo data. The list is read from the server's own
          coverage table, so it always matches what the dispatcher will actually serve.
        </p>
        <ul className="rules__list">
          {rules.map((rule) => (
            <li key={rule.id} className="rule">
              <div className="rule__head">
                <CoverageBadge coverage={rule.kind} />
                <code className="rule__id">{rule.id}</code>
                <span className="rule__count">
                  {rule.endpoints.length} endpoint{rule.endpoints.length === 1 ? '' : 's'}
                </span>
              </div>
              <p className="rule__summary">{rule.summary}</p>
              {rule.fixtures.length > 0 ? (
                <div className="rule__fixtures">
                  {rule.fixtures.map((fixture) => (
                    <Badge key={fixture.file} tone={fixture.present ? 'good' : 'bad'}>
                      {fixture.file}
                    </Badge>
                  ))}
                </div>
              ) : null}
            </li>
          ))}
        </ul>
      </div>
    ),
  };

  return (
    <div className="endpoint-explorer">
      <PanelBoard
        pageId="endpoints"
        panels={[overviewPanel, listPanel, detailPanel, rulesPanel]}
        movable={capabilities.customizableLayout}
      />
    </div>
  );
};

const Stat = ({ label, value, tone }: { label: string; value: string; tone?: 'accent' }) => (
  <div className={`stat${tone ? ` stat--${tone}` : ''}`}>
    <span className="stat__value">{value}</span>
    <span className="stat__label">{label}</span>
  </div>
);
