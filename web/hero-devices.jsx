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
const HDIPhone = () => {
  const [rec, setRec] = useHD(true);
  const [sel, setSel] = useHD(0);
  const guests = [
    { n: 'Sarah Chen',     t: '2:05', k: 'buyer',   m: 'Pre-approved · close 60d' },
    { n: 'Mike Rodriguez', t: '2:22', k: 'seller',  m: 'Wants comp analysis' },
    { n: 'Jennifer Park',  t: '2:35', k: 'browser', m: 'Lease runs to 2027' },
  ];
  const shown = useStaggered([700, 1700, 2700]);
  const tickSec = useCount(0, 1000, 0);
  const totalSec = 14 * 60 + 22 + tickSec;
  const mm = String(Math.floor(totalSec / 60)).padStart(2, '0');
  const ss = String(totalSec % 60).padStart(2, '0');

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
        background: 'var(--bg-card)', padding: '54px 22px 26px',
        position: 'relative', display: 'flex', flexDirection: 'column',
      }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: 11, color: 'var(--text-dim)', marginTop: -8 }}>
          <span className="mono">2:14</span>
          <span className="mono">●●●●●</span>
        </div>
        <div className="eyebrow" style={{ marginTop: 18, color: rec ? 'var(--gold)' : 'var(--text-muted)' }}>
          {rec ? `● LIVE · ${mm}:${ss}` : '○ PAUSED'}
        </div>
        <div className="serif" style={{ fontSize: 26, lineHeight: 1.05, marginTop: 8, color: 'var(--cream)' }}>
          412 W 78th St<br/>
          <span className="serif-it" style={{ color: 'var(--gold)' }}>Open house</span>
        </div>
        <div style={{ marginTop: 18, padding: '14px 0', borderTop: '1px solid var(--hairline)', borderBottom: '1px solid var(--hairline)' }}>
          <div className="eyebrow" style={{ fontSize: 9 }}>{rec ? 'NOW RECORDING' : 'TAP TO RESUME'}</div>
          <div style={{ display: 'flex', gap: 2.5, alignItems: 'center', height: 32, marginTop: 10 }}>
            {Array.from({ length: 30 }).map((_, i) => (
              <div key={i} style={{
                width: 3, height: 4 + Math.abs(Math.sin(i * 0.7)) * 26, background: 'var(--gold)',
                opacity: rec ? (0.35 + (i % 3) * 0.22) : 0.15,
                animation: rec ? `hbar${i % 4} 0.9s ease-in-out ${i * 50}ms infinite alternate` : 'none',
                transition: 'opacity .4s',
              }}></div>
            ))}
          </div>
        </div>
        <div className="eyebrow" style={{ fontSize: 9, marginTop: 16 }}>GUESTS · {shown}</div>
        <div style={{ marginTop: 10, display: 'flex', flexDirection: 'column', gap: 0, flex: 1 }}>
          {guests.map((g, i) => (
            <button key={g.n} onClick={() => setSel(i)} style={{
              all: 'unset', cursor: 'pointer',
              display: 'flex', alignItems: 'center', justifyContent: 'space-between',
              padding: '10px 6px', borderBottom: '1px solid var(--hairline)',
              background: sel === i ? 'var(--gold-soft)' : 'transparent',
              margin: '0 -6px',
              opacity: i < shown ? 1 : 0,
              transform: i < shown ? 'translateY(0)' : 'translateY(8px)',
              transition: 'opacity .5s ease, transform .5s ease, background .2s',
            }}>
              <div>
                <div style={{ fontSize: 13, color: 'var(--cream)' }}>{g.n}</div>
                <div className="mono" style={{ fontSize: 9, color: 'var(--text-muted)', marginTop: 2, letterSpacing: '0.08em' }}>
                  SIGNED · {g.t}
                </div>
              </div>
              <span className={`tag tag-${g.k}`} style={{ fontSize: 8, padding: '2px 7px 3px' }}>
                <span className="tag-dot" style={{ width: 4, height: 4 }} />{g.k}
              </span>
            </button>
          ))}
        </div>
        <button onClick={() => setRec(r => !r)} style={{
          all: 'unset', cursor: 'pointer', marginTop: 16,
          height: 48, borderRadius: 24,
          background: rec ? 'var(--gold)' : 'transparent',
          border: '1px solid ' + (rec ? 'var(--gold)' : 'var(--border-strong)'),
          color: rec ? '#1a1610' : 'var(--cream)',
          display: 'grid', placeItems: 'center',
          fontFamily: 'var(--sans)', fontSize: 12, fontWeight: 500,
          letterSpacing: '0.16em', textTransform: 'uppercase',
        }}>{rec ? 'Stop & Save' : 'Resume Recording'}</button>
        <div style={{ position: 'absolute', bottom: 8, left: '50%', transform: 'translateX(-50%)', width: 110, height: 4, borderRadius: 100, background: 'rgba(255,255,255,0.3)' }} />
      </div>
    </div>
  );
};

// iPad LANDSCAPE — agent home (composition of IPadAgentHome)
const HDIPad = () => {
  const inSession = useStaggered([900, 1700, 2600]);
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
            { i: 'listings', label: 'Listings' },
            { i: 'sessions', label: 'Sessions' },
            { i: 'leads', label: 'Leads' },
            { i: 'templates', label: 'Templates' },
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
                  {it.i === 'listings' && <><rect x="2" y="3" width="12" height="10"/><path d="M2 7h12M6 3v10"/></>}
                  {it.i === 'sessions' && <><circle cx="8" cy="8" r="6"/><circle cx="8" cy="8" r="2"/></>}
                  {it.i === 'leads' && <><circle cx="8" cy="6" r="3"/><path d="M2 14c0-3 3-5 6-5s6 2 6 5"/></>}
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

        {/* MAIN */}
        <div style={{ padding: '22px 26px', overflow: 'hidden', display: 'flex', flexDirection: 'column' }}>
          {/* greeting + status */}
          <div style={{ display: 'flex', alignItems: 'flex-end', justifyContent: 'space-between' }}>
            <div>
              <div className="eyebrow" style={{ display: 'flex', alignItems: 'center', gap: 10, fontSize: 9 }}>
                <span style={{ display: 'inline-block', width: 16, height: 1, background: 'var(--gold)' }}></span>
                Saturday · May 10 · 2:14 PM
              </div>
              <h1 className="serif" style={{ fontSize: 30, lineHeight: 1, margin: '8px 0 0', fontWeight: 500 }}>
                Good afternoon, <span className="serif-it" style={{ color: 'var(--gold)' }}>John.</span>
              </h1>
            </div>
            <div className="mono" style={{
              fontSize: 9, letterSpacing: '0.14em', color: 'var(--sage)',
              padding: '6px 10px', border: '1px solid var(--sage)', borderRadius: 999,
              background: 'var(--sage-soft)',
              display: 'inline-flex', alignItems: 'center', gap: 6,
            }}>
              <span style={{ width: 5, height: 5, borderRadius: '50%', background: 'var(--sage)' }}></span>
              MLS · LIVE
            </div>
          </div>

          {/* hero row */}
          <div style={{ marginTop: 16, display: 'grid', gridTemplateColumns: '1.4fr 1fr', gap: 12 }}>
            <div style={{
              position: 'relative', overflow: 'hidden',
              background:
                'linear-gradient(95deg, rgba(10,14,19,0.0) 35%, rgba(10,14,19,0.85) 90%),' +
                'repeating-linear-gradient(135deg, transparent 0 12px, rgba(201,168,106,0.05) 12px 13px),' +
                'linear-gradient(135deg, #2a2218 0%, #3a2e1f 50%, #1d1812 100%)',
              border: '1px solid var(--border-strong)', borderRadius: 12,
              padding: '20px 22px', minHeight: 140,
              display: 'flex', alignItems: 'flex-end', justifyContent: 'space-between',
            }}>
              <div style={{ maxWidth: 280 }}>
                <div className="eyebrow" style={{ display: 'flex', alignItems: 'center', gap: 8, fontSize: 9 }}>
                  <span style={{ width: 5, height: 5, borderRadius: '50%', background: 'var(--terracotta)' }}></span>
                  Hosting now · 412 W 78th St
                </div>
                <h2 className="serif" style={{ fontSize: 26, lineHeight: 1, margin: '8px 0 0', fontWeight: 500 }}>
                  Launch the <span className="serif-it" style={{ color: 'var(--gold)' }}>sign-in form</span>
                </h2>
                <p style={{ fontSize: 11, color: 'var(--cream-dim)', marginTop: 6, lineHeight: 1.5 }}>
                  Today's listing pulls from MLS · photos rotate during sign-in.
                </p>
              </div>
              <button style={{
                padding: '12px 18px', background: 'var(--gold)', color: '#1a1610',
                border: 'none', borderRadius: 8,
                fontFamily: 'var(--sans)', fontSize: 11, fontWeight: 500, letterSpacing: '0.04em',
                textTransform: 'uppercase', display: 'inline-flex', alignItems: 'center', gap: 8,
              }}>
                Launch
                <span className="serif-it" style={{ fontSize: 14, textTransform: 'none' }}>→</span>
              </button>
            </div>
            <div style={{
              border: '1px solid var(--hairline)', borderRadius: 12,
              background: 'var(--bg-card)', padding: '18px 20px', minHeight: 140,
              display: 'flex', flexDirection: 'column', justifyContent: 'space-between',
            }}>
              <div>
                <div className="eyebrow" style={{ color: 'var(--terracotta)', fontSize: 9 }}>Quick capture</div>
                <h3 className="serif" style={{ fontSize: 22, lineHeight: 1, margin: '8px 0 0', fontWeight: 500 }}>
                  Start <span className="serif-it" style={{ color: 'var(--terracotta)' }}>recording</span>
                </h3>
                <p style={{ fontSize: 10.5, color: 'var(--text-dim)', marginTop: 6, lineHeight: 1.5 }}>
                  No sign-in — just listen.
                </p>
              </div>
              <button style={{
                display: 'flex', alignItems: 'center', gap: 10, padding: '10px 12px',
                background: 'transparent', border: '1px solid var(--terracotta)',
                color: 'var(--terracotta)', borderRadius: 8,
                fontFamily: 'var(--sans)', fontSize: 10.5,
                fontWeight: 500, letterSpacing: '0.04em', textTransform: 'uppercase',
              }}>
                <span style={{ width: 10, height: 10, borderRadius: '50%', background: 'var(--terracotta)', boxShadow: '0 0 0 3px rgba(196,102,61,0.18)' }}></span>
                Tap to record
              </button>
            </div>
          </div>

          {/* Today's open house listing card */}
          <div style={{ marginTop: 16 }}>
            <div style={{ display: 'flex', alignItems: 'flex-end', justifyContent: 'space-between', marginBottom: 8 }}>
              <div>
                <div className="eyebrow" style={{ fontSize: 9 }}>Your open house · pulled from MLS</div>
                <div className="serif" style={{ fontSize: 17, marginTop: 4 }}>
                  Hosting today <span className="serif-it" style={{ color: 'var(--text-dim)' }}>2–4 PM</span>
                </div>
              </div>
              <a className="serif-it" style={{ fontSize: 11, color: 'var(--gold)' }}>All listings →</a>
            </div>

            <div style={{
              background: 'var(--bg-card)', borderColor: 'var(--gold)',
              border: '1px solid var(--gold)', boxShadow: '0 0 0 1px var(--gold-soft)',
              borderRadius: 12, display: 'grid', gridTemplateColumns: '1.3fr 1fr',
              minHeight: 120, overflow: 'hidden',
            }}>
              <div style={{
                position: 'relative',
                background:
                  'linear-gradient(135deg, rgba(10,14,19,0.0) 50%, rgba(10,14,19,0.85) 100%),' +
                  'repeating-linear-gradient(135deg, transparent 0 10px, rgba(201,168,106,0.05) 10px 11px),' +
                  'linear-gradient(135deg, #3a2e1f 0%, #1d1812 100%)',
                padding: '12px 14px',
              }}>
                <span style={{
                  fontFamily: 'var(--mono)', fontSize: 8, letterSpacing: '0.18em',
                  color: 'var(--terracotta)',
                  padding: '3px 7px', background: 'rgba(10,14,19,0.7)', backdropFilter: 'blur(6px)',
                  border: '1px solid var(--terracotta)',
                  display: 'inline-flex', alignItems: 'center', gap: 5,
                }}>
                  <span style={{ width: 4, height: 4, borderRadius: '50%', background: 'var(--terracotta)' }}></span>
                  HOSTING
                </span>
                <div style={{
                  position: 'absolute', bottom: 10, left: 12, right: 12,
                  display: 'flex', justifyContent: 'space-between', alignItems: 'flex-end',
                }}>
                  <div style={{ display: 'flex', gap: 3 }}>
                    {[0,1,2,3].map(d => (
                      <span key={d} style={{ width: 12, height: 2, background: d === 0 ? 'var(--gold)' : 'rgba(235,229,214,0.25)' }}></span>
                    ))}
                  </div>
                  <span className="mono" style={{ fontSize: 7, letterSpacing: '0.16em', color: 'rgba(235,229,214,0.45)' }}>
                    MLS · 4072281
                  </span>
                </div>
              </div>
              <div style={{ padding: '12px 14px', display: 'flex', flexDirection: 'column', gap: 4 }}>
                <div className="serif" style={{ fontSize: 15, lineHeight: 1.1 }}>412 W 78th St</div>
                <div className="mono" style={{ fontSize: 8.5, color: 'var(--text-muted)', letterSpacing: '0.10em' }}>
                  UPPER WEST SIDE · 3 / 2.5 / 1,840
                </div>
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', marginTop: 4 }}>
                  <div className="serif" style={{ fontSize: 16, color: 'var(--gold)' }}>$1,295,000</div>
                  <div className="mono" style={{ fontSize: 8, color: 'var(--text-dim)', letterSpacing: '0.10em' }}>2–4 PM</div>
                </div>
                <div style={{
                  marginTop: 4, paddingTop: 6, borderTop: '1px solid var(--hairline)',
                  display: 'flex', alignItems: 'center', justifyContent: 'space-between',
                }}>
                  <span className="mono" style={{ fontSize: 8, color: 'var(--sage)', letterSpacing: '0.10em' }}>
                    {guestsIn} SIGNED IN
                  </span>
                  <a className="serif-it" style={{ fontSize: 11, color: 'var(--gold)' }}>Launch →</a>
                </div>
              </div>
            </div>
          </div>

          {/* recordings & leads — compact row */}
          <div style={{ marginTop: 14 }}>
            <div style={{ display: 'flex', alignItems: 'flex-end', justifyContent: 'space-between', marginBottom: 8 }}>
              <div>
                <div className="eyebrow" style={{ fontSize: 9 }}>Recordings & leads</div>
                <div className="serif" style={{ fontSize: 14, marginTop: 2 }}>
                  <span className="serif-it" style={{ color: 'var(--terracotta)' }}>8 follow-ups</span> ready
                </div>
              </div>
              <a className="serif-it" style={{ fontSize: 11, color: 'var(--gold)' }}>All sessions →</a>
            </div>
            <div style={{ border: '1px solid var(--hairline)', borderRadius: 10, background: 'var(--bg-card)' }}>
              {[
                { addr: '301 E 79th St',       when: 'YESTERDAY · 3:14 PM', dur: '54 min', leads: 8,  hot: 2, ready: 5, sent: 1 },
                { addr: '212 W End · #6F',     when: 'THU · 5:02 PM',       dur: '38 min', leads: 4,  hot: 1, ready: 3, sent: 0 },
                { addr: '88 Greenwich St',     when: 'WED · 1:22 PM',       dur: '1 h 12', leads: 11, hot: 4, ready: 0, sent: 11 },
              ].map((s, i) => (
                <div key={s.addr} style={{
                  display: 'grid', gridTemplateColumns: '1.4fr 0.6fr 0.5fr 1fr 1fr 0.4fr',
                  gap: 10, alignItems: 'center',
                  padding: '8px 14px', borderTop: i ? '1px solid var(--hairline)' : 'none',
                  opacity: i < inSession ? 1 : 0,
                  transform: i < inSession ? 'translateY(0)' : 'translateY(6px)',
                  transition: 'opacity .4s ease, transform .4s ease',
                }}>
                  <div>
                    <div className="serif" style={{ fontSize: 12 }}>{s.addr}</div>
                    <div className="mono" style={{ fontSize: 7.5, color: 'var(--text-muted)', letterSpacing: '0.10em', marginTop: 2 }}>
                      {s.when}
                    </div>
                  </div>
                  <div className="mono" style={{ fontSize: 9, color: 'var(--text-dim)', letterSpacing: '0.08em' }}>{s.dur}</div>
                  <div style={{ display: 'flex', alignItems: 'baseline', gap: 4 }}>
                    <span className="serif" style={{ fontSize: 16, color: 'var(--cream)' }}>{s.leads}</span>
                    <span className="mono" style={{ fontSize: 7, color: 'var(--text-muted)', letterSpacing: '0.10em' }}>LEADS</span>
                  </div>
                  <div style={{ display: 'flex', gap: 4, flexWrap: 'wrap' }}>
                    {s.hot > 0 && <span className="tag tag-buyer" style={{ fontSize: 7, padding: '1.5px 5px' }}><span className="tag-dot"></span>{s.hot} HOT</span>}
                    {s.ready > 0 && <span className="tag tag-seller" style={{ fontSize: 7, padding: '1.5px 5px' }}><span className="tag-dot"></span>{s.ready} READY</span>}
                  </div>
                  <div>
                    <div style={{ display: 'flex', height: 2, background: 'var(--hairline)', overflow: 'hidden' }}>
                      <span style={{ width: (s.sent / s.leads * 100) + '%', background: 'var(--sage)' }}></span>
                      <span style={{ width: (s.ready / s.leads * 100) + '%', background: 'var(--gold)' }}></span>
                      <span style={{ width: (s.hot / s.leads * 100) + '%', background: 'var(--terracotta)' }}></span>
                    </div>
                    <div className="mono" style={{ fontSize: 7, color: 'var(--text-muted)', letterSpacing: '0.10em', marginTop: 3 }}>
                      {s.sent}/{s.leads} SENT
                    </div>
                  </div>
                  <a className="serif-it" style={{ fontSize: 11, color: 'var(--gold)', textAlign: 'right' }}>Open →</a>
                </div>
              ))}
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};

// Laptop — dashboard
const HDLaptop = () => {
  const [sel, setSel] = useHD(0);
  const guests = [
    { n: 'Sarah Chen',     k: 'buyer',   sub: 'pre-approved $1.4M',
      sum: 'Actively searching the West Side. Sold her Queens place last year. Drawn by the kitchen. Pre-approved to $1.4M, ready to close in 60 days.',
      tags: ['Pre-approved $1.4M','Close 60d','3+ bedrooms'] },
    { n: 'Mike Rodriguez', k: 'seller',  sub: 'wants comp analysis',
      sum: 'Lives two blocks away. 15 years in his home. Kids off to college, considering downsizing in six months. Requested a complimentary comp.',
      tags: ['Owner 15 yrs','Downsizing 6mo','Wants comp'] },
    { n: 'Jennifer Park',  k: 'browser', sub: 'curious renter',
      sum: 'Local renter, lease through 2027. Loves the neighborhood but undecided. Open to low-pressure listing updates.',
      tags: ['Lease 2027','No urgency','Curious'] },
  ];
  const g = guests[sel];
  const shownGuests = useStaggered([400, 900, 1400]);
  const detailIn = useDelayed(0, 1, 1700);
  const [bodyTyped] = useTyped(
    g.k === 'buyer'
      ? 'It was great meeting you today at the open house. I love how prepared you and Tom are — pre-approved and ready in 60 days is exactly the position to be in for 412 W 78th. I’ve attached three comps from the block.'
      : g.k === 'seller'
      ? "It was great meeting you today. I'd love to put together a complimentary comparative market analysis for your place on Riverside — no obligations, just real numbers from this quarter."
      : 'It was great meeting you today. Totally understand you’re in the early stages — there’s no rush. I’ll send a quiet listing update once a week, and you can unsubscribe with one tap.',
    2600, 18
  );

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
          background: 'var(--bg)', border: '1px solid var(--hairline)',
          display: 'flex', flexDirection: 'column',
        }}>
          <div style={{
            padding: '10px 18px', display: 'flex', alignItems: 'center', gap: 14,
            borderBottom: '1px solid var(--hairline)', background: 'var(--bg-deep)',
          }}>
            <div style={{ display: 'flex', gap: 6 }}>
              {['#3a3328','#3a3328','#3a3328'].map((c, i) => (
                <span key={i} style={{ width: 10, height: 10, borderRadius: '50%', background: c }} />
              ))}
            </div>
            <Crest size={14} />
            <div style={{ flex: 1 }} />
            <span className="mono" style={{ fontSize: 10, letterSpacing: '0.16em', color: 'var(--text-muted)' }}>
              app.foyer.house / sessions / 412-w-78
            </span>
          </div>
          <div style={{ flex: 1, display: 'grid', gridTemplateColumns: '180px 1fr', minHeight: 0 }}>
            <div style={{ borderRight: '1px solid var(--hairline)', padding: '14px 12px', background: 'var(--bg-deep)' }}>
              <div className="eyebrow" style={{ fontSize: 9, marginBottom: 6 }}>SAT MAY 10</div>
              <div className="serif" style={{ fontSize: 15, color: 'var(--cream)', lineHeight: 1.1 }}>412 W 78th St</div>
              <div className="mono" style={{ fontSize: 8, color: 'var(--text-muted)', letterSpacing: '0.1em', marginTop: 3 }}>1H 47M · 3 GUESTS</div>
              <div style={{ height: 1, background: 'var(--hairline)', margin: '14px 0' }} />
              <div className="eyebrow" style={{ fontSize: 8, marginBottom: 6 }}>GUESTS</div>
              {guests.map((gg, i) => (
                <button key={gg.n} onClick={() => setSel(i)} style={{
                  all: 'unset', cursor: 'pointer', display: 'block',
                  padding: '8px 10px', margin: '0 -10px',
                  background: sel === i ? 'var(--gold-soft)' : 'transparent',
                  borderLeft: sel === i ? '2px solid var(--gold)' : '2px solid transparent',
                  width: 'calc(100% + 20px)', boxSizing: 'border-box',
                  opacity: i < shownGuests ? 1 : 0,
                  transform: i < shownGuests ? 'translateX(0)' : 'translateX(-8px)',
                  transition: 'opacity .45s ease, transform .45s ease, background .2s',
                }}>
                  <div style={{ fontSize: 11, color: 'var(--cream)' }}>{gg.n}</div>
                  <div className="mono" style={{ fontSize: 8, color: 'var(--text-muted)', marginTop: 2, letterSpacing: '0.06em' }}>{gg.sub}</div>
                </button>
              ))}
            </div>
            <div style={{
              padding: '18px 22px', minHeight: 0, overflow: 'hidden',
              opacity: detailIn,
              transform: detailIn ? 'translateY(0)' : 'translateY(8px)',
              transition: 'opacity .55s ease, transform .55s ease',
            }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start' }}>
                <div>
                  <div className="eyebrow" style={{ fontSize: 9 }}>GUEST</div>
                  <div className="serif" style={{ fontSize: 24, color: 'var(--cream)', marginTop: 4 }}>{g.n}</div>
                </div>
                <span className={`tag tag-${g.k}`} style={{ fontSize: 9, padding: '3px 9px 4px' }}>
                  <span className="tag-dot" style={{ width: 5, height: 5 }} />{g.k}
                </span>
              </div>
              <p style={{ fontSize: 12, color: 'var(--cream-dim)', lineHeight: 1.6, marginTop: 12 }}>{g.sum}</p>
              <div style={{ display: 'flex', gap: 5, marginTop: 10, flexWrap: 'wrap' }}>
                {g.tags.map(t => (
                  <span key={t} className="mono" style={{
                    fontSize: 9, letterSpacing: '0.05em',
                    padding: '3px 7px', border: '1px solid var(--hairline)', color: 'var(--text-dim)',
                  }}>{t}</span>
                ))}
              </div>
              <div style={{ height: 1, background: 'var(--hairline)', margin: '14px 0' }} />
              <div className="eyebrow" style={{ fontSize: 9 }}>DRAFTED · SENDS TMRW 9:14 AM</div>
              <div style={{ marginTop: 8, padding: 12, background: 'var(--bg-deep)', border: '1px solid var(--hairline)', fontSize: 11, lineHeight: 1.55, color: 'var(--cream-dim)' }}>
                <span className="serif-it" style={{ color: 'var(--gold)' }}>Hi {g.n.split(' ')[0]},</span><br/>
                {bodyTyped}<span style={{
                  display: 'inline-block', width: 6, height: 12, marginLeft: 2,
                  background: 'var(--gold)', verticalAlign: '-1px',
                  animation: 'hdBlink 0.9s steps(2) infinite',
                }} />
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
