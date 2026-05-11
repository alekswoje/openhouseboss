/* global React, Crest, Tag, Eyebrow, useFoyerData, allLoadedVisitors, leadBucket, fmtRelative, fmtClock, greetingHour, foyerSignOut */

const Dashboard = () => {
  const { user, summaries, sessionsById, loading, error } = useFoyerData();
  const [menuOpen, setMenuOpen] = React.useState(false);

  // Most recent ready session = "today's open house" feature.
  const recordedSummaries = summaries.filter(s => (s.kind || 'recorded') !== 'manual');
  const allSummaries = summaries;
  const featured = recordedSummaries.find(s => s.status === 'ready') || allSummaries[0];
  const featuredSession = featured ? sessionsById[featured.id] : null;
  const featuredVisitors = (featuredSession?.result?.visitors || []).slice().sort((a, b) =>
    (b.analysis?.score || 0) - (a.analysis?.score || 0)
  );

  // Inbox view: every loaded visitor across every session, bucketed by lead
  // state. Drives the right-rail follow-up queue and the YTD count.
  const visitors = allLoadedVisitors(sessionsById);
  const needs = visitors.filter(v => leadBucket(v.lead_state) === 'needs');
  const done = visitors.filter(v => leadBucket(v.lead_state) === 'done');
  const topScore = visitors.reduce((m, v) => Math.max(m, v.analysis?.score || 0), 0);
  const topScoreVisitor = visitors.find(v => (v.analysis?.score || 0) === topScore);

  const firstName = (user?.name || '').split(' ')[0] || 'there';

  return (
    <div className="foyer" data-screen-label="Dashboard" style={{ background: 'var(--bg)', minHeight: '100%', display: 'grid', gridTemplateColumns: '240px 1fr' }}>

      {/* SIDEBAR */}
      <aside style={{ borderRight: '1px solid var(--hairline)', padding: '24px 0', background: 'var(--bg-deep)', position: 'relative' }}>
        <div style={{ padding: '0 24px 24px', borderBottom: '1px solid var(--hairline)' }}>
          <Crest size={18} />
        </div>
        <nav style={{ padding: '20px 0' }}>
          {[
            { label: 'Today',     sub: featured ? featured.address || 'Recent session' : 'No sessions yet', active: true },
            { label: 'Sessions',  sub: `${recordedSummaries.length} recorded`, go: () => featured && goToSession(featured.id) },
            { label: 'Leads',     sub: `${visitors.length} total` },
            { label: 'Needs action', sub: `${needs.length} open` },
            { label: 'Done',      sub: `${done.length} archived/replied` },
          ].map(item => (
            <div key={item.label}
                 className={'nav-item' + (item.active ? ' is-active' : '')}
                 onClick={item.go || (() => {})} style={{
              padding: '12px 24px',
              borderLeft: item.active ? '2px solid var(--gold)' : '2px solid transparent',
              background: item.active ? 'var(--gold-soft)' : 'transparent',
              cursor: item.go ? 'pointer' : 'default',
            }}>
              <div className="nav-item-label" style={{ fontSize: 14, color: item.active ? 'var(--gold)' : 'var(--cream)', fontWeight: item.active ? 500 : 400 }}>{item.label}</div>
              <div className="mono" style={{ fontSize: 10, color: 'var(--text-muted)', marginTop: 2, letterSpacing: '0.1em' }}>{item.sub}</div>
            </div>
          ))}
        </nav>

        {/* User card pinned to bottom */}
        <div style={{ padding: '20px 24px', borderTop: '1px solid var(--hairline)', position: 'absolute', bottom: 24, width: 240 }}>
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
              <div className="mono" style={{ fontSize: 10, color: 'var(--text-muted)', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{(user?.email || '').toUpperCase()}</div>
            </div>
            <span className="mono" style={{ fontSize: 14, color: 'var(--text-muted)' }}>⌄</span>
          </div>
          {menuOpen && (
            <div style={{
              position: 'absolute', left: 16, bottom: 78, width: 240,
              background: 'var(--bg-card)', border: '1px solid var(--border-strong)', borderRadius: 12,
              boxShadow: '0 30px 80px -20px rgba(0,0,0,0.6)', padding: '8px 0',
            }}>
              <div onClick={() => { setMenuOpen(false); foyerSignOut(); }}
                   style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '10px 16px', fontSize: 13, color: 'var(--terracotta)', cursor: 'pointer' }}>
                <span style={{ width: 16, textAlign: 'center' }}>⇥</span>Log out
              </div>
            </div>
          )}
        </div>
      </aside>

      {/* MAIN */}
      <main style={{ padding: '40px 56px 80px', overflowY: 'auto' }}>
        {loading && (
          <div className="mono" style={{ color: 'var(--text-muted)', letterSpacing: '0.14em', fontSize: 11 }}>LOADING SESSIONS…</div>
        )}
        {error && (
          <div style={{ padding: 16, border: '1px solid var(--terracotta)', color: 'var(--terracotta)', fontSize: 13 }}>
            Couldn't load: {error}
          </div>
        )}

        {!loading && (
          <>
            {/* greeting */}
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-end' }}>
              <div>
                <div className="eyebrow">{new Date().toLocaleDateString(undefined, { weekday: 'long', month: 'long', day: 'numeric' }).toUpperCase()}</div>
                <h1 className="serif" style={{ fontSize: 56, margin: '12px 0 0', color: 'var(--cream)', lineHeight: 1 }}>
                  Good {greetingHour()}, <span className="serif-it" style={{ color: 'var(--gold)' }}>{firstName}.</span>
                </h1>
                <p style={{ marginTop: 14, color: 'var(--text-dim)', fontSize: 15 }}>
                  {needs.length === 0
                    ? <>Inbox zero — every captured lead has been handled. Nice.</>
                    : <>You have <span style={{ color: 'var(--cream)' }}>{needs.length} {needs.length === 1 ? 'lead' : 'leads'}</span> waiting on a follow-up.</>
                  }
                </p>
              </div>
              <div style={{ display: 'flex', gap: 12 }}>
                <button className="btn" onClick={() => alert('Open the iOS app to start recording.')}>Start session</button>
                {featured && (
                  <button className="btn btn-primary" onClick={() => goToSession(featured.id)}>Review follow-ups</button>
                )}
              </div>
            </div>

            {/* numbers row */}
            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: 12, marginTop: 56 }}>
              {[
                { v: featuredVisitors.length || 0, label: 'Last session', sub: featured?.address || '—' },
                { v: topScore || 0, s: topScore ? '/100' : '', label: 'Top lead score', sub: topScoreVisitor?.visitor?.name || '—' },
                { v: needs.length, label: 'Needs action', sub: 'in the inbox' },
                { v: visitors.length, label: 'Leads captured', sub: `${recordedSummaries.length} open houses` },
              ].map(stat => (
                <div key={stat.label} className="stat-card" style={{ background: 'var(--bg-card)', borderRadius: 14, padding: '28px 24px' }}>
                  <div className="eyebrow">{stat.label}</div>
                  <div style={{ marginTop: 14, fontFamily: 'var(--serif)', fontSize: 48, lineHeight: 1, color: 'var(--cream)' }}>
                    {stat.v}
                    {stat.s && <span style={{ color: 'var(--gold)', fontStyle: 'italic', fontSize: 28 }}>{stat.s}</span>}
                  </div>
                  <div className="mono" style={{ fontSize: 10, color: 'var(--text-muted)', marginTop: 10, letterSpacing: '0.1em' }}>{(stat.sub || '').toUpperCase()}</div>
                </div>
              ))}
            </div>

            {/* featured session */}
            <div style={{ marginTop: 64, display: 'grid', gridTemplateColumns: '1.4fr 1fr', gap: 40 }}>
              <div>
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline' }}>
                  <Eyebrow>{featured ? 'Most recent session' : 'No sessions yet'}</Eyebrow>
                  {featured && (
                    <a onClick={() => goToSession(featured.id)} className="serif-it" style={{ fontSize: 12, color: 'var(--gold)', cursor: 'pointer' }}>Open session →</a>
                  )}
                </div>
                {featured ? (
                  <>
                    <div className="serif" style={{ fontSize: 36, marginTop: 14, color: 'var(--cream)', lineHeight: 1.05 }}>
                      {featured.address || 'Untitled session'}
                    </div>
                    <div className="mono" style={{ fontSize: 11, color: 'var(--text-muted)', marginTop: 10, letterSpacing: '0.14em' }}>
                      {fmtClock(featured.created_at)} · {featured.visitor_count || 0} {(featured.visitor_count || 0) === 1 ? 'GUEST' : 'GUESTS'}
                      {featured.completed_at ? ` · COMPLETED ${fmtRelative(featured.completed_at)}` : ''}
                    </div>

                    <div style={{ marginTop: 28, display: 'flex', flexDirection: 'column', gap: 0 }}>
                      {featuredVisitors.length === 0 ? (
                        <div style={{ padding: '22px 0', borderTop: '1px solid var(--hairline)', color: 'var(--text-dim)', fontSize: 13 }}>
                          No guests detected — recording may have been too short.
                        </div>
                      ) : featuredVisitors.map((v, i) => {
                        const tagToken = (v.analysis?.tag || '').toLowerCase();
                        const sig = (v.analysis?.signals || [])[0];
                        return (
                          <div
                            key={v.visitor.name + ':' + (v.visitor.speaker || '')}
                            className="lead-row"
                            onClick={() => goToSession(featured.id, v.visitor.name)}
                            style={{
                              padding: '22px 4px',
                              borderTop: '1px solid var(--hairline)',
                              borderBottom: i === featuredVisitors.length - 1 ? '1px solid var(--hairline)' : 'none',
                              display: 'grid', gridTemplateColumns: '40px 1fr auto', gap: 20, alignItems: 'start',
                            }}>
                            <div className="mono" style={{ fontSize: 12, color: 'var(--gold)', letterSpacing: '0.1em' }}>{String(i + 1).padStart(2, '0')}</div>
                            <div>
                              <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
                                <span className="serif" style={{ fontSize: 22, color: 'var(--cream)' }}>{v.visitor.name}</span>
                                <Tag kind={tagToken}>{v.analysis.tag} · {v.analysis.score}</Tag>
                              </div>
                              <div style={{ marginTop: 8, fontSize: 13, color: 'var(--text-dim)', lineHeight: 1.55, maxWidth: 540 }}>
                                {(v.analysis?.summary || '').split('. ')[0]}.
                              </div>
                              {sig && (
                                <div style={{ marginTop: 10, display: 'flex', gap: 8, flexWrap: 'wrap' }}>
                                  <span className="mono" style={{ fontSize: 9, padding: '3px 8px', border: '1px solid var(--hairline)', color: 'var(--text-dim)', letterSpacing: '0.06em' }}>{sig.toUpperCase()}</span>
                                </div>
                              )}
                            </div>
                            <div style={{ textAlign: 'right' }}>
                              <div className="mono" style={{ fontSize: 10, color: 'var(--text-muted)' }}>{leadStateLabel(v.lead_state)}</div>
                              <div className="serif-it lead-row-review" style={{ fontSize: 13, color: 'var(--gold)', marginTop: 18 }}>Review →</div>
                            </div>
                          </div>
                        );
                      })}
                    </div>
                  </>
                ) : (
                  <div style={{ marginTop: 18, padding: 24, border: '1px solid var(--hairline)', color: 'var(--text-dim)', fontSize: 14 }}>
                    Record an open house from the iOS app and it'll show up here.
                  </div>
                )}
              </div>

              {/* right column — needs-action queue */}
              <div>
                <Eyebrow>The follow-up queue</Eyebrow>
                <div style={{ marginTop: 16 }}>
                  {needs.length === 0 ? (
                    <div style={{ padding: '20px 0', color: 'var(--text-dim)', fontSize: 13 }}>
                      Nothing waiting on you. New recordings will land here as drafts.
                    </div>
                  ) : needs.slice(0, 8).map((v, i) => {
                    const tagToken = (v.analysis?.tag || '').toLowerCase();
                    return (
                      <div key={v._session.id + ':' + v._id}
                           className="queue-row"
                           onClick={() => goToSession(v._session.id, v.visitor.name)}
                           style={{ padding: '16px 6px', borderBottom: '1px solid var(--hairline)' }}>
                        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                          <span style={{ fontSize: 14, color: 'var(--cream)' }}>{v.visitor.name}</span>
                          <Tag kind={tagToken} />
                        </div>
                        <div style={{ display: 'flex', justifyContent: 'space-between', marginTop: 6 }}>
                          <span className="mono" style={{ fontSize: 10, color: 'var(--gold)', letterSpacing: '0.1em' }}>
                            {(v._session.address || 'NO ADDRESS').toUpperCase()}
                          </span>
                          <span className="mono" style={{ fontSize: 10, color: 'var(--text-muted)' }}>
                            {leadStateLabel(v.lead_state)}
                          </span>
                        </div>
                      </div>
                    );
                  })}
                </div>
              </div>
            </div>
          </>
        )}
      </main>
    </div>
  );
};

function leadStateLabel(s) {
  if (!s) return 'NEEDS DRAFT';
  if (s.snoozed_until) {
    const t = Date.parse(s.snoozed_until);
    if (!Number.isNaN(t) && t > Date.now()) return `SNOOZED · ${new Date(t).toLocaleDateString(undefined, { month: 'short', day: 'numeric' }).toUpperCase()}`;
  }
  switch (s.status) {
    case 'drafted':  return 'DRAFT';
    case 'sent':     return s.sent_at ? `SENT · ${fmtRelative(s.sent_at)}` : 'SENT';
    case 'replied':  return 'REPLIED';
    case 'archived': return 'ARCHIVED';
    default:         return (s.status || '').toUpperCase();
  }
}

function goToSession(sessionId, visitorName) {
  window.foyerActiveSessionId = sessionId;
  if (visitorName) window.foyerActiveVisitorName = visitorName;
  window.foyerGo('#/session');
}

Object.assign(window, { Dashboard });
