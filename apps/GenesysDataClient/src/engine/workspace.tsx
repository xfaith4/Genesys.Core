/**
 * Workspace state: everything the user has personalized, persisted between sessions.
 *
 * This is the substrate that makes the Atlas skin "controllable" - saved views, panel order,
 * theme, density and accent all live here rather than being baked into any screen.
 */

import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
  type ReactNode,
} from 'react';
import {
  emptyWorkspace,
  newId,
  WORKSPACE_VERSION,
  type DashboardDefinition,
  type Density,
  type ReportDefinition,
  type SkinId,
  type ThemeMode,
  type ViewDefinition,
  type Workspace,
} from '../core/contracts';
import { CoreClient, defaultConnection, type ConnectionConfig } from '../core/client';
import { accentFor, GENESYS_ACCENT } from '../core/accents';
import { setSourceClient } from '../core/sources';
import { useAuth } from '../app/AuthProvider';

const STORAGE_KEY = 'genesys-data-client.workspace.v1';

const loadWorkspace = (): Workspace => {
  const base = emptyWorkspace();
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) return base;
    const parsed = JSON.parse(raw) as Partial<Workspace>;
    // Older shapes are merged onto the current default rather than discarded.
    if (parsed.version !== WORKSPACE_VERSION) return { ...base, ...parsed, version: WORKSPACE_VERSION };
    return { ...base, ...parsed };
  } catch {
    // A corrupt or unavailable store must never stop the app from rendering.
    return base;
  }
};

const persist = (workspace: Workspace): void => {
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(workspace));
  } catch {
    // Private browsing and blocked site data are expected; personalization is best-effort.
  }
};

export interface WorkspaceApi {
  workspace: Workspace;
  client: CoreClient;
  /** Derived from the authenticated session; authentication owns it, not the workspace. */
  connection: ConnectionConfig;

  setSkin: (skin: SkinId) => void;
  setTheme: (theme: ThemeMode) => void;
  setAccent: (accent: string) => void;
  setDensity: (density: Density) => void;

  saveView: (view: ViewDefinition) => void;
  deleteView: (id: string) => void;
  viewsFor: (sourceId: string) => ViewDefinition[];

  saveReport: (report: ReportDefinition) => void;
  deleteReport: (id: string) => void;

  saveDashboard: (dashboard: DashboardDefinition) => void;
  deleteDashboard: (id: string) => void;

  panelOrder: (pageId: string, fallback: string[]) => string[];
  movePanel: (pageId: string, panelId: string, direction: -1 | 1, fallback: string[]) => void;
  setPanelOrder: (pageId: string, order: string[]) => void;
  togglePanelCollapsed: (panelId: string) => void;
  isPanelCollapsed: (panelId: string) => boolean;

  resetWorkspace: () => void;
}

const WorkspaceContext = createContext<WorkspaceApi | null>(null);

/** Resolves the effective light/dark choice, following the OS when set to system. */
const useResolvedTheme = (mode: ThemeMode): 'light' | 'dark' => {
  const [systemDark, setSystemDark] = useState(
    () => typeof matchMedia === 'function' && matchMedia('(prefers-color-scheme: dark)').matches,
  );

  useEffect(() => {
    if (typeof matchMedia !== 'function') return;
    const query = matchMedia('(prefers-color-scheme: dark)');
    const onChange = (event: MediaQueryListEvent) => setSystemDark(event.matches);
    query.addEventListener('change', onChange);
    return () => query.removeEventListener('change', onChange);
  }, []);

  if (mode === 'system') return systemDark ? 'dark' : 'light';
  return mode;
};

export const WorkspaceProvider = ({ children }: { children: ReactNode }) => {
  const [workspace, setWorkspace] = useState<Workspace>(loadWorkspace);
  const { session } = useAuth();

  // The bearer and API base come from the authenticated session. Signing in or out, or a token
  // refresh, therefore reconfigures every data source without anything else being touched.
  const connection: ConnectionConfig = session
    ? { baseUrl: session.apiBase, token: session.accessToken }
    : defaultConnection();

  // One client instance for the app's lifetime, reconfigured in place so in-flight
  // components never hold a stale reference.
  //
  // The data sources are handed the client here, during render, rather than from an effect.
  // React runs child effects before parent effects, so a screen that fetches on mount - which is
  // what a cold deep link to an explorer does - would otherwise run before the client was installed.
  const clientRef = useRef<CoreClient | null>(null);
  if (clientRef.current === null) {
    clientRef.current = new CoreClient(connection);
    setSourceClient(clientRef.current);
  } else if (
    clientRef.current.connection.token !== connection.token ||
    clientRef.current.connection.baseUrl !== connection.baseUrl
  ) {
    // Reconfiguring during render rather than in an effect, for the same ordering reason: a
    // child that fetches on mount would otherwise run against the previous token.
    clientRef.current.configure(connection);
  }
  const client = clientRef.current;

  useEffect(() => persist(workspace), [workspace]);

  const resolvedTheme = useResolvedTheme(workspace.theme);

  // The Genesys skin reproduces the productized light interface and does not follow the
  // user's theme; that difference is the point of comparing the two skins.
  const effectiveTheme = workspace.skin === 'genesys' ? 'light' : resolvedTheme;

  useEffect(() => {
    const root = document.documentElement;
    root.dataset.skin = workspace.skin;
    root.dataset.theme = effectiveTheme;
    root.dataset.density = workspace.density;
    root.style.colorScheme = effectiveTheme;

    // The Genesys skin is fixed to the product's own orange; only Atlas honours the choice.
    const accent = workspace.skin === 'genesys' ? GENESYS_ACCENT : accentFor(workspace.accent);
    root.style.setProperty('--accent', accent.base);
    root.style.setProperty('--accent-strong', accent.strong);
    root.style.setProperty(
      '--accent-text',
      effectiveTheme === 'dark' ? accent.textOnDark : accent.textOnLight,
    );
  }, [workspace.skin, workspace.density, workspace.accent, effectiveTheme]);

  const update = useCallback((patch: Partial<Workspace>) => {
    setWorkspace((current) => ({ ...current, ...patch }));
  }, []);

  const api = useMemo<WorkspaceApi>(
    () => ({
      workspace,
      client,
      connection,

      setSkin: (skin) => update({ skin }),
      setTheme: (theme) => update({ theme }),
      setAccent: (accent) => update({ accent }),
      setDensity: (density) => update({ density }),

      saveView: (view) =>
        setWorkspace((current) => {
          const existing = current.views.findIndex((v) => v.id === view.id);
          const views = [...current.views];
          if (existing >= 0) views[existing] = view;
          else views.push(view);
          return { ...current, views };
        }),
      deleteView: (id) =>
        setWorkspace((current) => ({ ...current, views: current.views.filter((v) => v.id !== id) })),
      viewsFor: (sourceId) => workspace.views.filter((v) => v.sourceId === sourceId),

      saveReport: (report) =>
        setWorkspace((current) => {
          const existing = current.reports.findIndex((r) => r.id === report.id);
          const reports = [...current.reports];
          if (existing >= 0) reports[existing] = report;
          else reports.push(report);
          return { ...current, reports };
        }),
      deleteReport: (id) =>
        setWorkspace((current) => ({ ...current, reports: current.reports.filter((r) => r.id !== id) })),

      saveDashboard: (dashboard) =>
        setWorkspace((current) => {
          const existing = current.dashboards.findIndex((d) => d.id === dashboard.id);
          const dashboards = [...current.dashboards];
          if (existing >= 0) dashboards[existing] = dashboard;
          else dashboards.push(dashboard);
          return { ...current, dashboards };
        }),
      deleteDashboard: (id) =>
        setWorkspace((current) => ({
          ...current,
          dashboards: current.dashboards.filter((d) => d.id !== id),
        })),

      panelOrder: (pageId, fallback) => {
        const saved = workspace.panelOrder[pageId];
        if (!saved) return fallback;
        // Keep saved order, drop panels that no longer exist, append any new ones.
        const known = saved.filter((id) => fallback.includes(id));
        const added = fallback.filter((id) => !known.includes(id));
        return [...known, ...added];
      },

      setPanelOrder: (pageId, order) =>
        setWorkspace((current) => ({
          ...current,
          panelOrder: { ...current.panelOrder, [pageId]: order },
        })),

      movePanel: (pageId, panelId, direction, fallback) =>
        setWorkspace((current) => {
          const saved = current.panelOrder[pageId];
          const base = saved
            ? [...saved.filter((id) => fallback.includes(id)), ...fallback.filter((id) => !saved.includes(id))]
            : [...fallback];
          const index = base.indexOf(panelId);
          const target = index + direction;
          if (index < 0 || target < 0 || target >= base.length) return current;
          const next = [...base];
          const [moved] = next.splice(index, 1);
          next.splice(target, 0, moved as string);
          return { ...current, panelOrder: { ...current.panelOrder, [pageId]: next } };
        }),

      togglePanelCollapsed: (panelId) =>
        setWorkspace((current) => ({
          ...current,
          collapsedPanels: current.collapsedPanels.includes(panelId)
            ? current.collapsedPanels.filter((id) => id !== panelId)
            : [...current.collapsedPanels, panelId],
        })),

      isPanelCollapsed: (panelId) => workspace.collapsedPanels.includes(panelId),

      resetWorkspace: () => setWorkspace(emptyWorkspace()),
    }),
    [workspace, client, connection, update],
  );

  return <WorkspaceContext.Provider value={api}>{children}</WorkspaceContext.Provider>;
};

export const useWorkspace = (): WorkspaceApi => {
  const ctx = useContext(WorkspaceContext);
  if (!ctx) throw new Error('useWorkspace must be used inside a WorkspaceProvider');
  return ctx;
};

/** Creates a saved view from the current on-screen state. */
export const viewFromState = (
  name: string,
  sourceId: string,
  query: ViewDefinition['query'],
  columns: ViewDefinition['columns'],
  density: Density,
): ViewDefinition => {
  const now = new Date().toISOString();
  return {
    id: newId('view'),
    name,
    sourceId,
    query: structuredClone(query),
    columns: structuredClone(columns),
    density,
    createdAt: now,
    updatedAt: now,
  };
};
