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
// iPhone — RECORDING surface that captures the open house and lets
// the AI identify each voice without the agent doing anything. The
// only "typing" you'll see is the AI revealing the names it just
// pulled out of the diarization stream.
const HDIPhone = () => {
  // Elapsed recording counter that ticks every second.
  const tickSec = useCount(0, 1000, 0);
  const totalSec = 14 * 60 + 22 + tickSec;
  const mm = String(Math.floor(totalSec / 60)).padStart(2, '0');
  const ss = String(totalSec % 60).padStart(2, '0');

  // Speaker detection timeline — each speaker first appears as
  // "Speaker N", then is replaced by their real name after another
  // beat. Drives the "AI identified" animation.
  const speakerStages = useStaggered([900, 1700, 2500, 3500, 4500, 5500]);
  const speakers = [
    { id: 'A', detectedAt: 1, namedAt: 2, name: 'Sarah Chen',     kind: 'buyer'   },
    { id: 'B', detectedAt: 3, namedAt: 4, name: 'Mike Rodriguez', kind: 'seller'  },
    { id: 'C', detectedAt: 5, namedAt: 6, name: 'Jennifer Park',  kind: 'browser' },
  ];
  // Cloud upload pulse — flashes a "Saved" indicator every few seconds
  // to communicate that nothing's stored locally only.
  const savedPulse = useStaggered([2200, 4400, 6600]);

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
          <span className="mono">2:14</span>
          <span className="mono">●●●●●</span>
        </div>

        {/* Recording header — pulsing red dot + counter */}
        <div style={{
          marginTop: 14, display: 'flex', alignItems: 'center', gap: 8,
          padding: '8px 10px', borderRadius: 10,
          background: 'rgba(202, 80, 71, 0.10)',
          border: '1px solid rgba(202, 80, 71, 0.30)',
        }}>
          <span style={{
            width: 8, height: 8, borderRadius: '50%',
            background: 'var(--terracotta)',
            boxShadow: '0 0 8px var(--terracotta)',
            animation: 'hdPulse 1.4s ease-in-out infinite',
          }} />
          <span className="mono" style={{ fontSize: 10, color: 'var(--terracotta)', letterSpacing: '0.18em', fontWeight: 600 }}>
            RECORDING
          </span>
          <span style={{ flex: 1 }} />
          <span className="mono" style={{ fontSize: 12, color: 'var(--cream)', letterSpacing: '0.06em' }}>
            {mm}:{ss}
          </span>
        </div>

        {/* Listing title */}
        <div style={{ marginTop: 12 }}>
          <div className="mono" style={{ fontSize: 8.5, color: 'var(--text-dim)', letterSpacing: '0.14em' }}>HOSTING</div>
          <div className="serif" style={{ fontSize: 20, color: 'var(--cream)', marginTop: 2, letterSpacing: '-0.01em' }}>
            412 W 78th St
          </div>
        </div>

        {/* Live waveform — auto-animates, no human input */}
        <div style={{ marginTop: 12, padding: '12px 0', borderTop: '1px solid var(--hairline)', borderBottom: '1px solid var(--hairline)' }}>
          <div style={{ display: 'flex', gap: 2.5, alignItems: 'center', height: 28 }}>
            {Array.from({ length: 32 }).map((_, i) => (
              <div key={i} style={{
                width: 3, flex: 1,
                background: 'var(--gold)',
                opacity: 0.45 + (i % 3) * 0.18,
                animation: `hbar${i % 4} 0.9s ease-in-out ${i * 45}ms infinite alternate`,
                transformOrigin: 'center',
              }} />
            ))}
          </div>
        </div>

        {/* AI-identified speakers — appears row-by-row as the AI tags them */}
        <div style={{ marginTop: 14, flex: 1 }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 5 }}>
            <svg width="9" height="9" viewBox="0 0 24 24" fill="var(--gold)" stroke="none"><path d="M12 2v6m0 8v6M2 12h6m8 0h6M5.6 5.6l3.5 3.5M14.9 14.9l3.5 3.5M5.6 18.4l3.5-3.5M14.9 9.1l3.5-3.5"/></svg>
            <span className="mono" style={{ fontSize: 8.5, color: 'var(--gold)', letterSpacing: '0.14em' }}>
              AI IDENTIFIED · {Math.min(speakerStages, speakers.length * 2)}
            </span>
          </div>
          <div style={{ marginTop: 8, display: 'flex', flexDirection: 'column', gap: 6 }}>
            {speakers.map((sp, i) => {
              const detected = speakerStages >= sp.detectedAt;
              const named    = speakerStages >= sp.namedAt;
              if (!detected) return null;
              return (
                <div key={sp.id} style={{
                  padding: '8px 10px', borderRadius: 8,
                  background: 'rgba(255,255,255,0.04)',
                  border: '1px solid var(--hairline)',
                  display: 'flex', alignItems: 'center', gap: 9,
                  animation: 'hdSlideIn .45s cubic-bezier(.22,1,.36,1) both',
                }}>
                  <div style={{
                    width: 24, height: 24, borderRadius: '50%',
                    background: named ? 'var(--gold-soft)' : 'rgba(255,255,255,0.08)',
                    color: named ? 'var(--gold)' : 'var(--text-muted)',
                    display: 'grid', placeItems: 'center',
                    fontFamily: 'var(--sans)', fontSize: 10, fontWeight: 600,
                    transition: 'background .35s ease, color .35s ease',
                  }}>
                    {named ? sp.name.charAt(0) : sp.id}
                  </div>
                  <div style={{ flex: 1, minWidth: 0 }}>
                    <div style={{ fontSize: 11.5, color: 'var(--cream)' }}>
                      {named ? sp.name : `Speaker ${sp.id}`}
                    </div>
                    <div className="mono" style={{ fontSize: 8.5, color: 'var(--text-muted)', marginTop: 1, letterSpacing: '0.08em' }}>
                      {named ? 'IDENTIFIED' : 'DETECTING…'}
                    </div>
                  </div>
                  {named && (
                    <span className={`tag tag-${sp.kind}`} style={{ fontSize: 7.5, padding: '2px 6px 3px' }}>
                      <span className="tag-dot" style={{ width: 4, height: 4 }} />{sp.kind}
                    </span>
                  )}
                </div>
              );
            })}
          </div>
        </div>

        {/* Auto-save indicator + Stop & save button (cosmetic) */}
        <div style={{ marginTop: 10, display: 'flex', alignItems: 'center', gap: 8 }}>
          <div style={{
            display: 'inline-flex', alignItems: 'center', gap: 5,
            padding: '5px 9px', borderRadius: 999,
            background: 'rgba(134,166,128,0.12)',
            color: 'var(--sage)',
            fontSize: 9, fontWeight: 600,
            opacity: 0.5 + (savedPulse % 2 === 0 ? 0 : 0.5),
            transition: 'opacity .4s ease',
          }}>
            <svg width="9" height="9" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5"><polyline points="20 6 9 17 4 12"/></svg>
            <span className="mono" style={{ letterSpacing: '0.1em' }}>SAVED · {savedPulse}m AGO</span>
          </div>
          <span style={{ flex: 1 }} />
        </div>

        {/* Tab bar — same as actual app */}
        <div style={{
          marginTop: 8,
          background: 'rgba(20,20,22,0.96)',
          border: '1px solid var(--hairline)',
          borderRadius: 18,
          padding: '6px 4px',
          display: 'grid', gridTemplateColumns: 'repeat(5, 1fr)',
          boxShadow: '0 8px 16px rgba(0,0,0,0.4)',
        }}>
          {[
            { i: 'home',  l: 'Home' },
            { i: 'rec',   l: 'Record', active: true },
            { i: 'kiosk', l: 'Kiosk' },
            { i: 'leads', l: 'Leads' },
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
                {t.i === 'leads' && <><path d="M4 7h16M4 12h16M4 17h10"/><circle cx="19" cy="17" r="2.5" fill="none"/></>}
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

// iPad LANDSCAPE — KIOSK in fullscreen guest mode. Side rail is hidden
// (locked kiosk), big listing photo on the left, sign-in form on the
// right that auto-fills itself in a loop so visitors see what the
// device does without anyone touching it.
const HDIPad = () => {
  // Total guests counter that ticks up as the cycle loops.
  const tickSec = useCount(0, 1000, 0);
  const guestsIn = 4 + Math.floor(tickSec / 6);

  // Cycling guest auto-fill. Stage indicates how far the form has
  // animated:
  //   0  empty
  //   1  name typed
  //   2  email typed
  //   3  phone typed
  //   4  agent answered + terms checked
  //   5  Welcome overlay
  // Loops back to 0 with the next guest.
  const guestRotation = [
    { name: 'Sarah Chen',     email: 'sarah.chen@example.com',  phone: '(212) 555-0101', hasAgent: 'no'  },
    { name: 'Mike Rodriguez', email: 'mike.r@example.com',      phone: '(212) 555-0142', hasAgent: 'no'  },
    { name: 'Jennifer Park',  email: 'jpark.nyc@example.com',   phone: '(212) 555-0173', hasAgent: 'yes' },
  ];
  const cycleStep = useCount(0, 700, 0);
  const stepInCycle = cycleStep % 7;           // 0..6
  const guestIdx = Math.floor(cycleStep / 7) % guestRotation.length;
  const guest = guestRotation[guestIdx];

  // Typed field strings advance one char per ~25ms while their stage
  // is active. Once the stage advances, the next field starts.
  const nameTyped  = stepInCycle >= 1 ? guest.name  : '';
  const emailTyped = stepInCycle >= 2 ? guest.email : '';
  const phoneTyped = stepInCycle >= 3 ? guest.phone : '';
  const agentSet   = stepInCycle >= 4;
  const termsOK    = stepInCycle >= 4;
  const showSuccess = stepInCycle >= 5;

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
        display: 'grid', gridTemplateColumns: '1.1fr 0.9fr',
        position: 'relative',
      }}>
        {/* LISTING PHOTO PANE — mirrors the locked kiosk's full-bleed
            listing splash. Gold "OPEN HOUSE" badge, address huge in
            serif, price + specs at the bottom. */}
        <div style={{
          position: 'relative', overflow: 'hidden',
          background:
            'linear-gradient(180deg, rgba(0,0,0,0) 30%, rgba(0,0,0,0.55) 70%, rgba(0,0,0,0.94) 100%),' +
            'linear-gradient(115deg, #2c3340 0%, #1a1f29 40%, #0e1218 100%)',
        }}>
          <div style={{
            position: 'absolute', inset: 0,
            backgroundImage:
              'repeating-linear-gradient(45deg, rgba(196,162,82,0.04) 0 14px, transparent 14px 28px)',
            opacity: 0.7,
          }} />
          <div style={{
            position: 'absolute', top: 60, right: 40, width: 240, height: 150,
            opacity: 0.20,
            background:
              'linear-gradient(180deg, transparent 30%, rgba(196,162,82,0.45) 100%)',
            clipPath: 'polygon(8% 100%, 8% 50%, 50% 12%, 92% 50%, 92% 100%)',
          }} />
          {/* OPEN HOUSE badge */}
          <div style={{
            position: 'absolute', top: 24, left: 24,
            display: 'inline-flex', alignItems: 'center', gap: 7,
            fontSize: 10, letterSpacing: '0.18em', fontFamily: 'var(--mono)',
            color: 'var(--gold)', textTransform: 'uppercase',
          }}>
            <span style={{ width: 6, height: 6, borderRadius: '50%', background: 'var(--gold)', boxShadow: '0 0 8px var(--gold)' }} />
            OPEN HOUSE
          </div>
          {/* Address + price */}
          <div style={{ position: 'absolute', left: 0, right: 0, bottom: 0, padding: 28 }}>
            <div className="serif" style={{ fontSize: 44, color: '#fff', lineHeight: 1, letterSpacing: '-0.025em' }}>
              412 W 78th St
            </div>
            <div style={{ marginTop: 14, fontSize: 13, color: 'rgba(255,255,255,0.7)' }}>
              Upper West Side
            </div>
            <div style={{ marginTop: 22, display: 'flex', alignItems: 'flex-end', justifyContent: 'space-between' }}>
              <span className="serif" style={{ fontSize: 28, color: 'var(--gold)', fontWeight: 500 }}>$1.29M</span>
              <span className="mono" style={{ fontSize: 10, color: 'rgba(255,255,255,0.55)', letterSpacing: '0.1em' }}>
                3BD · 2.5BA · 1,840 SF
              </span>
            </div>
          </div>
          {/* Live "guests signed in" pill — counts up so visitors see
              automation in motion */}
          <div style={{
            position: 'absolute', top: 24, right: 24,
            display: 'inline-flex', alignItems: 'center', gap: 6,
            fontSize: 10, letterSpacing: '0.12em', fontFamily: 'var(--mono)',
            color: 'var(--sage)', fontWeight: 600,
            padding: '5px 10px', borderRadius: 999,
            background: 'rgba(134, 166, 128, 0.14)',
            border: '1px solid rgba(134, 166, 128, 0.4)',
          }}>
            <span style={{
              width: 6, height: 6, borderRadius: '50%', background: 'var(--sage)',
              animation: 'hdPulse 1.6s ease-in-out infinite',
            }} />
            {guestsIn} SIGNED IN
          </div>
        </div>

        {/* SIGN-IN FORM PANE — animated auto-fill, no human typing */}
        <div style={{
          background: '#000', padding: '32px 28px',
          display: 'flex', flexDirection: 'column',
          position: 'relative',
        }}>
          <div style={{ marginBottom: 18 }}>
            <div className="serif" style={{ fontSize: 22, color: 'var(--cream)', lineHeight: 1, letterSpacing: '-0.02em' }}>
              Welcome in
            </div>
            <div style={{ fontSize: 11, color: 'var(--text-dim)', marginTop: 4 }}>
              Quick sign-in so we can follow up.
            </div>
          </div>

          {/* Form fields — each shows its typed value once its stage hits */}
          <KioskField label="NAME"  value={nameTyped}  active={stepInCycle === 1} />
          <KioskField label="EMAIL" value={emailTyped} active={stepInCycle === 2} />
          <KioskField label="PHONE" value={phoneTyped} active={stepInCycle === 3} />

          {/* Agent + terms — toggle in when stage hits 4 */}
          <div style={{ marginTop: 6, opacity: agentSet ? 1 : 0.3, transition: 'opacity .35s ease' }}>
            <div className="mono" style={{ fontSize: 8.5, color: 'var(--text-dim)', letterSpacing: '0.14em' }}>
              WORKING WITH AN AGENT?
            </div>
            <div style={{ marginTop: 6, display: 'flex', gap: 6 }}>
              <span style={{
                padding: '5px 11px', borderRadius: 999, fontSize: 10, fontWeight: 500,
                background: agentSet && guest.hasAgent === 'no'  ? 'var(--gold-soft)' : 'rgba(255,255,255,0.04)',
                color:      agentSet && guest.hasAgent === 'no'  ? 'var(--gold)'      : 'var(--text-dim)',
                border: '1px solid ' + (agentSet && guest.hasAgent === 'no' ? 'var(--gold)' : 'var(--hairline)'),
                transition: 'all .35s ease',
              }}>Not yet</span>
              <span style={{
                padding: '5px 11px', borderRadius: 999, fontSize: 10, fontWeight: 500,
                background: agentSet && guest.hasAgent === 'yes' ? 'var(--gold-soft)' : 'rgba(255,255,255,0.04)',
                color:      agentSet && guest.hasAgent === 'yes' ? 'var(--gold)'      : 'var(--text-dim)',
                border: '1px solid ' + (agentSet && guest.hasAgent === 'yes' ? 'var(--gold)' : 'var(--hairline)'),
                transition: 'all .35s ease',
              }}>Yes</span>
            </div>
          </div>

          <div style={{ flex: 1 }} />

          {/* Submit button — pulses gold when the form is "complete" */}
          <button style={{
            marginTop: 14,
            padding: '12px', border: 0,
            background: termsOK ? 'var(--gold)' : 'rgba(196, 162, 82, 0.35)',
            color: 'var(--ink-on-gold)',
            borderRadius: 12, fontFamily: 'var(--sans)', fontSize: 13, fontWeight: 600,
            boxShadow: termsOK ? '0 0 0 4px rgba(196,162,82,0.18)' : 'none',
            transition: 'all .35s ease',
          }}>
            Sign in
          </button>

          {/* Success overlay — fully covers the form when stage hits 5 */}
          {showSuccess && (
            <div style={{
              position: 'absolute', inset: 0, background: '#000',
              display: 'flex', flexDirection: 'column',
              alignItems: 'center', justifyContent: 'center',
              animation: 'hdFadeIn .4s ease both',
              padding: 28,
            }}>
              <div style={{
                width: 64, height: 64, borderRadius: '50%',
                background: 'var(--gold-soft)', color: 'var(--gold)',
                display: 'grid', placeItems: 'center',
                boxShadow: '0 0 0 6px rgba(196,162,82,0.16)',
                animation: 'hdPop .5s cubic-bezier(.22,1.4,.36,1) both',
              }}>
                <svg width="30" height="30" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="3"><polyline points="20 6 9 17 4 12"/></svg>
              </div>
              <div className="serif" style={{ marginTop: 18, fontSize: 22, color: 'var(--cream)', textAlign: 'center', letterSpacing: '-0.02em' }}>
                Welcome, {guest.name.split(' ')[0]}
              </div>
              <div style={{ marginTop: 6, fontSize: 11, color: 'var(--text-dim)', textAlign: 'center' }}>
                Saved · ready to listen
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  );
};

// One labeled field in the kiosk form. Renders the value as it types in,
// with a blinking caret while the parent says this row is "active".
function KioskField({ label, value, active }) {
  return (
    <div style={{ marginBottom: 12 }}>
      <div className="mono" style={{ fontSize: 8.5, color: 'var(--text-dim)', letterSpacing: '0.14em' }}>
        {label}
      </div>
      <div style={{
        marginTop: 5, padding: '9px 12px',
        background: 'rgba(255,255,255,0.04)',
        border: '1px solid ' + (active ? 'var(--gold)' : 'var(--hairline)'),
        borderRadius: 8,
        fontSize: 12, color: value ? 'var(--cream)' : 'var(--text-muted)',
        fontFamily: 'var(--sans)', minHeight: 16,
        transition: 'border-color .35s ease',
      }}>
        {value || <span style={{ color: 'var(--text-muted)' }}>…</span>}
        {active && value && (
          <span style={{
            display: 'inline-block', width: 1.5, height: 12, marginLeft: 2,
            background: 'var(--gold)', verticalAlign: '-1px',
            animation: 'hdBlink 0.9s steps(2) infinite',
          }} />
        )}
      </div>
    </div>
  );
}

// Laptop — web Leads inbox with the AI doing the work. Cycles through
// leads, drafts the email letter-by-letter (no human typing), then
// flips a "SCHEDULED" badge on and bumps the "sent this week" counter
// — communicating that the laptop is the automation cockpit, not a
// place where the agent writes anything.
const HDLaptop = () => {
  // Auto-cycling current lead. Each cycle = ~6s.
  const cycleStep = useCount(0, 1100, 0);
  const sel = Math.floor(cycleStep / 7) % 3;
  const stepInLead = cycleStep % 7;
  // Step gates:
  //   0  loading "Drafting personalized follow-up…"
  //   1+ typing the draft
  //   5  AI DRAFTED badge + Schedule button auto-clicks
  //   6  SCHEDULED toast appears
  const drafting = stepInLead === 0;
  const aiBadge  = stepInLead >= 5;
  const scheduled = stepInLead >= 6;

  // Cumulative "scheduled this week" counter — bumps once per cycle.
  const cyclesDone = Math.floor(cycleStep / 7);
  const scheduledCount = 8 + cyclesDone;

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
  const [bodyTyped] = useTyped(
    drafting ? '' : (
      g.k === 'buyer'
        ? "Sarah — great meeting you today. I'd love to share three comps from the block plus a private-showing slot for Saturday morning. Want me to send them over?"
        : g.k === 'seller'
        ? "Mike — great meeting you today. I'd love to put together a complimentary CMA for your place — no obligations, just real numbers from this quarter."
        : "Jennifer — great meeting you today. Totally understand you're early. I'll send a quiet listing update once a week — unsubscribe with one tap."
    ),
    800, 22
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
                  <span className="mono" style={{
                    padding: '3px 8px', borderRadius: 999,
                    background: 'var(--gold-soft)', color: 'var(--gold)',
                    fontSize: 8.5, letterSpacing: '0.1em', fontWeight: 600,
                  }}>
                    {scheduledCount}/14 SCHEDULED
                  </span>
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
                {guests.map((gg, i) => {
                  const isActive = sel === i;
                  const isDone = i < sel;          // looped past — "sent"
                  return (
                    <div key={gg.n} style={{
                      display: 'block',
                      padding: '10px 10px', margin: '0 0 4px',
                      background: isActive ? 'rgba(255,255,255,0.06)' : 'transparent',
                      borderRadius: 8,
                      width: '100%', boxSizing: 'border-box',
                      opacity: i < shownGuests ? 1 : 0,
                      transform: i < shownGuests ? 'translateX(0)' : 'translateX(-6px)',
                      transition: 'opacity .45s ease, transform .45s ease, background .35s',
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
                          <div style={{ fontSize: 8.5, color: isDone ? 'var(--sage)' : 'var(--text-dim)', marginTop: 1 }}>
                            {isDone ? '✓ Scheduled' : gg.sub}
                          </div>
                        </div>
                        <span className="mono" style={{ fontSize: 8.5, color: 'var(--gold)', letterSpacing: '0.04em' }}>
                          {gg.score}
                        </span>
                      </div>
                    </div>
                  );
                })}
              </div>

              {/* Detail */}
              <div style={{
                padding: '18px 22px', minHeight: 0, overflow: 'hidden',
                position: 'relative',
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

                {/* Drafted follow-up — drafted by AI, no human typing */}
                <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
                  <span className="mono" style={{ fontSize: 8.5, color: 'var(--gold)', letterSpacing: '0.1em' }}>
                    DRAFTED FOLLOW-UP
                  </span>
                  {aiBadge && (
                    <span style={{
                      display: 'inline-flex', alignItems: 'center', gap: 4,
                      padding: '2px 7px', borderRadius: 999,
                      background: 'var(--gold-soft)', color: 'var(--gold)',
                      fontSize: 8, letterSpacing: '0.1em', fontWeight: 600,
                      animation: 'hdSlideIn .35s ease both',
                    }}>
                      <svg width="7" height="7" viewBox="0 0 24 24" fill="currentColor"><path d="M12 2v6m0 8v6M2 12h6m8 0h6M5.6 5.6l3.5 3.5M14.9 14.9l3.5 3.5M5.6 18.4l3.5-3.5M14.9 9.1l3.5-3.5"/></svg>
                      AI DRAFTED
                    </span>
                  )}
                </div>
                <div style={{
                  marginTop: 5, padding: 10, background: 'rgba(0,0,0,0.3)',
                  border: '1px solid var(--hairline)', borderRadius: 6,
                  fontSize: 10.5, lineHeight: 1.55, color: 'var(--cream-dim)',
                  minHeight: 56,
                }}>
                  {drafting ? (
                    <div style={{
                      display: 'inline-flex', alignItems: 'center', gap: 7,
                      color: 'var(--text-dim)',
                    }}>
                      <span style={{
                        display: 'inline-block', width: 8, height: 8, borderRadius: '50%',
                        background: 'var(--gold)',
                        animation: 'hdPulse 1s ease-in-out infinite',
                      }} />
                      Drafting personalized follow-up…
                    </div>
                  ) : (
                    <>
                      {bodyTyped}<span style={{
                        display: 'inline-block', width: 5, height: 11, marginLeft: 1,
                        background: 'var(--gold)', verticalAlign: '-1px',
                        animation: 'hdBlink 0.9s steps(2) infinite',
                      }} />
                    </>
                  )}
                </div>

                {/* Auto-schedule bar — flips green + ticked when scheduled */}
                <div style={{
                  marginTop: 8, padding: '7px 10px',
                  background: scheduled ? 'rgba(134,166,128,0.14)' : 'var(--gold-soft)',
                  border: '1px solid ' + (scheduled ? 'rgba(134,166,128,0.45)' : 'rgba(196,162,82,0.4)'),
                  borderRadius: 6,
                  display: 'flex', alignItems: 'center', gap: 6,
                  transition: 'background .35s ease, border-color .35s ease',
                }}>
                  {scheduled ? (
                    <>
                      <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="var(--sage)" strokeWidth="3"><polyline points="20 6 9 17 4 12"/></svg>
                      <span className="mono" style={{ fontSize: 8.5, color: 'var(--sage)', letterSpacing: '0.1em', fontWeight: 600 }}>
                        SCHEDULED · TMRW 9:14 AM
                      </span>
                    </>
                  ) : (
                    <>
                      <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="var(--gold)" strokeWidth="2"><circle cx="12" cy="12" r="9"/><polyline points="12 7 12 12 16 14"/></svg>
                      <span className="mono" style={{ fontSize: 8.5, color: 'var(--gold)', letterSpacing: '0.1em' }}>
                        AUTO-SCHEDULING…
                      </span>
                    </>
                  )}
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
    { id: 'phone',  label: 'iPhone',  caption: 'Records the room. Identifies each voice.' },
    { id: 'ipad',   label: 'iPad',    caption: 'Hand to a guest. Sign-in flows itself.' },
    { id: 'laptop', label: 'Laptop',  caption: 'AI drafts and schedules every follow-up.' },
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
        @keyframes hdPulse { 0%,100% { transform: scale(1); opacity: 1; } 50% { transform: scale(1.4); opacity: 0.55; } }
        @keyframes hdSlideIn { from { opacity: 0; transform: translateY(6px); } to { opacity: 1; transform: translateY(0); } }
        @keyframes hdFadeIn { from { opacity: 0; } to { opacity: 1; } }
        @keyframes hdPop { 0% { transform: scale(0.6); opacity: 0; } 70% { transform: scale(1.08); opacity: 1; } 100% { transform: scale(1); opacity: 1; } }
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
