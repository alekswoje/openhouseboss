/* global React, Crest, Eyebrow, Tag, Stat, Hairline, HeroDevices */

const Landing = () => {
  return (
    <div className="foyer" data-screen-label="Landing" style={{ background: 'var(--bg-deep)', minHeight: '100%', width: '100%' }}>

      {/* TOP NAV */}
      <header style={{
        padding: '28px 56px',
        display: 'flex', alignItems: 'center', justifyContent: 'space-between',
        borderBottom: '1px solid var(--hairline)',
      }}>
        <a href="#/" style={{ textDecoration: 'none', color: 'inherit' }}><Crest /></a>
        <nav style={{ display: 'flex', gap: 36, fontSize: 13, color: 'var(--text-dim)' }}>
          <a href="#method" style={{ color: 'inherit', textDecoration: 'none', cursor: 'pointer' }}>The Method</a>
          <a onClick={() => window.foyerToast('For agents · drop in your brokerage email and we’ll be in touch')} style={{ color: 'inherit', textDecoration: 'none', cursor: 'pointer' }}>For Agents</a>
          <a onClick={() => window.foyerToast('Pricing · $0 for your first three open houses')} style={{ color: 'inherit', textDecoration: 'none', cursor: 'pointer' }}>Pricing</a>
          <a onClick={() => window.foyerToast({ message: 'Journal · field notes coming soon', kind: 'info' })} style={{ color: 'inherit', textDecoration: 'none', cursor: 'pointer' }}>Journal</a>
        </nav>
        <div style={{ display: 'flex', gap: 14, alignItems: 'center' }}>
          <button className="btn btn-ghost" style={{ fontSize: 13 }} onClick={() => window.foyerGo('#/login')}>Sign in</button>
          <button className="btn btn-primary" onClick={() => window.foyerToast('Request received · we’ll reach out within 24h')}>Request access</button>
        </div>
      </header>

      {/* HERO */}
      <section style={{ padding: '90px 56px 120px', position: 'relative' }}>
        <div className="foyer-hero-grid" style={{ display: 'grid', gridTemplateColumns: '1.05fr 0.95fr', gap: 64, alignItems: 'center' }}>
          <div>
            <Eyebrow num="01">For the modern broker</Eyebrow>
            <h1 className="serif" style={{
              fontSize: 104,
              lineHeight: 0.94,
              margin: '32px 0 0',
              letterSpacing: '-0.025em',
              color: 'var(--cream)',
              fontWeight: 500,
            }}>
              Every open house,<br/>
              <span className="serif-it" style={{ color: 'var(--gold)', fontWeight: 400 }}>quietly remembered.</span>
            </h1>
            <p style={{
              maxWidth: 480, marginTop: 36,
              fontSize: 17, lineHeight: 1.6,
              color: 'var(--text-dim)',
            }}>
              Foyer listens through your phone, identifies each guest who walked in,
              and drafts the follow-up before you've locked the front door. So you
              spend the showing showing — not scribbling.
            </p>
            <div style={{ display: 'flex', gap: 16, marginTop: 44, alignItems: 'center' }}>
              <button
                className="btn btn-primary"
                style={{ padding: '16px 28px', fontSize: 14 }}
                onClick={() => window.foyerToast('Opening the App Store · Foyer for iPhone')}
              >
                Download for iPhone
                <span style={{ fontFamily: 'var(--serif)', fontStyle: 'italic', marginLeft: 4 }}>→</span>
              </button>
              <button
                className="btn btn-ghost"
                style={{ fontSize: 14, color: 'var(--cream-dim)' }}
                onClick={() => window.foyerToast({ message: 'Tour rolling · 90 seconds', kind: 'info' })}
              >
                Watch the 90-second tour
              </button>
            </div>
            <div style={{ marginTop: 56, display: 'flex', gap: 36, alignItems: 'center', flexWrap: 'wrap' }}>
              <span className="eyebrow" style={{ color: 'var(--text-muted)' }}>Trusted at</span>
              {['DOUGLAS ELLIMAN', 'COMPASS', 'CORCORAN', 'SOTHEBY\u2019S'].map(n => (
                <span key={n} className="mono" style={{ fontSize: 11, letterSpacing: '0.2em', color: 'var(--text-dim)' }}>{n}</span>
              ))}
            </div>
          </div>

          {/* device lineup — top-right on desktop, below on mobile */}
          <HeroDevices />
        </div>
      </section>

      <Hairline />

      {/* THE METHOD — 3 step */}
      <section id="method" style={{ padding: '120px 56px', scrollMarginTop: 80 }}>
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 2fr', gap: 80, alignItems: 'start' }}>
          <div>
            <Eyebrow num="02">The method</Eyebrow>
            <h2 className="serif" style={{ fontSize: 56, lineHeight: 1, marginTop: 28, color: 'var(--cream)' }}>
              Three movements,<br/>
              <span className="serif-it" style={{ color: 'var(--gold)' }}>one finished record.</span>
            </h2>
          </div>
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 1, background: 'var(--hairline)' }}>
            {[
              { n: '01', title: 'Record', body: 'Tap once when the first guest arrives. Foyer captures every conversation through the open house, in pocket, on airplane mode if needed.' },
              { n: '02', title: 'Recognize', body: "Guests sign in on your iPad — we match each voice to a name, separate the buyers from the browsers, and pull out what they said matters to them." },
              { n: '03', title: 'Reach out', body: 'Walk out and the follow-up is already drafted in your voice, scheduled to send tomorrow at 9:14 AM, ready for your read.' },
            ].map(step => (
              <div key={step.n} style={{ background: 'var(--bg-deep)', padding: '40px 36px 48px' }}>
                <div className="mono" style={{ fontSize: 14, color: 'var(--gold)', lineHeight: 1, letterSpacing: '0.16em' }}>{step.n} /</div>
                <div className="serif" style={{ fontSize: 28, marginTop: 28, color: 'var(--cream)' }}>{step.title}</div>
                <p style={{ marginTop: 18, fontSize: 14, lineHeight: 1.7, color: 'var(--text-dim)' }}>{step.body}</p>
              </div>
            ))}
          </div>
        </div>
      </section>

      <Hairline />

      {/* SHOWCASE — product capture */}
      <section style={{ padding: '120px 56px', background: 'var(--bg)' }}>
        <div style={{ maxWidth: 1240, margin: '0 auto' }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', marginBottom: 60 }}>
            <div>
              <Eyebrow num="03">A closer look</Eyebrow>
              <h2 className="serif" style={{ fontSize: 56, lineHeight: 1, marginTop: 28, color: 'var(--cream)' }}>
                What you see, <span className="serif-it" style={{ color: 'var(--gold)' }}>Monday morning.</span>
              </h2>
            </div>
            <div style={{ maxWidth: 380, color: 'var(--text-dim)', fontSize: 14, lineHeight: 1.7 }}>
              Every guest, in plain language: who they are, what they want, and the
              note we'd send on your behalf — yours to approve, edit, or rewrite.
            </div>
          </div>

          {/* mock dashboard preview card */}
          <div style={{
            border: '1px solid var(--border)',
            borderRadius: 10,
            background: 'var(--bg-card)',
            padding: 0,
            boxShadow: 'var(--shadow-deep)',
            overflow: 'hidden',
          }}>
            <div style={{ display: 'grid', gridTemplateColumns: '320px 1fr', minHeight: 460 }}>
              <div style={{ borderRight: '1px solid var(--hairline)', padding: 28 }}>
                <div className="eyebrow">Saturday, May 10</div>
                <div className="serif" style={{ fontSize: 24, color: 'var(--cream)', marginTop: 6 }}>412 W 78th Street</div>
                <div className="mono" style={{ fontSize: 11, color: 'var(--text-muted)', marginTop: 4 }}>2:00 PM — 4:00 PM · 1h 47m</div>
                <Hairline style={{ margin: '24px 0' }}/>
                {[
                  { n: 'Sarah Chen', sub: 'pre-approved $1.4M', tag: 'buyer', active: true },
                  { n: 'Mike Rodriguez', sub: 'wants comp analysis', tag: 'seller' },
                  { n: 'Jennifer Park', sub: 'curious renter', tag: 'browser' },
                ].map(v => (
                  <div key={v.n} style={{
                    padding: '14px 14px',
                    margin: '0 -14px',
                    background: v.active ? 'var(--gold-soft)' : 'transparent',
                    borderLeft: v.active ? '2px solid var(--gold)' : '2px solid transparent',
                  }}>
                    <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                      <div style={{ fontSize: 14, color: 'var(--cream)' }}>{v.n}</div>
                      <Tag kind={v.tag}>{v.tag}</Tag>
                    </div>
                    <div style={{ fontSize: 12, color: 'var(--text-muted)', marginTop: 4 }}>{v.sub}</div>
                  </div>
                ))}
              </div>
              <div style={{ padding: 40 }}>
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start' }}>
                  <div>
                    <div className="eyebrow">Guest · 14:05</div>
                    <div className="serif" style={{ fontSize: 36, marginTop: 6, color: 'var(--cream)' }}>Sarah Chen</div>
                    <div className="mono" style={{ fontSize: 11, color: 'var(--text-muted)', marginTop: 6 }}>SARAH@EXAMPLE.COM · 555-0101</div>
                  </div>
                  <Tag kind="buyer">Buyer · 94</Tag>
                </div>
                <p style={{ marginTop: 28, fontSize: 15, lineHeight: 1.65, color: 'var(--cream-dim)' }}>
                  Actively searching the West Side. Sold her Queens place last year. Drawn by the
                  kitchen. Needs three bedrooms — two kids. <span style={{ color: 'var(--gold)' }}>Pre-approved to $1.4M.</span> Ready to close in 60 days.
                </p>
                <div style={{ display: 'flex', gap: 8, marginTop: 20, flexWrap: 'wrap' }}>
                  {['Pre-approved $1.4M', 'Close in 60d', '3+ bedrooms', '6mo searching'].map(s => (
                    <span key={s} className="mono" style={{ fontSize: 10, letterSpacing: '0.06em', padding: '5px 10px', border: '1px solid var(--hairline)', color: 'var(--text-dim)' }}>{s}</span>
                  ))}
                </div>
                <Hairline style={{ margin: '32px 0 24px' }}/>
                <div className="eyebrow">Drafted follow-up · sends tomorrow 9:14 AM</div>
                <div style={{ marginTop: 16, padding: 22, background: 'var(--bg-deep)', border: '1px solid var(--hairline)', fontSize: 14, lineHeight: 1.65, color: 'var(--cream-dim)' }}>
                  <span className="serif-it" style={{ color: 'var(--gold)' }}>Hi Sarah,</span><br/><br/>
                  It was great meeting you today. I love how prepared you and Tom are —
                  pre-approved and ready to close in 60 days is exactly the position that gives
                  buyers an edge in this market…
                </div>
              </div>
            </div>
          </div>
        </div>
      </section>

      <Hairline />

      {/* PROOF — pull quotes */}
      <section style={{ padding: '140px 56px', background: 'var(--bg-deep)' }}>
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 48 }}>
          {[
            { quote: "It is the difference between hosting an open house and harvesting one.", who: 'Eliana Morales', title: 'Top producer, UWS' },
            { quote: "Foyer wrote a follow-up that closed a $2.4M townhouse. I sent it word for word.", who: 'David Chen', title: 'Principal broker' },
            { quote: "My team's response time went from three days to nine minutes. Quietly.", who: 'Renée Pinault', title: 'Brokerage owner, Boston' },
          ].map(q => (
            <figure key={q.who} style={{ margin: 0 }}>
              <div className="serif-it" style={{ fontSize: 40, color: 'var(--gold)', lineHeight: 1 }}>"</div>
              <blockquote className="serif" style={{ margin: '8px 0 28px', fontSize: 26, lineHeight: 1.25, color: 'var(--cream)', fontWeight: 400 }}>
                {q.quote}
              </blockquote>
              <figcaption>
                <div style={{ fontSize: 13, color: 'var(--cream)' }}>{q.who}</div>
                <div className="eyebrow" style={{ marginTop: 4 }}>{q.title}</div>
              </figcaption>
            </figure>
          ))}
        </div>
      </section>

      {/* STATS */}
      <section style={{ padding: '90px 56px', borderTop: '1px solid var(--hairline)', borderBottom: '1px solid var(--hairline)' }}>
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: 48 }}>
          <Stat value="9" suffix="min" label="Avg. response time" />
          <Stat value="3.4" suffix="×" label="More follow-ups sent" />
          <Stat value="92" suffix="%" label="Speaker recognition" />
          <Stat value="0" label="Notes to write" />
        </div>
      </section>

      {/* CTA */}
      <section style={{ padding: '140px 56px', textAlign: 'center' }}>
        <Eyebrow num="04">An invitation</Eyebrow>
        <h2 className="serif" style={{ fontSize: 88, lineHeight: 1, margin: '32px 0 0', color: 'var(--cream)' }}>
          The next showing is <span className="serif-it" style={{ color: 'var(--gold)' }}>Saturday.</span>
        </h2>
        <p style={{ maxWidth: 520, margin: '32px auto 0', color: 'var(--text-dim)', fontSize: 16, lineHeight: 1.7 }}>
          Be ready. Free for your first three open houses — no card, no contract,
          no calls from anyone in a quarter-zip.
        </p>
        <div style={{ marginTop: 44, display: 'flex', justifyContent: 'center', gap: 14 }}>
          <button
            className="btn btn-primary"
            style={{ padding: '16px 32px', fontSize: 14 }}
            onClick={() => window.foyerToast('Opening the App Store · Foyer for iPhone')}
          >Download for iPhone</button>
          <button
            className="btn"
            onClick={() => window.foyerToast({ message: 'Calendly link sent · check your inbox', kind: 'info' })}
          >Talk to founder</button>
        </div>
      </section>

      {/* FOOTER */}
      <footer style={{ padding: '60px 56px 40px', borderTop: '1px solid var(--hairline)', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
        <Crest size={18} />
        <div className="mono" style={{ fontSize: 11, color: 'var(--text-muted)', letterSpacing: '0.14em' }}>
          MADE IN NEW YORK · © MMXXVI
        </div>
        <div style={{ display: 'flex', gap: 32, fontSize: 12, color: 'var(--text-dim)' }}>
          <a onClick={() => window.foyerToast('Privacy policy · v 2.1')} style={{ color: 'inherit', textDecoration: 'none', cursor: 'pointer' }}>Privacy</a>
          <a onClick={() => window.foyerToast('SOC 2 II · end-to-end encrypted')} style={{ color: 'inherit', textDecoration: 'none', cursor: 'pointer' }}>Security</a>
          <a onClick={() => window.foyerToast('Press kit · press@foyer.house')} style={{ color: 'inherit', textDecoration: 'none', cursor: 'pointer' }}>Press</a>
        </div>
      </footer>
    </div>
  );
};

Object.assign(window, { Landing });
