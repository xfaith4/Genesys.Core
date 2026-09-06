/**
 * Getting Started - the instruction surface.
 *
 * Explains what this application is, how it relates to Genesys.Core, how to run it, and what to
 * try first. Connectivity is probed live so the page tells the truth about the current session
 * rather than reciting static setup notes.
 */

import { useEffect, useMemo, useState } from 'react';
import { ApiError, DiscoveryApi, type ServerOverview } from '../core/client';
import { MOCK_ENVIRONMENT, environmentById } from '../core/auth';
import { useAuth } from '../app/AuthProvider';
import { DATA_SOURCES } from '../core/sources';
import { useWorkspace } from '../engine/workspace';
import { PanelBoard, type PanelSpec } from '../components/Panel';
import { Badge, Button, DetailRow } from '../components/primitives';
import type { PageId, SkinCapabilities } from '../skins';

const DEMO_IDENTITY = 'Demo Admin <demo.admin@genesys-testplatform.local>';

type Probe =
  | { state: 'checking' }
  | { state: 'connected'; overview: ServerOverview }
  | { state: 'failed'; message: string };

const CodeBlock = ({ children }: { children: string }) => (
  <pre className="code-block">
    <code>{children}</code>
  </pre>
);

export const GettingStarted = ({
  capabilities,
  onNavigate,
}: {
  capabilities: SkinCapabilities;
  onNavigate: (page: PageId, sourceId?: string) => void;
}) => {
  const { client, workspace } = useWorkspace();
  const { session, expiresIn, signOut, refreshNow } = useAuth();
  const discovery = useMemo(() => new DiscoveryApi(client), [client]);
  const [probe, setProbe] = useState<Probe>({ state: 'checking' });

  useEffect(() => {
    const controller = new AbortController();
    discovery
      .overview(controller.signal)
      .then((overview) => {
        if (!controller.signal.aborted) setProbe({ state: 'connected', overview });
      })
      .catch((cause: unknown) => {
        if (controller.signal.aborted) return;
        const message =
          cause instanceof ApiError && cause.status === 0
            ? 'The demo server is not reachable.'
            : cause instanceof Error
              ? cause.message
              : String(cause);
        setProbe({ state: 'failed', message });
      });
    return () => controller.abort();
  }, [discovery]);

  const connectionPanel: PanelSpec = {
    id: 'connection',
    title: 'Session',
    render: () => {
      const environment = environmentById(session?.environmentId ?? MOCK_ENVIRONMENT.id);
      const minutes = Math.floor(expiresIn / 60);
      const seconds = expiresIn % 60;

      return (
        <div className="connection">
          <div className="connection__row">
            {session?.flow === 'pkce' ? (
              <Badge tone="good">Authorization Code + PKCE</Badge>
            ) : (
              <Badge tone="warn">Static demo token</Badge>
            )}
            {environment.isDemo ? <Badge tone="muted">Demo</Badge> : <Badge tone="accent">Live org</Badge>}
          </div>

          <DetailRow label="Environment">{environment.label}</DetailRow>
          <DetailRow label="API base">
            <code className="inline-code">{environment.apiBase || 'same origin'}/api/v2</code>
          </DetailRow>
          <DetailRow label="Signed in as">{DEMO_IDENTITY}</DetailRow>
          <DetailRow label="OAuth client">
            <code className="inline-code">{session?.clientId ?? '—'}</code>
          </DetailRow>
          {session?.scope ? <DetailRow label="Scope">{session.scope}</DetailRow> : null}
          <DetailRow label="Access token">
            {/* Only the shape is shown. A token is a credential and never belongs on screen. */}
            <code className="inline-code">
              {session ? `${session.accessToken.slice(0, 12)}… (${session.accessToken.length} chars)` : '—'}
            </code>
          </DetailRow>
          <DetailRow label="Expires in">
            {expiresIn > 0 ? `${minutes}m ${String(seconds).padStart(2, '0')}s` : 'expired'}
          </DetailRow>
          <DetailRow label="Refresh token">
            {session?.refreshToken ? <Badge tone="good">held</Badge> : <Badge tone="muted">none</Badge>}
          </DetailRow>

          {probe.state === 'connected' ? (
            <p className="connection__note">
              {probe.overview.counts.endpoints.toLocaleString()} endpoints registered,{' '}
              {probe.overview.counts.withDemoData} returning real fixtures.
            </p>
          ) : probe.state === 'failed' ? (
            <p className="connection__note">
              The discovery API is unavailable ({probe.message}). That is expected against a live
              org, which has no <code className="inline-code">/__meta</code> — the data explorers
              still work.
            </p>
          ) : null}

          <div className="connection__actions">
            {session?.refreshToken ? <Button onClick={() => void refreshNow()}>Refresh token</Button> : null}
            <Button variant="ghost" onClick={() => void signOut()}>
              Sign out
            </Button>
          </div>
        </div>
      );
    },
  };

  const whatPanel: PanelSpec = {
    id: 'what',
    title: 'What this is',
    wide: true,
    render: () => (
      <div className="prose">
        <p>
          <strong>Genesys Data Client</strong> is a customizable data exploration, analysis, reporting and
          visualization application built on Genesys.Core. It deliberately does not reproduce the agent, supervisor
          or administrative workflows of the native Genesys Cloud client. It centres on the data instead:
        </p>
        <div className="pillars">
          <div className="pillar">
            <h3>Explore</h3>
            <p>records, objects, APIs, events</p>
          </div>
          <div className="pillar">
            <h3>Analyze</h3>
            <p>metrics, trends, correlations</p>
          </div>
          <div className="pillar">
            <h3>Build</h3>
            <p>reports, dashboards, exports, views</p>
          </div>
        </div>
        <p>
          Every screen is assembled from the same primitives — <code className="inline-code">DataSource</code>,{' '}
          <code className="inline-code">QueryDefinition</code>, <code className="inline-code">ViewDefinition</code>,{' '}
          <code className="inline-code">ReportDefinition</code> and <code className="inline-code">ExportDefinition</code>{' '}
          — so a new explorer is a new data source, not a new hand-built screen.
        </p>
      </div>
    ),
  };

  const skinPanel: PanelSpec = {
    id: 'skins',
    title: 'The two skins',
    wide: true,
    render: () => (
      <div className="prose">
        <p>The same application, the same data, two different interface philosophies:</p>
        <div className="skin-compare">
          <div className="skin-compare__col">
            <h3>Genesys</h3>
            <p className="skin-compare__sub">Mirrors the productized unified navigation experience.</p>
            <ul>
              <li>Unified global menu with a structured hierarchy</li>
              <li>Top bar with page title, back button, Collaborate, Inbox and avatar</li>
              <li>Fixed layout — the arrangement is the product's, not yours</li>
              <li>Light theme only</li>
            </ul>
          </div>
          <div className="skin-compare__col skin-compare__col--accent">
            <h3>Atlas</h3>
            <p className="skin-compare__sub">What the interface could be when the user is in control.</p>
            <ul>
              <li>Light, dark or system theme, plus a configurable accent</li>
              <li>Move sections around the page; collapse what you do not need</li>
              <li>Sort, filter, reorder, resize and hide any column of any dataset</li>
              <li>Ad-hoc reports over conversation detail, and export to CSV, JSON, NDJSON or Markdown</li>
              <li>Saved views that remember filters, sort and column layout</li>
            </ul>
          </div>
        </div>
        <p>
          Switch between them at any time from the {capabilities.customizableLayout ? 'controls in the header' : 'skin switcher in the top bar'}.
          The current skin is <Badge tone="accent">{workspace.skin}</Badge>.
        </p>
      </div>
    ),
  };

  const startPanel: PanelSpec = {
    id: 'start',
    title: 'Where to start',
    wide: true,
    render: () => (
      <div className="starters">
        <button type="button" className="starter" onClick={() => onNavigate('endpoints')}>
          <span className="starter__title">Browse what the server can exercise</span>
          <span className="starter__body">
            The endpoint outline, read live from the server's own coverage table, with a runner for any endpoint.
          </span>
        </button>
        {DATA_SOURCES.slice(0, 5).map((source) => (
          <button
            key={source.id}
            type="button"
            className="starter"
            onClick={() => onNavigate('explore', source.id)}
          >
            <span className="starter__title">{source.name}</span>
            <span className="starter__body">{source.description}</span>
          </button>
        ))}
      </div>
    ),
  };

  const runPanel: PanelSpec = {
    id: 'run',
    title: 'Running it',
    render: () => (
      <div className="prose">
        <p>From the repository root, start the offline data source:</p>
        <CodeBlock>dotnet run --project tools/Genesys.MockServer</CodeBlock>
        <p>Then, in this application's directory:</p>
        <CodeBlock>{'cd apps/GenesysDataClient\nnpm install\nnpm run dev'}</CodeBlock>
        <p>
          Or build once and let the demo server host it, which needs no Node at runtime:
        </p>
        <CodeBlock>{'npm run build\ndotnet run --project tools/Genesys.MockServer\n# then open http://localhost:7777'}</CodeBlock>
        <p className="prose__note">
          Node is a build dependency of this application only. Genesys.Core itself stays free of any frontend
          toolchain.
        </p>
      </div>
    ),
  };

  return (
    <div className="getting-started">
      <PanelBoard
        pageId="getting-started"
        panels={[whatPanel, connectionPanel, skinPanel, startPanel, runPanel]}
        movable={capabilities.customizableLayout}
      />
    </div>
  );
};
