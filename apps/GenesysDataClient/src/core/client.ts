/**
 * The application's boundary onto Genesys.Core.
 *
 * The app talks to a Genesys.Core-shaped surface, never to Genesys Cloud directly. Today that
 * surface is the Genesys.MockServer offline implementation; pointing `baseUrl` at a real
 * Genesys.Core-backed gateway is the only change needed to run against live data, because the
 * request/response contract is identical on both sides.
 */

import type { RequestTrace } from './contracts';

export const DEMO_TOKEN = 'demo-bearer-token-genesys-testplatform';

export interface ConnectionConfig {
  /** Empty string means same-origin, which is how both the Vite proxy and dist/ hosting work. */
  baseUrl: string;
  token: string;
}

export const defaultConnection = (): ConnectionConfig => ({
  baseUrl: '',
  token: DEMO_TOKEN,
});

export class ApiError extends Error {
  constructor(
    message: string,
    readonly status: number,
    readonly body: unknown,
    readonly url: string,
  ) {
    super(message);
    this.name = 'ApiError';
  }
}

export interface RequestOptions {
  method?: string;
  body?: unknown;
  query?: Record<string, string | number | boolean | undefined>;
  signal?: AbortSignal;
  /** Catalog key recorded on the trace so the UI can link back to the endpoint outline. */
  endpointKey?: string;
  /** Metadata routes describe the server itself and take no bearer token. */
  anonymous?: boolean;
}

export interface ApiResponse<T> {
  data: T;
  trace: RequestTrace;
}

const buildUrl = (
  baseUrl: string,
  path: string,
  query?: Record<string, string | number | boolean | undefined>,
): string => {
  const search = new URLSearchParams();
  for (const [key, value] of Object.entries(query ?? {})) {
    if (value !== undefined && value !== '') search.set(key, String(value));
  }
  const qs = search.toString();
  return `${baseUrl}${path}${qs ? `?${qs}` : ''}`;
};

/** Thin HTTP client that records a trace for every call so the UI can show its work. */
export class CoreClient {
  constructor(private config: ConnectionConfig) {}

  get connection(): ConnectionConfig {
    return this.config;
  }

  configure(config: ConnectionConfig): void {
    this.config = config;
  }

  async request<T = unknown>(path: string, options: RequestOptions = {}): Promise<ApiResponse<T>> {
    const { method = 'GET', body, query, signal, endpointKey, anonymous } = options;
    const url = buildUrl(this.config.baseUrl, path, query);
    const started = performance.now();

    const headers: Record<string, string> = { Accept: 'application/json' };
    if (!anonymous) headers.Authorization = `Bearer ${this.config.token}`;
    if (body !== undefined) headers['Content-Type'] = 'application/json';

    let response: Response;
    try {
      response = await fetch(url, {
        method,
        headers,
        signal,
        body: body === undefined ? undefined : JSON.stringify(body),
      });
    } catch (cause) {
      // A network-level failure has no status, so there is no trace to record - only an error.
      throw new ApiError(
        `Could not reach ${url}. Is the mock server running? (${String(cause)})`,
        0,
        null,
        url,
      );
    }

    const durationMs = Math.round(performance.now() - started);
    const text = await response.text();
    let data: unknown = null;
    if (text) {
      try {
        data = JSON.parse(text);
      } catch {
        data = text;
      }
    }

    const trace: RequestTrace = {
      method,
      url: url || path,
      status: response.status,
      durationMs,
      endpointKey,
    };

    if (!response.ok) {
      const message =
        (data && typeof data === 'object' && 'message' in data
          ? String((data as { message: unknown }).message)
          : null) ?? `${method} ${path} failed with ${response.status}`;
      throw new ApiError(message, response.status, data, url);
    }

    return { data: data as T, trace };
  }

  get<T = unknown>(path: string, options: Omit<RequestOptions, 'method'> = {}) {
    return this.request<T>(path, { ...options, method: 'GET' });
  }

  post<T = unknown>(path: string, body: unknown, options: Omit<RequestOptions, 'method' | 'body'> = {}) {
    return this.request<T>(path, { ...options, method: 'POST', body });
  }
}

// ─── Discovery API types (served by the mock server's /__meta routes) ────────

export type CoverageKind =
  | 'fixture'
  | 'paged-fixture'
  | 'cursor-fixture'
  | 'async-submit'
  | 'async-poll'
  | 'inline'
  | 'generated';

export interface EndpointSummary {
  key: string;
  method: string;
  path: string;
  group: string;
  tags: string[];
  title: string;
  operationId: string | null;
  pagingProfile: string;
  retryProfile: string;
  itemsPath: string;
  curated: boolean;
  hasDefaultBody: boolean;
  hasDefaultQueryParams: boolean;
  coverage: CoverageKind;
  coverageId: string | null;
  coverageSummary: string | null;
  hasDemoData: boolean;
  itemsProperty: string | null;
  fixtures: string[];
}

export interface EndpointDetail extends Omit<EndpointSummary, 'fixtures'> {
  description: string | null;
  notes: string[];
  defaultBody: unknown;
  defaultQueryParams: Record<string, string> | null;
  defaultRouteValues: Record<string, string> | null;
  fixtures: { file: string; present: boolean }[];
}

export interface ServerOverview {
  server: string;
  version: string;
  demoToken: string;
  tokenEndpoint: string;
  catalog: { path: string; version: string; generatedAt: string };
  fixturesRoot: string;
  counts: {
    endpoints: number;
    routes: number;
    withDemoData: number;
    curated: number;
    groups: number;
    coverageRules: number;
  };
}

export interface GroupSummary {
  group: string;
  endpoints: number;
  withDemoData: number;
  curated: number;
  methods: string[];
}

export interface CoverageRuleInfo {
  id: string;
  kind: CoverageKind;
  summary: string;
  method: string | null;
  itemsProperty: string | null;
  fixtures: { file: string; present: boolean }[];
  endpoints: { key: string; method: string; path: string }[];
}

/** Reads the demo server's self-description. All routes here are unauthenticated. */
export class DiscoveryApi {
  constructor(private client: CoreClient) {}

  async overview(signal?: AbortSignal): Promise<ServerOverview> {
    const { data } = await this.client.get<ServerOverview>('/__meta', { anonymous: true, signal });
    return data;
  }

  async groups(signal?: AbortSignal): Promise<GroupSummary[]> {
    const { data } = await this.client.get<{ items: GroupSummary[] }>('/__meta/groups', {
      anonymous: true,
      signal,
    });
    return data.items;
  }

  async endpoints(
    params: {
      group?: string;
      coverage?: string;
      method?: string;
      q?: string;
      demoData?: boolean;
      limit?: number;
      offset?: number;
    } = {},
    signal?: AbortSignal,
  ): Promise<{ total: number; items: EndpointSummary[] }> {
    const { data } = await this.client.get<{ total: number; items: EndpointSummary[] }>(
      '/__meta/endpoints',
      { anonymous: true, signal, query: { ...params } },
    );
    return data;
  }

  async endpoint(key: string, signal?: AbortSignal): Promise<EndpointDetail> {
    const { data } = await this.client.get<EndpointDetail>(
      `/__meta/endpoints/${encodeURIComponent(key)}`,
      { anonymous: true, signal },
    );
    return data;
  }

  async coverage(signal?: AbortSignal): Promise<CoverageRuleInfo[]> {
    const { data } = await this.client.get<{ items: CoverageRuleInfo[] }>('/__meta/coverage', {
      anonymous: true,
      signal,
    });
    return data.items;
  }
}
