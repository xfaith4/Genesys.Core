/**
 * Application shell.
 *
 * Owns navigation state and picks the skin. The feature screens below are identical across skins;
 * only the chrome and the declared capabilities change.
 */

import { useEffect, useMemo, useState } from 'react';
import { useWorkspace } from '../engine/workspace';
import { useAuth } from './AuthProvider';
import { SignIn } from '../features/SignIn';
import { Spinner } from '../components/primitives';
import { EndpointExplorer } from '../features/EndpointExplorer';
import { Explorer } from '../features/Explorer';
import { GettingStarted } from '../features/GettingStarted';
import { atlasSkin } from '../skins/AtlasSkin';
import { genesysSkin } from '../skins/GenesysSkin';
import { buildNavigation, titleFor, type PageId, type SkinDefinition } from '../skins';
import { currentRoute, toHash, type Route } from './route';

const SKINS: Record<string, SkinDefinition> = {
  genesys: genesysSkin,
  atlas: atlasSkin,
};

export const App = () => {
  const { workspace } = useWorkspace();
  const { status } = useAuth();
  const [route, setRoute] = useState<Route>(currentRoute);
  const { page, sourceId } = route;

  // Back/forward and hand-edited URLs both drive the app.
  useEffect(() => {
    const onHashChange = () => setRoute(currentRoute());
    window.addEventListener('hashchange', onHashChange);
    return () => window.removeEventListener('hashchange', onHashChange);
  }, []);

  const sections = useMemo(() => buildNavigation(), []);
  const skin = SKINS[workspace.skin] ?? genesysSkin;
  const title = titleFor(page, sourceId);

  const navigate = (nextPage: PageId, nextSourceId?: string) => {
    const next: Route = { page: nextPage, sourceId: nextSourceId };
    // Writing the hash fires hashchange, which is what actually updates state.
    const hash = toHash(next);
    if (location.hash === hash) setRoute(next);
    else location.hash = hash;
  };

  const content = (() => {
    switch (page) {
      case 'endpoints':
        return <EndpointExplorer capabilities={skin.capabilities} />;
      case 'explore':
        return sourceId ? (
          <Explorer key={sourceId} sourceId={sourceId} capabilities={skin.capabilities} />
        ) : (
          <GettingStarted capabilities={skin.capabilities} onNavigate={navigate} />
        );
      case 'home':
      default:
        return <GettingStarted capabilities={skin.capabilities} onNavigate={navigate} />;
    }
  })();

  const Shell = skin.Shell;

  // Nothing is retrieved until there is a session, so the shell never renders unauthenticated.
  if (status === 'restoring') {
    return (
      <div className="page-state">
        <Spinner label="Restoring your session…" />
      </div>
    );
  }

  if (status !== 'signed-in') return <SignIn />;

  return (
    <Shell
      sections={sections}
      activePage={page}
      activeSourceId={sourceId}
      title={title}
      onNavigate={navigate}
    >
      {content}
    </Shell>
  );
};
