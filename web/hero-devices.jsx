/* global React, Crest, Tag */
// Hero devices — rotating carousel: iPhone (live), iPad LANDSCAPE (agent home), Laptop (dashboard)

const { useState: useHD, useEffect: useHDEf, useRef: useHDRef } = React;

const useTyped = (target, delay = 0, step = 55) => {
  const [val, setVal] = useHD('');
  useHDEf(() => {
    let raf;
    const start = performance.now() + delay;
    const tick = (now) => {
      if (now < start) { raf = requestAnimationFrame(tick); return; }
      const n = Math.min(target.length, Math.floor((now - start) / step));
      setVal(target.slice(0, n));
      if (n < target.length) raf = requestAnimationFrame(tick);
    };
    raf = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(raf);
  }, []);
  return [val, setVal];
};

const useDelayed = (initial, to, delay) => {
  const [v, setV] = useHD(initial);
  useHDEf(() => {
    const t = setTimeout(() => setV(to), delay);
    return () => clearTimeout(t);
  }, []);
  return v;
};

const useCount = (start, interval = 1000, delay = 0) => {
  const [n, setN] = useHD(start);
  useHDEf(() => {
    let id;
    const to = setTimeout(() => { id = setInterval(() => setN(x => x + 1), interval); }, delay);
    return () => { clearTimeout(to); clearInterval(id); };
  }, []);
  return n;
};

const useStaggered = (schedule) => {
  const [i, setI] = useHD(0);
  useHDEf(() => {
    const timers = schedule.map((t, k) => setTimeout(() => setI(k + 1), t));
    return () => timers.forEach(clearTimeout);
  }, []);
  return i;
};

// iPhone — agent recording
// iPhone Leads detail — mirrors the current iPhone UI: bottom tab bar,
// lead detail with avatar + name + pill row, "What we heard" preview,
// drafted follow-up, and the Refine/Send action row.
const HDIPhone = () => {
  const pillsIn = useDelayed(0, 1, 600);
  const draftIn = useDelayed(0, 1, 1100);
  const [bodyTyped] = useTyped(
    "Sarah — great meeting you today. I'd love to share the West Side comps with you. Want me to send three close to your range plus a Saturday tour slot?",
    1600, 22
  );

  return (
    <div style={{
      width: 300, height: 612, borderRadius: 48, padding: 7,
      background: 'linear-gradient(165deg, #1a1a1c 0%, #050505 100%)',
      boxShadow: '0 60px 120px rgba(0,0,0,0.55), 0 0 0 1.5px rgba(255,255,255,0.06)',
      position: 'relative',
    }}>
      <div style={{ position: 'absolute', top: 14, left: '50%', transform: 'translateX(-50%)', width: 96, height: 30, borderRadius: 20, background: '#000', zIndex: 10 }} />
      <div style={{
        width: '100%', height: '100%', borderRadius: 42, overflow: 'hidden',
        background: 'var(--bg-deep)', padding: '50px 16px 14px',
        position: 'relative', display: 'flex', flexDirection: 'column',
      }}>
        {/* Status bar */}
        <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: 10, color: 'var(--cream)', marginTop: -4 }}>
          <span className="mono">13:18</span>
          <span className="mono">●●●●●</span>
        </div>

        {/* Back to Leads chip */}
        <div style={{ marginTop: 10 }}>
          <span style={{
            display: 'inline-flex', alignItems: 'center', gap: 5,
            padding: '5px 9px', borderRadius: 999,
            background: 'rgba(255,255,255,0.06)',
            fontSize: 10, color: 'var(--cream-dim)',
          }}>
            <svg width="9" height="9" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="2"><polyline points="10 4 6 8 10 12"/></svg>
            Leads
          </span>
        </div>

        {/* Visitor header row: avatar + name + delete */}
        <div style={{ marginTop: 12, display: 'flex', alignItems: 'center', gap: 10 }}>
          <div style={{
            width: 40, height: 40, borderRadius: '50%',
            background: 'var(--bg-elev)', color: 'var(--gold)',
            display: 'grid', placeItems: 'center',
            fontFamily: 'var(--sans)', fontWeight: 600, fontSize: 14,
          }}>S</div>
          <div className="serif" style={{ flex: 1, fontSize: 22, color: 'var(--cream)', letterSpacing: '-0.02em' }}>
            Sarah Chen
          </div>
          <span style={{
            padding: '5px 8px', borderRadius: 999,
            background: 'rgba(202, 80, 71, 0.14)',
            color: 'var(--terracotta)',
            fontSize: 10, fontWeight: 600,
            display: 'inline-flex', alignItems: 'center', gap: 4,
          }}>
            <svg width="9" height="9" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><polyline points="3 6 5 6 21 6"/><path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6"/></svg>
          </span>
        </div>

        {/* Pill row — FlowLayout style */}
        <div style={{
          marginTop: 10, display: 'flex', gap: 6, flexWrap: 'wrap',
          opacity: pillsIn, transform: pillsIn ? 'translateY(0)' : 'translateY(4px)',
          transition: 'opacity .4s ease, transform .4s ease',
        }}>
          <span style={{
            padding: '3px 8px', borderRadius: 999, fontSize: 10, fontWeight: 500,
            color: 'var(--gold)', background: 'rgba(196,162,82,0.14)',
          }}>Buyer</span>
          <span style={{
            padding: '3px 8px', borderRadius: 999, fontSize: 10, fontWeight: 500,
            color: 'var(--cream-dim)', background: 'rgba(255,255,255,0.06)',
          }}>Score 94/100</span>
          <span style={{
            padding: '3px 8px', borderRadius: 999, fontSize: 10, fontWeight: 500,
            color: 'var(--sage)', background: 'rgba(134,166,128,0.14)',
          }}>Replied</span>
        </div>

        {/* What we heard */}
        <div style={{ marginTop: 14 }}>
          <div className="mono" style={{ fontSize: 8.5, color: 'var(--text-dim)', letterSpacing: '0.1em' }}>WHAT WE HEARD</div>
          <p style={{
            margin: '5px 0 0',
            fontSize: 11, lineHeight: 1.5, color: 'var(--cream-dim)',
            display: '-webkit-box', WebkitLineClamp: 2, WebkitBoxOrient: 'vertical',
            overflow: 'hidden',
          }}>
            Pre-approved to $1.4M. Sold her Queens place last year. Drawn by the kitchen…
          </p>
        </div>

        {/* Drafted follow-up */}
        <div style={{
          marginTop: 14, padding: '10px 11px', flex: 1,
          borderRadius: 10,
          background: 'rgba(255,255,255,0.03)',
          border: '1px solid rgba(196,162,82,0.22)',
          opacity: draftIn,
          transform: draftIn ? 'translateY(0)' : 'translateY(4px)',
          transition: 'opacity .5s ease, transform .5s ease',
        }}>
          <div className="mono" style={{ fontSize: 8.5, color: 'var(--gold)', letterSpacing: '0.1em' }}>DRAFTED FOLLOW-UP</div>
          <div style={{ marginTop: 6, fontSize: 11, lineHeight: 1.5, color: 'var(--cream)' }}>
            {bodyTyped}
            <span style={{
              display: 'inline-block', width: 5, height: 11, marginLeft: 1,
              background: 'var(--gold)', verticalAlign: '-1px',
              animation: 'hdBlink 0.9s steps(2) infinite',
            }} />
          </div>
        </div>

        {/* Action row */}
        <div style={{ marginTop: 10, display: 'flex', gap: 6, alignItems: 'center' }}>
          <span style={{
            padding: '6px 9px', borderRadius: 999,
            background: 'rgba(255,255,255,0.05)',
            color: 'var(--cream-dim)', fontSize: 10, fontWeight: 500,
          }}>Archive</span>
          <span style={{ flex: 1 }} />
          <span style={{
            padding: '6px 9px', borderRadius: 999,
            background: 'rgba(255,255,255,0.05)',
            color: 'var(--cream-dim)', fontSize: 10, fontWeight: 500,
          }}>Schedule</span>
          <span style={{
            padding: '6px 11px', borderRadius: 999,
            background: 'var(--gold)', color: 'var(--ink-on-gold)',
            fontSize: 10.5, fontWeight: 600,
            display: 'inline-flex', alignItems: 'center', gap: 4,
          }}>
            <svg width="9" height="9" viewBox="0 0 24 24" fill="currentColor"><path d="M22 2 11 13"/><path d="M22 2 15 22l-4-9-9-4 20-7Z"/></svg>
            Send
          </span>
        </div>

        {/* Bottom tab bar — floating capsule */}
        <div style={{
          marginTop: 10,
          background: 'rgba(20,20,22,0.96)',
          border: '1px solid var(--hairline)',
          borderRadius: 18,
          padding: '6px 4px',
          display: 'grid', gridTemplateColumns: 'repeat(5, 1fr)',
          boxShadow: '0 8px 16px rgba(0,0,0,0.4)',
        }}>
          {[
            { i: 'home',  l: 'Home' },
            { i: 'rec',   l: 'Record' },
            { i: 'kiosk', l: 'Kiosk' },
            { i: 'leads', l: 'Leads', active: true },
            { i: 'more',  l: 'More' },
          ].map(t => (
            <div key={t.i} style={{
              display: 'flex', flexDirection: 'column', alignItems: 'center',
              gap: 2, padding: '4px 0',
              color: t.active ? 'var(--gold)' : 'var(--text-muted)',
            }}>
              <svg width="13" height="13" viewBox="0 0 24 24" fill={t.active ? 'currentColor' : 'none'} stroke="currentColor" strokeWidth="1.6">
                {t.i === 'home'  && <path d="M3 11 12 3l9 8v9a2 2 0 0 1-2 2h-4v-7h-6v7H5a2 2 0 0 1-2-2v-9Z"/>}
                {t.i === 'rec'   && <><circle cx="12" cy="12" r="3"/><circle cx="12" cy="12" r="8"/></>}
                {t.i === 'kiosk' && <><rect x="3" y="5" width="18" height="13" rx="2"/><path d="M8 22h8M12 18v4"/></>}
                {t.i === 'leads' && <><path d="M4 7h16M4 12h16M4 17h10"/><circle cx="19" cy="17" r="2.5" fill="currentColor"/></>}
                {t.i === 'more'  && <><circle cx="5" cy="12" r="1.5" fill="currentColor"/><circle cx="12" cy="12" r="1.5" fill="currentColor"/><circle cx="19" cy="12" r="1.5" fill="currentColor"/></>}
              </svg>
              <span style={{ fontSize: 7, fontWeight: 500 }}>{t.l}</span>
            </div>
          ))}
        </div>

        <div style={{ position: 'absolute', bottom: 5, left: '50%', transform: 'translateX(-50%)', width: 110, height: 4, borderRadius: 100, background: 'rgba(255,255,255,0.3)' }} />
      </div>
    </div>
  );
};

// iPad LANDSCAPE — agent Home matching the real IPadHome:
//   side rail (Home active) + greeting + hero listing card with photo
//   + recent sessions feed below.
const HDIPad = () => {
  const sessionsIn = useStaggered([900, 1500, 2100]);
  const tickSec = useCount(0, 1000, 0);
  const guestsIn = Math.min(6, 4 + Math.floor(tickSec / 4));

  return (
    <div style={{
      width: 920, height: 660,
      borderRadius: 30, padding: 11,
      background: 'linear-gradient(165deg, #1d1d1f 0%, #0a0a0c 100%)',
      boxShadow: '0 60px 120px rgba(0,0,0,0.6), 0 0 0 1px rgba(0,0,0,0.2)',
      position: 'relative',
    }}>
      {/* front camera — landscape top mid */}
      <div style={{
        position: 'absolute', top: 18, left: '50%', transform: 'translateX(-50%)',
        width: 7, height: 7, borderRadius: '50%', background: '#0a0a0a',
        boxShadow: 'inset 0 0 0 1.5px rgba(255,255,255,0.05)', zIndex: 10,
      }} />
      <div style={{
        width: '100%', height: '100%', borderRadius: 22, overflow: 'hidden',
        background: 'var(--bg-deep)', color: 'var(--cream)',
        display: 'grid', gridTemplateColumns: '72px 1fr',
      }}>
        {/* SIDE RAIL */}
        <div style={{
          borderRight: '1px solid var(--hairline)',
          padding: '20px 0', display: 'flex', flexDirection: 'column',
          alignItems: 'center', gap: 22,
        }}>
          <div className="crest-mark" style={{ width: 32, height: 32, fontSize: 15 }}>F</div>
          {[
            { i: 'home', active: true, label: 'Home' },
            { i: 'kiosk', label: 'Kiosk' },
            { i: 'sessions', label: 'Sessions' },
            { i: 'leads', label: 'Leads' },
            { i: 'offers', label: 'Offers' },
            { i: 'listings', label: 'Listings' },
          ].map(it => (
            <div key={it.i} style={{
              display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 6,
              color: it.active ? 'var(--gold)' : 'var(--text-muted)',
            }}>
              <div style={{
                width: 30, height: 30, display: 'grid', placeItems: 'center',
                border: '1px solid ' + (it.active ? 'var(--gold)' : 'var(--hairline)'),
                borderRadius: 8,
                background: it.active ? 'var(--gold-soft)' : 'transparent',
              }}>
                <svg width="14" height="14" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.2">
                  {it.i === 'home' && <path d="M2 7l6-5 6 5v7H2z"/>}
                  {it.i === 'kiosk' && <><rect x="2" y="3" width="12" height="9" rx="1"/><path d="M6 14h4M8 12v2"/><circle cx="8" cy="7.5" r="1.5"/></>}
                  {it.i === 'listings' && <><rect x="2" y="3" width="12" height="10"/><path d="M2 7h12M6 3v10"/></>}
                  {it.i === 'sessions' && <><circle cx="8" cy="8" r="6"/><circle cx="8" cy="8" r="2"/></>}
                  {it.i === 'leads' && <><circle cx="8" cy="6" r="3"/><path d="M2 14c0-3 3-5 6-5s6 2 6 5"/></>}
                  {it.i === 'offers' && <path d="M13 8.5L8.5 13a1 1 0 01-1.4 0L2 7.9V2h5.9l5.1 5.1a1 1 0 010 1.4zM5 5h0"/>}
                  {it.i === 'templates' && <><rect x="3" y="2" width="10" height="12"/><path d="M5 5h6M5 8h6M5 11h4"/></>}
                </svg>
              </div>
              <div className="mono" style={{ fontSize: 7, letterSpacing: '0.16em', textTransform: 'uppercase' }}>{it.label}</div>
            </div>
          ))}
          <div style={{ marginTop: 'auto', width: 28, height: 28, borderRadius: '50%',
            background: 'var(--bg-elev-2)', border: '1px solid var(--border)',
            display: 'grid', placeItems: 'center',
            fontFamily: 'var(--serif)', fontStyle: 'italic', fontSize: 12, color: 'var(--gold)',
          }}>JH</div>
        </div>

        {/* MAIN — mirrors IPadHome: greeting, hero listing card with
            photo, recent sessions feed. */}
        <div style={{ padding: '24px 30px 0', overflow: 'hidden', display: 'flex', flexDirection: 'column' }}>
          {/* Greeting */}
          <div>
            <div className="eyebrow" style={{ fontSize: 10, color: 'var(--text-dim)' }}>
              SATURDAY, MAY 10
            </div>
            <h1 className="serif" style={{ fontSize: 30, lineHeight: 1, margin: '4px 0 0', fontWeight: 500, letterSpacing: '-0.02em' }}>
              Good afternoon, <span className="serif-it" style={{ color: 'var(--gold)' }}>John</span>
            </h1>
          </div>

          {/* HERO LISTING CARD — big photo + address + price + Sign-in / Record */}
          <div style={{
            marginTop: 20, position: 'relative', overflow: 'hidden',
            borderRadius: 16, minHeight: 240,
            background:
              'linear-gradient(180deg, rgba(0,0,0,0) 30%, rgba(0,0,0,0.55) 70%, rgba(0,0,0,0.92) 100%),' +
              'linear-gradient(115deg, #2c3340 0%, #1a1f29 40%, #0e1218 100%)',
          }}>
            {/* Tiled-photo texture */}
            <div style={{
              position: 'absolute', inset: 0,
              backgroundImage:
                'repeating-linear-gradient(45deg, rgba(196,162,82,0.04) 0 14px, transparent 14px 28px)',
              opacity: 0.7,
            }} />
            {/* Faux house silhouette */}
            <div style={{
              position: 'absolute', top: 24, right: 28, width: 220, height: 130,
              opacity: 0.18,
              background:
                'linear-gradient(180deg, transparent 30%, rgba(196,162,82,0.4) 100%)',
              clipPath: 'polygon(8% 100%, 8% 50%, 50% 12%, 92% 50%, 92% 100%)',
            }} />
            <div style={{ position: 'absolute', inset: 0, padding: 22, display: 'flex', flexDirection: 'column', justifyContent: 'flex-end' }}>
              <div style={{
                display: 'inline-flex', alignItems: 'center', gap: 6,
                fontSize: 9, letterSpacing: '0.16em', fontFamily: 'var(--mono)',
                color: '#fff', textTransform: 'uppercase',
                marginBottom: 8,
              }}>
                <span style={{ width: 6, height: 6, borderRadius: '50%', background: 'var(--terracotta)', boxShadow: '0 0 8px var(--terracotta)' }} />
                HOSTING TODAY
              </div>
              <div className="serif" style={{ fontSize: 28, color: '#fff', lineHeight: 1.05, letterSpacing: '-0.02em' }}>
                412 W 78th St
              </div>
              <div style={{ display: 'flex', alignItems: 'flex-end', justifyContent: 'space-between', marginTop: 14, gap: 12 }}>
                <div style={{ display: 'flex', alignItems: 'baseline', gap: 12 }}>
                  <span className="serif" style={{ fontSize: 16, color: 'var(--gold)', fontWeight: 500 }}>$1.29M</span>
                  <span style={{ fontSize: 11, color: 'rgba(255,255,255,0.75)' }}>
                    3 Beds · 2.5 Baths · 1,840 SF
                  </span>
                </div>
                <div style={{ display: 'flex', gap: 8 }}>
                  <button style={{
                    padding: '8px 14px',
                    background: 'rgba(255,255,255,0.12)', color: '#fff',
                    border: 0, borderRadius: 999,
                    fontFamily: 'var(--sans)', fontSize: 11, fontWeight: 500,
                    display: 'inline-flex', alignItems: 'center', gap: 6,
                  }}>
                    <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><path d="M16 11a4 4 0 1 0-8 0v3"/><path d="M5 14h14v6H5z"/></svg>
                    Sign-in
                  </button>
                  <button style={{
                    padding: '8px 14px',
                    background: 'var(--gold)', color: 'var(--ink-on-gold)',
                    border: 0, borderRadius: 999,
                    fontFamily: 'var(--sans)', fontSize: 11, fontWeight: 600,
                    display: 'inline-flex', alignItems: 'center', gap: 6,
                  }}>
                    <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5"><line x1="6" y1="12" x2="6" y2="12"/><path d="M3 12c0-3 1-6 3-6m15 6c0-3-1-6-3-6M3 12c0 3 1 6 3 6m15-6c0 3-1 6-3 6"/></svg>
                    Record
                  </button>
                </div>
              </div>
            </div>
          </div>

          {/* RECENT SESSIONS feed — matches IPadHome session rows */}
          <div style={{ marginTop: 20 }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', marginBottom: 12 }}>
              <h2 className="serif" style={{ fontSize: 18, fontWeight: 500, color: 'var(--cream)', margin: 0 }}>
                Recent sessions
              </h2>
              <span className="mono" style={{ fontSize: 9, color: 'var(--text-muted)', letterSpacing: '0.12em' }}>
                {guestsIn} TOTAL
              </span>
            </div>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
              {[
                { addr: '301 E 79th St',   when: 'Yesterday', leads: 8 },
                { addr: '212 W End · #6F', when: '2 days ago', leads: 4 },
                { addr: '88 Greenwich St', when: '4 days ago', leads: 11 },
              ].map((s, i) => (
                <div key={s.addr} style={{
                  display: 'flex', alignItems: 'center', gap: 12,
                  padding: '10px 12px',
                  background: 'rgba(255,255,255,0.04)',
                  borderRadius: 12,
                  opacity: i < sessionsIn ? 1 : 0,
                  transform: i < sessionsIn ? 'translateY(0)' : 'translateY(6px)',
                  transition: 'opacity .4s ease, transform .4s ease',
                }}>
                  {/* Thumb */}
                  <div style={{
                    width: 56, height: 40, borderRadius: 8,
                    background: 'linear-gradient(135deg, #20262f, #0c0e12)',
                    display: 'grid', placeItems: 'center',
                    color: 'rgba(196,162,82,0.55)',
                  }}>
                    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5">
                      <path d="M3 12c0-3 1-6 3-6m15 6c0-3-1-6-3-6M3 12c0 3 1 6 3 6m15-6c0 3-1 6-3 6"/>
                    </svg>
                  </div>
                  <div style={{ flex: 1 }}>
                    <div className="serif" style={{ fontSize: 14, color: 'var(--cream)' }}>{s.addr}</div>
                    <div style={{ display: 'flex', gap: 6, fontSize: 10, color: 'var(--text-dim)', marginTop: 2 }}>
                      <span>{s.when}</span>
                      <span>·</span>
                      <span>{s.leads} leads</span>
                    </div>
                  </div>
                  <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" style={{ color: 'var(--text-muted)' }}>
                    <polyline points="9 6 15 12 9 18"/>
                  </svg>
                </div>
              ))}
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};

// Laptop — web Leads inbox mirroring the actual /#/leads page: the new
// sidebar (Home / Kiosk / Sessions / Leads / Offers / Listings), a lead
// list on the left, and a focused lead detail on the right with the
// draft + Refine-with-AI bar.
const HDLaptop = () => {
  const [sel, setSel] = useHD(0);
  const guests = [
    { n: 'Sarah Chen',     k: 'buyer',   sub: 'Pre-approved $1.4M', score: 94,
      sum: 'Actively searching the West Side. Sold her Queens place last year. Drawn by the kitchen. Pre-approved to $1.4M, ready to close in 60 days.' },
    { n: 'Mike Rodriguez', k: 'seller',  sub: 'Wants comp analysis', score: 76,
      sum: 'Lives two blocks away. 15 years in his home. Kids off to college, considering downsizing in six months. Requested a complimentary comp.' },
    { n: 'Jennifer Park',  k: 'browser', sub: 'Curious renter', score: 38,
      sum: 'Local renter, lease through 2027. Loves the neighborhood but undecided. Open to low-pressure listing updates.' },
  ];
  const g = guests[sel];
  const shownGuests = useStaggered([400, 900, 1400]);
  const detailIn = useDelayed(0, 1, 1700);
  const [bodyTyped] = useTyped(
    g.k === 'buyer'
      ? "Sarah — great meeting you today. I'd love to share three comps from the block plus a private-showing slot for Saturday morning. Want me to send them over?"
      : g.k === 'seller'
      ? "Mike — great meeting you today. I'd love to put together a complimentary CMA for your place — no obligations, just real numbers from this quarter."
      : "Jennifer — great meeting you today. Totally understand you're early. I'll send a quiet listing update once a week — unsubscribe with one tap.",
    1800, 22
  );

  const navItems = [
    { i: 'home',  l: 'Home' },
    { i: 'kiosk', l: 'Kiosk' },
    { i: 'sess',  l: 'Sessions' },
    { i: 'leads', l: 'Leads', active: true },
    { i: 'off',   l: 'Offers' },
    { i: 'list',  l: 'Listings' },
  ];

  return (
    <div style={{ width: 880, position: 'relative' }}>
      <div style={{
        width: '100%', aspectRatio: '16 / 10',
        background: 'linear-gradient(180deg, #1a1d23 0%, #0e1116 100%)',
        borderRadius: '14px 14px 4px 4px',
        border: '1px solid rgba(255,255,255,0.06)',
        padding: 14, position: 'relative',
        boxShadow: '0 60px 120px rgba(0,0,0,0.55)',
      }}>
        <div style={{ position: 'absolute', top: 0, left: '50%', transform: 'translateX(-50%)', width: 110, height: 9, background: '#000', borderRadius: '0 0 8px 8px' }} />
        <div style={{
          width: '100%', height: '100%', overflow: 'hidden',
          background: 'var(--bg-deep)', border: '1px solid var(--hairline)',
          display: 'flex', flexDirection: 'column',
        }}>
          {/* Browser chrome */}
          <div style={{
            padding: '10px 18px', display: 'flex', alignItems: 'center', gap: 14,
            borderBottom: '1px solid var(--hairline)', background: 'rgba(0,0,0,0.4)',
          }}>
            <div style={{ display: 'flex', gap: 6 }}>
              {['#3a3328','#3a3328','#3a3328'].map((c, i) => (
                <span key={i} style={{ width: 10, height: 10, borderRadius: '50%', background: c }} />
              ))}
            </div>
            <div style={{ flex: 1 }} />
            <span className="mono" style={{ fontSize: 10, letterSpacing: '0.16em', color: 'var(--text-muted)' }}>
              foyer.house /#/leads
            </span>
          </div>

          {/* App: sidebar + main */}
          <div style={{ flex: 1, display: 'grid', gridTemplateColumns: '140px 1fr', minHeight: 0 }}>
            {/* SIDEBAR — new web nav */}
            <div style={{
              borderRight: '1px solid var(--hairline)',
              padding: '12px 8px',
              background: 'rgba(255,255,255,0.02)',
              display: 'flex', flexDirection: 'column',
            }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 8, padding: '4px 8px 14px', borderBottom: '1px solid var(--hairline)' }}>
                <Crest size={11} />
              </div>
              <div className="mono" style={{ fontSize: 7, color: 'var(--text-muted)', letterSpacing: '0.16em', padding: '12px 10px 6px' }}>
                OPEN HOUSE
              </div>
              {navItems.slice(0, 2).map(it => (
                <NavRow key={it.i} item={it} />
              ))}
              <div className="mono" style={{ fontSize: 7, color: 'var(--text-muted)', letterSpacing: '0.16em', padding: '12px 10px 6px' }}>
                LIBRARY
              </div>
              {navItems.slice(2).map(it => (
                <NavRow key={it.i} item={it} />
              ))}
              <div style={{ flex: 1 }} />
              <div style={{
                margin: '8px 4px 0', padding: '8px 10px', borderRadius: 8,
                background: 'rgba(255,255,255,0.04)',
                display: 'flex', alignItems: 'center', gap: 8,
              }}>
                <div style={{
                  width: 22, height: 22, borderRadius: '50%',
                  background: 'var(--gold-soft)', color: 'var(--gold)',
                  display: 'grid', placeItems: 'center',
                  fontSize: 9, fontWeight: 600,
                }}>JH</div>
                <span style={{ fontSize: 9.5, color: 'var(--cream)' }}>John H.</span>
              </div>
            </div>

            {/* MAIN — Leads inbox: list + detail */}
            <div style={{ display: 'grid', gridTemplateColumns: '220px 1fr', minHeight: 0 }}>
              {/* Lead list */}
              <div style={{
                borderRight: '1px solid var(--hairline)',
                padding: '14px 10px',
                background: 'rgba(0,0,0,0.18)',
                overflow: 'hidden',
              }}>
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', padding: '0 4px 10px' }}>
                  <div className="serif" style={{ fontSize: 18, color: 'var(--cream)' }}>Leads</div>
                  <span style={{
                    width: 22, height: 22, borderRadius: '50%',
                    background: 'var(--gold)', color: 'var(--ink-on-gold)',
                    display: 'grid', placeItems: 'center', fontSize: 12,
                  }}>+</span>
                </div>
                <div style={{
                  margin: '0 4px 10px', padding: '8px 10px', borderRadius: 8,
                  background: 'rgba(196,162,82,0.08)',
                  border: '1px solid rgba(196,162,82,0.22)',
                  display: 'flex', alignItems: 'center', gap: 7,
                }}>
                  <svg width="10" height="10" viewBox="0 0 24 24" fill="var(--gold)" stroke="none"><path d="M12 2v6m0 8v6M2 12h6m8 0h6M5.6 5.6l3.5 3.5M14.9 14.9l3.5 3.5M5.6 18.4l3.5-3.5M14.9 9.1l3.5-3.5"/></svg>
                  <span style={{ fontSize: 9.5, color: 'var(--cream-dim)' }}>Ask your inbox anything…</span>
                </div>
                {guests.map((gg, i) => (
                  <button key={gg.n} onClick={() => setSel(i)} style={{
                    all: 'unset', cursor: 'pointer', display: 'block',
                    padding: '10px 10px', margin: '0 0 4px',
                    background: sel === i ? 'rgba(255,255,255,0.06)' : 'transparent',
                    borderRadius: 8,
                    width: '100%', boxSizing: 'border-box',
                    opacity: i < shownGuests ? 1 : 0,
                    transform: i < shownGuests ? 'translateX(0)' : 'translateX(-6px)',
                    transition: 'opacity .45s ease, transform .45s ease, background .2s',
                  }}>
                    <div style={{ display: 'flex', alignItems: 'center', gap: 7 }}>
                      <div style={{
                        width: 22, height: 22, borderRadius: '50%',
                        background: 'var(--bg-elev)', color: 'var(--gold)',
                        display: 'grid', placeItems: 'center',
                        fontSize: 9, fontWeight: 600,
                      }}>{gg.n.charAt(0)}</div>
                      <div style={{ flex: 1, minWidth: 0 }}>
                        <div style={{ fontSize: 11, color: 'var(--cream)', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{gg.n}</div>
                        <div style={{ fontSize: 8.5, color: 'var(--text-dim)', marginTop: 1 }}>{gg.sub}</div>
                      </div>
                      <span className="mono" style={{ fontSize: 8.5, color: 'var(--gold)', letterSpacing: '0.04em' }}>
                        {gg.score}
                      </span>
                    </div>
                  </button>
                ))}
              </div>

              {/* Detail */}
              <div style={{
                padding: '18px 22px', minHeight: 0, overflow: 'hidden',
                opacity: detailIn,
                transform: detailIn ? 'translateY(0)' : 'translateY(8px)',
                transition: 'opacity .55s ease, transform .55s ease',
              }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
                  <div style={{
                    width: 30, height: 30, borderRadius: '50%',
                    background: 'var(--bg-elev)', color: 'var(--gold)',
                    display: 'grid', placeItems: 'center',
                    fontSize: 11, fontWeight: 600,
                  }}>{g.n.charAt(0)}</div>
                  <div className="serif" style={{ fontSize: 22, color: 'var(--cream)', letterSpacing: '-0.02em' }}>{g.n}</div>
                </div>
                <div style={{ display: 'flex', gap: 5, marginTop: 8, flexWrap: 'wrap' }}>
                  <span className={`tag tag-${g.k}`} style={{ fontSize: 9, padding: '2px 7px 3px' }}>
                    <span className="tag-dot" style={{ width: 4, height: 4 }} />{g.k}
                  </span>
                  <span style={{
                    padding: '2px 7px', borderRadius: 999, fontSize: 9, fontWeight: 500,
                    color: 'var(--cream-dim)', background: 'rgba(255,255,255,0.05)',
                  }}>Score {g.score}/100</span>
                </div>
                <p style={{ fontSize: 11, color: 'var(--cream-dim)', lineHeight: 1.55, marginTop: 10,
                  display: '-webkit-box', WebkitLineClamp: 2, WebkitBoxOrient: 'vertical', overflow: 'hidden',
                }}>
                  {g.sum}
                </p>
                <div style={{ height: 1, background: 'var(--hairline)', margin: '10px 0 8px' }} />
                <div className="mono" style={{ fontSize: 8.5, color: 'var(--gold)', letterSpacing: '0.1em' }}>DRAFTED FOLLOW-UP</div>
                <div style={{ marginTop: 5, padding: 10, background: 'rgba(0,0,0,0.3)', border: '1px solid var(--hairline)', borderRadius: 6, fontSize: 10.5, lineHeight: 1.55, color: 'var(--cream-dim)' }}>
                  {bodyTyped}<span style={{
                    display: 'inline-block', width: 5, height: 11, marginLeft: 1,
                    background: 'var(--gold)', verticalAlign: '-1px',
                    animation: 'hdBlink 0.9s steps(2) infinite',
                  }} />
                </div>
                {/* Refine bar */}
                <div style={{
                  marginTop: 8, padding: '7px 10px',
                  background: 'var(--gold-soft)',
                  border: '1px solid rgba(196,162,82,0.4)',
                  borderRadius: 6, display: 'flex', alignItems: 'center', gap: 6,
                }}>
                  <svg width="10" height="10" viewBox="0 0 24 24" fill="var(--gold)" stroke="none"><path d="M12 2v6m0 8v6M2 12h6m8 0h6"/></svg>
                  <span className="mono" style={{ fontSize: 8.5, color: 'var(--gold)', letterSpacing: '0.1em' }}>REFINE WITH AI</span>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
      <div style={{
        height: 14, background: 'linear-gradient(180deg, #1a1d23 0%, #0a0c10 100%)',
        borderRadius: '0 0 22px 22px', margin: '0 -30px', position: 'relative',
        boxShadow: '0 8px 18px rgba(0,0,0,0.35)',
      }}>
        <div style={{ position: 'absolute', top: 0, left: '50%', transform: 'translateX(-50%)', width: 140, height: 5, background: '#000', borderRadius: '0 0 8px 8px' }} />
      </div>
    </div>
  );
};

// Small helper for the laptop mock sidebar — one nav row matching the
// real web AppShell visual.
function NavRow({ item }) {
  const icon = {
    home:  <><path d="M3 11 12 3l9 8"/><path d="M5 10v10a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V10"/><path d="M9 22v-7h6v7"/></>,
    kiosk: <><rect x="3" y="5" width="18" height="13" rx="2"/><path d="M8 22h8M12 18v4"/><circle cx="12" cy="11" r="2.5"/></>,
    sess:  <><rect x="3" y="4" width="18" height="16" rx="2"/><path d="M3 9h18M9 14h6"/></>,
    leads: <><path d="M4 7h16M4 12h16M4 17h10"/><circle cx="19" cy="17" r="2.5" fill={item.active ? 'currentColor' : 'none'}/></>,
    off:   <><path d="M20.59 13.41 13.41 20.59a2 2 0 0 1-2.83 0L2 12V2h10l8.59 8.59a2 2 0 0 1 0 2.82Z"/><circle cx="7" cy="7" r="1.4"/></>,
    list:  <><path d="M3 12 12 4l9 8"/><path d="M5 10v10h14V10"/></>,
  }[item.i];
  return (
    <div style={{
      display: 'flex', alignItems: 'center', gap: 8,
      padding: '7px 10px', margin: '1px 2px', borderRadius: 6,
      background: item.active ? 'rgba(196,162,82,0.12)' : 'transparent',
      color: item.active ? 'var(--gold)' : 'var(--cream-dim)',
    }}>
      <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round">
        {icon}
      </svg>
      <span style={{ fontSize: 10, fontWeight: item.active ? 500 : 400 }}>{item.l}</span>
    </div>
  );
}

// HeroDevices — rotating carousel
const HeroDevices = () => {
  const [idx, setIdx] = useHD(0);
  const tRef = useHDRef(null);

  useHDEf(() => {
    tRef.current = setInterval(() => setIdx(i => (i + 1) % 3), 8000);
    return () => clearInterval(tRef.current);
  }, []);

  const devices = [
    { id: 'phone',  label: 'iPhone',  caption: 'Captures every conversation, in pocket' },
    { id: 'ipad',   label: 'iPad',    caption: 'Agent home — host, sign-in, follow-up' },
    { id: 'laptop', label: 'Laptop',  caption: 'The whole open house, by Monday' },
  ];

  return (
    <div style={{ position: 'relative', minHeight: 660, height: 660, userSelect: 'none', width: '100%', maxWidth: 620, justifySelf: 'center', alignSelf: 'center' }}>
      <div style={{
        position: 'absolute', inset: '-20px',
        background: 'radial-gradient(ellipse 65% 55% at center 45%, var(--gold-soft), transparent 70%)',
        pointerEvents: 'none',
      }} />
      <div style={{ position: 'absolute', top: 0, left: 0, color: 'var(--gold)', zIndex: 5 }}>
        <svg width="60" height="60" viewBox="0 0 60 60"><path d="M0 1 L30 1 M1 0 L1 30" stroke="currentColor" strokeWidth="1" fill="none"/></svg>
      </div>
      <div style={{ position: 'absolute', top: 0, right: 0, color: 'var(--gold)', transform: 'rotate(90deg)', zIndex: 5 }}>
        <svg width="60" height="60" viewBox="0 0 60 60"><path d="M0 1 L30 1 M1 0 L1 30" stroke="currentColor" strokeWidth="1" fill="none"/></svg>
      </div>

      <div style={{
        position: 'absolute', inset: '0 0 90px',
        display: 'grid', placeItems: 'center', perspective: '1800px',
      }}>
        {devices.map((d, i) => {
          if (idx !== i) return null;
          const anim = d.id === 'laptop'
            ? 'hdLaptopOpen 1.1s cubic-bezier(.22,1,.36,1) both'
            : d.id === 'ipad'
              ? 'hdIPadIn 0.9s cubic-bezier(.22,1,.36,1) both'
              : 'hdPhoneIn 0.85s cubic-bezier(.22,1,.36,1) both';
          const scale = d.id === 'laptop' ? 0.58 : d.id === 'ipad' ? 0.62 : 0.92;
          const base  = d.id === 'laptop' ? { w: 880, h: 580 }
                     : d.id === 'ipad'   ? { w: 920, h: 660 }
                     : { w: 300, h: 612 };
          return (
            <div key={`${d.id}-${idx}`} style={{
              gridColumn: 1, gridRow: 1,
              width: base.w * scale, height: base.h * scale,
              animation: anim,
              transformStyle: 'preserve-3d',
              transformOrigin: d.id === 'laptop' ? 'center bottom' : 'center center',
            }}>
              <div style={{ width: base.w, height: base.h, transform: `scale(${scale})`, transformOrigin: 'top left' }}>
                {d.id === 'phone'  && <HDIPhone />}
                {d.id === 'ipad'   && <HDIPad />}
                {d.id === 'laptop' && <HDLaptop />}
              </div>
            </div>
          );
        })}
      </div>

      <div style={{
        position: 'absolute', bottom: 0, left: 0, right: 0,
        display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 14,
        paddingTop: 18, borderTop: '1px solid var(--hairline)',
      }}>
        {devices.map((d, i) => (
          <button key={d.id} onClick={() => setIdx(i)} style={{
            all: 'unset', cursor: 'pointer', padding: '4px 0 0',
            borderTop: '2px solid ' + (idx === i ? 'var(--gold)' : 'transparent'),
            marginTop: -19, transition: 'border-color .3s',
          }}>
            <div className="mono" style={{
              fontSize: 11, letterSpacing: '0.2em', marginTop: 14,
              color: idx === i ? 'var(--gold)' : 'var(--text-muted)',
              transition: 'color .3s',
            }}>
              0{i + 1} · {d.label.toUpperCase()}
            </div>
            <div style={{
              fontSize: 13, lineHeight: 1.45, marginTop: 7,
              color: idx === i ? 'var(--cream-dim)' : 'var(--text-muted)',
              transition: 'color .3s',
            }}>{d.caption}</div>
            <div style={{ height: 1, marginTop: 10, background: 'var(--hairline)', position: 'relative', overflow: 'hidden' }}>
              {idx === i && (
                <div key={`bar-${idx}`} style={{
                  position: 'absolute', inset: 0, background: 'var(--gold)',
                  transformOrigin: 'left center', animation: 'hdBar 8s linear forwards',
                }} />
              )}
            </div>
          </button>
        ))}
      </div>

      <style>{`
        @keyframes hbar0 { from { transform: scaleY(.3); } to { transform: scaleY(1); } }
        @keyframes hbar1 { from { transform: scaleY(.6); } to { transform: scaleY(.4); } }
        @keyframes hbar2 { from { transform: scaleY(.5); } to { transform: scaleY(.9); } }
        @keyframes hbar3 { from { transform: scaleY(.8); } to { transform: scaleY(.3); } }
        @keyframes hdBar { from { transform: scaleX(0); } to { transform: scaleX(1); } }
        @keyframes hdBlink { 0%,100% { opacity: 1; } 50% { opacity: 0; } }
        @keyframes hdLaptopOpen {
          0%   { transform: rotateX(-95deg) translateY(40px); opacity: 0; filter: brightness(0.3); }
          35%  { opacity: 1; }
          70%  { transform: rotateX(8deg) translateY(0); filter: brightness(0.95); }
          100% { transform: rotateX(0) translateY(0); filter: brightness(1); }
        }
        @keyframes hdIPadIn {
          0%   { transform: translateY(60px) rotateX(35deg) scale(0.86); opacity: 0; }
          60%  { opacity: 1; }
          100% { transform: translateY(0) rotateX(0) scale(1); opacity: 1; }
        }
        @keyframes hdPhoneIn {
          0%   { transform: translateY(80px) rotateZ(-4deg) scale(0.9); opacity: 0; }
          50%  { opacity: 1; }
          100% { transform: translateY(0) rotateZ(0) scale(1); opacity: 1; }
        }
      `}</style>
    </div>
  );
};

Object.assign(window, { HeroDevices, HDIPhone, HDIPad, HDLaptop });
