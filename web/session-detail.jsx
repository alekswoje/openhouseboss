/* global React, Crest, Tag, Eyebrow, Hairline, SAMPLE_VISITORS, SAMPLE_TRANSCRIPT */
const { useState: useStateS } = React;

const SessionDetail = () => {
  const [active, setActive] = useStateS(1);
  const [search, setSearch] = useStateS('');
  const [filter, setFilter] = useStateS('all');
  const [editing, setEditing] = useStateS(false);
  const [draft, setDraft] = useStateS(SAMPLE_VISITORS[0].followUp);
  const [tagOverride, setTagOverride] = useStateS({});

  const visitors = SAMPLE_VISITORS.filter(v => {
    const t = tagOverride[v.id] || v.tag;
    if (filter !== 'all' && t !== filter) return false;
    if (search && !v.name.toLowerCase().includes(search.toLowerCase())) return false;
    return true;
  });

  const v = SAMPLE_VISITORS.find(x => x.id === active);
  const currentTag = tagOverride[active] || v.tag;

  const setTag = (id, t) => setTagOverride(o => ({ ...o, [id]: t }));

  return (
    <div className="foyer" data-screen-label="Session detail" style={{ background: 'var(--bg)', minHeight: '100%', display: 'grid', gridTemplateColumns: '240px 320px 1fr' }}>

      {/* SIDEBAR (collapsed nav) */}
      <aside style={{ borderRight: '1px solid var(--hairline)', padding: '24px 0', background: 'var(--bg-deep)' }}>
        <div style={{ padding: '0 24px 24px', borderBottom: '1px solid var(--hairline)' }}>
          <Crest size={18} />
        </div>
        <div style={{ padding: '20px 24px' }}>
          <a
            className="serif-it"
            style={{ fontSize: 13, color: 'var(--gold)', cursor: 'pointer' }}
            onClick={() => window.foyerGo('#/app')}
          >← Today</a>
        </div>
        <div style={{ padding: '0 24px' }}>
          <Eyebrow>Recent sessions</Eyebrow>
          <div style={{ marginTop: 14 }}>
            {[
              { addr: '412 W 78th St', date: 'Today', active: true },
              { addr: '88 Riverside Dr', date: 'May 3' },
              { addr: '224 E 64th, 12-B', date: 'Apr 27' },
              { addr: '15 Central Pk W', date: 'Apr 19' },
            ].map(s => (
              <div key={s.addr} style={{ padding: '10px 0', borderBottom: '1px solid var(--hairline)' }}>
                <div style={{ fontSize: 13, color: s.active ? 'var(--gold)' : 'var(--cream)' }}>{s.addr}</div>
                <div className="mono" style={{ fontSize: 10, color: 'var(--text-muted)', letterSpacing: '0.1em', marginTop: 3 }}>{s.date.toUpperCase()}</div>
              </div>
            ))}
          </div>
        </div>
      </aside>

      {/* LEAD LIST */}
      <section style={{ borderRight: '1px solid var(--hairline)', display: 'flex', flexDirection: 'column' }}>
        <div style={{ padding: '32px 28px 0' }}>
          <Eyebrow>Session</Eyebrow>
          <div className="serif" style={{ fontSize: 24, color: 'var(--cream)', marginTop: 8, lineHeight: 1.1 }}>
            412 W 78th St<br/>
            <span className="serif-it" style={{ color: 'var(--gold)', fontSize: 16 }}>Saturday, May 10</span>
          </div>
          <div className="mono" style={{ fontSize: 10, color: 'var(--text-muted)', marginTop: 8, letterSpacing: '0.14em' }}>
            1H 47M · 3 GUESTS · $1.295M
          </div>

          {/* search */}
          <div style={{ marginTop: 24, position: 'relative' }}>
            <input
              value={search}
              onChange={e => setSearch(e.target.value)}
              placeholder="Search guests…"
              style={{
                width: '100%', background: 'transparent', border: 0, borderBottom: '1px solid var(--hairline)',
                padding: '10px 0', color: 'var(--cream)', fontSize: 13, fontFamily: 'var(--sans)',
                outline: 'none',
              }}
            />
            <span style={{ position: 'absolute', right: 0, top: 10, color: 'var(--text-muted)', fontSize: 12 }} className="mono">⌘K</span>
          </div>

          {/* filter chips */}
          <div style={{ marginTop: 18, display: 'flex', gap: 6, flexWrap: 'wrap' }}>
            {['all', 'buyer', 'seller', 'browser'].map(t => (
              <button key={t} onClick={() => setFilter(t)} className="mono" style={{
                padding: '4px 12px',
                background: filter === t ? 'var(--gold-soft)' : 'transparent',
                color: filter === t ? 'var(--gold)' : 'var(--text-dim)',
                border: '1px solid ' + (filter === t ? 'var(--gold)' : 'var(--hairline)'),
                fontSize: 10, letterSpacing: '0.12em', textTransform: 'uppercase', cursor: 'pointer',
                borderRadius: 999,
              }}>{t}</button>
            ))}
          </div>
        </div>

        <div style={{ marginTop: 24, flex: 1, overflowY: 'auto', padding: '0 0 28px' }}>
          {visitors.map(vis => {
            const t = tagOverride[vis.id] || vis.tag;
            return (
              <div
                key={vis.id}
                onClick={() => { setActive(vis.id); setDraft(vis.followUp); setEditing(false); }}
                style={{
                  padding: '16px 28px',
                  borderLeft: vis.id === active ? '2px solid var(--gold)' : '2px solid transparent',
                  background: vis.id === active ? 'var(--gold-soft)' : 'transparent',
                  cursor: 'pointer',
                  borderBottom: '1px solid var(--hairline)',
                }}
              >
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                  <span className="serif" style={{ fontSize: 18, color: vis.id === active ? 'var(--gold)' : 'var(--cream)' }}>{vis.name}</span>
                  <Tag kind={t}>{vis.score}</Tag>
                </div>
                <div className="mono" style={{ fontSize: 10, color: 'var(--text-muted)', marginTop: 4, letterSpacing: '0.1em' }}>
                  SIGNED · {vis.signedAt} · SPOKE {vis.spokeWords}W
                </div>
                <div style={{ fontSize: 12, color: 'var(--text-dim)', marginTop: 8, lineHeight: 1.5, overflow: 'hidden', display: '-webkit-box', WebkitLineClamp: 2, WebkitBoxOrient: 'vertical' }}>
                  {vis.summary}
                </div>
              </div>
            );
          })}
        </div>
      </section>

      {/* DETAIL PANE */}
      <section style={{ overflowY: 'auto' }}>
        <div style={{ padding: '32px 48px 60px' }}>

          {/* header */}
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start' }}>
            <div>
              <div className="eyebrow">Guest № {v.id} of 3</div>
              <h1 className="serif" style={{ fontSize: 56, margin: '14px 0 0', color: 'var(--cream)', lineHeight: 1 }}>{v.name}</h1>
              <div className="mono" style={{ fontSize: 11, color: 'var(--text-muted)', marginTop: 10, letterSpacing: '0.14em' }}>
                {v.email.toUpperCase()} · {v.phone}
              </div>
            </div>
            <div style={{ display: 'flex', gap: 10, alignItems: 'center' }}>
              <span className="serif" style={{ fontSize: 56, lineHeight: 1, color: 'var(--gold)' }}>
                {v.score}<span className="serif-it" style={{ fontSize: 24, color: 'var(--text-dim)' }}>/100</span>
              </span>
            </div>
          </div>

          {/* tag swap */}
          <div style={{ marginTop: 32, display: 'flex', alignItems: 'center', gap: 16 }}>
            <span className="eyebrow">Foyer reads them as</span>
            <div style={{ display: 'flex', gap: 6 }}>
              {['buyer', 'seller', 'browser'].map(t => (
                <button key={t} onClick={() => setTag(active, t)} className="mono" style={{
                  padding: '5px 14px',
                  background: currentTag === t ? `var(--${t === 'buyer' ? 'gold' : t === 'seller' ? 'terracotta' : 'sage'}-soft)` : 'transparent',
                  border: '1px solid ' + (currentTag === t ? `var(--${t === 'buyer' ? 'gold' : t === 'seller' ? 'terracotta' : 'sage'})` : 'var(--hairline)'),
                  color: currentTag === t ? `var(--${t === 'buyer' ? 'gold' : t === 'seller' ? 'terracotta' : 'sage'})` : 'var(--text-dim)',
                  fontSize: 10, letterSpacing: '0.14em', textTransform: 'uppercase', cursor: 'pointer',
                  borderRadius: 999,
                }}>{t}</button>
              ))}
            </div>
            <span className="serif-it" style={{ fontSize: 13, color: 'var(--text-muted)' }}>— change if you disagree</span>
          </div>

          {/* summary */}
          <div style={{ marginTop: 36 }}>
            <Eyebrow num={v.id}>The read</Eyebrow>
            <p className="serif" style={{ fontSize: 22, lineHeight: 1.5, marginTop: 16, color: 'var(--cream)', fontWeight: 400, letterSpacing: '-0.005em' }}>
              {v.summary}
            </p>
          </div>

          {/* signals */}
          <div style={{ marginTop: 32, display: 'grid', gridTemplateColumns: 'repeat(2, 1fr)', gap: 1, background: 'var(--hairline)', border: '1px solid var(--hairline)' }}>
            {v.signals.map((s, i) => (
              <div key={s} style={{ background: 'var(--bg-card)', padding: '18px 22px' }}>
                <div className="mono" style={{ fontSize: 10, color: 'var(--gold)', letterSpacing: '0.14em', textTransform: 'uppercase' }}>Signal 0{i + 1}</div>
                <div className="serif" style={{ fontSize: 20, color: 'var(--cream)', marginTop: 6 }}>{s}</div>
              </div>
            ))}
          </div>

          {/* transcript */}
          <div style={{ marginTop: 56 }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline' }}>
              <Eyebrow>Transcript</Eyebrow>
              <span className="mono" style={{ fontSize: 11, color: 'var(--text-muted)', letterSpacing: '0.14em' }}>SHOWING {v.name.toUpperCase()}'S TURNS · {v.spokeWords}W</span>
            </div>

            {/* audio scrub */}
            <div style={{ marginTop: 18, padding: '14px 18px', border: '1px solid var(--hairline)', background: 'var(--bg-card)', display: 'flex', alignItems: 'center', gap: 16 }}>
              <button style={{ width: 32, height: 32, borderRadius: '50%', background: 'var(--gold)', color: '#1a1610', border: 0, cursor: 'pointer', fontSize: 12 }}>▶</button>
              <span className="mono" style={{ fontSize: 11, color: 'var(--cream)' }}>0:15</span>
              <div style={{ flex: 1, height: 28, position: 'relative', display: 'flex', alignItems: 'center', gap: 1 }}>
                {Array.from({ length: 90 }).map((_, i) => {
                  const isVisitor = (i > 6 && i < 14) || (i > 30 && i < 38) || (i > 56 && i < 64);
                  const isPlayed = i < 18;
                  return <div key={i} style={{ flex: 1, height: isVisitor ? 18 : 8, background: isVisitor ? (isPlayed ? 'var(--gold)' : 'var(--gold-deep)') : 'var(--text-muted)', opacity: isPlayed ? 1 : 0.5 }}></div>;
                })}
              </div>
              <span className="mono" style={{ fontSize: 11, color: 'var(--text-muted)' }}>1:47:18</span>
            </div>

            {/* transcript lines */}
            <div style={{ marginTop: 20 }}>
              {SAMPLE_TRANSCRIPT.filter(line => line.vid === active || line.who === 'agent' || line.who === 'gap').slice(0, 10).map((line, i) => {
                if (line.who === 'gap') {
                  return <div key={i} className="divider serif-it" style={{ margin: '24px 0', color: 'var(--text-muted)', fontStyle: 'italic', textTransform: 'none', letterSpacing: 0, fontSize: 12 }}>{line.text}</div>;
                }
                const isAgent = line.who === 'agent';
                return (
                  <div key={i} style={{ display: 'grid', gridTemplateColumns: '60px 1fr', gap: 16, padding: '12px 0' }}>
                    <div className="mono" style={{ fontSize: 10, color: 'var(--text-muted)', letterSpacing: '0.1em', paddingTop: 4 }}>{line.t}</div>
                    <div>
                      <div className="eyebrow" style={{ color: isAgent ? 'var(--text-muted)' : 'var(--gold)' }}>
                        {isAgent ? 'John (you)' : line.name}
                      </div>
                      <div style={{ marginTop: 4, fontSize: 14, lineHeight: 1.6, color: isAgent ? 'var(--text-dim)' : 'var(--cream)' }}>
                        {line.highlight ? (
                          <span style={{ background: 'var(--gold-soft)', boxShadow: 'inset 0 -2px 0 var(--gold)', padding: '0 2px' }}>{line.text}</span>
                        ) : line.text}
                      </div>
                    </div>
                  </div>
                );
              })}
              <div className="divider" style={{ margin: '28px 0 0' }}>End of {v.name.split(' ')[0]}'s turns</div>
            </div>
          </div>

          {/* follow-up */}
          <div style={{ marginTop: 64, padding: 36, border: '1px solid var(--border-strong)', background: 'var(--bg-card)' }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline' }}>
              <Eyebrow>Drafted follow-up</Eyebrow>
              <span className="mono" style={{ fontSize: 10, color: 'var(--gold)', letterSpacing: '0.14em' }}>SENDS · TOMORROW 9:14 AM</span>
            </div>
            <div className="mono" style={{ fontSize: 11, color: 'var(--text-muted)', marginTop: 14, letterSpacing: '0.06em' }}>
              <span style={{ color: 'var(--cream)' }}>To:</span> {v.email}<br/>
              <span style={{ color: 'var(--cream)' }}>Subject:</span> Great meeting you at 412 W 78th today
            </div>
            <Hairline style={{ margin: '20px 0' }}/>
            {editing ? (
              <textarea
                value={draft}
                onChange={e => setDraft(e.target.value)}
                style={{
                  width: '100%', minHeight: 280,
                  background: 'var(--bg-deep)', border: '1px solid var(--gold)',
                  padding: 18, fontFamily: 'var(--sans)', fontSize: 14, lineHeight: 1.7,
                  color: 'var(--cream)', resize: 'vertical', outline: 'none',
                }}
              />
            ) : (
              <div className="serif" style={{ fontSize: 17, lineHeight: 1.7, color: 'var(--cream-dim)', whiteSpace: 'pre-wrap', fontWeight: 400 }}>
                {draft}
              </div>
            )}

            <div style={{ marginTop: 28, display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
              <div style={{ display: 'flex', gap: 16, fontSize: 12, color: 'var(--text-dim)' }}>
                <label style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
                  <input type="checkbox" defaultChecked style={{ accentColor: 'var(--gold)' }}/> Send by email
                </label>
                <label style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
                  <input type="checkbox" style={{ accentColor: 'var(--gold)' }}/> + SMS recap
                </label>
                <label style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
                  <input type="checkbox" defaultChecked style={{ accentColor: 'var(--gold)' }}/> Add to nurture
                </label>
              </div>
              <div style={{ display: 'flex', gap: 10 }}>
                <button
                  className="btn"
                  onClick={() => {
                    if (editing) window.foyerToast('Draft saved');
                    setEditing(e => !e);
                  }}
                >{editing ? 'Done' : 'Edit'}</button>
                <button
                  className="btn"
                  onClick={() => window.foyerToast({ message: 'Send time bumped to Mon · 9:14 AM', kind: 'info' })}
                >Reschedule</button>
                <button
                  className="btn btn-primary"
                  onClick={() => window.foyerToast(`Sent to ${v.name} · scheduled for tomorrow 9:14 AM`)}
                >Approve & queue</button>
              </div>
            </div>
          </div>

          {/* footer actions */}
          <div style={{ marginTop: 32, display: 'flex', gap: 24, justifyContent: 'space-between', alignItems: 'center', paddingBottom: 20 }}>
            <div className="serif-it" style={{ fontSize: 13, color: 'var(--text-muted)' }}>
              Foyer's read accuracy on this session: <span style={{ color: 'var(--gold)' }}>96%</span>
            </div>
            <div style={{ display: 'flex', gap: 12 }}>
              <button
                className="btn"
                onClick={() => window.foyerToast('PDF exported · 412-W-78th-session.pdf')}
              >Export PDF</button>
              <button
                className="btn"
                onClick={() => window.foyerToast('CSV exported · 3 leads')}
              >Export CSV</button>
              <button
                className="btn btn-ghost"
                style={{ color: 'var(--terracotta)' }}
                onClick={() => {
                  if (window.confirm('Delete this session? Audio and transcript will be removed.')) {
                    window.foyerToast({ message: 'Session deleted', kind: 'warn' });
                    setTimeout(() => window.foyerGo('#/app'), 400);
                  }
                }}
              >Delete session</button>
            </div>
          </div>
        </div>
      </section>
    </div>
  );
};

Object.assign(window, { SessionDetail });
