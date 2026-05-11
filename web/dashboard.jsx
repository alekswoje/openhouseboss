/* global React, Crest, Tag, Eyebrow, Hairline, SAMPLE_VISITORS */
const { useState: useStateD } = React;

const Dashboard = () => {
  return (
    <div className="foyer" data-screen-label="Dashboard" style={{ background: 'var(--bg)', minHeight: '100%', display: 'grid', gridTemplateColumns: '240px 1fr' }}>

      {/* SIDEBAR */}
      <aside style={{ borderRight: '1px solid var(--hairline)', padding: '24px 0', background: 'var(--bg-deep)' }}>
        <div style={{ padding: '0 24px 24px', borderBottom: '1px solid var(--hairline)' }}>
          <Crest size={18} />
        </div>
        <nav style={{ padding: '20px 0' }}>
          {[
            { label: 'Today', sub: '1 active', active: true, go: () => window.foyerToast('Today · 412 W 78th St is live') },
            { label: 'Sessions', sub: '34 total', go: () => window.foyerGo('#/session') },
            { label: 'Leads', sub: '127', go: () => window.foyerToast('127 leads · year to date') },
            { label: 'Follow-ups', sub: '8 queued', go: () => window.foyerToast('8 follow-ups queued · sends through Thursday') },
            { label: 'Listings', sub: '6', go: () => window.foyerToast('6 active listings · MLS synced') },
          ].map(item => (
            <div key={item.label} onClick={item.go} style={{
              padding: '12px 24px',
              borderLeft: item.active ? '2px solid var(--gold)' : '2px solid transparent',
              background: item.active ? 'var(--gold-soft)' : 'transparent',
              cursor: 'pointer',
            }}>
              <div style={{ fontSize: 14, color: item.active ? 'var(--gold)' : 'var(--cream)', fontWeight: item.active ? 500 : 400 }}>{item.label}</div>
              <div className="mono" style={{ fontSize: 10, color: 'var(--text-muted)', marginTop: 2, letterSpacing: '0.1em' }}>{item.sub}</div>
            </div>
          ))}
        </nav>
        <div style={{ padding: '20px 24px', borderTop: '1px solid var(--hairline)', marginTop: 'auto', position: 'absolute', bottom: 24, width: 240 }}>
          <div style={{
            display: 'flex', alignItems: 'center', gap: 12,
            padding: 10, borderRadius: 12,
            background: 'var(--bg-card)', border: '1px solid var(--hairline)', cursor: 'pointer',
          }}>
            <div style={{ width: 36, height: 36, borderRadius: '50%', background: 'var(--gold-soft)', display: 'grid', placeItems: 'center', color: 'var(--gold)', fontFamily: 'var(--serif)', fontStyle: 'italic' }}>J</div>
            <div style={{ flex: 1 }}>
              <div style={{ fontSize: 13, color: 'var(--cream)' }}>John Whitlock</div>
              <div className="mono" style={{ fontSize: 10, color: 'var(--text-muted)' }}>DOUGLAS ELLIMAN · UWS</div>
            </div>
            <span className="mono" style={{ fontSize: 14, color: 'var(--text-muted)' }}>⌄</span>
          </div>
          {/* dropdown sketch — always shown above; click avatar to open in product */}
          <div style={{
            position: 'absolute', left: 16, bottom: 78, width: 240,
            background: 'var(--bg-card)', border: '1px solid var(--border-strong)', borderRadius: 12,
            boxShadow: '0 30px 80px -20px rgba(0,0,0,0.6)', padding: '8px 0',
          }}>
            {[
              { i: '⚙', l: 'Settings',   k: '⌘,' },
              { i: '⊕', l: 'Language',   k: '›'  },
              { i: '?',  l: 'Get help',   k: ''    },
            ].map(m => (
              <div key={m.l} onClick={() => window.foyerToast(m.l + ' · coming soon')} style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', padding: '10px 16px', fontSize: 13, color: 'var(--cream-dim)', cursor: 'pointer' }}>
                <span style={{ display: 'inline-flex', alignItems: 'center', gap: 12 }}>
                  <span style={{ width: 16, textAlign: 'center', color: 'var(--text-muted)' }}>{m.i}</span>{m.l}
                </span>
                <span className="mono" style={{ fontSize: 9.5, color: 'var(--text-muted)', letterSpacing: '0.08em' }}>{m.k}</span>
              </div>
            ))}
            <div style={{ borderTop: '1px solid var(--hairline)', margin: '6px 0' }}></div>
            {['View all plans','Get apps & extensions','Refer an agent','Learn more'].map(l => (
              <div key={l} onClick={() => window.foyerToast(l)} style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '10px 16px', fontSize: 13, color: 'var(--cream-dim)', cursor: 'pointer' }}>
                <span style={{ width: 16, textAlign: 'center', color: 'var(--text-muted)' }}>·</span>{l}
              </div>
            ))}
            <div style={{ borderTop: '1px solid var(--hairline)', margin: '6px 0' }}></div>
            <div
              onClick={() => { window.foyerToast({ message: 'Signed out · see you Saturday', kind: 'warn' }); setTimeout(() => window.foyerGo('#/login'), 400); }}
              style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '10px 16px', fontSize: 13, color: 'var(--terracotta)', cursor: 'pointer' }}>
              <span style={{ width: 16, textAlign: 'center' }}>⇥</span>Log out
            </div>
          </div>
        </div>
      </aside>

      {/* MAIN */}
      <main style={{ padding: '40px 56px 80px', overflowY: 'auto' }}>
        {/* greeting */}
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-end' }}>
          <div>
            <div className="eyebrow">Saturday · May 10 · 5:47 PM</div>
            <h1 className="serif" style={{ fontSize: 56, margin: '12px 0 0', color: 'var(--cream)', lineHeight: 1 }}>
              Good evening, <span className="serif-it" style={{ color: 'var(--gold)' }}>John.</span>
            </h1>
            <p style={{ marginTop: 14, color: 'var(--text-dim)', fontSize: 15 }}>
              Today's open house ended <span style={{ color: 'var(--cream)' }}>23 minutes ago.</span> Three follow-ups await your read.
            </p>
          </div>
          <div style={{ display: 'flex', gap: 12 }}>
            <button className="btn" onClick={() => window.foyerToast('Day exported · check Downloads')}>Export day</button>
            <button className="btn btn-primary" onClick={() => window.foyerGo('#/session')}>Review follow-ups</button>
          </div>
        </div>

        {/* numbers row */}
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: 12, marginTop: 56 }}>
          {[
            { v: '3', s: 'guests', label: 'This session', sub: '412 W 78th' },
            { v: '94', s: '/100', label: 'Top lead score', sub: 'Sarah Chen' },
            { v: '8', label: 'Queued sends', sub: 'next: tomorrow 9:14 AM' },
            { v: '127', label: 'Leads year-to-date', sub: '+23% vs Q1' },
          ].map(stat => (
            <div key={stat.label} style={{ background: 'var(--bg-card)', border: '1px solid var(--hairline)', borderRadius: 14, padding: '28px 24px' }}>
              <div className="eyebrow">{stat.label}</div>
              <div style={{ marginTop: 14, fontFamily: 'var(--serif)', fontSize: 48, lineHeight: 1, color: 'var(--cream)' }}>
                {stat.v}
                {stat.s && <span style={{ color: 'var(--gold)', fontStyle: 'italic', fontSize: 28 }}>{stat.s}</span>}
              </div>
              <div className="mono" style={{ fontSize: 10, color: 'var(--text-muted)', marginTop: 10, letterSpacing: '0.1em' }}>{stat.sub.toUpperCase()}</div>
            </div>
          ))}
        </div>

        {/* today's session feature */}
        <div style={{ marginTop: 64, display: 'grid', gridTemplateColumns: '1.4fr 1fr', gap: 40 }}>
          <div>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline' }}>
              <Eyebrow>Today's open house</Eyebrow>
              <a
                onClick={() => window.foyerGo('#/session')}
                style={{ fontSize: 12, color: 'var(--gold)', cursor: 'pointer' }}
                className="serif-it"
              >Open full session →</a>
            </div>
            <div className="serif" style={{ fontSize: 36, marginTop: 14, color: 'var(--cream)', lineHeight: 1.05 }}>
              412 West 78th Street<br/>
              <span className="serif-it" style={{ color: 'var(--gold)', fontSize: 24 }}>Apt 4-A · $1.295M</span>
            </div>
            <div className="mono" style={{ fontSize: 11, color: 'var(--text-muted)', marginTop: 10, letterSpacing: '0.14em' }}>
              2:00 — 4:00 PM · 1h 47m RECORDED · 3 GUESTS
            </div>

            {/* visitor cards stacked */}
            <div style={{ marginTop: 28, display: 'flex', flexDirection: 'column', gap: 0 }}>
              {SAMPLE_VISITORS.map((v, i) => (
                <div
                  key={v.id}
                  onClick={() => window.foyerGo('#/session')}
                  style={{
                    padding: '22px 0',
                    borderTop: '1px solid var(--hairline)',
                    borderBottom: i === SAMPLE_VISITORS.length - 1 ? '1px solid var(--hairline)' : 'none',
                    display: 'grid', gridTemplateColumns: '40px 1fr auto', gap: 20, alignItems: 'start',
                    cursor: 'pointer',
                  }}>
                  <div className="mono" style={{ fontSize: 12, color: 'var(--gold)', lineHeight: 1, letterSpacing: '0.1em' }}>0{i + 1}</div>
                  <div>
                    <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
                      <span className="serif" style={{ fontSize: 22, color: 'var(--cream)' }}>{v.name}</span>
                      <Tag kind={v.tag}>{v.tag} · {v.score}</Tag>
                    </div>
                    <div style={{ marginTop: 8, fontSize: 13, color: 'var(--text-dim)', lineHeight: 1.55, maxWidth: 540 }}>
                      {v.summary.split('.')[0]}.
                    </div>
                    <div style={{ marginTop: 10, display: 'flex', gap: 8, flexWrap: 'wrap' }}>
                      {v.signals.slice(0, 3).map(s => (
                        <span key={s} className="mono" style={{ fontSize: 9, padding: '3px 8px', border: '1px solid var(--hairline)', color: 'var(--text-dim)', letterSpacing: '0.06em' }}>{s.toUpperCase()}</span>
                      ))}
                    </div>
                  </div>
                  <div style={{ textAlign: 'right' }}>
                    <div className="mono" style={{ fontSize: 10, color: 'var(--text-muted)' }}>SIGNED {v.signedAt}</div>
                    <div className="serif-it" style={{ fontSize: 13, color: 'var(--gold)', marginTop: 18 }}>Review →</div>
                  </div>
                </div>
              ))}
            </div>
          </div>

          {/* right column — queue + activity */}
          <div>
            <Eyebrow>The follow-up queue</Eyebrow>
            <div style={{ marginTop: 16 }}>
              {[
                { who: 'Sarah Chen', when: 'Tomorrow · 9:14 AM', via: 'Email · SMS · 24h', kind: 'buyer' },
                { who: 'Mike Rodriguez', when: 'Tomorrow · 10:30 AM', via: 'Email + comp link', kind: 'seller' },
                { who: 'Jennifer Park', when: 'Wed · 5:00 PM', via: 'Email · low touch', kind: 'browser' },
                { who: 'Daniel Voss', when: 'Fri · 11:00 AM', via: 'SMS check-in', kind: 'buyer', faint: true },
                { who: 'Lila Adebayo', when: 'Next Mon · 8:30 AM', via: 'Email · listing match', kind: 'buyer', faint: true },
              ].map((f, i) => (
                <div key={i} style={{ padding: '16px 0', borderBottom: '1px solid var(--hairline)', opacity: f.faint ? 0.55 : 1 }}>
                  <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                    <span style={{ fontSize: 14, color: 'var(--cream)' }}>{f.who}</span>
                    <Tag kind={f.kind} />
                  </div>
                  <div style={{ display: 'flex', justifyContent: 'space-between', marginTop: 6 }}>
                    <span className="mono" style={{ fontSize: 10, color: 'var(--gold)', letterSpacing: '0.1em' }}>{f.when.toUpperCase()}</span>
                    <span className="mono" style={{ fontSize: 10, color: 'var(--text-muted)' }}>{f.via.toUpperCase()}</span>
                  </div>
                </div>
              ))}
            </div>
            <button
              className="btn"
              style={{ marginTop: 18, width: '100%', justifyContent: 'center' }}
              onClick={() => window.foyerToast('8 follow-ups queued · sends through Thursday')}
            >See all 8 queued →</button>

            <Eyebrow>Pipeline this month</Eyebrow>
            <div style={{ marginTop: 14, padding: 24, border: '1px solid var(--hairline)' }}>
              {/* simple bar chart */}
              <div style={{ display: 'flex', alignItems: 'flex-end', gap: 6, height: 100 }}>
                {[28, 41, 22, 56, 38, 64, 48, 72, 58, 88, 76, 94].map((v, i) => (
                  <div key={i} style={{ flex: 1, background: i === 11 ? 'var(--gold)' : 'var(--gold-soft)', height: `${v}%`, borderTop: i === 11 ? '2px solid var(--gold-bright)' : 'none' }}></div>
                ))}
              </div>
              <div style={{ display: 'flex', justifyContent: 'space-between', marginTop: 12 }}>
                <span className="mono" style={{ fontSize: 10, color: 'var(--text-muted)' }}>WK 18</span>
                <span className="mono" style={{ fontSize: 10, color: 'var(--gold)' }}>THIS WEEK · 94 LEADS</span>
              </div>
            </div>
          </div>
        </div>
      </main>
    </div>
  );
};

Object.assign(window, { Dashboard });
