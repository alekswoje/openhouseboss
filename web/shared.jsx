/* global React */

// ============================================================
// Shared brand components
// ============================================================

// Brand mark — the glowing-F image lives at /foyer-mark.png. Single
// source for the rail, the crest, and any marketing surfaces; switch the
// image and every surface picks it up.
const FoyerMark = ({ size = 32, rounded = 7 }) => (
  <img
    src="foyer-mark.png"
    alt="Foyer"
    width={size}
    height={size}
    style={{
      width: size, height: size,
      borderRadius: rounded,
      display: 'block',
      objectFit: 'cover',
    }}
  />
);

const Crest = ({ size = 22, name = 'Foyer' }) => (
  <div className="crest" style={{ fontSize: size, gap: size * 0.4, alignItems: 'center' }}>
    <FoyerMark size={size * 1.3} rounded={Math.max(4, size * 0.3)} />
    <span>{name}</span>
  </div>
);

// Animated brand-mark GIF — drop this wherever the page would have shown a
// generic spinner. The native <img> tag handles GIF animation; we just frame
// it consistently and trim with border-radius so it matches the iPad app's
// FoyerLoadingView. Pass `label` to show a small caption underneath.
const FoyerLoader = ({ size = 96, rounded = 14, label, padding = 0 }) => (
  <div style={{
    display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 12,
    padding,
  }}>
    <img
      src="foyer-loading.gif"
      alt="Loading"
      width={size}
      height={size}
      style={{
        width: size, height: size,
        borderRadius: rounded,
        objectFit: 'cover',
        display: 'block',
      }} />
    {label && (
      <div style={{ fontSize: 12, color: 'var(--text-dim)', letterSpacing: '0.04em' }}>
        {label}
      </div>
    )}
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

// Pulls FastAPI's `{"detail": "..."}` body out of an errored response
// so the UI can show what actually went wrong instead of a bare status
// code. Falls through to `${status} ${statusText}` for non-JSON bodies.
async function _readError(r) {
  let detail = '';
  try {
    const j = await r.clone().json();
    if (j && typeof j === 'object') {
      detail = j.detail || j.error || j.message || '';
    }
  } catch {
    try { detail = (await r.text()).slice(0, 280); } catch {}
  }
  return detail ? `${detail}` : `${r.status} ${r.statusText}`;
}

const foyerApi = {
  async get(path) {
    const r = await fetch(path, { credentials: 'include' });
    if (r.status === 401) throw new Error('unauthenticated');
    if (!r.ok) throw new Error(await _readError(r));
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
    if (!r.ok) throw new Error(await _readError(r));
    return r.json();
  },
  async patch(path, body) {
    const r = await fetch(path, {
      method: 'PATCH',
      credentials: 'include',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body || {}),
    });
    if (r.status === 401) throw new Error('unauthenticated');
    if (!r.ok) throw new Error(await _readError(r));
    return r.json();
  },
  async del(path) {
    const r = await fetch(path, { method: 'DELETE', credentials: 'include' });
    if (r.status === 401) throw new Error('unauthenticated');
    if (!r.ok) throw new Error(await _readError(r));
    try { return await r.json(); } catch { return {}; }
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

// SF-Symbols-inspired stroke icons. One source so the rail + lead detail
// + buttons all share the same line weight. Each takes a `size` prop.
function Icon({ name, size = 18, active = false }) {
  const stroke = 'currentColor';
  const sw = 1.6;
  const common = { width: size, height: size, viewBox: '0 0 24 24', fill: 'none', stroke, strokeWidth: sw, strokeLinecap: 'round', strokeLinejoin: 'round' };
  switch (name) {
    case 'home':
      return active
        ? <svg {...common} fill="currentColor" stroke="none"><path d="M3 11 12 3l9 8v9a2 2 0 0 1-2 2h-4v-7h-6v7H5a2 2 0 0 1-2-2v-9Z"/></svg>
        : <svg {...common}><path d="M3 11 12 3l9 8"/><path d="M5 10v10a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V10"/><path d="M9 22v-7h6v7"/></svg>;
    case 'record':
      return <svg {...common}><circle cx="12" cy="12" r="3.5" fill={active ? 'currentColor' : 'none'} stroke="currentColor"/><circle cx="12" cy="12" r="8.5"/></svg>;
    case 'kiosk':
      return <svg {...common}><rect x="3" y="5" width="18" height="13" rx="2"/><path d="M8 22h8"/><path d="M12 18v4"/><circle cx="12" cy="11" r="2.5"/></svg>;
    case 'leads':
      return <svg {...common}><path d="M4 7h16"/><path d="M4 12h16"/><path d="M4 17h10"/><circle cx="19" cy="17" r="2.5" fill={active ? 'currentColor' : 'none'}/></svg>;
    case 'listings':
      return <svg {...common}><path d="M3 12 12 4l9 8"/><path d="M5 10v10h14V10"/><path d="M10 20v-6h4v6"/></svg>;
    case 'sessions':
      return <svg {...common}><rect x="3" y="4" width="18" height="16" rx="2"/><path d="M3 9h18"/><path d="M9 14h6"/></svg>;
    case 'chevronLeft':  return <svg {...common}><polyline points="15 6 9 12 15 18"/></svg>;
    case 'chevronRight': return <svg {...common}><polyline points="9 6 15 12 9 18"/></svg>;
    case 'logout':       return <svg {...common}><path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4"/><polyline points="16 17 21 12 16 7"/><line x1="21" y1="12" x2="9" y2="12"/></svg>;
    case 'plus':         return <svg {...common}><line x1="12" y1="5" x2="12" y2="19"/><line x1="5" y1="12" x2="19" y2="12"/></svg>;
    case 'send':         return <svg {...common}><path d="M22 2 11 13"/><path d="M22 2 15 22l-4-9-9-4 20-7Z"/></svg>;
    case 'clock':        return <svg {...common}><circle cx="12" cy="12" r="9"/><polyline points="12 7 12 12 16 14"/></svg>;
    case 'check':        return <svg {...common}><polyline points="20 6 9 17 4 12"/></svg>;
    case 'checkCircle':  return <svg {...common} fill={active ? 'currentColor' : 'none'}><circle cx="12" cy="12" r="9"/><polyline points="9 12 11.5 14.5 16 9.5" stroke={active ? 'var(--bg-deep)' : 'currentColor'}/></svg>;
    case 'circle':       return <svg {...common}><circle cx="12" cy="12" r="9"/></svg>;
    case 'x':            return <svg {...common}><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></svg>;
    case 'archive':      return <svg {...common}><rect x="3" y="3" width="18" height="5" rx="1"/><path d="M5 8v11a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8"/><path d="M10 13h4"/></svg>;
    case 'inbox':        return <svg {...common}><path d="M22 12h-6l-2 3h-4l-2-3H2"/><path d="M5.45 5.11 2 12v6a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2v-6l-3.45-6.89A2 2 0 0 0 16.76 4H7.24a2 2 0 0 0-1.79 1.11Z"/></svg>;
    case 'envelope':     return <svg {...common}><rect x="3" y="5" width="18" height="14" rx="2"/><polyline points="3 7 12 13 21 7"/></svg>;
    case 'phone':        return <svg {...common}><path d="M22 16.92v3a2 2 0 0 1-2.18 2 19.79 19.79 0 0 1-8.63-3.07 19.5 19.5 0 0 1-6-6 19.79 19.79 0 0 1-3.07-8.67A2 2 0 0 1 4.11 2h3a2 2 0 0 1 2 1.72c.13.96.36 1.9.7 2.8a2 2 0 0 1-.45 2.11L8.09 9.91a16 16 0 0 0 6 6l1.28-1.28a2 2 0 0 1 2.11-.45c.9.34 1.84.57 2.8.7A2 2 0 0 1 22 16.92Z"/></svg>;
    case 'spark':        return <svg {...common} fill="currentColor" stroke="none"><path d="M12 2v6m0 8v6M2 12h6m8 0h6M5 5l4 4m6 6 4 4M5 19l4-4m6-6 4-4"/></svg>;
    case 'trash':        return <svg {...common}><polyline points="3 6 5 6 21 6"/><path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"/></svg>;
    case 'search':       return <svg {...common}><circle cx="11" cy="11" r="7"/><line x1="21" y1="21" x2="16.65" y2="16.65"/></svg>;
    default:             return null;
  }
}

function AppShell({ active, children, sessionStats }) {
  const { user, summaries, sessionsById } = useFoyerData();
  const [menuOpen, setMenuOpen] = React.useState(false);
  // Sidebar collapse — persisted across page loads, matches the iPad
  // app's `sidebarCollapsed` UserDefault.
  const [collapsed, setCollapsed] = React.useState(() => {
    return localStorage.getItem('foyer.sidebarCollapsed') === '1';
  });
  const toggleCollapsed = React.useCallback(() => {
    setCollapsed(c => {
      const next = !c;
      localStorage.setItem('foyer.sidebarCollapsed', next ? '1' : '0');
      return next;
    });
  }, []);

  const recordedCount = summaries.filter(s => (s.kind || 'recorded') !== 'manual').length;
  const visitors = allLoadedVisitors(sessionsById);
  const needs = visitors.filter(v => leadBucket(v.lead_state) === 'needs').length;

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
        { id: 'today',   label: 'Today',    icon: 'home',   sub: 'Live overview',   hash: '#/app' },
        { id: 'kiosk',   label: 'Kiosk',    icon: 'kiosk',  sub: 'Hand to a guest', hash: '#/kiosk' },
      ],
    },
    {
      label: 'Library',
      items: [
        { id: 'sessions', label: 'Sessions', icon: 'sessions', sub: `${recordedCount} recorded`, hash: '#/sessions' },
        { id: 'leads',    label: 'Leads',    icon: 'leads',    sub: `${visitors.length} captured · ${needs} need action`, hash: '#/leads' },
      ],
    },
  ];

  const railWidth = collapsed ? 68 : 232;
  // Click-empty-space-to-expand. Matches iPad behavior — any tap on a
  // collapsed rail opens it; on an expanded rail this becomes a no-op.
  const onRailClick = (e) => {
    if (!collapsed) return;
    if (e.target.closest('a, button, .user-card-wrap')) return;
    toggleCollapsed();
  };

  return (
    <div className="foyer" style={{ background: 'var(--bg-deep)', minHeight: '100%', display: 'grid', gridTemplateColumns: `${railWidth}px 1fr`, transition: 'grid-template-columns 280ms cubic-bezier(0.4, 0, 0.2, 1)' }}>
      <aside onClick={onRailClick} style={{
        borderRight: '1px solid var(--hairline)',
        background: 'rgba(255,255,255,0.02)',
        display: 'flex', flexDirection: 'column',
        padding: '20px 0 16px',
        position: 'sticky', top: 0, height: '100vh',
        width: railWidth,
        cursor: collapsed ? 'pointer' : 'default',
        transition: 'width 280ms cubic-bezier(0.4, 0, 0.2, 1)',
        overflow: 'hidden',
      }}>
        {/* Brand row */}
        <div style={{
          padding: collapsed ? '0 14px 18px' : '0 18px 18px',
          borderBottom: '1px solid var(--hairline)',
          display: 'flex', alignItems: 'center', justifyContent: collapsed ? 'center' : 'space-between',
          gap: 10,
        }}>
          {collapsed ? (
            <button
              onClick={(e) => { e.stopPropagation(); toggleCollapsed(); }}
              aria-label="Expand sidebar"
              style={{
                width: 40, height: 40,
                background: 'transparent', border: 0, padding: 0,
                cursor: 'pointer',
                display: 'inline-flex',
              }}>
              <FoyerMark size={40} rounded={9} />
            </button>
          ) : (
            <>
              <a href="#/app" style={{ textDecoration: 'none', display: 'inline-flex', alignItems: 'center', gap: 10 }}>
                <FoyerMark size={32} rounded={7} />
                <span style={{ fontFamily: 'var(--sans)', fontWeight: 500, fontSize: 16, color: 'var(--cream)', letterSpacing: '-0.02em' }}>Foyer</span>
              </a>
              <button
                onClick={(e) => { e.stopPropagation(); toggleCollapsed(); }}
                aria-label="Collapse sidebar"
                style={{ background: 'transparent', border: 0, color: 'var(--text-dim)', cursor: 'pointer', padding: 4, display: 'inline-flex' }}>
                <Icon name="chevronLeft" size={16} />
              </button>
            </>
          )}
        </div>

        <nav style={{ padding: '10px 0', flex: 1, overflowY: 'auto' }}>
          {sections.map(section => (
            <div key={section.label} style={{ padding: '10px 0' }}>
              {!collapsed && (
                <div className="eyebrow" style={{ padding: '0 22px 8px', color: 'var(--text-muted)' }}>{section.label}</div>
              )}
              {section.items.map(item => {
                const isActive = item.id === active;
                return collapsed ? (
                  <a key={item.id}
                     href={item.hash}
                     onClick={(e) => { e.stopPropagation(); }}
                     title={item.label}
                     className="nav-item"
                     style={{
                       display: 'flex', alignItems: 'center', justifyContent: 'center',
                       width: 40, height: 40, margin: '4px auto',
                       borderRadius: 8,
                       background: isActive ? 'var(--gold-soft)' : 'transparent',
                       color: isActive ? 'var(--gold)' : 'var(--text-dim)',
                       textDecoration: 'none',
                     }}>
                    <Icon name={item.icon} size={18} />
                  </a>
                ) : (
                  <a key={item.id}
                     href={item.hash}
                     className={'nav-item' + (isActive ? ' is-active' : '')}
                     style={{
                       display: 'flex', alignItems: 'center', gap: 12,
                       textDecoration: 'none',
                       margin: '2px 12px',
                       padding: '10px 12px',
                       borderRadius: 8,
                       background: isActive ? 'var(--gold-soft)' : 'transparent',
                       color: isActive ? 'var(--gold)' : 'var(--cream)',
                     }}>
                    <span style={{ display: 'inline-flex', color: isActive ? 'var(--gold)' : 'var(--text-dim)' }}>
                      <Icon name={item.icon} size={17} />
                    </span>
                    <div style={{ flex: 1 }}>
                      <div className="nav-item-label" style={{ fontSize: 14, fontWeight: isActive ? 500 : 400 }}>{item.label}</div>
                      <div className="mono" style={{ fontSize: 9, color: 'var(--text-muted)', marginTop: 2, letterSpacing: '0.08em' }}>{item.sub}</div>
                    </div>
                  </a>
                );
              })}
            </div>
          ))}
        </nav>

        <div className="user-card-wrap" style={{ padding: collapsed ? '12px 14px 0' : '12px 14px 0', borderTop: '1px solid var(--hairline)', position: 'relative' }}>
          {collapsed ? (
            <div className="user-card" onClick={(e) => { e.stopPropagation(); setMenuOpen(o => !o); }}
              title={user?.name || 'Signed in'}
              style={{
                width: 40, height: 40, margin: '0 auto', borderRadius: '50%',
                background: 'var(--gold-soft)', color: 'var(--gold)',
                display: 'grid', placeItems: 'center',
                fontFamily: 'var(--sans)', fontWeight: 500, fontSize: 14,
                cursor: 'pointer',
              }}>
              {(user?.name || '?').slice(0, 1).toUpperCase()}
            </div>
          ) : (
            <div className="user-card" onClick={() => setMenuOpen(o => !o)} style={{
              display: 'flex', alignItems: 'center', gap: 10,
              padding: 10, borderRadius: 10,
              background: 'rgba(255,255,255,0.03)', border: '1px solid var(--hairline)', cursor: 'pointer',
            }}>
              <div style={{ width: 32, height: 32, borderRadius: '50%', background: 'var(--gold-soft)', display: 'grid', placeItems: 'center', color: 'var(--gold)', fontFamily: 'var(--sans)', fontWeight: 500, fontSize: 12 }}>
                {(user?.name || '?').slice(0, 1).toUpperCase()}
              </div>
              <div style={{ flex: 1, overflow: 'hidden' }}>
                <div style={{ fontSize: 13, color: 'var(--cream)', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{user?.name || 'Signed in'}</div>
                <div className="mono" style={{ fontSize: 9, color: 'var(--text-muted)', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis', letterSpacing: '0.06em' }}>{(user?.email || '').toLowerCase()}</div>
              </div>
            </div>
          )}
          {menuOpen && (
            <div style={{
              position: 'absolute',
              left: collapsed ? 60 : 18, right: collapsed ? 'auto' : 18,
              bottom: collapsed ? 12 : 64,
              minWidth: 200,
              background: 'var(--bg-card)', border: '1px solid var(--border-strong)', borderRadius: 10,
              boxShadow: '0 30px 80px -20px rgba(0,0,0,0.7)', padding: '6px 0',
              zIndex: 10,
            }}>
              <a href="#/profile" onClick={(e) => { e.preventDefault(); setMenuOpen(false); window.foyerGo('#/profile'); }}
                 style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '10px 16px', fontSize: 13, color: 'var(--cream-dim)', textDecoration: 'none' }}>
                <Icon name="envelope" size={14} />Profile & Gmail
              </a>
              <a href="#/" onClick={(e) => { e.preventDefault(); setMenuOpen(false); window.foyerGo('#/'); }}
                 style={{ display: 'block', padding: '10px 16px', fontSize: 13, color: 'var(--cream-dim)', textDecoration: 'none' }}>
                Marketing site
              </a>
              <div style={{ borderTop: '1px solid var(--hairline)', margin: '6px 0' }}></div>
              <div onClick={() => { setMenuOpen(false); foyerSignOut(); }}
                   style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '10px 16px', fontSize: 13, color: 'var(--terracotta)', cursor: 'pointer' }}>
                <Icon name="logout" size={14} />Log out
              </div>
            </div>
          )}
        </div>
      </aside>

      <main style={{ overflowY: 'auto', background: 'var(--bg-deep)' }}>
        {children}
      </main>
    </div>
  );
}

Object.assign(window, {
  Crest, FoyerMark, FoyerLoader, Eyebrow, Tag, Stat, Hairline, Icon,
  foyerApi, foyerLoad, useFoyerData, foyerSignOut,
  visitorKey, allLoadedVisitors, leadBucket, fmtRelative, fmtClock, greetingHour,
  AppShell,
});
