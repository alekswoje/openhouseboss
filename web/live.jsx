// Live companion — second-device coaching view.
//
// The agent records on their phone; this page runs on a second device
// (laptop, iPad) on the same Google account. No pairing dance: we
// authenticate via the existing fb_session cookie like the rest of the
// SPA, ask /live/sessions/current for whatever session is in flight,
// and show a glanceable coaching panel + "Check in now" button.
//
// Flow:
//   1. Page checks /auth/me — bounce to sign in if needed.
//   2. Poll /live/sessions/current every 3s. While nothing is live,
//      show a friendly empty state ("Start a recording on your phone…").
//   3. Once a live session is detected, switch to its slim view +
//      "Check in now" button.
//   4. Tap → POST /live/sessions/{id}/check_in → wait for the iPhone's
//      polling loop to pick it up and trigger a snapshot. Watch for
//      session.last_check_in_id == our request id to know it landed.

async function liveFetchJSON(path, init = {}) {
  const r = await fetch(path, {
    credentials: 'include',
    ...init,
    headers: {
      'Content-Type': 'application/json',
      ...(init.headers || {}),
    },
  });
  if (r.status === 401) {
    const e = new Error('unauthenticated');
    e.status = 401;
    throw e;
  }
  if (!r.ok) {
    let detail = '';
    try {
      const j = await r.clone().json();
      detail = j?.detail || j?.error || j?.message || '';
    } catch {
      try { detail = (await r.text()).slice(0, 280); } catch {}
    }
    const e = new Error(detail || `${r.status} ${r.statusText}`);
    e.status = r.status;
    throw e;
  }
  try { return await r.json(); } catch { return {}; }
}

function fmtRelativeSeconds(iso) {
  if (!iso) return 'just now';
  const t = Date.parse(iso);
  if (Number.isNaN(t)) return 'just now';
  const secs = Math.max(0, Math.floor((Date.now() - t) / 1000));
  if (secs < 30) return 'just now';
  if (secs < 60) return `${secs}s ago`;
  const mins = Math.floor(secs / 60);
  if (mins < 60) return `${mins}m ago`;
  const hrs = Math.floor(mins / 60);
  return `${hrs}h ago`;
}

function LiveCoach() {
  const [authState, setAuthState] = React.useState('checking');  // checking | signedout | signedin
  const [session, setSession] = React.useState(null);            // slim _live_session_view, or null
  const [fetchErr, setFetchErr] = React.useState('');
  const [checkInBusy, setCheckInBusy] = React.useState(false);
  const [pendingCheckInId, setPendingCheckInId] = React.useState(null);
  const [tick, setTick] = React.useState(0);  // forces the "Updated Xs ago" label to reflow

  // Auth gate. Done once on mount; if signed in we kick off the polling
  // effect, otherwise show a Sign-in button (foyerSignIn from index.html).
  React.useEffect(() => {
    (async () => {
      const me = await window.foyerMe?.();
      setAuthState(me ? 'signedin' : 'signedout');
    })();
  }, []);

  // Poll loop — only runs while signed in. The /live/sessions/current
  // endpoint returns the most-recently-snapshotted in-flight session,
  // or {session: null} when nothing is live.
  React.useEffect(() => {
    if (authState !== 'signedin') return;
    let alive = true;

    async function once() {
      try {
        let s = null;
        if (session?.id) {
          // We're already tracking a session — poll it directly so the
          // companion keeps watching even after is_live flips to false
          // (final tick lands a few seconds after End Session).
          s = await liveFetchJSON(`/live/sessions/${session.id}`);
        } else {
          const r = await liveFetchJSON('/live/sessions/current');
          s = r.session;
        }
        if (!alive) return;
        setSession(s);
        setFetchErr('');
        if (s && pendingCheckInId && s.last_check_in_id === pendingCheckInId) {
          setCheckInBusy(false);
          setPendingCheckInId(null);
        }
      } catch (e) {
        if (!alive) return;
        if (e.status === 401) {
          setAuthState('signedout');
          return;
        }
        setFetchErr(e.message || 'Could not reach the backend.');
      }
    }
    once();
    const t = setInterval(once, 3000);
    return () => { alive = false; clearInterval(t); };
  }, [authState, session?.id, pendingCheckInId]);

  // 1s ticker for the "Updated Ns ago" label.
  React.useEffect(() => {
    const t = setInterval(() => setTick((v) => v + 1), 1000);
    return () => clearInterval(t);
  }, []);

  async function requestCheckIn() {
    if (!session?.id || checkInBusy) return;
    setCheckInBusy(true);
    try {
      const r = await liveFetchJSON(`/live/sessions/${session.id}/check_in`, {
        method: 'POST',
        body: JSON.stringify({}),
      });
      setPendingCheckInId(r.check_in_id);
    } catch (e) {
      setCheckInBusy(false);
      if (e.status === 401) {
        setAuthState('signedout');
        return;
      }
      window.foyerToast?.({ message: e.message || 'Check-in failed', kind: 'error' });
    }
  }

  // ---- render branches ----

  if (authState === 'checking') {
    return (
      <div style={pageWrap}>
        <div style={panel}>
          <div style={spinner} />
          <div style={{ color: 'var(--cream-dim)' }}>Loading…</div>
        </div>
      </div>
    );
  }

  if (authState === 'signedout') {
    return (
      <div style={pageWrap}>
        <div style={panel}>
          <div style={eyebrow}>LIVE COACH</div>
          <h1 style={title}>Sign in to watch live</h1>
          <p style={lede}>
            Use the same Google account you sign in with on the phone.
            Whatever's recording there will show up here automatically.
          </p>
          <button onClick={() => window.foyerSignIn?.()} style={primaryBtn}>
            Sign in with Google
          </button>
        </div>
      </div>
    );
  }

  // Signed in but nothing live yet.
  if (!session) {
    return (
      <div style={pageWrap}>
        <div style={panel}>
          <div style={eyebrow}>LIVE COACH</div>
          <h1 style={title}>Waiting for a recording…</h1>
          <p style={lede}>
            Start a session on your phone. Once it's running, this page
            will switch over and let you ask for live coaching whenever
            buyers wander off to look around.
          </p>
          {fetchErr && (
            <div style={errorLine}>Can't reach the backend: {fetchErr}</div>
          )}
          <div style={{ ...lede, fontSize: 12, marginTop: 12 }}>
            We check every few seconds — leave this tab open.
          </div>
        </div>
      </div>
    );
  }

  // Signed in + a live session in flight.
  const headline = session.address || session.name || 'Open house';
  const isLive = !!session.is_live;
  const coverage = session.script_coverage;

  return (
    <div style={pageWrap}>
      <div style={liveHeader}>
        <div>
          <div style={eyebrow}>
            {isLive ? 'LIVE' : 'WRAPPING UP'} · LIVE COACH
          </div>
          <h1 style={{ ...title, marginBottom: 6 }}>{headline}</h1>
          <div style={{ fontSize: 12, color: 'var(--cream-dim)' }}>
            Updated {fmtRelativeSeconds(session.last_snapshot_at)}
            <span style={{ display: 'none' }}>{tick}</span>
          </div>
        </div>
      </div>

      <div style={checkInRow}>
        <button
          type="button"
          onClick={requestCheckIn}
          disabled={checkInBusy}
          style={{ ...primaryBtn, opacity: checkInBusy ? 0.6 : 1, marginBottom: 12 }}
        >
          {checkInBusy ? 'Listening… (usually 20–40s)' : 'Check in now'}
        </button>
        <div style={{ fontSize: 12, color: 'var(--cream-dim)', lineHeight: 1.5 }}>
          Tap when the buyers wander off — we'll grab the conversation so
          far and tell you what's missing and what to ask next.
        </div>
      </div>

      <CoverageBlock coverage={coverage} />
    </div>
  );
}

// Phase-1 panel: render the existing script_coverage block. Phase 2 will
// swap this for purpose-built coaching cards (headline / covered /
// missing / suggested next questions).
function CoverageBlock({ coverage }) {
  if (!coverage) {
    return (
      <div style={panelSoft}>
        <div style={{ fontSize: 14, fontWeight: 600 }}>No script attached.</div>
        <div style={{ fontSize: 12, color: 'var(--cream-dim)', marginTop: 6, lineHeight: 1.5 }}>
          Pick a script on the phone before recording to get live coverage
          feedback here. (Phase 2 will also work without one.)
        </div>
      </div>
    );
  }
  if (coverage.error) {
    return (
      <div style={panelSoft}>
        <div style={{ fontWeight: 600, marginBottom: 6 }}>Coverage analysis failed</div>
        <div style={{ fontSize: 13, color: 'var(--cream-dim)' }}>{coverage.error}</div>
      </div>
    );
  }
  const steps = coverage.steps || [];
  const hit = steps.filter((s) => s.status === 'hit');
  const partial = steps.filter((s) => s.status === 'partial');
  const missed = steps.filter((s) => s.status === 'missed');

  return (
    <div>
      <div style={scoreCard}>
        <div style={{ fontSize: 11, letterSpacing: 1.4, color: 'var(--cream-dim)' }}>
          {(coverage.script_name || 'Script').toUpperCase()}
        </div>
        <div style={{ display: 'flex', alignItems: 'baseline', gap: 8, marginTop: 6 }}>
          <div style={{ fontSize: 44, fontWeight: 600, color: 'var(--cream)' }}>
            {coverage.score ?? '—'}
          </div>
          <div style={{ fontSize: 14, color: 'var(--cream-dim)' }}>/ 100</div>
        </div>
        {coverage.overall_summary && (
          <div style={{ fontSize: 13, color: 'var(--cream-dim)', marginTop: 10, lineHeight: 1.5 }}>
            {coverage.overall_summary}
          </div>
        )}
      </div>

      <CoverageColumn title="Covered" tone="sage" steps={hit} />
      <CoverageColumn title="Partially covered" tone="gold" steps={partial} />
      <CoverageColumn title="Missed — ask next" tone="terracotta" steps={missed} />
    </div>
  );
}

function CoverageColumn({ title, tone, steps }) {
  if (!steps.length) return null;
  const dot = tone === 'sage' ? '#86efac' : tone === 'gold' ? '#c9a86a' : '#f87171';
  return (
    <div style={{ marginBottom: 22 }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 10 }}>
        <span style={{ width: 8, height: 8, borderRadius: '50%', background: dot }} />
        <div style={{
          fontSize: 11, letterSpacing: 1.4, color: 'var(--cream-dim)',
          textTransform: 'uppercase',
        }}>{title} · {steps.length}</div>
      </div>
      {steps.map((s) => (
        <div key={s.step_id} style={coverageRow}>
          <div style={{ fontSize: 14, color: 'var(--cream)', fontWeight: 500 }}>
            {s.step_id}
          </div>
          {s.evidence && (
            <div style={{ fontSize: 12, color: 'var(--cream-dim)', marginTop: 4, lineHeight: 1.5 }}>
              "{s.evidence}"
            </div>
          )}
          {s.suggestion && (
            <div style={{ fontSize: 12, color: 'var(--cream-dim)', marginTop: 6, lineHeight: 1.5,
                          fontStyle: 'italic' }}>
              {s.suggestion}
            </div>
          )}
        </div>
      ))}
    </div>
  );
}

// ---------- styles (inline so the file is self-contained) ----------

const pageWrap = {
  minHeight: '100vh',
  background: 'var(--bg-deep)',
  color: 'var(--cream)',
  padding: '36px 28px 48px',
  fontFamily: "'Geist', -apple-system, system-ui, sans-serif",
  maxWidth: 720,
  margin: '0 auto',
};

const panel = {
  background: 'var(--bg-elev)',
  border: '1px solid var(--hairline)',
  borderRadius: 18,
  padding: '36px 32px',
  textAlign: 'left',
  marginTop: 60,
};

const panelSoft = {
  padding: 22,
  background: 'var(--bg-elev)',
  border: '1px solid var(--hairline)',
  borderRadius: 14,
};

const liveHeader = {
  marginBottom: 24,
};

const eyebrow = {
  fontSize: 10,
  letterSpacing: 1.6,
  color: 'var(--gold)',
  fontFamily: "'Geist Mono', monospace",
  marginBottom: 10,
};

const title = {
  fontSize: 30,
  fontWeight: 500,
  margin: '0 0 12px',
  fontFamily: "'Newsreader', serif",
};

const lede = {
  fontSize: 13,
  color: 'var(--cream-dim)',
  lineHeight: 1.6,
  marginBottom: 24,
};

const primaryBtn = {
  background: 'var(--gold)',
  color: '#08090b',
  border: 0,
  borderRadius: 10,
  padding: '14px 22px',
  fontSize: 15,
  fontWeight: 600,
  cursor: 'pointer',
  width: '100%',
};

const checkInRow = {
  background: 'var(--bg-elev)',
  border: '1px solid var(--hairline)',
  borderRadius: 14,
  padding: 20,
  marginBottom: 28,
};

const scoreCard = {
  background: 'var(--bg-elev)',
  border: '1px solid var(--hairline)',
  borderRadius: 14,
  padding: 22,
  marginBottom: 24,
};

const coverageRow = {
  padding: '12px 14px',
  background: 'var(--bg-elev)',
  border: '1px solid var(--hairline)',
  borderRadius: 10,
  marginBottom: 8,
};

const errorLine = {
  fontSize: 12,
  color: '#f87171',
  marginBottom: 8,
};

const spinner = {
  width: 28, height: 28, margin: '0 auto 16px',
  border: '2px solid var(--hairline)',
  borderTopColor: 'var(--gold)',
  borderRadius: '50%',
  animation: 'spin 0.9s linear infinite',
};

// Spin animation — appended once per page load.
if (typeof document !== 'undefined' && !document.getElementById('live-coach-styles')) {
  const style = document.createElement('style');
  style.id = 'live-coach-styles';
  style.textContent = `
    @keyframes spin { from { transform: rotate(0deg); } to { transform: rotate(360deg); } }
  `;
  document.head.appendChild(style);
}
