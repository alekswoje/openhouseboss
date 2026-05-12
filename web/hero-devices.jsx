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

// Laptop — web Leads inbox where the AI drafts a follow-up, then the
// agent clicks Send and watches it confirm. Cycles through leads so
// visitors see the full draft → send → sent loop more than once.
const HDLaptop = () => {
  // Pick a starting lead on first mount, then auto-advance.
  const guests = [
    { n: 'Sarah Chen',     k: 'buyer',   sub: 'Pre-approved $1.4M', score: 94,
      sum: 'Actively searching the West Side. Sold her Queens place last year. Drawn by the kitchen. Pre-approved to $1.4M, ready to close in 60 days.' },
    { n: 'Mike Rodriguez', k: 'seller',  sub: 'Wants comp analysis', score: 76,
      sum: 'Lives two blocks away. 15 years in his home. Kids off to college, considering downsizing in six months. Requested a complimentary comp.' },
    { n: 'Jennifer Park',  k: 'browser', sub: 'Curious renter', score: 38,
      sum: 'Local renter, lease through 2027. Loves the neighborhood but undecided. Open to low-pressure listing updates.' },
  ];

  // 70ms tick drives the whole sequence. Phases per lead:
  //   T_DRAFT_SPIN  — "Drafting personalized follow-up…" spinner
  //   T_TYPE        — email body types in letter by letter
  //   T_AI_BADGE    — "AI DRAFTED" badge has popped, Send button glows
  //   T_CLICK       — Send button gets the "about to click" highlight
  //   T_CLICK_FLASH — Send button visibly flashes (the "click")
  //   T_SENT        — "✓ SENT" toast slides in, lead moves to "Sent"
  //   T_HOLD        — hold the sent state long enough to read
  const tickFast = useCount(0, 70, 0);
  const T_DRAFT_SPIN  = 12;   // ~840ms
  const T_TYPE        = 36;   // ~2520ms
  const T_AI_BADGE    = 8;
  const T_CLICK       = 6;
  const T_CLICK_FLASH = 4;
  const T_SENT        = 14;
  const T_HOLD        = 18;
  const T_LEAD =
    T_DRAFT_SPIN + T_TYPE + T_AI_BADGE +
    T_CLICK + T_CLICK_FLASH + T_SENT + T_HOLD;

  const sel = Math.floor(tickFast / T_LEAD) % guests.length;
  const t = tickFast % T_LEAD;

  // Phase boundaries
  const DRAFT_END     = T_DRAFT_SPIN;
  const TYPE_END      = DRAFT_END + T_TYPE;
  const AI_BADGE_END  = TYPE_END + T_AI_BADGE;
  const CLICK_END     = AI_BADGE_END + T_CLICK;
  const FLASH_END     = CLICK_END + T_CLICK_FLASH;
  const SENT_END      = FLASH_END + T_SENT;

  const drafting    = t < DRAFT_END;
  const aiBadge     = t >= TYPE_END;
  const sendHover   = t >= AI_BADGE_END && t < CLICK_END;
  const sendFlash   = t >= CLICK_END    && t < FLASH_END;
  const sent        = t >= FLASH_END;
  const sentToast   = t >= FLASH_END    && t < SENT_END + 12;

  // Cumulative "sent this week" counter — bumps the moment the click
  // flash fires (matches the user's mental model: I clicked, count up).
  const cyclesDone = Math.floor(tickFast / T_LEAD);
  const sentThisWeek = 8 + cyclesDone + (sent ? 1 : 0);

  const g = guests[sel];
  const shownGuests = useStaggered([400, 900, 1400]);

  // Type the draft body manually from the tick — useTyped is mount-
  // anchored and doesn't restart per lead. This way each lead gets
  // its own fresh char-by-char typing in its TYPE window.
  const fullBody =
    g.k === 'buyer'
      ? "Sarah — great meeting you today. I'd love to share three comps from the block plus a private-showing slot for Saturday morning. Want me to send them over?"
      : g.k === 'seller'
      ? "Mike — great meeting you today. I'd love to put together a complimentary CMA for your place — no obligations, just real numbers from this quarter."
      : "Jennifer — great meeting you today. Totally understand you're early. I'll send a quiet listing update once a week — unsubscribe with one tap.";
  let typedChars = 0;
  if (t >= DRAFT_END && t < TYPE_END) {
    const localT = t - DRAFT_END;
    typedChars = Math.ceil(localT / T_TYPE * fullBody.length);
  } else if (t >= TYPE_END) {
    typedChars = fullBody.length;
  }
  const draftText = fullBody.slice(0, typedChars);
  const draftActive = t >= DRAFT_END && t < TYPE_END;

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
                    {sentThisWeek}/14 SENT
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
                  // A previously-active lead this loop counts as sent.
                  // The currently-active lead flips to "Sent" the moment
                  // its send-flash phase ends.
                  const isDone = i < sel || (isActive && sent);
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
                            {isDone ? '✓ Sent' : gg.sub}
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
                      {draftText}
                      {draftActive && (
                        <span style={{
                          display: 'inline-block', width: 5, height: 11, marginLeft: 1,
                          background: 'var(--gold)', verticalAlign: '-1px',
                          animation: 'hdBlink 0.9s steps(2) infinite',
                        }} />
                      )}
                    </>
                  )}
                </div>

                {/* Action row: Archive · Schedule · SEND. The Send
                    button is the focal point — it glows when the
                    draft is ready, flashes when the (animated) click
                    fires, then everything flips to a green "Sent"
                    state. Animates the agent clicking Send. */}
                <div style={{
                  marginTop: 10, display: 'flex', alignItems: 'center', gap: 6,
                }}>
                  <span style={{
                    padding: '4px 8px', borderRadius: 999,
                    background: 'rgba(255,255,255,0.05)',
                    color: 'var(--cream-dim)', fontSize: 9, fontWeight: 500,
                  }}>Archive</span>
                  <span style={{ flex: 1 }} />
                  <span style={{
                    padding: '4px 8px', borderRadius: 999,
                    background: 'rgba(255,255,255,0.05)',
                    color: 'var(--cream-dim)', fontSize: 9, fontWeight: 500,
                  }}>Schedule</span>
                  {/* Send button — color flips green after send */}
                  <div style={{
                    position: 'relative',
                    padding: sendFlash ? '5px 14px' : '5px 13px',
                    borderRadius: 999,
                    background: sent ? 'var(--sage)' : 'var(--gold)',
                    color: sent ? '#0a1208' : 'var(--ink-on-gold)',
                    fontSize: 10, fontWeight: 600,
                    display: 'inline-flex', alignItems: 'center', gap: 5,
                    boxShadow: sendHover ? '0 0 0 4px rgba(196,162,82,0.32), 0 4px 10px rgba(196,162,82,0.45)'
                             : sendFlash ? '0 0 0 8px rgba(196,162,82,0.55), 0 6px 12px rgba(196,162,82,0.55)'
                             : sent      ? '0 0 0 3px rgba(134,166,128,0.28)'
                             : 'none',
                    transition: 'all .25s ease',
                    transform: sendFlash ? 'scale(0.96)' : 'scale(1)',
                  }}>
                    {sent ? (
                      <>
                        <svg width="9" height="9" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="3.5"><polyline points="20 6 9 17 4 12"/></svg>
                        Sent
                      </>
                    ) : (
                      <>
                        <svg width="9" height="9" viewBox="0 0 24 24" fill="currentColor"><path d="M22 2 11 13"/><path d="M22 2 15 22l-4-9-9-4 20-7Z"/></svg>
                        Send
                      </>
                    )}
                    {/* Faux "cursor about to click" indicator */}
                    {sendHover && (
                      <span style={{
                        position: 'absolute',
                        bottom: -10, right: -2,
                        width: 14, height: 14,
                        color: 'var(--cream)',
                        animation: 'hdPulse 0.7s ease-in-out infinite',
                      }}>
                        <svg width="14" height="14" viewBox="0 0 24 24" fill="currentColor">
                          <path d="M5 3l14 9-6 1-3 8z"/>
                        </svg>
                      </span>
                    )}
                  </div>
                </div>

                {/* SENT toast — slides in over the right edge of the
                    detail pane when the click fires. Self-dismisses
                    when the cycle moves on. */}
                {sentToast && (
                  <div style={{
                    position: 'absolute',
                    top: 14, right: 14,
                    padding: '7px 12px', borderRadius: 999,
                    background: 'rgba(134,166,128,0.18)',
                    border: '1px solid rgba(134,166,128,0.45)',
                    color: 'var(--sage)',
                    fontSize: 10, fontWeight: 600,
                    display: 'inline-flex', alignItems: 'center', gap: 6,
                    boxShadow: '0 4px 12px rgba(134,166,128,0.18)',
                    animation: 'hdSlideIn .35s cubic-bezier(.22,1,.36,1) both',
                  }}>
                    <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="3"><polyline points="20 6 9 17 4 12"/></svg>
                    <span className="mono" style={{ letterSpacing: '0.1em' }}>SENT · GMAIL</span>
                  </div>
                )}
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
