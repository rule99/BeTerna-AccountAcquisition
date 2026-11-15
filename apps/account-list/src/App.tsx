import { useCallback, useEffect, useState } from 'react';
import { AccountTable } from './components/AccountTable';
import { ErrorPanel } from './components/ErrorPanel';
import { Legend } from './components/Legend';
import { loadAccounts } from './data/loadAccounts';
import type { AccountList } from './data/loadAccounts';
import { APP_VERSION } from './version';
import './App.css';

type State =
  | { kind: 'loading' }
  | { kind: 'ready'; list: AccountList }
  | { kind: 'error'; message: string };

/** Loads the list and turns any failure into an error state, so callers only set state once with the result. */
async function fetchState(): Promise<State> {
  try {
    return { kind: 'ready', list: await loadAccounts() };
  } catch (e) {
    return { kind: 'error', message: e instanceof Error ? e.message : String(e) };
  }
}

function App() {
  const [state, setState] = useState<State>({ kind: 'loading' });
  const [busy, setBusy] = useState(true);
  const [status, setStatus] = useState('');

  // Load on open. State is set only after the data arrives, and ignored if the component unmounted meanwhile.
  useEffect(() => {
    let active = true;
    void fetchState().then((next) => {
      if (!active) return;
      setState(next);
      setBusy(false);
    });
    return () => {
      active = false;
    };
  }, []);

  const reload = useCallback(async () => {
    setBusy(true);
    setStatus('Loading…');
    const next = await fetchState();
    setState(next);
    setStatus(next.kind === 'ready' ? 'Updated.' : 'Reload failed.');
    setBusy(false);
  }, []);

  return (
    <div className="page">
      <header className="site-header">
        <span className="site-title">Account List</span>
        <span className="site-version">Code app · v{APP_VERSION}</span>
      </header>
      <main className="site-main">
        <div className="toolbar">
          <h1>Active accounts</h1>
          <button type="button" className="button" onClick={() => void reload()} disabled={busy}>
            Reload
          </button>
          <span className="reload-status" role="status" aria-live="polite">{status}</span>
        </div>
        <Legend />
        <div aria-busy={busy}>
          {state.kind === 'loading' && <p className="muted">Loading accounts…</p>}
          {state.kind === 'error' && <ErrorPanel message={state.message} />}
          {state.kind === 'ready' && <AccountTable list={state.list} />}
        </div>
      </main>
    </div>
  );
}

export default App;
