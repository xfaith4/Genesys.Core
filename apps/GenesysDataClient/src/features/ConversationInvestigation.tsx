import { useLayoutEffect, useMemo, useRef, type MutableRefObject } from 'react';
import template from '../../../ConversationAnalysis/Investigation.html?raw';
import engine from '../../../ConversationAnalysis/population.js?raw';

// Reuse the portable Ops frontend. The sandbox cannot access the shell's session or API client.
// Only state is exchanged, and only with the exact frame window that this component owns.
const bridge = `
<script>
let publishedBundle = null;
const originalRenderGrid = renderGrid;
function publishViewState() {
  const state = {filters, page, metric, group, sortField, sortDirection, columns, search: $('search').value};
  if (bundle !== publishedBundle) { state.bundle = bundle; publishedBundle = bundle; }
  parent.postMessage({type:'gc-investigation-state', state}, '*');
}
renderGrid = function () { originalRenderGrid(); publishViewState(); };
$('search').addEventListener('input',publishViewState);
window.addEventListener('message', event => {
  if(event.source !== parent || event.data?.type !== 'gc-investigation-restore') return;
  const saved = event.data.state;
  if(!saved?.bundle) return;
  columns=saved.columns;
  publishedBundle=saved.bundle; // Parent already owns this population; avoid cloning it back.
  const renderBeforeRestore=render;
  render=()=>{}; // Restore the selected view before the first expensive population render.
  try { load(saved.bundle); } finally { render=renderBeforeRestore; }
  filters=saved.filters; page=saved.page; metric=saved.metric; group=saved.group;
  sortField=saved.sortField; sortDirection=saved.sortDirection; columns=saved.columns;
  $('search').value=saved.search; $('metric').value=metric; $('group').value=group;
  render();
});
parent.postMessage({type:'gc-investigation-ready'}, '*');
</script>`;

export const investigationDocument = () => template.replace(
  '<script src="population.js"></script>',
  () => `<script>${engine.replace(/<\/script/gi, '<\\/script')}</script>`,
).replace('</body>', () => `${bridge}</body>`);

export type InvestigationSnapshot = Record<string, unknown>;

export const ConversationInvestigation = ({ snapshot }: {
  snapshot: MutableRefObject<InvestigationSnapshot | null>;
}) => {
  const frame = useRef<HTMLIFrameElement>(null);
  const document = useMemo(investigationDocument, []);
  useLayoutEffect(() => {
    const receive = (event: MessageEvent) => {
      if (event.source !== frame.current?.contentWindow) return;
      if (event.data?.type === 'gc-investigation-ready' && snapshot.current) {
        frame.current?.contentWindow?.postMessage({
          type: 'gc-investigation-restore', state: snapshot.current,
        }, '*');
      }
      if (event.data?.type === 'gc-investigation-state' && event.data.state) {
        snapshot.current = { ...snapshot.current, ...event.data.state };
      }
    };
    window.addEventListener('message', receive);
    return () => window.removeEventListener('message', receive);
  }, [snapshot]);
  return <iframe
    ref={frame}
    title="Conversation investigation workbench"
    srcDoc={document}
    sandbox="allow-scripts allow-downloads allow-forms"
    style={{ width: '100%', height: 'calc(100dvh - 160px)', minHeight: 600, border: 0, display: 'block' }}
  />;
};
