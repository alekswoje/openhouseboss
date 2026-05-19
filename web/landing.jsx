/* global React, Crest, Eyebrow, Tag, Stat, Hairline, HeroDevices, HDIPhone, HDIPad, HDLaptop */

const Landing = () => {
  // Waitlist modal — opens from any CTA on the page. Open House Copilot is invite-
  // only for now, so neither the header nor the bottom-of-page CTAs
  // expose a Sign-in / Sign-up path. Visitors drop their email and we
  // ping them when their cohort opens.
  const [waitlistOpen, setWaitlistOpen] = React.useState(false);
  const openWaitlist = (source) => () => {
    window._foyerWaitlistSource = source || 'landing';
    setWaitlistOpen(true);
  };

  return (
    <div className="foyer" data-screen-label="Landing" style={{ background: 'var(--bg-deep)', minHeight: '100%', width: '100%', overflowX: 'hidden' }}>

      {/* TOP NAV */}
      <header className="foyer-nav" style={{
        padding: '28px 56px',
        display: 'flex', alignItems: 'center', justifyContent: 'space-between',
        borderBottom: '1px solid var(--hairline)',
      }}>
        <a href="#/" style={{ textDecoration: 'none', color: 'inherit' }}><Crest /></a>
        <nav className="foyer-nav-links" style={{ display: 'flex', gap: 36, fontSize: 13, color: 'var(--text-dim)' }}>
          {/* Anchor scrolling done via onClick because index.html uses hash
              routing — `href="#pricing"` would otherwise be treated as a
              route hash and bounce back to home.

              We target #pricing-tiers and #security-pillars (the actual
              card grids) instead of the section roots so the user lands
              on the cards, not on a screenful of section heading +
              top padding. Visitors who scroll there organically still
              see the headline first. */}
          <a onClick={() => document.getElementById('pricing-tiers')?.scrollIntoView({ behavior: 'smooth', block: 'start' })} style={{ color: 'inherit', textDecoration: 'none', cursor: 'pointer' }}>Pricing</a>
          <a onClick={() => document.getElementById('security-pillars')?.scrollIntoView({ behavior: 'smooth', block: 'start' })} style={{ color: 'inherit', textDecoration: 'none', cursor: 'pointer' }}>Security</a>
        </nav>
        <div style={{ display: 'flex', gap: 14, alignItems: 'center' }}>
          {/* Sign-in is intentionally hidden on the marketing site —
              Open House Copilot is invite-only and invited agents get a direct
              #/login link in their welcome email. The only CTA here
              is "Join the waitlist", wired to the newsletter API. */}
          <button className="btn btn-primary" onClick={openWaitlist('header')}>Join the waitlist</button>
        </div>
      </header>

      {/* HERO */}
      <section className="foyer-hero" style={{ padding: '90px 56px 120px', position: 'relative' }}>
        <div className="foyer-hero-grid foyer-cols-2" style={{ display: 'grid', gridTemplateColumns: '1.05fr 0.95fr', gap: 64, alignItems: 'center' }}>
          <div>
            <Eyebrow num="01">For the modern broker</Eyebrow>
            <h1 className="serif foyer-hero-title" style={{
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
              Open House Copilot listens through your phone, identifies each guest who walked in,
              and drafts the follow-up before you've locked the front door. So you
              spend the showing showing — not scribbling.
            </p>
            <div style={{ display: 'flex', gap: 16, marginTop: 44, alignItems: 'center' }}>
              <button
                className="btn btn-primary"
                style={{ padding: '16px 28px', fontSize: 14 }}
                onClick={openWaitlist('hero')}
              >
                Join the waitlist
                <span style={{ fontFamily: 'var(--serif)', fontStyle: 'italic', marginLeft: 4 }}>→</span>
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
        <div className="foyer-cols-2" style={{ display: 'grid', gridTemplateColumns: '1fr 2fr', gap: 80, alignItems: 'start' }}>
          <div>
            <Eyebrow num="02">The method</Eyebrow>
            <h2 className="serif foyer-h2" style={{ fontSize: 56, lineHeight: 1, marginTop: 28, color: 'var(--cream)' }}>
              Three movements,<br/>
              <span className="serif-it" style={{ color: 'var(--gold)' }}>one finished record.</span>
            </h2>
          </div>
          <div className="foyer-cols-3" style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 1, background: 'var(--hairline)' }}>
            {[
              { n: '01', title: 'Record', body: 'Tap once when the first guest arrives. Open House Copilot captures every conversation through the open house, in pocket, on airplane mode if needed.' },
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
          <div className="foyer-section-head" style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', marginBottom: 60 }}>
            <div>
              <Eyebrow num="03">A closer look</Eyebrow>
              <h2 className="serif foyer-h2" style={{ fontSize: 56, lineHeight: 1, marginTop: 28, color: 'var(--cream)' }}>
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
            <div className="foyer-preview-inner" style={{ display: 'grid', gridTemplateColumns: '320px 1fr', minHeight: 460 }}>
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
          <div className="foyer-section-head" style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', marginBottom: 60 }}>
            <div>
              <Eyebrow num="03.5">Inside the inbox</Eyebrow>
              <h2 className="serif foyer-h2" style={{ fontSize: 56, lineHeight: 1, marginTop: 28, color: 'var(--cream)' }}>
                An AI you can <span className="serif-it" style={{ color: 'var(--gold)' }}>actually talk to.</span>
              </h2>
            </div>
            <div style={{ maxWidth: 420, color: 'var(--text-dim)', fontSize: 14, lineHeight: 1.7 }}>
              Three new surfaces — built on the same Open House Copilot pipeline — that
              turn the inbox into a conversation, not a backlog.
            </div>
          </div>

          {/* Three feature cards */}
          <div className="foyer-cols-3" style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 24 }}>
            {/* Ask your inbox */}
            <FeatureCard
              eyebrow="01 / LEADS AGENT"
              title="Ask your inbox anything."
              body={
                <>Type a question or a request — <span className="serif-it" style={{ color: 'var(--gold)' }}>"send the $2,500
                buyer credit blast to all warm buyers from Maple St"</span> — and
                Open House Copilot drafts every email, lines up the right recipients,
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
                lock, your seller comp report — Open House Copilot references them
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
                credit." Open House Copilot rewrites in seconds — your tone, your
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
          <div className="foyer-section-head" style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', marginBottom: 80 }}>
            <div>
              <Eyebrow num="04">Three devices, three jobs</Eyebrow>
              <h2 className="serif foyer-h2" style={{ fontSize: 56, lineHeight: 1, marginTop: 28, color: 'var(--cream)' }}>
                You bring the people. <span className="serif-it" style={{ color: 'var(--gold)' }}>Open House Copilot does the rest.</span>
              </h2>
            </div>
            <div style={{ maxWidth: 420, color: 'var(--text-dim)', fontSize: 14, lineHeight: 1.7 }}>
              Each device has one job — and Open House Copilot runs it without you
              touching a thing. Pocket, podium, follow-up.
            </div>
          </div>

          {/* iPhone — Records every word */}
          <DeviceJob
            eyebrow="THE iPhone · pocket microphone"
            title={<>Records the open house. <span className="serif-it" style={{ color: 'var(--gold)' }}>Names every voice.</span></>}
            bullets={[
              { k: 'Drop your phone in your pocket and tap once.',
                d: 'Open House Copilot captures the entire walkthrough in the background, even with the screen off.' },
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
                d: 'The moment Open House Copilot hears them speak, the signed-in name attaches to their voiceprint.' },
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
                d: 'Open House Copilot reads what each lead actually said and drafts in your voice — not a template.' },
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
        <div className="foyer-cols-3" style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 48 }}>
          {[
            { quote: "It is the difference between hosting an open house and harvesting one.", who: 'Eliana Morales', title: 'Top producer, UWS' },
            { quote: "Open House Copilot wrote a follow-up that closed a $2.4M townhouse. I sent it word for word.", who: 'David Chen', title: 'Principal broker' },
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
        <div className="foyer-cols-4" style={{ display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: 48 }}>
          <Stat value="9" suffix="min" label="Avg. response time" />
          <Stat value="3.4" suffix="×" label="More follow-ups sent" />
          <Stat value="92" suffix="%" label="Speaker recognition" />
          <Stat value="0" label="Notes to write" />
        </div>
      </section>

      {/* PRICING */}
      <section id="pricing" style={{ padding: '140px 56px', scrollMarginTop: 24 }}>
        <div style={{ maxWidth: 1240, margin: '0 auto' }}>
          <div className="foyer-section-head" style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', marginBottom: 72 }}>
            <div>
              <Eyebrow num="05">Pricing</Eyebrow>
              <h2 className="serif foyer-h2" style={{ fontSize: 56, lineHeight: 1, marginTop: 28, color: 'var(--cream)' }}>
                Start free.<br/>
                <span className="serif-it" style={{ color: 'var(--gold)' }}>Pay when it earns its keep.</span>
              </h2>
            </div>
            <div style={{ maxWidth: 380, color: 'var(--text-dim)', fontSize: 14, lineHeight: 1.7 }}>
              Three open houses on the house. If Open House Copilot doesn't draft a
              follow-up worth sending, you'll never see a charge.
            </div>
          </div>

          <div id="pricing-tiers" className="foyer-cols-3" style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 24, scrollMarginTop: 64 }}>
            <PricingTier
              tier="TRIAL"
              price="$0"
              cadence="for first 3 open houses"
              blurb="Full product. No card on file. See your first three Monday-morning recaps before you decide anything."
              features={[
                'Up to 3 sessions',
                'Per-visitor summaries',
                'Drafted follow-ups',
                'iPhone + iPad + web',
              ]}
              cta={{ label: 'Start free', onClick: openWaitlist('pricing-trial') }}
            />
            <PricingTier
              tier="SOLO AGENT"
              price="$99"
              cadence="per month, unlimited"
              blurb="Every open house, every guest, every follow-up. One agent, all three devices, no per-session metering."
              features={[
                'Unlimited sessions',
                'AI follow-up rewrites',
                'Offers library + scheduling',
                'Connected Gmail + CRM exports',
                'Priority transcription',
              ]}
              cta={{ label: 'Join the waitlist', onClick: openWaitlist('pricing-solo') }}
              highlight
            />
            <PricingTier
              tier="BROKERAGE"
              price="Talk to us"
              cadence="for teams of 3+"
              blurb="Seats for the whole office, shared listings library, brokerage-level analytics, and a named onboarding contact."
              features={[
                'Multi-agent seats',
                'Shared offers + listings',
                'Brokerage-level analytics',
                'SSO + per-seat permissions',
                'Named onboarding contact',
              ]}
              cta={{ label: 'Get in touch', onClick: openWaitlist('pricing-brokerage') }}
            />
          </div>

          <div style={{ marginTop: 32, fontSize: 12, color: 'var(--text-muted)', textAlign: 'center', fontStyle: 'italic' }}>
            Introductory pricing while we onboard our first cohort. Locked in for the life of your subscription.
          </div>
        </div>
      </section>

      <Hairline />

      {/* SECURITY */}
      <section id="security" style={{ padding: '140px 56px', scrollMarginTop: 24, background: 'var(--bg)' }}>
        <div style={{ maxWidth: 1240, margin: '0 auto' }}>
          <div className="foyer-cols-2" style={{ display: 'grid', gridTemplateColumns: '1fr 1.4fr', gap: 80, alignItems: 'start', marginBottom: 64 }}>
            <div>
              <Eyebrow num="06">Security</Eyebrow>
              <h2 className="serif foyer-h2" style={{ fontSize: 56, lineHeight: 1, marginTop: 28, color: 'var(--cream)' }}>
                Quietly.<br/>
                <span className="serif-it" style={{ color: 'var(--gold)' }}>And on the record.</span>
              </h2>
            </div>
            <div style={{ color: 'var(--text-dim)', fontSize: 15, lineHeight: 1.7 }}>
              <p style={{ margin: 0 }}>
                Recording in someone's home is sensitive by default. Open House Copilot
                is built to keep you on the right side of consent law — and your
                clients' data on the right side of the door.
              </p>
              <p style={{ marginTop: 18 }}>
                The posture below is verified against the running product. If a
                guarantee isn't on this page, we don't make it. SOC 2 is on the
                roadmap, not on the wall.
              </p>
            </div>
          </div>

          {/* Security pillars — every one of these maps to code on the
              live product (kiosk disclosure, LIVE indicator on iOS,
              DELETE /sessions/{id}, DELETE /me, HSTS middleware,
              post-transcription AAI delete). No aspirational claims. */}
          <div id="security-pillars" className="foyer-cols-2" style={{ display: 'grid', gridTemplateColumns: 'repeat(2, 1fr)', gap: 1, background: 'var(--hairline)', scrollMarginTop: 64 }}>
            {[
              { title: 'Consent on every sign-in',
                body: 'Every kiosk shows a recording notice above the form and a consent line above the submit button. Required for two-party-consent states; safe everywhere.' },
              { title: 'No silent recording',
                body: 'Whenever the iPhone is capturing audio, a red LIVE indicator runs on the lock screen and Dynamic Island. There is no hidden mode and no background-only state.' },
              { title: 'One-tap session delete',
                body: 'Delete any open house from your dashboard. Audio, transcript, and drafted follow-ups are removed from our storage immediately — no soft-delete graveyard.' },
              { title: 'Walk away at any time',
                body: 'A single button in your profile wipes every session, transcript, headshot, and the Google connection. The user record itself is gone, not flagged.' },
              { title: 'Encrypted in transit',
                body: 'TLS 1.3 between every device. HSTS pinned for a year on every response. Session cookies are HttpOnly + Secure + SameSite. No password to phish — sign-in is Google-only.' },
              { title: 'Vendors process briefly and forget',
                body: 'AssemblyAI handles transcription; we call their delete API the moment a transcript is in our hands, so the audio leaves their servers right away. Anthropic\'s API processes the transcript under its default zero-retention policy — no training, no caching.' },
            ].map(item => (
              <div key={item.title} style={{ background: 'var(--bg-deep)', padding: '32px 36px 40px' }}>
                <div className="serif" style={{ fontSize: 22, color: 'var(--cream)', lineHeight: 1.25, letterSpacing: '-0.01em' }}>{item.title}</div>
                <p style={{ marginTop: 14, fontSize: 13.5, lineHeight: 1.7, color: 'var(--text-dim)' }}>{item.body}</p>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* CTA */}
      <section style={{ padding: '140px 56px', textAlign: 'center', borderTop: '1px solid var(--hairline)' }}>
        <Eyebrow num="07">An invitation</Eyebrow>
        <h2 className="serif foyer-cta-title" style={{ fontSize: 88, lineHeight: 1, margin: '32px 0 0', color: 'var(--cream)' }}>
          The next cohort opens <span className="serif-it" style={{ color: 'var(--gold)' }}>soon.</span>
        </h2>
        <p style={{ maxWidth: 520, margin: '32px auto 0', color: 'var(--text-dim)', fontSize: 16, lineHeight: 1.7 }}>
          Open House Copilot is invite-only while we onboard our first hundred brokers.
          Drop your email and we'll write when your seat opens — no spam, no
          calls from anyone in a quarter-zip.
        </p>
        <div style={{ marginTop: 44, display: 'flex', justifyContent: 'center', gap: 14 }}>
          <button
            className="btn btn-primary"
            style={{ padding: '16px 32px', fontSize: 14 }}
            onClick={openWaitlist('cta')}
          >Join the waitlist</button>
        </div>
      </section>

      {/* WAITLIST MODAL — single shared dialog for every CTA on the page */}
      {waitlistOpen && (
        <WaitlistModal
          source={window._foyerWaitlistSource || 'landing'}
          onClose={() => setWaitlistOpen(false)}
        />
      )}

      {/* FOOTER */}
      <footer className="foyer-footer" style={{ padding: '60px 56px 40px', borderTop: '1px solid var(--hairline)', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
        <Crest size={18} />
        <div className="mono" style={{ fontSize: 11, color: 'var(--text-muted)', letterSpacing: '0.14em' }}>
          MADE IN NEW YORK · © MMXXVI
        </div>
        <div style={{ display: 'flex', gap: 32, fontSize: 12, color: 'var(--text-dim)' }}>
          {/* Privacy + Terms link to the standalone policy pages — required
              for Google OAuth verification and good practice anyway.
              Security still scrolls to the on-page #security pillars. */}
          <a href="/privacy" style={{ color: 'inherit', textDecoration: 'none', cursor: 'pointer' }}>Privacy</a>
          <a href="/terms" style={{ color: 'inherit', textDecoration: 'none', cursor: 'pointer' }}>Terms</a>
          <a onClick={() => document.getElementById('security')?.scrollIntoView({ behavior: 'smooth', block: 'start' })} style={{ color: 'inherit', textDecoration: 'none', cursor: 'pointer' }}>Security</a>
          <a href="mailto:press@openhousecopilot.com" style={{ color: 'inherit', textDecoration: 'none', cursor: 'pointer' }}>Press</a>
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
    <div className="foyer-device-job" style={{
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

// Waitlist signup modal. POSTs { email, note, source } to
// /newsletter/subscribe and shows a short success state on the same
// surface. Self-contained — no external state library needed. The
// "submit on Enter" + "close on Escape" wiring keeps it feeling
// native for keyboard users.
function WaitlistModal({ source, onClose }) {
  const [email, setEmail] = React.useState('');
  const [note, setNote] = React.useState('');
  const [submitting, setSubmitting] = React.useState(false);
  const [success, setSuccess] = React.useState(false);
  const [error, setError] = React.useState(null);
  const inputRef = React.useRef(null);

  React.useEffect(() => {
    // Autofocus the email field once the modal mounts. setTimeout so
    // the modal's enter animation doesn't fight with the focus call.
    const t = setTimeout(() => inputRef.current?.focus(), 80);
    const onKey = (e) => { if (e.key === 'Escape') onClose(); };
    document.addEventListener('keydown', onKey);
    return () => { clearTimeout(t); document.removeEventListener('keydown', onKey); };
  }, [onClose]);

  const trimmedEmail = email.trim();
  const looksValid = /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(trimmedEmail);
  const canSubmit = looksValid && !submitting && !success;

  const submit = async (e) => {
    e?.preventDefault?.();
    if (!canSubmit) return;
    setSubmitting(true);
    setError(null);
    try {
      const r = await fetch('/newsletter/subscribe', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          email: trimmedEmail,
          note: note.trim() || null,
          source: source || 'landing',
        }),
      });
      if (!r.ok) {
        let detail = '';
        try {
          const j = await r.json();
          detail = j.detail || '';
        } catch { /* ignore */ }
        throw new Error(detail || `${r.status} ${r.statusText}`);
      }
      setSuccess(true);
    } catch (err) {
      setError(err.message || 'Something went wrong. Try again?');
    } finally {
      setSubmitting(false);
    }
  };

  // Render to document.body — the page's .route-frame has a transform
  // for route-change animations, which would otherwise make our
  // `position: fixed` resolve relative to the route frame instead of
  // the viewport. Portal-to-body sidesteps the whole containing-block
  // problem.
  const modal = (
    <div
      onClick={(e) => { if (e.target === e.currentTarget) onClose(); }}
      style={{
        position: 'fixed', inset: 0, zIndex: 10000,
        background: 'rgba(0, 0, 0, 0.62)',
        backdropFilter: 'blur(6px)',
        WebkitBackdropFilter: 'blur(6px)',
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        padding: 24,
        animation: 'foyerFadeIn 200ms ease',
      }}>
      <div style={{
        width: '100%', maxWidth: 460,
        background: 'var(--bg-card)',
        border: '1px solid var(--border)',
        borderRadius: 16,
        boxShadow: '0 40px 100px -20px rgba(0,0,0,0.85), 0 0 0 1px rgba(196,162,82,0.12)',
        padding: 32,
        position: 'relative',
      }}>
        {/* Close (×) */}
        <button
          onClick={onClose}
          aria-label="Close"
          style={{
            position: 'absolute', top: 14, right: 14,
            background: 'transparent', border: 0,
            color: 'var(--text-dim)', cursor: 'pointer',
            width: 30, height: 30, borderRadius: '50%',
            display: 'grid', placeItems: 'center',
            fontSize: 18,
          }}>×</button>

        {success ? (
          <div style={{ textAlign: 'center', padding: '8px 0 4px' }}>
            <div style={{
              margin: '0 auto', width: 56, height: 56, borderRadius: '50%',
              background: 'var(--gold-soft)', color: 'var(--gold)',
              display: 'grid', placeItems: 'center',
              boxShadow: '0 0 0 6px rgba(196,162,82,0.12)',
            }}>
              <svg width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="3">
                <polyline points="20 6 9 17 4 12"/>
              </svg>
            </div>
            <h3 className="serif" style={{ fontSize: 28, margin: '20px 0 8px', color: 'var(--cream)', letterSpacing: '-0.02em' }}>
              You're on the list.
            </h3>
            <p style={{ fontSize: 14, color: 'var(--text-dim)', lineHeight: 1.6, margin: 0 }}>
              We'll write when your seat opens. No spam — promise.
            </p>
            <button
              onClick={onClose}
              className="btn btn-primary"
              style={{ marginTop: 22, padding: '12px 22px', fontSize: 13 }}>
              Close
            </button>
          </div>
        ) : (
          <form onSubmit={submit}>
            <div className="mono" style={{
              fontSize: 11, letterSpacing: '0.16em',
              color: 'var(--gold)', marginBottom: 12,
            }}>
              WAITLIST · INVITE-ONLY
            </div>
            <h3 className="serif" style={{ fontSize: 30, margin: '0 0 10px', color: 'var(--cream)', letterSpacing: '-0.02em', lineHeight: 1.15 }}>
              Join the next cohort.
            </h3>
            <p style={{ fontSize: 14, color: 'var(--text-dim)', lineHeight: 1.6, margin: '0 0 22px' }}>
              Open House Copilot is invite-only while we onboard our first hundred
              brokers. Drop your email — we'll write when a seat opens.
            </p>

            <label style={{ display: 'block' }}>
              <div className="mono" style={{
                fontSize: 10, letterSpacing: '0.12em',
                color: 'var(--text-muted)', marginBottom: 6,
              }}>
                EMAIL
              </div>
              <input
                ref={inputRef}
                type="email"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                placeholder="you@brokerage.com"
                autoComplete="email"
                required
                style={{
                  width: '100%', padding: '12px 14px',
                  background: 'var(--bg-deep)',
                  border: '1px solid var(--hairline)',
                  borderRadius: 10, color: 'var(--cream)',
                  fontSize: 14, fontFamily: 'var(--sans)',
                  outline: 'none', boxSizing: 'border-box',
                }}
              />
            </label>

            <label style={{ display: 'block', marginTop: 14 }}>
              <div className="mono" style={{
                fontSize: 10, letterSpacing: '0.12em',
                color: 'var(--text-muted)', marginBottom: 6,
              }}>
                OPTIONAL · A LINE ABOUT YOU
              </div>
              <textarea
                value={note}
                onChange={(e) => setNote(e.target.value)}
                placeholder="Brokerage, market, how many open houses you host…"
                rows={3}
                maxLength={500}
                style={{
                  width: '100%', padding: '12px 14px',
                  background: 'var(--bg-deep)',
                  border: '1px solid var(--hairline)',
                  borderRadius: 10, color: 'var(--cream)',
                  fontSize: 13, fontFamily: 'var(--sans)',
                  outline: 'none', boxSizing: 'border-box',
                  resize: 'vertical', minHeight: 64, lineHeight: 1.5,
                }}
              />
            </label>

            {error && (
              <div style={{
                marginTop: 14, padding: '10px 12px', borderRadius: 8,
                background: 'rgba(202,80,71,0.08)',
                border: '1px solid rgba(202,80,71,0.3)',
                fontSize: 12, color: 'var(--terracotta)',
              }}>
                {error}
              </div>
            )}

            <button
              type="submit"
              disabled={!canSubmit}
              className="btn btn-primary"
              style={{
                marginTop: 22, width: '100%',
                padding: '14px 22px', fontSize: 14,
                opacity: canSubmit ? 1 : 0.55,
                cursor: canSubmit ? 'pointer' : 'not-allowed',
              }}>
              {submitting ? 'Adding you…' : 'Join the waitlist'}
            </button>

            <div style={{
              marginTop: 14, fontSize: 11, color: 'var(--text-muted)',
              textAlign: 'center', lineHeight: 1.5,
            }}>
              We only email you when your invite is ready.
            </div>
          </form>
        )}
      </div>
    </div>
  );

  // Portal to body so the route-frame's transform doesn't trap our
  // `position: fixed` modal inside a transformed ancestor.
  return ReactDOM.createPortal(modal, document.body);
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

// One column in the Pricing section. The `highlight` tier gets a gold
// border + soft glow so the Solo plan visually anchors the row.
function PricingTier({ tier, price, cadence, blurb, features, cta, highlight }) {
  return (
    <div style={{
      background: 'var(--bg-card)',
      border: '1px solid ' + (highlight ? 'var(--gold)' : 'var(--hairline)'),
      borderRadius: 14,
      padding: '32px 30px 30px',
      display: 'flex', flexDirection: 'column',
      boxShadow: highlight ? '0 30px 80px -40px rgba(196,162,82,0.55)' : 'none',
      position: 'relative',
    }}>
      {highlight && (
        <div className="mono" style={{
          position: 'absolute', top: -10, left: 22,
          background: 'var(--gold)', color: '#1a1610',
          fontSize: 9, letterSpacing: '0.16em',
          padding: '4px 9px', borderRadius: 999,
        }}>MOST AGENTS</div>
      )}
      <div className="mono" style={{
        fontSize: 11, letterSpacing: '0.18em',
        color: highlight ? 'var(--gold)' : 'var(--text-muted)',
      }}>
        {tier}
      </div>
      <div style={{ display: 'flex', alignItems: 'baseline', gap: 8, marginTop: 18 }}>
        <div className="serif" style={{ fontSize: 56, lineHeight: 1, color: 'var(--cream)', letterSpacing: '-0.02em' }}>
          {price}
        </div>
      </div>
      <div className="eyebrow" style={{ marginTop: 10 }}>{cadence}</div>
      <p style={{ marginTop: 22, fontSize: 13.5, lineHeight: 1.7, color: 'var(--text-dim)', minHeight: 76 }}>
        {blurb}
      </p>
      <ul style={{
        listStyle: 'none', margin: '20px 0 28px', padding: 0,
        display: 'flex', flexDirection: 'column', gap: 10,
      }}>
        {features.map(f => (
          <li key={f} style={{ display: 'grid', gridTemplateColumns: '18px 1fr', gap: 10, alignItems: 'start' }}>
            <span style={{ color: 'var(--gold)', fontSize: 12, marginTop: 1, lineHeight: 1.4 }}>
              <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="3" strokeLinecap="round" strokeLinejoin="round">
                <polyline points="20 6 9 17 4 12"/>
              </svg>
            </span>
            <span style={{ fontSize: 13, color: 'var(--cream-dim)', lineHeight: 1.5 }}>{f}</span>
          </li>
        ))}
      </ul>
      <button
        className={'btn ' + (highlight ? 'btn-primary' : '')}
        onClick={cta.onClick}
        style={{ marginTop: 'auto', padding: '12px 18px', fontSize: 13 }}>
        {cta.label}
      </button>
    </div>
  );
}

Object.assign(window, { Landing });
