/** Retrieval lifecycle for a DataSource, with abort handling and manual refresh. */

import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import type { DataSet, DataSource, QueryDefinition } from '../core/contracts';
import { emptyQuery } from '../core/contracts';

export type LoadStatus = 'idle' | 'loading' | 'ready' | 'error';

export interface DataSourceState {
  status: LoadStatus;
  dataSet: DataSet | null;
  error: string | null;
  reload: () => void;
}

export const useDataSource = (source: DataSource | undefined, params: Record<string, unknown> = {}): DataSourceState => {
  const [status, setStatus] = useState<LoadStatus>('idle');
  const [dataSet, setDataSet] = useState<DataSet | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [nonce, setNonce] = useState(0);

  // Params are compared by value so a caller passing a fresh object literal each render
  // does not cause an infinite refetch loop.
  const paramsKey = JSON.stringify(params ?? {});
  const abortRef = useRef<AbortController | null>(null);

  const reload = useCallback(() => setNonce((n) => n + 1), []);

  useEffect(() => {
    if (!source) {
      setStatus('idle');
      setDataSet(null);
      setError(null);
      return;
    }

    abortRef.current?.abort();
    const controller = new AbortController();
    abortRef.current = controller;

    const query: QueryDefinition = {
      ...emptyQuery(source.id),
      ...source.defaultQuery,
      params: JSON.parse(paramsKey) as Record<string, unknown>,
    };

    setStatus('loading');
    setError(null);

    source
      .fetch({ signal: controller.signal }, query)
      .then((result) => {
        if (controller.signal.aborted) return;
        setDataSet(result);
        setStatus('ready');
      })
      .catch((cause: unknown) => {
        if (controller.signal.aborted) return;
        setError(cause instanceof Error ? cause.message : String(cause));
        setStatus('error');
      });

    return () => controller.abort();
  }, [source, paramsKey, nonce]);

  return useMemo(() => ({ status, dataSet, error, reload }), [status, dataSet, error, reload]);
};
