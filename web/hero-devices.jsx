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
// VoiceWave — flowing sine-wave layers radiating from a glowing center
// orb. Replaces every old "vertical bar VU meter" instance across the
// app. Visually: black canvas, multiple gold sine paths at different
// amplitudes/phases drifting horizontally, a soft gold glow in the
// middle. No mic icon — the orb itself is the voice metaphor.
//
// Usage: <VoiceWave width={300} height={140} /> — sizes itself to its
// container. Pure CSS animation on each path so it doesn't burn CPU.
function VoiceWave({ width = 280, height = 140, orbSize = 64, animated = true }) {
  // Each layer: amplitude (vertical swing), period (px per cycle),
  // initial phase, stroke opacity, stroke width, scroll speed (s
  // per cycle — negative scrolls right-to-left). The first three
  // dominate the silhouette; the rest fill in the depth.
  const layers = [
    { amp: 22, period: 95,  phase: 0.0,  opacity: 0.85, sw: 1.6, dur: 7.0 },
    { amp: 14, period: 70,  phase: 1.1,  opacity: 0.65, sw: 1.4, dur: 5.5 },
    { amp: 28, period: 130, phase: 2.0,  opacity: 0.45, sw: 1.2, dur: 9.0 },
    { amp: 10, period: 55,  phase: 2.8,  opacity: 0.55, sw: 1.0, dur: 4.5 },
    { amp: 18, period: 105, phase: 0.6,  opacity: 0.35, sw: 1.0, dur: 8.0 },
    { amp:  8, period: 42,  phase: 1.7,  opacity: 0.30, sw: 0.8, dur: 3.8 },
  ];

  // The wave SVG is rendered 2× wider than the visible area; we shift
  // each path horizontally to animate flow. That way the wave never
  // shows a seam where the path ends.
  const svgWidth = width * 2;
  const cy = height / 2;

  function buildPath(layer) {
    let d = `M 0 ${cy}`;
    for (let x = 0; x <= svgWidth; x += 3) {
      const y = cy + Math.sin(x / layer.period + layer.phase) * layer.amp;
      d += ` L ${x.toFixed(1)} ${y.toFixed(2)}`;
    }
    return d;
  }

  return (
    <div style={{
      position: 'relative',
      width, height,
      overflow: 'hidden',
      // Soft radial glow behind the orb so the waves feel like they're
      // emanating from a light source.
      background: 'radial-gradient(ellipse 50% 80% at center, rgba(196,162,82,0.10), transparent 70%)',
    }}>
      {/* Waves — mask to fade out at the edges so the loop is invisible */}
      <svg
        width={svgWidth} height={height}
        viewBox={`0 0 ${svgWidth} ${height}`}
        style={{
          position: 'absolute',
          top: 0, left: -width / 2,
          WebkitMaskImage: `linear-gradient(to right, transparent 0%, black 10%, black 90%, transparent 100%)`,
          maskImage: `linear-gradient(to right, transparent 0%, black 10%, black 90%, transparent 100%)`,
        }}
        aria-hidden="true">
        {layers.map((l, i) => (
          <path
            key={i}
            d={buildPath(l)}
            stroke="var(--gold)"
            strokeWidth={l.sw}
            strokeLinecap="round"
            fill="none"
            opacity={l.opacity}
            style={{
              animation: animated ? `voiceWaveFlow${i % 2} ${l.dur}s linear infinite` : 'none',
            }}
          />
        ))}
      </svg>

      {/* Center orb — no mic icon, just a gold glow */}
      <div style={{
        position: 'absolute',
        left: '50%', top: '50%',
        width: orbSize, height: orbSize,
        marginLeft: -orbSize / 2, marginTop: -orbSize / 2,
        borderRadius: '50%',
        background:
          'radial-gradient(circle at 35% 30%, #fff5d6 0%, var(--gold) 35%, rgba(196,162,82,0.6) 70%, transparent 100%)',
        boxShadow:
          '0 0 30px rgba(196,162,82,0.8), 0 0 80px rgba(196,162,82,0.45), inset 0 0 14px rgba(255,250,220,0.4)',
        animation: animated ? 'voiceWavePulse 2.4s ease-in-out infinite' : 'none',
      }} />

      <style>{`
        @keyframes voiceWaveFlow0 {
          from { transform: translateX(0); }
          to   { transform: translateX(-50%); }
        }
        @keyframes voiceWaveFlow1 {
          from { transform: translateX(-50%); }
          to   { transform: translateX(0); }
        }
        @keyframes voiceWavePulse {
          0%, 100% { transform: scale(1); }
          50%      { transform: scale(1.06); }
        }
      `}</style>
    </div>
  );
}

// iPhone — captures the open house, then ends the session and shows
// the transcript transcribing with 5 identified speakers. Three
// phases: RECORDING (live waves + AI identifying speakers) →
// TRANSCRIBING (spinner + processing) → READY (transcript with 5
// leads, each their own colored speaker pill).
const HDIPhone = () => {
  // Master 60ms tick.
  const tickFast = useCount(0, 60, 0);

  // Phase plan:
  //   RECORDING  ticks  0..69   (~4.2s) — waves + 4 voices identified
  //   ENDING     ticks 70..78   (~0.5s) — "STOPPING…" banner
  //   TRANSCRIBE ticks 79..104  (~1.5s) — spinner overlay
  //   READY      ticks 105+    — transcript card with 5 speaker lines
  const T_REC      = 70;
  const T_ENDING   = 9;
  const T_TRANS    = 26;
  const t = tickFast;
  const recording   = t < T_REC;
  const ending      = t >= T_REC && t < T_REC + T_ENDING;
  const transcribing = t >= T_REC + T_ENDING && t < T_REC + T_ENDING + T_TRANS;
  const ready       = t >= T_REC + T_ENDING + T_TRANS;

  // Elapsed timer — counts up during recording, freezes after.
  const recSec = recording ? Math.min(60 * 14 + Math.floor(t * 0.06 * 5), 60 * 14 + 22) : (60 * 14 + 22);
  const totalSec = 14 * 60 + 22 + (recording ? Math.floor(t / 17) : 0);
  const mm = String(Math.floor(totalSec / 60)).padStart(2, '0');
  const ss = String(totalSec % 60).padStart(2, '0');

  // Speaker detection — paced across the recording phase so all 4
  // appear before STOPPING. After the session ends, transcript
  // unveils a 5th speaker (Speaker E who arrived late).
  const speakers = [
    { id: 'A', detectedAt:  8, namedAt: 14, name: 'Sarah Chen',     kind: 'buyer'   },
    { id: 'B', detectedAt: 22, namedAt: 28, name: 'Mike Rodriguez', kind: 'seller'  },
    { id: 'C', detectedAt: 38, namedAt: 44, name: 'Jennifer Park',  kind: 'browser' },
    { id: 'D', detectedAt: 54, namedAt: 60, name: 'David Lee',      kind: 'buyer'   },
  ];
  const liveSpeakersIdentified = speakers.filter(s => t >= s.namedAt).length;

  // Transcript lines, revealed one at a time during READY. 5
  // speakers — the 4 above plus a "late arrival" Elena.
  const transcriptLines = [
    { speaker: 'Sarah',    kind: 'buyer',   line: "Pre-approved to $1.4M. We can close in 60 days." },
    { speaker: 'Mike',     kind: 'seller',  line: "I've been here 15 years — kids are off to college now." },
    { speaker: 'Jennifer', kind: 'browser', line: "Just curious — my lease runs through 2027." },
    { speaker: 'David',    kind: 'buyer',   line: "We love the kitchen. Could we see the basement?" },
    { speaker: 'Elena',    kind: 'browser', line: "What's the HOA like?" },
  ];
  // After the READY phase starts, each line appears 9 ticks (~540ms)
  // after the previous one.
  const readyTicks = ready ? t - (T_REC + T_ENDING + T_TRANS) : -1;
  const linesShown = readyTicks < 0 ? 0 : Math.min(5, Math.floor(readyTicks / 8) + 1);

  // Cloud "Saved" pulse — runs during recording.
  const savedPulse = recording ? Math.floor(t / 28) : Math.floor(T_REC / 28);

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

        {/* Phase banner — flips between Recording / Stopping /
            Transcribing / Ready. Colors track the lifecycle. */}
        <div style={{
          marginTop: 14, display: 'flex', alignItems: 'center', gap: 8,
          padding: '8px 10px', borderRadius: 10,
          background: ready ? 'rgba(134,166,128,0.10)'
                    : transcribing ? 'rgba(196,162,82,0.10)'
                    : ending ? 'rgba(255,255,255,0.04)'
                    : 'rgba(202, 80, 71, 0.10)',
          border: '1px solid ' + (ready ? 'rgba(134,166,128,0.32)'
                    : transcribing ? 'rgba(196,162,82,0.32)'
                    : ending ? 'var(--hairline)'
                    : 'rgba(202, 80, 71, 0.30)'),
          transition: 'background .35s, border-color .35s',
        }}>
          <span style={{
            width: 8, height: 8, borderRadius: '50%',
            background: ready ? 'var(--sage)'
                      : transcribing ? 'var(--gold)'
                      : ending ? 'var(--text-muted)'
                      : 'var(--terracotta)',
            boxShadow: ready ? '0 0 8px var(--sage)'
                      : transcribing ? '0 0 8px var(--gold)'
                      : ending ? 'none'
                      : '0 0 8px var(--terracotta)',
            animation: (recording || transcribing) ? 'hdPulse 1.4s ease-in-out infinite' : 'none',
          }} />
          <span className="mono" style={{
            fontSize: 10, letterSpacing: '0.18em', fontWeight: 600,
            color: ready ? 'var(--sage)'
                 : transcribing ? 'var(--gold)'
                 : ending ? 'var(--text-dim)'
                 : 'var(--terracotta)',
          }}>
            {ready ? 'SESSION READY' : transcribing ? 'TRANSCRIBING' : ending ? 'STOPPING…' : 'RECORDING'}
          </span>
          <span style={{ flex: 1 }} />
          <span className="mono" style={{ fontSize: 12, color: 'var(--cream)', letterSpacing: '0.06em' }}>
            {ready ? `${transcriptLines.length} LEADS` : `${mm}:${ss}`}
          </span>
        </div>

        {/* Listing title */}
        <div style={{ marginTop: 12 }}>
          <div className="mono" style={{ fontSize: 8.5, color: 'var(--text-dim)', letterSpacing: '0.14em' }}>
            {ready ? 'TRANSCRIPT' : 'HOSTING'}
          </div>
          <div className="serif" style={{ fontSize: 20, color: 'var(--cream)', marginTop: 2, letterSpacing: '-0.01em' }}>
            412 W 78th St
          </div>
        </div>

        {/* Main content area — wave during recording, spinner during
            transcribing, transcript when ready. */}
        {ready ? (
          // READY — transcript card with 5 speakers, lines fade in
          <div style={{
            marginTop: 14, flex: 1,
            overflow: 'hidden',
            display: 'flex', flexDirection: 'column', gap: 7,
          }}>
            {transcriptLines.slice(0, linesShown).map((ln, i) => (
              <div key={ln.speaker} style={{
                animation: 'hdSlideIn .35s cubic-bezier(.22,1,.36,1) both',
                padding: '7px 10px', borderRadius: 8,
                background: 'rgba(255,255,255,0.03)',
                border: '1px solid var(--hairline)',
              }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: 6, marginBottom: 3 }}>
                  <span className={`tag tag-${ln.kind}`} style={{ fontSize: 7.5, padding: '2px 6px 3px' }}>
                    <span className="tag-dot" style={{ width: 4, height: 4 }} />{ln.speaker}
                  </span>
                </div>
                <div style={{ fontSize: 10.5, lineHeight: 1.45, color: 'var(--cream-dim)' }}>
                  "{ln.line}"
                </div>
              </div>
            ))}
          </div>
        ) : transcribing ? (
          // TRANSCRIBING — wave fades, spinner shows
          <div style={{ marginTop: 14, flex: 1, display: 'flex', alignItems: 'center', justifyContent: 'center', flexDirection: 'column', gap: 14 }}>
            <div style={{
              width: 38, height: 38, borderRadius: '50%',
              border: '2px solid rgba(196,162,82,0.18)',
              borderTopColor: 'var(--gold)',
              animation: 'hdSpin 0.85s linear infinite',
            }} />
            <div style={{
              display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 4,
            }}>
              <div className="mono" style={{ fontSize: 9, color: 'var(--gold)', letterSpacing: '0.14em' }}>
                SEPARATING VOICES…
              </div>
              <div style={{ fontSize: 11, color: 'var(--text-dim)' }}>
                Tagging each guest
              </div>
            </div>
          </div>
        ) : (
          // RECORDING / ENDING — live wave + identified speakers
          <>
            <div style={{ marginTop: 14, padding: '6px 0', borderTop: '1px solid var(--hairline)', borderBottom: '1px solid var(--hairline)', opacity: ending ? 0.5 : 1, transition: 'opacity .35s' }}>
              <VoiceWave width={268} height={92} orbSize={48} animated={!ending} />
            </div>
            <div style={{ marginTop: 14, flex: 1 }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 5 }}>
                <svg width="9" height="9" viewBox="0 0 24 24" fill="var(--gold)" stroke="none"><path d="M12 2v6m0 8v6M2 12h6m8 0h6M5.6 5.6l3.5 3.5M14.9 14.9l3.5 3.5M5.6 18.4l3.5-3.5M14.9 9.1l3.5-3.5"/></svg>
                <span className="mono" style={{ fontSize: 8.5, color: 'var(--gold)', letterSpacing: '0.14em' }}>
                  AI IDENTIFIED · {liveSpeakersIdentified}
                </span>
              </div>
              <div style={{ marginTop: 8, display: 'flex', flexDirection: 'column', gap: 6 }}>
                {speakers.map(sp => {
                  const detected = t >= sp.detectedAt;
                  const named    = t >= sp.namedAt;
                  if (!detected) return null;
                  return (
                    <div key={sp.id} style={{
                      padding: '7px 10px', borderRadius: 8,
                      background: 'rgba(255,255,255,0.04)',
                      border: '1px solid var(--hairline)',
                      display: 'flex', alignItems: 'center', gap: 9,
                      animation: 'hdSlideIn .45s cubic-bezier(.22,1,.36,1) both',
                    }}>
                      <div style={{
                        width: 22, height: 22, borderRadius: '50%',
                        background: named ? 'var(--gold-soft)' : 'rgba(255,255,255,0.08)',
                        color: named ? 'var(--gold)' : 'var(--text-muted)',
                        display: 'grid', placeItems: 'center',
                        fontFamily: 'var(--sans)', fontSize: 9, fontWeight: 600,
                        transition: 'background .35s ease, color .35s ease',
                      }}>
                        {named ? sp.name.charAt(0) : sp.id}
                      </div>
                      <div style={{ flex: 1, minWidth: 0 }}>
                        <div style={{ fontSize: 11, color: 'var(--cream)' }}>
                          {named ? sp.name : `Speaker ${sp.id}`}
                        </div>
                        <div className="mono" style={{ fontSize: 8, color: 'var(--text-muted)', marginTop: 1, letterSpacing: '0.08em' }}>
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
          </>
        )}

        {/* Status pill below the content. Saved during recording,
            "5 leads ready" once the transcript lands. */}
        {!transcribing && (
          <div style={{ marginTop: 10, display: 'flex', alignItems: 'center', gap: 8 }}>
            <div style={{
              display: 'inline-flex', alignItems: 'center', gap: 5,
              padding: '5px 9px', borderRadius: 999,
              background: 'rgba(134,166,128,0.12)',
              color: 'var(--sage)',
              fontSize: 9, fontWeight: 600,
            }}>
              <svg width="9" height="9" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5"><polyline points="20 6 9 17 4 12"/></svg>
              <span className="mono" style={{ letterSpacing: '0.1em' }}>
                {ready ? `READY · ${linesShown}/${transcriptLines.length} TRANSCRIBED` : `SAVED · ${savedPulse}m AGO`}
              </span>
            </div>
            <span style={{ flex: 1 }} />
          </div>
        )}

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
// right. ONE guest signs in per carousel visit (no looping within a
// mount) — the carousel moves to the next device after success holds
// for a beat. A window-scoped counter rotates the guest on each
// remount so successive iPad visits show different people.
const HDIPad = () => {
  // Pick this visit's guest once on mount. Window-scoped counter
  // increments per remount so the rotation persists across the
  // carousel's conditional render cycle.
  const guestRotation = [
    { name: 'Sarah Chen',     email: 'sarah.chen@example.com',  phone: '(212) 555-0101', hasAgent: 'no'  },
    { name: 'Mike Rodriguez', email: 'mike.r@example.com',      phone: '(212) 555-0142', hasAgent: 'no'  },
    { name: 'Jennifer Park',  email: 'jpark.nyc@example.com',   phone: '(212) 555-0173', hasAgent: 'yes' },
    { name: 'David Lee',      email: 'd.lee@example.com',       phone: '(212) 555-0188', hasAgent: 'no'  },
    { name: 'Elena Morales',  email: 'elena.m@example.com',     phone: '(212) 555-0124', hasAgent: 'yes' },
  ];
  const [guestIdx] = useHD(() => {
    const next = (window._foyerIPadVisit ?? 0) % guestRotation.length;
    window._foyerIPadVisit = (window._foyerIPadVisit ?? 0) + 1;
    return next;
  });
  const guest = guestRotation[guestIdx];

  // Fast tick (every 60ms) drives a single sign-in. Phase durations
  // are tuned so the form completes in ~4.5s, then the success
  // overlay holds until the carousel moves on. No looping.
  const tickFast = useCount(0, 60, 0);

  const T_NAME    = 12;   // ~720ms
  const T_PAUSE_1 = 4;
  const T_EMAIL   = 22;   // ~1320ms
  const T_PAUSE_2 = 4;
  const T_PHONE   = 16;
  const T_PAUSE_3 = 3;
  const T_AGENT   = 6;
  const T_SUCCESS_START = T_NAME + T_PAUSE_1 + T_EMAIL + T_PAUSE_2 + T_PHONE + T_PAUSE_3 + T_AGENT;

  // Clamp so the animation freezes on the success overlay until
  // the carousel unmounts us.
  const t = Math.min(tickFast, T_SUCCESS_START + 60);

  // The "N SIGNED IN" badge on the listing photo. Bumps the moment
  // this guest's success overlay fires.
  const baseSignedIn = 6 + guestIdx;
  const guestsIn = t >= T_SUCCESS_START ? baseSignedIn + 1 : baseSignedIn;

  // Return a typed substring of `target` that fills proportionally
  // through the [startTick, startTick + duration) window. Before the
  // window starts: empty. After it ends: full string.
  function typedSubstring(target, startTick, duration) {
    if (t < startTick) return '';
    if (t >= startTick + duration) return target;
    const localT = t - startTick;
    return target.slice(0, Math.ceil((localT + 1) / duration * target.length));
  }

  const nameStart  = 0;
  const emailStart = T_NAME + T_PAUSE_1;
  const phoneStart = emailStart + T_EMAIL + T_PAUSE_2;
  const agentStart = phoneStart + T_PHONE + T_PAUSE_3;
  const successStart = T_SUCCESS_START;

  const nameTyped  = typedSubstring(guest.name,  nameStart,  T_NAME);
  const emailTyped = typedSubstring(guest.email, emailStart, T_EMAIL);
  const phoneTyped = typedSubstring(guest.phone, phoneStart, T_PHONE);
  const agentSet   = t >= agentStart;
  const termsOK    = t >= agentStart;
  const showSuccess = t >= successStart;

  // Which field has the focus caret right now. Used to put the gold
  // border + blinking cursor on the field currently being typed.
  const nameActive  = t >= nameStart  && t < nameStart  + T_NAME;
  const emailActive = t >= emailStart && t < emailStart + T_EMAIL;
  const phoneActive = t >= phoneStart && t < phoneStart + T_PHONE;

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

          {/* Form fields — each types its target string letter by letter
              during the field's active window. The blinking caret only
              shows on the field currently being typed. */}
          <KioskField label="NAME"  value={nameTyped}  active={nameActive}  />
          <KioskField label="EMAIL" value={emailTyped} active={emailActive} />
          <KioskField label="PHONE" value={phoneTyped} active={phoneActive} />

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
        boxShadow: active ? '0 0 0 3px rgba(196, 162, 82, 0.14)' : 'none',
        borderRadius: 8,
        fontSize: 12, color: value ? 'var(--cream)' : 'var(--text-muted)',
        fontFamily: 'var(--sans)', minHeight: 16,
        transition: 'border-color .25s ease, box-shadow .25s ease',
      }}>
        {value || (active ? '' : <span style={{ color: 'var(--text-muted)' }}>…</span>)}
        {active && (
          <span style={{
            display: 'inline-block', width: 1.5, height: 12, marginLeft: 1,
            background: 'var(--gold)', verticalAlign: '-1px',
            animation: 'hdBlink 0.9s steps(2) infinite',
          }} />
        )}
      </div>
    </div>
  );
}

// Laptop — BULK FOLLOW-UP COCKPIT. The agent types a prompt into "Ask
// your inbox" and the AI fans out across 14 leads: each tile cascades
// from PENDING → DRAFTING → DRAFTED → SENDING → SENT in rapid
// succession. Showcases scale (14 personalized emails) and speed
// (whole queue clears in ~4s). No slow per-char typing — the
// "personalization" is implied by each tile carrying the lead's
// name + tag + a per-recipient draft preview that fades in when
// drafted.
const HDLaptop = () => {
  // 14 warm-buyer leads queued for the bulk send. Mixed tags + scores
  // so the grid looks like a real inbox slice.
  const queue = [
    { n: 'Sarah Chen',     k: 'buyer',   score: 94 },
    { n: 'Mike Rodriguez', k: 'seller',  score: 76 },
    { n: 'Jennifer Park',  k: 'browser', score: 38 },
    { n: 'David Lee',      k: 'buyer',   score: 88 },
    { n: 'Elena Morales',  k: 'buyer',   score: 82 },
    { n: 'Tom Walker',     k: 'buyer',   score: 91 },
    { n: 'Aisha Patel',    k: 'seller',  score: 71 },
    { n: 'Marcus Reed',    k: 'buyer',   score: 86 },
    { n: 'Lia Schmidt',    k: 'buyer',   score: 79 },
    { n: 'Ben Park',       k: 'browser', score: 44 },
    { n: 'Olivia Reyes',   k: 'buyer',   score: 92 },
    { n: 'Noah Patel',     k: 'seller',  score: 68 },
    { n: 'Priya Joshi',    k: 'buyer',   score: 84 },
    { n: 'Carlos Diaz',    k: 'buyer',   score: 89 },
  ];

  // 50ms tick — fine-grained enough that the cascade reads as smooth
  // motion rather than a stepped animation.
  const tickFast = useCount(0, 50, 0);

  // Phase plan (one cycle = one bulk send, then hold):
  //   T_PROMPT     prompt fades in
  //   T_BUILD      "Building plan…" spinner
  //   T_PLAN       plan panel + recipient grid appears
  //   T_CASCADE    each tile staggers through drafting → sent
  //   T_HOLD       all-sent state holds for the dwell remainder
  const T_PROMPT  = 10;   // ~500ms
  const T_BUILD   = 10;   // ~500ms
  const T_STAGGER = 4;    // ~200ms between tile starts
  const T_DRAFT   = 8;    // ~400ms drafting per tile
  const T_SEND    = 4;    // ~200ms sending per tile

  const PROMPT_START = 0;
  const BUILD_START  = T_PROMPT;
  const PLAN_START   = BUILD_START + T_BUILD;
  // Last tile begins at PLAN_START + (N-1) * T_STAGGER, finishes
  // T_DRAFT + T_SEND ticks later.
  const ALL_SENT_AT  = PLAN_START + (queue.length - 1) * T_STAGGER + T_DRAFT + T_SEND;

  // Run once and freeze on the "all sent" state. The carousel slot
  // for laptop is ~9.5s; the cascade completes around 5s in, then
  // we hold the green stat until the carousel switches devices.
  // No looping inside a mount — looping back to empty mid-view was
  // confusing.
  const t = Math.min(tickFast, ALL_SENT_AT + 6);

  const showPrompt = t >= PROMPT_START;
  const showBuild  = t >= BUILD_START && t < PLAN_START;
  const showPlan   = t >= PLAN_START;

  // Per-tile status. Each tile starts T_STAGGER ticks after the
  // previous one. States cycle drafting → drafted → sending → sent.
  function tileState(i) {
    if (t < PLAN_START) return 'pending';
    const startedAt = PLAN_START + i * T_STAGGER;
    if (t < startedAt) return 'pending';
    const localT = t - startedAt;
    if (localT < T_DRAFT) return 'drafting';
    if (localT < T_DRAFT + T_SEND) return 'sending';
    return 'sent';
  }

  // Live counts for the progress bar + summary stat.
  const sentCount = queue.filter((_, i) => tileState(i) === 'sent').length;
  const inFlight  = queue.filter((_, i) => {
    const s = tileState(i);
    return s === 'drafting' || s === 'sending';
  }).length;
  const allSent = sentCount === queue.length;

  // The completion time — frozen once everything sends so the
  // "X sent in 4.2s" stat doesn't keep climbing.
  const completedAt = ALL_SENT_AT * 0.05;  // seconds

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

          {/* App: sidebar + bulk send panel */}
          <div style={{ flex: 1, display: 'grid', gridTemplateColumns: '140px 1fr', minHeight: 0 }}>
            {/* SIDEBAR */}
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
              {navItems.slice(0, 2).map(it => <NavRow key={it.i} item={it} />)}
              <div className="mono" style={{ fontSize: 7, color: 'var(--text-muted)', letterSpacing: '0.16em', padding: '12px 10px 6px' }}>
                LIBRARY
              </div>
              {navItems.slice(2).map(it => <NavRow key={it.i} item={it} />)}
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

            {/* MAIN — bulk send cockpit */}
            <div style={{
              padding: '16px 22px 0',
              display: 'flex', flexDirection: 'column', minHeight: 0,
            }}>
              {/* Header */}
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', marginBottom: 12 }}>
                <div className="serif" style={{ fontSize: 22, color: 'var(--cream)', letterSpacing: '-0.02em' }}>
                  Leads
                </div>
                <span className="mono" style={{
                  padding: '3px 10px', borderRadius: 999,
                  background: allSent ? 'rgba(134,166,128,0.18)' : 'var(--gold-soft)',
                  color: allSent ? 'var(--sage)' : 'var(--gold)',
                  fontSize: 8.5, letterSpacing: '0.1em', fontWeight: 600,
                  border: '1px solid ' + (allSent ? 'rgba(134,166,128,0.45)' : 'transparent'),
                  transition: 'background .35s, color .35s, border-color .35s',
                }}>
                  {allSent
                    ? `✓ ${queue.length} SENT IN ${completedAt.toFixed(1)}s`
                    : `${sentCount}/${queue.length} SENT`}
                </span>
              </div>

              {/* Ask-your-inbox prompt — the bulk send trigger */}
              <div style={{
                padding: '10px 12px', borderRadius: 10,
                background: 'rgba(196,162,82,0.08)',
                border: '1px solid rgba(196,162,82,0.30)',
                display: 'flex', alignItems: 'center', gap: 8,
                opacity: showPrompt ? 1 : 0,
                transform: showPrompt ? 'translateY(0)' : 'translateY(-4px)',
                transition: 'opacity .35s ease, transform .35s ease',
              }}>
                <svg width="11" height="11" viewBox="0 0 24 24" fill="var(--gold)" stroke="none">
                  <path d="M12 2v6m0 8v6M2 12h6m8 0h6M5.6 5.6l3.5 3.5M14.9 14.9l3.5 3.5M5.6 18.4l3.5-3.5M14.9 9.1l3.5-3.5"/>
                </svg>
                <span style={{ fontSize: 11, color: 'var(--cream)' }}>
                  Send the <span className="mono" style={{ color: 'var(--gold)', fontWeight: 600 }}>@SpringBuyerCredit</span> to all warm buyers from the Maple St open house
                </span>
                {showBuild && (
                  <span style={{
                    marginLeft: 'auto',
                    display: 'inline-flex', alignItems: 'center', gap: 5,
                    fontSize: 9, color: 'var(--gold)', fontWeight: 600,
                  }}>
                    <span style={{
                      width: 8, height: 8, borderRadius: '50%',
                      background: 'var(--gold)',
                      animation: 'hdPulse 0.9s ease-in-out infinite',
                    }} />
                    <span className="mono" style={{ letterSpacing: '0.1em' }}>BUILDING PLAN…</span>
                  </span>
                )}
                {showPlan && (
                  <span className="mono" style={{
                    marginLeft: 'auto',
                    padding: '3px 8px', borderRadius: 999,
                    background: 'rgba(196,162,82,0.18)', color: 'var(--gold)',
                    fontSize: 8.5, letterSpacing: '0.12em', fontWeight: 600,
                  }}>
                    PLAN · {queue.length} RECIPIENTS
                  </span>
                )}
              </div>

              {/* Recipient grid — 4 columns × ~4 rows for 14 tiles */}
              <div style={{
                marginTop: 12, flex: 1, minHeight: 0,
                display: 'grid',
                gridTemplateColumns: 'repeat(4, 1fr)',
                gap: 6,
                alignContent: 'start',
                opacity: showPlan ? 1 : 0,
                transition: 'opacity .35s ease .1s',
              }}>
                {queue.map((q, i) => (
                  <RecipientTile
                    key={q.n}
                    lead={q}
                    state={tileState(i)}
                  />
                ))}
              </div>

              {/* Bottom: progress bar */}
              <div style={{
                padding: '10px 0 12px',
                opacity: showPlan ? 1 : 0,
                transition: 'opacity .35s ease',
              }}>
                <div style={{
                  height: 4, borderRadius: 2,
                  background: 'rgba(255,255,255,0.06)',
                  overflow: 'hidden',
                }}>
                  <div style={{
                    height: '100%',
                    width: `${(sentCount / queue.length) * 100}%`,
                    background: allSent ? 'var(--sage)' : 'var(--gold)',
                    transition: 'width .25s ease, background .35s ease',
                    boxShadow: allSent
                      ? '0 0 10px rgba(134,166,128,0.6)'
                      : '0 0 10px rgba(196,162,82,0.5)',
                  }} />
                </div>
                <div style={{
                  marginTop: 6, display: 'flex', justifyContent: 'space-between',
                  fontSize: 9, color: 'var(--text-muted)',
                }}>
                  <span className="mono" style={{ letterSpacing: '0.1em' }}>
                    {sentCount} SENT · {inFlight} IN FLIGHT · {queue.length - sentCount - inFlight} QUEUED
                  </span>
                  <span className="mono" style={{
                    letterSpacing: '0.1em',
                    color: allSent ? 'var(--sage)' : 'var(--gold)',
                    fontWeight: 600,
                  }}>
                    {allSent ? '✓ ALL SENT' : `${Math.round((sentCount / queue.length) * 100)}%`}
                  </span>
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

// One recipient tile in the bulk-send grid. State drives an icon +
// label + color: pending (dim), drafting (gold spinner), sending
// (gold paper-plane), sent (green checkmark). Tile fades + shifts
// slightly on each transition so the cascade reads as motion.
function RecipientTile({ lead, state }) {
  const isSent     = state === 'sent';
  const isSending  = state === 'sending';
  const isDrafting = state === 'drafting';
  const isPending  = state === 'pending';

  const accent = isSent ? 'var(--sage)'
              : isSending ? 'var(--gold)'
              : isDrafting ? 'var(--gold)'
              : 'rgba(255,255,255,0.3)';

  return (
    <div style={{
      padding: '7px 9px', borderRadius: 8,
      background: isSent ? 'rgba(134,166,128,0.10)'
                : isPending ? 'rgba(255,255,255,0.025)'
                : 'rgba(196,162,82,0.08)',
      border: '1px solid ' + (isSent ? 'rgba(134,166,128,0.32)'
                : isPending ? 'var(--hairline)'
                : 'rgba(196,162,82,0.28)'),
      display: 'flex', alignItems: 'center', gap: 7,
      transition: 'background .25s ease, border-color .25s ease',
      opacity: isPending ? 0.55 : 1,
    }}>
      {/* Avatar with state-driven status pip */}
      <div style={{
        position: 'relative', flexShrink: 0,
        width: 22, height: 22, borderRadius: '50%',
        background: 'var(--bg-elev)', color: accent,
        display: 'grid', placeItems: 'center',
        fontFamily: 'var(--sans)', fontSize: 9, fontWeight: 600,
      }}>
        {lead.n.charAt(0)}
        <span style={{
          position: 'absolute', bottom: -1, right: -1,
          width: 10, height: 10, borderRadius: '50%',
          background: accent,
          display: 'grid', placeItems: 'center',
          border: '1.5px solid var(--bg-deep)',
        }}>
          {isSent && (
            <svg width="6" height="6" viewBox="0 0 24 24" fill="none" stroke="#0a1208" strokeWidth="4">
              <polyline points="20 6 9 17 4 12"/>
            </svg>
          )}
          {isSending && (
            <svg width="5" height="5" viewBox="0 0 24 24" fill="#1a1610">
              <path d="M22 2 11 13"/><path d="M22 2 15 22l-4-9-9-4 20-7Z"/>
            </svg>
          )}
          {isDrafting && (
            <span style={{
              width: 4, height: 4, borderRadius: '50%',
              background: '#1a1610',
              animation: 'hdPulse 0.7s ease-in-out infinite',
            }} />
          )}
        </span>
      </div>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{
          fontSize: 10, color: 'var(--cream)',
          whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis',
          fontWeight: 500,
        }}>
          {lead.n}
        </div>
        <div className="mono" style={{
          fontSize: 7.5, letterSpacing: '0.08em', marginTop: 1,
          color: isSent ? 'var(--sage)'
               : isSending ? 'var(--gold)'
               : isDrafting ? 'var(--gold)'
               : 'var(--text-muted)',
        }}>
          {isSent ? '✓ SENT' : isSending ? 'SENDING…' : isDrafting ? 'DRAFTING…' : 'QUEUED'}
        </div>
      </div>
    </div>
  );
}

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

  // Per-device dwell times so each animation gets exactly the time it
  // needs — iPhone has the longest (recording → transcribing → 5
  // transcript lines), iPad is the shortest (one sign-in then hold
  // success briefly).
  const dwellMs = [9500, 6500, 9500];

  useHDEf(() => {
    function advance() {
      setIdx(i => {
        const next = (i + 1) % 3;
        tRef.current = setTimeout(advance, dwellMs[next]);
        return next;
      });
    }
    tRef.current = setTimeout(advance, dwellMs[0]);
    return () => clearTimeout(tRef.current);
  }, []);

  const devices = [
    { id: 'phone',  label: 'iPhone',  caption: 'Records the room. Tags every voice.' },
    { id: 'ipad',   label: 'iPad',    caption: 'Hand to a guest. Sign-in does itself.' },
    { id: 'laptop', label: 'Laptop',  caption: 'AI drafts each follow-up — you hit send.' },
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
                  transformOrigin: 'left center',
                  animation: `hdBar ${dwellMs[i]}ms linear forwards`,
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
        @keyframes hdSpin { from { transform: rotate(0deg); } to { transform: rotate(360deg); } }
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

Object.assign(window, { HeroDevices, HDIPhone, HDIPad, HDLaptop, VoiceWave });
