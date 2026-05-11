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

Object.assign(window, {
  Crest, Eyebrow, Tag, Stat, Hairline,
  foyerApi, foyerLoad, useFoyerData, foyerSignOut,
  visitorKey, allLoadedVisitors, leadBucket, fmtRelative, fmtClock, greetingHour,
});
