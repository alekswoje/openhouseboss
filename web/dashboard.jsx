/* global React, AppShell, Tag, Eyebrow, useFoyerData, allLoadedVisitors, leadBucket, fmtRelative, fmtClock, greetingHour */

const Dashboard = () => {
  const { user, summaries, sessionsById, loading, error } = useFoyerData();

  const recordedSummaries = summaries.filter(s => (s.kind || 'recorded') !== 'manual');
  const featured = recordedSummaries.find(s => s.status === 'ready') || summaries[0];
  const featuredSession = featured ? sessionsById[featured.id] : null;
  const featuredVisitors = (featuredSession?.result?.visitors || []).slice().sort((a, b) =>
    (b.analysis?.score || 0) - (a.analysis?.score || 0)
  );

  const visitors = allLoadedVisitors(sessionsById);
  const needs = visitors.filter(v => leadBucket(v.lead_state) === 'needs');
  const topScore = visitors.reduce((m, v) => Math.max(m, v.analysis?.score || 0), 0);
  const topScoreVisitor = visitors.find(v => (v.analysis?.score || 0) === topScore);

  const firstName = (user?.name || '').split(' ')[0] || 'there';

  return (
    <AppShell active="today">
      <div style={{ padding: '40px 56px 80px' }}>
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
                <a href="#/kiosk" className="btn">Open kiosk</a>
                <a href="#/sessions" className="btn btn-primary">All sessions</a>
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
                    <a href="#/sessions" className="serif-it" style={{ fontSize: 12, color: 'var(--gold)', textDecoration: 'none' }}>Browse all →</a>
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

                    <div style={{ marginTop: 28 }}>
                      {featuredVisitors.length === 0 ? (
                        <div style={{ padding: '22px 0', borderTop: '1px solid var(--hairline)', color: 'var(--text-dim)', fontSize: 13 }}>
                          No guests detected — recording may have been too short.
                        </div>
                      ) : featuredVisitors.map((v, i) => {
                        const tagToken = (v.analysis?.tag || '').toLowerCase();
                        const sig = (v.analysis?.signals || [])[0];
                        return (
                          <div key={v.visitor.name + ':' + (v.visitor.speaker || '')}
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

              <div>
                <Eyebrow>The follow-up queue</Eyebrow>
                <div style={{ marginTop: 16 }}>
                  {needs.length === 0 ? (
                    <div style={{ padding: '20px 0', color: 'var(--text-dim)', fontSize: 13 }}>
                      Nothing waiting on you. New recordings will land here as drafts.
                    </div>
                  ) : needs.slice(0, 8).map((v) => {
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
      </div>
    </AppShell>
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

Object.assign(window, { Dashboard, foyerGoToSession: goToSession });
