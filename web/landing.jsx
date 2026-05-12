/* global React, Crest, Eyebrow, Tag, Stat, Hairline, HeroDevices, HDIPhone, HDIPad, HDLaptop */

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
          <button className="btn btn-ghost" style={{ fontSize: 13 }} onClick={() => window.foyerSignIn()}>Sign in</button>
          <button className="btn btn-primary" onClick={() => window.foyerSignIn()}>Request access</button>
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

      {/* NEW FEATURES — AI you can talk to */}
      <section style={{ padding: '120px 56px', background: 'var(--bg-deep)' }}>
        <div style={{ maxWidth: 1240, margin: '0 auto' }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', marginBottom: 60 }}>
            <div>
              <Eyebrow num="03.5">Inside the inbox</Eyebrow>
              <h2 className="serif" style={{ fontSize: 56, lineHeight: 1, marginTop: 28, color: 'var(--cream)' }}>
                An AI you can <span className="serif-it" style={{ color: 'var(--gold)' }}>actually talk to.</span>
              </h2>
            </div>
            <div style={{ maxWidth: 420, color: 'var(--text-dim)', fontSize: 14, lineHeight: 1.7 }}>
              Three new surfaces — built on the same Foyer pipeline — that
              turn the inbox into a conversation, not a backlog.
            </div>
          </div>

          {/* Three feature cards */}
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 24 }}>
            {/* Ask your inbox */}
            <FeatureCard
              eyebrow="01 / LEADS AGENT"
              title="Ask your inbox anything."
              body={
                <>Type a question or a request — <span className="serif-it" style={{ color: 'var(--gold)' }}>"send the $2,500
                buyer credit blast to all warm buyers from Maple St"</span> — and
                Foyer drafts every email, lines up the right recipients,
                and asks you to confirm once. Not 30 times.</>
              }
              mock={
                <div style={{
                  background: 'var(--bg-card)', border: '1px solid var(--gold-soft)',
                  borderRadius: 10, padding: 14,
                }}>
                  <div style={{
                    display: 'inline-flex', alignItems: 'center', gap: 8,
                    fontSize: 11, color: 'var(--gold)', fontFamily: 'var(--mono)',
                    letterSpacing: '0.14em',
                  }}>
                    <span style={{ width: 6, height: 6, borderRadius: '50%', background: 'var(--gold)', boxShadow: '0 0 10px var(--gold)' }} />
                    ASK YOUR INBOX
                  </div>
                  <div style={{ marginTop: 12, fontSize: 13, color: 'var(--cream)', lineHeight: 1.55 }}>
                    Send the @SpringBuyerCredit to all warm buyers from Maple St
                  </div>
                  <div style={{ marginTop: 14, padding: 12, background: 'var(--bg-deep)', border: '1px solid var(--hairline)', borderRadius: 8 }}>
                    <div className="mono" style={{ fontSize: 10, color: 'var(--gold)', letterSpacing: '0.12em' }}>PLAN · 6 RECIPIENTS</div>
                    <div style={{ marginTop: 8, display: 'flex', flexDirection: 'column', gap: 6 }}>
                      {['Sarah Chen', 'Mike Rodriguez', 'Jennifer Park', '+ 3 more'].map((n) => (
                        <div key={n} style={{ display: 'flex', justifyContent: 'space-between', fontSize: 11, color: 'var(--cream-dim)' }}>
                          <span>{n}</span>
                          <span style={{ color: 'var(--gold)' }}>personalized ✓</span>
                        </div>
                      ))}
                    </div>
                  </div>
                </div>
              }
            />

            {/* Offers library */}
            <FeatureCard
              eyebrow="02 / OFFERS LIBRARY"
              title="Campaigns the AI can pull from."
              body={
                <>Drop in your $2,500 buyer credit, your spring rate
                lock, your seller comp report — Foyer references them
                with <span className="mono" style={{ color: 'var(--gold)' }}>@name</span> in any prompt, or quietly picks
                the best fit for each lead all on its own.</>
              }
              mock={
                <div style={{
                  background: 'var(--bg-card)', border: '1px solid var(--hairline)',
                  borderRadius: 10, padding: 0, overflow: 'hidden',
                }}>
                  {[
                    { name: 'Spring buyer credit', desc: '$2,500 toward closing for any buyer signing by April 30', on: true, ref: '@spring' },
                    { name: 'Seller comp report', desc: 'Free comp + neighborhood pricing for any seller intro', on: true, ref: '@comp' },
                    { name: 'Rate lock — 30 day', desc: 'Hold the current rate while we close. Partner lender.', on: false, ref: '@ratelock' },
                  ].map((o, i) => (
                    <div key={o.name} style={{
                      padding: '12px 14px',
                      borderTop: i ? '1px solid var(--hairline)' : 'none',
                      opacity: o.on ? 1 : 0.5,
                    }}>
                      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                        <div style={{ fontSize: 12.5, color: 'var(--cream)' }}>{o.name}</div>
                        <span className="mono" style={{ fontSize: 9, color: o.on ? 'var(--gold)' : 'var(--text-muted)', letterSpacing: '0.12em' }}>
                          {o.on ? 'ACTIVE' : 'OFF'}
                        </span>
                      </div>
                      <div style={{ fontSize: 11, color: 'var(--text-dim)', marginTop: 4, lineHeight: 1.4 }}>
                        {o.desc}
                      </div>
                      <div className="mono" style={{ fontSize: 9, color: 'var(--gold)', marginTop: 6, letterSpacing: '0.08em' }}>
                        {o.ref}
                      </div>
                    </div>
                  ))}
                </div>
              }
            />

            {/* Refine with AI */}
            <FeatureCard
              eyebrow="03 / REFINE WITH AI"
              title="Edit drafts by asking for it."
              body={
                <>"Make it shorter," <span className="serif-it" style={{ color: 'var(--gold)' }}>"add a CTA to schedule
                a private showing,"</span> "swap in the spring buyer
                credit." Foyer rewrites in seconds — your tone, your
                edits, every time.</>
              }
              mock={
                <div style={{
                  background: 'var(--bg-card)', border: '1px solid var(--hairline)',
                  borderRadius: 10, padding: 14,
                }}>
                  <div className="mono" style={{ fontSize: 9, color: 'var(--text-muted)', letterSpacing: '0.14em' }}>
                    DRAFTED FOLLOW-UP
                  </div>
                  <div style={{
                    marginTop: 10, padding: 12,
                    background: 'var(--bg-deep)', border: '1px solid var(--hairline)',
                    borderRadius: 6, fontSize: 11.5, lineHeight: 1.55, color: 'var(--cream-dim)',
                  }}>
                    Hi Sarah — great meeting you today. I'd love to share a
                    full set of comps for the West Side block. Want me to
                    send those over with a private-showing slot for
                    Saturday morning?
                  </div>
                  <div style={{ marginTop: 14, padding: '8px 10px', borderRadius: 8, background: 'var(--gold-soft)', border: '1px solid var(--gold)' }}>
                    <div className="mono" style={{ fontSize: 9, color: 'var(--gold)', letterSpacing: '0.12em' }}>REFINE WITH AI</div>
                    <div style={{ marginTop: 6, fontSize: 12, color: 'var(--cream)' }}>
                      add the @spring credit and ask for a Saturday tour
                    </div>
                  </div>
                </div>
              }
            />
          </div>
        </div>
      </section>

      <Hairline />

      {/* THREE JOBS — each device, one role, all automated */}
      <section style={{ padding: '120px 56px 60px', background: 'var(--bg-deep)' }}>
        <div style={{ maxWidth: 1240, margin: '0 auto' }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', marginBottom: 80 }}>
            <div>
              <Eyebrow num="04">Three devices, three jobs</Eyebrow>
              <h2 className="serif" style={{ fontSize: 56, lineHeight: 1, marginTop: 28, color: 'var(--cream)' }}>
                You bring the people. <span className="serif-it" style={{ color: 'var(--gold)' }}>Foyer does the rest.</span>
              </h2>
            </div>
            <div style={{ maxWidth: 420, color: 'var(--text-dim)', fontSize: 14, lineHeight: 1.7 }}>
              Each device has one job — and Foyer runs it without you
              touching a thing. Pocket, podium, follow-up.
            </div>
          </div>

          {/* iPhone — Records every word */}
          <DeviceJob
            eyebrow="THE iPhone · pocket microphone"
            title={<>Records the open house. <span className="serif-it" style={{ color: 'var(--gold)' }}>Names every voice.</span></>}
            bullets={[
              { k: 'Drop your phone in your pocket and tap once.',
                d: 'Foyer captures the entire walkthrough in the background, even with the screen off.' },
              { k: 'Speakers identified automatically.',
                d: 'AI diarization separates every voice and matches them to the guests who signed in.' },
              { k: 'Saved continuously to the cloud.',
                d: 'No "press save," no lost recordings. Each session lands in your library by Monday morning.' },
            ]}
            device="phone"
            scale={0.78}
            flip={false}
          />

          {/* iPad — Sign-in kiosk */}
          <DeviceJob
            eyebrow="THE iPad · sign-in podium"
            title={<>Hand to a guest. <span className="serif-it" style={{ color: 'var(--gold)' }}>Sign-in does itself.</span></>}
            bullets={[
              { k: 'Locked guest mode — they can\'t escape it.',
                d: 'Biometric exit. Even a curious kid can\'t navigate away from the form mid-tour.' },
              { k: 'Validation as the field types.',
                d: 'Email gets checked while they\'re still on the page. Bad addresses don\'t make it through.' },
              { k: 'Queues guests for voice-matching.',
                d: 'The moment Foyer hears them speak, the signed-in name attaches to their voiceprint.' },
            ]}
            device="ipad"
            scale={0.45}
            flip={true}
          />

          {/* Laptop — AI drafts + auto-schedules */}
          <DeviceJob
            eyebrow="THE Laptop · follow-up cockpit"
            title={<>AI drafts each follow-up. <span className="serif-it" style={{ color: 'var(--gold)' }}>And schedules it.</span></>}
            bullets={[
              { k: 'Personalized email per guest, written for you.',
                d: 'Foyer reads what each lead actually said and drafts in your voice — not a template.' },
              { k: 'Auto-scheduled to 9:14 AM tomorrow.',
                d: 'No "click send 30 times." Open houses turn into a queue of pre-flighted replies.' },
              { k: 'One confirmation for a hundred sends.',
                d: 'Tell the inbox "send the buyer credit blast to all warm buyers" — it builds the plan, you approve once.' },
            ]}
            device="laptop"
            scale={0.55}
            flip={false}
          />
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

// Single row in the "Three jobs" section: animated device mock on one
// side, copy + bullet list on the other. The mock auto-runs the same
// automation animation that plays in the hero carousel, so a visitor
// scrolling down can sit and watch the AI work.
function DeviceJob({ eyebrow, title, bullets, device, scale = 0.6, flip = false }) {
  const Mock = device === 'phone' ? HDIPhone
            : device === 'ipad'   ? HDIPad
            : HDLaptop;
  // The mocks render at large native dimensions — wrap in a scaled box
  // so the row stays balanced against the copy column.
  const base = device === 'laptop' ? { w: 880, h: 580 }
            : device === 'ipad'   ? { w: 920, h: 660 }
            : { w: 300, h: 612 };
  return (
    <div style={{
      display: 'grid',
      gridTemplateColumns: flip ? '1fr 1fr' : '1fr 1fr',
      gap: 60, alignItems: 'center',
      marginBottom: 80,
      direction: flip ? 'rtl' : 'ltr',
    }}>
      {/* Copy column */}
      <div style={{ direction: 'ltr' }}>
        <div className="mono" style={{
          fontSize: 11, color: 'var(--gold)', letterSpacing: '0.18em',
          textTransform: 'uppercase',
        }}>
          {eyebrow}
        </div>
        <h3 className="serif" style={{
          fontSize: 42, lineHeight: 1.05, margin: '18px 0 28px',
          color: 'var(--cream)', letterSpacing: '-0.02em',
        }}>
          {title}
        </h3>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 22 }}>
          {bullets.map((b, i) => (
            <div key={i} style={{ display: 'grid', gridTemplateColumns: '24px 1fr', gap: 14 }}>
              <div style={{
                marginTop: 3,
                width: 24, height: 24, borderRadius: '50%',
                background: 'var(--gold-soft)', color: 'var(--gold)',
                display: 'grid', placeItems: 'center',
              }}>
                <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="3" strokeLinecap="round" strokeLinejoin="round">
                  <polyline points="20 6 9 17 4 12"/>
                </svg>
              </div>
              <div>
                <div style={{ fontSize: 15, color: 'var(--cream)', lineHeight: 1.4, fontWeight: 500 }}>
                  {b.k}
                </div>
                <div style={{ fontSize: 13, color: 'var(--text-dim)', lineHeight: 1.55, marginTop: 4 }}>
                  {b.d}
                </div>
              </div>
            </div>
          ))}
        </div>
      </div>

      {/* Device column — scaled animation */}
      <div style={{
        direction: 'ltr',
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        minHeight: base.h * scale + 40,
        position: 'relative',
      }}>
        <div style={{
          position: 'absolute', inset: '-20px',
          background: 'radial-gradient(ellipse 70% 60% at center, var(--gold-soft), transparent 70%)',
          pointerEvents: 'none',
          opacity: 0.7,
        }} />
        <div style={{
          width: base.w * scale, height: base.h * scale,
          position: 'relative',
        }}>
          <div style={{ width: base.w, height: base.h, transform: `scale(${scale})`, transformOrigin: 'top left' }}>
            <Mock />
          </div>
        </div>
      </div>
    </div>
  );
}

// One column in the "Inside the inbox" section: small eyebrow, headline,
// short body, and a UI mock that previews the feature. Cards share a
// border + hover glow with the rest of the page.
function FeatureCard({ eyebrow, title, body, mock }) {
  return (
    <div className="stat-card" style={{
      background: 'var(--bg-card)',
      border: '1px solid var(--hairline)',
      borderRadius: 14,
      padding: 28,
      display: 'flex', flexDirection: 'column', gap: 18,
    }}>
      <div className="mono" style={{
        fontSize: 10, letterSpacing: '0.18em',
        color: 'var(--gold)',
      }}>
        {eyebrow}
      </div>
      <h3 className="serif" style={{
        fontSize: 26, margin: 0,
        lineHeight: 1.15, color: 'var(--cream)',
      }}>
        {title}
      </h3>
      <p style={{
        margin: 0, fontSize: 13.5, lineHeight: 1.7,
        color: 'var(--text-dim)', minHeight: 70,
      }}>
        {body}
      </p>
      <div style={{ marginTop: 4 }}>
        {mock}
      </div>
    </div>
  );
}

Object.assign(window, { Landing });
