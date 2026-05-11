/* global React, AppShell, Tag, Eyebrow, useFoyerData, leadBucket, fmtRelative, fmtClock, foyerGoToSession */

// /#/sessions — index page. The agent lands here when they click "Sessions"
// in the sidebar; only after picking one do we route into the detail view.
// Sortable by recency, filterable by recorded vs manual, with a per-card
// preview so they can spot the right session without drilling in.

const SessionsList = () => {
  const { summaries, sessionsById, loading, error } = useFoyerData();
  const [kindFilter, setKindFilter] = React.useState('all');  // all | recorded | manual
  const [search, setSearch] = React.useState('');

  const sortedSummaries = React.useMemo(() => {
    return [...summaries].sort((a, b) => (b.created_at || '').localeCompare(a.created_at || ''));
  }, [summaries]);

  const filtered = sortedSummaries.filter(s => {
    const kind = s.kind || 'recorded';
    if (kindFilter !== 'all' && kind !== kindFilter) return false;
    const q = search.trim().toLowerCase();
    if (!q) return true;
    if ((s.address || '').toLowerCase().includes(q)) return true;
    const visitors = sessionsById[s.id]?.result?.visitors || [];
    return visitors.some(v => (v.visitor?.name || '').toLowerCase().includes(q));
  });

  return (
    <AppShell active="sessions">
      <div style={{ padding: '40px 56px 80px' }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-end', marginBottom: 32 }}>
          <div>
            <div className="eyebrow">Library</div>
            <h1 className="serif" style={{ fontSize: 48, margin: '12px 0 0', color: 'var(--cream)', lineHeight: 1 }}>
              Sessions <span className="serif-it" style={{ color: 'var(--gold)' }}>·</span> {summaries.length}
            </h1>
            <p style={{ marginTop: 12, color: 'var(--text-dim)', fontSize: 14 }}>
              Every recording and manual lead, newest first. Pick one to dive in.
            </p>
          </div>
          <a href="#/kiosk" className="btn">Open kiosk</a>
        </div>

        {/* search + kind chips */}
        <div style={{ display: 'flex', gap: 18, alignItems: 'center', marginBottom: 24, flexWrap: 'wrap' }}>
          <div style={{ position: 'relative', flex: 1, minWidth: 260, maxWidth: 420 }}>
            <input
              value={search}
              onChange={e => setSearch(e.target.value)}
              placeholder="Search address or guest…"
              style={{
                width: '100%', background: 'transparent', border: 0,
                borderBottom: '1px solid var(--hairline)',
                padding: '10px 0', color: 'var(--cream)', fontSize: 13,
                fontFamily: 'var(--sans)', outline: 'none',
              }}
            />
          </div>
          <div style={{ display: 'flex', gap: 6 }}>
            {[
              { id: 'all',      label: 'All' },
              { id: 'recorded', label: 'Recorded' },
              { id: 'manual',   label: 'Manual' },
            ].map(opt => (
              <button key={opt.id}
                      onClick={() => setKindFilter(opt.id)}
                      className={'mono chip' + (kindFilter === opt.id ? ' is-active' : '')}
                      style={{
                        padding: '5px 14px',
                        background: kindFilter === opt.id ? 'var(--gold-soft)' : 'transparent',
                        color: kindFilter === opt.id ? 'var(--gold)' : 'var(--text-dim)',
                        border: '1px solid ' + (kindFilter === opt.id ? 'var(--gold)' : 'var(--hairline)'),
                        fontSize: 10, letterSpacing: '0.12em', textTransform: 'uppercase', cursor: 'pointer',
                        borderRadius: 999,
                      }}>{opt.label}</button>
            ))}
          </div>
        </div>

        {loading && (
          <div className="mono" style={{ color: 'var(--text-muted)', letterSpacing: '0.14em', fontSize: 11 }}>LOADING…</div>
        )}
        {error && (
          <div style={{ padding: 16, border: '1px solid var(--terracotta)', color: 'var(--terracotta)', fontSize: 13 }}>
            Couldn't load: {error}
          </div>
        )}

        {!loading && filtered.length === 0 && (
          <div style={{
            padding: '60px 32px', textAlign: 'center',
            border: '1px solid var(--hairline)', borderRadius: 14,
            color: 'var(--text-dim)',
          }}>
            <div className="serif" style={{ fontSize: 20, color: 'var(--cream)' }}>
              {summaries.length === 0 ? 'No sessions yet.' : 'No sessions match.'}
            </div>
            <p style={{ marginTop: 8, fontSize: 13 }}>
              {summaries.length === 0
                ? 'Record an open house from the iOS app, or add a lead manually below.'
                : 'Try clearing the search or switching kind filter.'}
            </p>
            {summaries.length === 0 && (
              <a href="#/kiosk" className="btn btn-primary" style={{ marginTop: 18, display: 'inline-block' }}>Open kiosk</a>
            )}
          </div>
        )}

        {/* card grid */}
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(340px, 1fr))', gap: 16 }}>
          {filtered.map(s => {
            const full = sessionsById[s.id];
            const visitors = full?.result?.visitors || [];
            const needsCount = visitors.filter(v => leadBucket(v.lead_state) === 'needs').length;
            const kind = s.kind || 'recorded';
            return (
              <div key={s.id}
                   className="stat-card lead-row"
                   onClick={() => foyerGoToSession(s.id)}
                   style={{
                     background: 'var(--bg-card)', borderRadius: 14, padding: '22px 22px 18px',
                     display: 'flex', flexDirection: 'column', gap: 14,
                     cursor: 'pointer',
                   }}>
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', gap: 12 }}>
                  <div>
                    <div className="serif" style={{ fontSize: 22, color: 'var(--cream)', lineHeight: 1.15 }}>
                      {s.address || <span style={{ color: 'var(--text-dim)' }}>Untitled session</span>}
                    </div>
                    <div className="mono" style={{ fontSize: 9.5, color: 'var(--text-muted)', marginTop: 6, letterSpacing: '0.14em' }}>
                      {fmtRelative(s.created_at)} · {s.visitor_count || 0} {(s.visitor_count || 0) === 1 ? 'GUEST' : 'GUESTS'}
                    </div>
                  </div>
                  <KindPill kind={kind} status={s.status} />
                </div>

                {visitors.length > 0 && (
                  <div style={{ display: 'flex', flexDirection: 'column', gap: 6, paddingTop: 10, borderTop: '1px solid var(--hairline)' }}>
                    {visitors.slice(0, 3).map(v => {
                      const tagToken = (v.analysis?.tag || '').toLowerCase();
                      return (
                        <div key={(v.visitor?.name || '') + ':' + (v.visitor?.speaker || '')}
                             style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 10 }}>
                          <span style={{ fontSize: 13, color: 'var(--cream-dim)', overflow: 'hidden', whiteSpace: 'nowrap', textOverflow: 'ellipsis' }}>
                            {v.visitor?.name || '—'}
                          </span>
                          <Tag kind={tagToken}>{v.analysis?.score ?? '—'}</Tag>
                        </div>
                      );
                    })}
                    {visitors.length > 3 && (
                      <div className="mono" style={{ fontSize: 9.5, color: 'var(--text-muted)', letterSpacing: '0.12em', paddingTop: 4 }}>
                        + {visitors.length - 3} MORE
                      </div>
                    )}
                  </div>
                )}

                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginTop: 'auto', paddingTop: 4 }}>
                  <span className="mono" style={{ fontSize: 9.5, color: needsCount > 0 ? 'var(--gold)' : 'var(--text-muted)', letterSpacing: '0.12em' }}>
                    {needsCount > 0 ? `${needsCount} NEED${needsCount === 1 ? 'S' : ''} ACTION` : 'INBOX CLEAR'}
                  </span>
                  <span className="serif-it lead-row-review" style={{ fontSize: 13, color: 'var(--gold)' }}>Open →</span>
                </div>
              </div>
            );
          })}
        </div>
      </div>
    </AppShell>
  );
};

function KindPill({ kind, status }) {
  const isProcessing = status === 'processing';
  if (isProcessing) {
    return (
      <span className="mono" style={{
        fontSize: 9, padding: '3px 8px', borderRadius: 999,
        color: 'var(--gold)', background: 'var(--gold-soft)',
        border: '1px solid var(--gold)', letterSpacing: '0.14em',
      }}>PROCESSING…</span>
    );
  }
  if (kind === 'manual') {
    return (
      <span className="mono" style={{
        fontSize: 9, padding: '3px 8px', borderRadius: 999,
        color: 'var(--cream)', background: 'transparent',
        border: '1px solid var(--hairline)', letterSpacing: '0.14em',
      }}>MANUAL</span>
    );
  }
  return (
    <span className="mono" style={{
      fontSize: 9, padding: '3px 8px', borderRadius: 999,
      color: 'var(--gold)', background: 'transparent',
      border: '1px solid var(--gold)', letterSpacing: '0.14em',
    }}>RECORDED</span>
  );
}

Object.assign(window, { SessionsList });
