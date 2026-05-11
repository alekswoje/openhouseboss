/* global React */

// ============================================================
// Shared brand components
// ============================================================

const Crest = ({ size = 22, name = 'Foyer' }) => (
  <div className="crest" style={{ fontSize: size, gap: size * 0.4 }}>
    <span className="crest-mark" style={{ width: size * 1.3, height: size * 1.3, fontSize: size * 0.75 }}>F</span>
    <span>{name}</span>
  </div>
);

const Eyebrow = ({ children, num }) => (
  <div className="eyebrow" style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
    {num && <span style={{ display: 'inline-block', width: 22, height: 1, background: 'var(--gold)' }}></span>}
    <span>{children}</span>
  </div>
);

const Tag = ({ kind = 'buyer', children }) => (
  <span className={`tag tag-${kind}`}>
    <span className="tag-dot"></span>
    {children || kind}
  </span>
);

const Stat = ({ value, label, suffix }) => (
  <div>
    <div className="serif" style={{ fontSize: 56, lineHeight: 1, color: 'var(--cream)' }}>
      {value}
      {suffix && <span style={{ color: 'var(--gold)', fontStyle: 'italic' }}>{suffix}</span>}
    </div>
    <div className="eyebrow" style={{ marginTop: 10 }}>{label}</div>
  </div>
);

const Hairline = ({ vertical = false, style = {} }) => (
  <div style={{
    background: 'var(--hairline)',
    ...(vertical ? { width: 1, alignSelf: 'stretch' } : { height: 1, width: '100%' }),
    ...style,
  }}></div>
);

// ============================================================
// Real-data layer
// ============================================================
//
// Both /#/app and /#/session need the same shape: the signed-in user, the
// list of session summaries, and full session payloads (with visitors,
// analysis, lead_state) cached by id. foyerLoad() promises that, fetching
// /auth/me + /sessions on first call and expanding every ready session in
// parallel. The result is memoized on window.foyerCache so navigating
// between routes doesn't re-fetch.

const foyerApi = {
  async get(path) {
    const r = await fetch(path, { credentials: 'include' });
    if (r.status === 401) throw new Error('unauthenticated');
    if (!r.ok) throw new Error(`${r.status} ${r.statusText}`);
    return r.json();
  },
  async post(path, body) {
    const r = await fetch(path, {
      method: 'POST',
      credentials: 'include',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body || {}),
    });
    if (r.status === 401) throw new Error('unauthenticated');
    if (!r.ok) throw new Error(`${r.status} ${r.statusText}`);
    return r.json();
  },
};

async function foyerLoad({ force = false } = {}) {
  if (window.foyerCache && !force) return window.foyerCache.promise;
  const promise = (async () => {
    const user = await foyerApi.get('/auth/me');
    const list = await foyerApi.get('/sessions');
    const summaries = (list.sessions || []);
    const sessionsById = {};
    await Promise.all(summaries.map(async (s) => {
      if (s.status === 'ready') {
        try {
          sessionsById[s.id] = await foyerApi.get(`/sessions/${s.id}`);
        } catch (e) {
          // Skip — keep loading the rest. The summary still shows in the list.
        }
      }
    }));
    return { user, summaries, sessionsById };
  })();
  window.foyerCache = { promise };
  // Drop the cache on failure so a retry actually retries.
  promise.catch(() => { window.foyerCache = null; });
  return promise;
}

function useFoyerData() {
  const [state, setState] = React.useState(() => ({
    user: null, summaries: [], sessionsById: {}, loading: true, error: null,
  }));
  React.useEffect(() => {
    let alive = true;
    foyerLoad()
      .then(({ user, summaries, sessionsById }) => {
        if (!alive) return;
        setState({ user, summaries, sessionsById, loading: false, error: null });
      })
      .catch((e) => {
        if (!alive) return;
        if (e?.message === 'unauthenticated') {
          // Route back to the marketing/login surface.
          window.location.hash = '#/';
          return;
        }
        setState((s) => ({ ...s, loading: false, error: e.message || String(e) }));
      });
    return () => { alive = false; };
  }, []);
  return state;
}

// Helpers used by the dashboard + session detail. Visitor `id` is
// "<name>:<speaker>" the same way iOS does it.
function visitorKey(v) {
  return (v.visitor?.name || '') + ':' + (v.visitor?.speaker || '');
}

// Convenience: every visitor across every loaded session, with a `_session`
// pointer back to its parent. Used for the inbox-style queue + lead lists.
function allLoadedVisitors(sessionsById) {
  const rows = [];
  for (const session of Object.values(sessionsById)) {
    const result = session.result || {};
    for (const v of (result.visitors || [])) {
      rows.push({ ...v, _session: session, _id: visitorKey(v) });
    }
  }
  return rows;
}

function leadBucket(leadState) {
  if (!leadState) return 'needs';
  if (leadState.snoozed_until) {
    const t = Date.parse(leadState.snoozed_until);
    if (!Number.isNaN(t) && t > Date.now()) return 'snoozed';
  }
  switch (leadState.status) {
    case 'drafted':
    case 'sent':
      return 'needs';
    case 'replied':
    case 'archived':
      return 'done';
    default:
      return 'needs';
  }
}

function fmtRelative(iso) {
  if (!iso) return '';
  const t = Date.parse(iso);
  if (Number.isNaN(t)) return '';
  const diffMin = Math.floor((Date.now() - t) / 60000);
  if (diffMin < 1) return 'JUST NOW';
  if (diffMin < 60) return `${diffMin}M AGO`;
  const hours = Math.floor(diffMin / 60);
  if (hours < 24) return `${hours}H AGO`;
  const days = Math.floor(hours / 24);
  if (days < 7) return `${days}D AGO`;
  return new Date(t).toLocaleDateString(undefined, { month: 'short', day: 'numeric' }).toUpperCase();
}

function fmtClock(iso) {
  if (!iso) return '—';
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return '—';
  return d.toLocaleTimeString(undefined, { hour: 'numeric', minute: '2-digit' });
}

function greetingHour() {
  const h = new Date().getHours();
  if (h < 12) return 'morning';
  if (h < 17) return 'afternoon';
  return 'evening';
}

async function foyerSignOut() {
  try { await fetch('/auth/logout', { method: 'POST', credentials: 'include' }); } catch {}
  window.foyerCache = null;
  window.location.hash = '#/';
}

// ============================================================
// AppShell — sidebar + main pane shared across all signed-in pages.
// Dashboard, SessionsList, SessionDetail, Kiosk all wrap their content
// in <AppShell active="…"> so navigation is consistent and the sidebar
// is one place to change.
// ============================================================

function AppShell({ active, children, sessionStats }) {
  const { user, summaries, sessionsById } = useFoyerData();
  const [menuOpen, setMenuOpen] = React.useState(false);

  const recordedCount = summaries.filter(s => (s.kind || 'recorded') !== 'manual').length;
  const visitors = allLoadedVisitors(sessionsById);
  const needs = visitors.filter(v => leadBucket(v.lead_state) === 'needs').length;

  // Hover-to-close for the menu.
  React.useEffect(() => {
    if (!menuOpen) return;
    const onClick = (e) => {
      if (!e.target.closest('.user-card-wrap')) setMenuOpen(false);
    };
    setTimeout(() => document.addEventListener('click', onClick), 0);
    return () => document.removeEventListener('click', onClick);
  }, [menuOpen]);

  const sections = [
    {
      label: 'Open house',
      items: [
        { id: 'today',   label: 'Today',          sub: 'Live overview',         hash: '#/app' },
        { id: 'kiosk',   label: 'Kiosk sign-in',  sub: 'Hand to a guest',       hash: '#/kiosk' },
      ],
    },
    {
      label: 'Library',
      items: [
        { id: 'sessions', label: 'Sessions',  sub: `${recordedCount} recorded`, hash: '#/sessions' },
        { id: 'leads',    label: 'Leads',     sub: `${visitors.length} captured · ${needs} need action`, hash: '#/leads' },
      ],
    },
  ];

  return (
    <div className="foyer" style={{ background: 'var(--bg)', minHeight: '100%', display: 'grid', gridTemplateColumns: '260px 1fr' }}>
      <aside style={{
        borderRight: '1px solid var(--hairline)',
        background: 'var(--bg-deep)',
        display: 'flex', flexDirection: 'column',
        padding: '24px 0 20px',
        position: 'sticky', top: 0, height: '100vh',
      }}>
        <div style={{ padding: '0 22px 22px', borderBottom: '1px solid var(--hairline)', display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
          <a href="#/app" style={{ textDecoration: 'none', color: 'inherit' }}>
            <Crest size={18} />
          </a>
          {sessionStats?.live && (
            <span className="mono" style={{ fontSize: 9, color: 'var(--gold)', letterSpacing: '0.18em', display: 'inline-flex', alignItems: 'center', gap: 6 }}>
              <span style={{ width: 6, height: 6, borderRadius: '50%', background: 'var(--gold)', boxShadow: '0 0 8px var(--gold)' }} />
              LIVE
            </span>
          )}
        </div>

        <nav style={{ padding: '12px 0', flex: 1, overflowY: 'auto' }}>
          {sections.map(section => (
            <div key={section.label} style={{ padding: '14px 0' }}>
              <div className="eyebrow" style={{ padding: '0 22px 8px' }}>{section.label}</div>
              {section.items.map(item => {
                const isActive = item.id === active;
                return (
                  <a key={item.id}
                     href={item.hash}
                     className={'nav-item' + (isActive ? ' is-active' : '')}
                     style={{
                       display: 'block',
                       textDecoration: 'none',
                       padding: '11px 22px',
                       borderLeft: isActive ? '2px solid var(--gold)' : '2px solid transparent',
                       background: isActive ? 'var(--gold-soft)' : 'transparent',
                     }}>
                    <div className="nav-item-label" style={{ fontSize: 14, color: isActive ? 'var(--gold)' : 'var(--cream)', fontWeight: isActive ? 500 : 400 }}>{item.label}</div>
                    <div className="mono" style={{ fontSize: 9.5, color: 'var(--text-muted)', marginTop: 3, letterSpacing: '0.1em' }}>{item.sub}</div>
                  </a>
                );
              })}
            </div>
          ))}
        </nav>

        <div className="user-card-wrap" style={{ padding: '14px 18px', borderTop: '1px solid var(--hairline)', position: 'relative' }}>
          <div className="user-card" onClick={() => setMenuOpen(o => !o)} style={{
            display: 'flex', alignItems: 'center', gap: 12,
            padding: 10, borderRadius: 12,
            background: 'var(--bg-card)', border: '1px solid var(--hairline)', cursor: 'pointer',
          }}>
            <div style={{ width: 36, height: 36, borderRadius: '50%', background: 'var(--gold-soft)', display: 'grid', placeItems: 'center', color: 'var(--gold)', fontFamily: 'var(--serif)', fontStyle: 'italic' }}>
              {(user?.name || '?').slice(0, 1).toUpperCase()}
            </div>
            <div style={{ flex: 1, overflow: 'hidden' }}>
              <div style={{ fontSize: 13, color: 'var(--cream)', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{user?.name || 'Signed in'}</div>
              <div className="mono" style={{ fontSize: 9.5, color: 'var(--text-muted)', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{(user?.email || '').toUpperCase()}</div>
            </div>
            <span className="mono" style={{ fontSize: 14, color: 'var(--text-muted)' }}>{menuOpen ? '⌃' : '⌄'}</span>
          </div>
          {menuOpen && (
            <div style={{
              position: 'absolute', left: 18, right: 18, bottom: 78,
              background: 'var(--bg-card)', border: '1px solid var(--border-strong)', borderRadius: 12,
              boxShadow: '0 30px 80px -20px rgba(0,0,0,0.6)', padding: '8px 0',
            }}>
              <a href="#/" onClick={(e) => { e.preventDefault(); setMenuOpen(false); window.foyerGo('#/'); }}
                 style={{ display: 'block', padding: '10px 16px', fontSize: 13, color: 'var(--cream-dim)', textDecoration: 'none' }}>
                Marketing site
              </a>
              <div style={{ borderTop: '1px solid var(--hairline)', margin: '6px 0' }}></div>
              <div onClick={() => { setMenuOpen(false); foyerSignOut(); }}
                   style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '10px 16px', fontSize: 13, color: 'var(--terracotta)', cursor: 'pointer' }}>
                <span style={{ width: 16, textAlign: 'center' }}>⇥</span>Log out
              </div>
            </div>
          )}
        </div>
      </aside>

      <main style={{ overflowY: 'auto' }}>
        {children}
      </main>
    </div>
  );
}

Object.assign(window, {
  Crest, Eyebrow, Tag, Stat, Hairline,
  foyerApi, foyerLoad, useFoyerData, foyerSignOut,
  visitorKey, allLoadedVisitors, leadBucket, fmtRelative, fmtClock, greetingHour,
  AppShell,
});
