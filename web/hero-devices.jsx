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
// the transcript transcribing with 5 identified speakers, scored by
// intent. Matches the real app: during recording we only show "we'll
// identify each speaker at the end" — the reveal is the payoff.
// Phases: RECORDING (wave + floating quote bubbles + offline flash) →
// ENDING → TRANSCRIBING (spinner) → READY (5 speakers cascade in
// best-intent-first with score rings filling around each avatar).
const HDIPhone = () => {
  // Master 60ms tick.
  const tickFast = useCount(0, 60, 0);

  // Phase plan @ 60ms/tick — total ~5.5s:
  //   RECORDING  ticks  0..37  (2.28s) — wave + 3 quote bubbles drift up
  //   ENDING     ticks 38..42  (0.30s) — "STOPPING…" banner
  //   TRANSCRIBE ticks 43..58  (0.96s) — spinner overlay
  //   READY      ticks 59..91  (~2.0s) — 5 speakers cascade, score rings fill
  const T_REC_END    = 38;
  const T_ENDING_END = 43;
  const T_TRANS_END  = 59;
  const t = tickFast;
  const recording    = t < T_REC_END;
  const ending       = t >= T_REC_END && t < T_ENDING_END;
  const transcribing = t >= T_ENDING_END && t < T_TRANS_END;
  const ready        = t >= T_TRANS_END;

  // Elapsed timer — sped to feel like a real open house compressed.
  const totalSec = 14 * 60 + 22 + (recording ? Math.floor(t * 1.6) : 0);
  const mm = String(Math.floor(totalSec / 60)).padStart(2, '0');
  const ss = String(totalSec % 60).padStart(2, '0');

  // Quote bubbles that float up over the wave during recording — these
  // are the things the agent would have to remember and write down by
  // hand. Each appears, drifts up, and fades over ~12 ticks (720ms).
  // No live speaker naming — the real app explicitly defers that.
  const quoteBubbles = [
    { text: "pre-approved $1.4M", appearAt:  6, kind: 'buyer'  },
    { text: "60-day close",        appearAt: 14, kind: 'buyer'  },
    { text: "loves the kitchen",   appearAt: 22, kind: 'buyer'  },
    { text: "HOA?",                appearAt: 30, kind: 'browser' },
  ];

  // Brief "WORKS OFFLINE · 0 BARS" flash on the SAVED pill so agents
  // catch that this thing keeps recording in basements.
  const showOfflineFlash = recording && t >= 18 && t < 28;

  // Transcript lines for the READY reveal. Ordered by buyer-intent
  // score descending — the TikTok "best leads first" payoff.
  const transcriptLines = [
    { first: 'Sarah',    name: 'Sarah Chen',     kind: 'buyer',   score: 94, line: "Pre-approved $1.4M. 60-day close." },
    { first: 'David',    name: 'David Lee',      kind: 'buyer',   score: 88, line: "We love the kitchen. Can we see the basement?" },
    { first: 'Mike',     name: 'Mike Rodriguez', kind: 'seller',  score: 76, line: "I've been here 15 years — kids off to college." },
    { first: 'Elena',    name: 'Elena Morales',  kind: 'browser', score: 41, line: "What's the HOA like?" },
    { first: 'Jennifer', name: 'Jennifer Park',  kind: 'browser', score: 38, line: "Just curious — lease runs through 2027." },
  ];
  // 5 ticks (~300ms) between each card appearing.
  const readyTicks = ready ? t - T_TRANS_END : -1;
  const linesShown = readyTicks < 0 ? 0 : Math.min(5, Math.floor(readyTicks / 4) + 1);

  // Cloud "Saved" pulse — runs during recording.
  const savedPulse = recording ? Math.max(1, Math.floor(t / 14)) : Math.floor(T_REC_END / 14);

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
            {ready ? 'SESSION READY' : transcribing ? 'TRANSCRIBING' : ending ? 'STOPPING…' : 'LISTENING'}
          </span>
          <span style={{ flex: 1 }} />
          <span className="mono" style={{ fontSize: 12, color: 'var(--cream)', letterSpacing: '0.06em' }}>
            {ready ? `${transcriptLines.length} LEADS` : `${mm}:${ss}`}
          </span>
        </div>

        {/* Listing title — matches the real app's Listening screen
            ("WE'LL IDENTIFY EACH SPEAKER AT THE END") so visitors see
            we don't mislabel mid-recording. */}
        <div style={{ marginTop: 12 }}>
          <div className="mono" style={{ fontSize: 8.5, color: 'var(--text-dim)', letterSpacing: '0.14em' }}>
            {ready ? 'TRANSCRIPT · BEST INTENT FIRST'
              : transcribing ? 'SEPARATING VOICES…'
              : `412 W 78TH ST · ${recording ? 'IDENTIFIED AT END' : 'HOSTED'}`}
          </div>
          <div className="serif" style={{ fontSize: 20, color: 'var(--cream)', marginTop: 2, letterSpacing: '-0.01em' }}>
            {ready ? '5 leads, scored' : 'Listening'}
          </div>
        </div>

        {/* Main content area — wave during recording, spinner during
            transcribing, transcript when ready. */}
        {ready ? (
          // READY — transcript card with 5 speakers, score ring around
          // each avatar, cards cascade in best-intent-first. The score
          // ring is the TikTok payoff: numbers tick up from 0.
          <div style={{
            marginTop: 12, flex: 1,
            overflow: 'hidden',
            display: 'flex', flexDirection: 'column', gap: 6,
          }}>
            {transcriptLines.slice(0, linesShown).map((ln, i) => (
              <SpeakerLeadRow key={ln.first} ln={ln} index={i} />
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
                SEPARATING 5 VOICES…
              </div>
              <div style={{ fontSize: 11, color: 'var(--text-dim)' }}>
                Tagging each guest
              </div>
            </div>
          </div>
        ) : (
          // RECORDING / ENDING — wave + floating quote bubbles drift up
          // and dissolve over the wave. The hint card explains that
          // speakers are tagged at the end (mirrors the real app copy).
          <>
            <div style={{
              position: 'relative',
              marginTop: 12, padding: '6px 0',
              borderTop: '1px solid var(--hairline)',
              borderBottom: '1px solid var(--hairline)',
              opacity: ending ? 0.5 : 1,
              transition: 'opacity .35s',
              overflow: 'hidden',
            }}>
              <VoiceWave width={268} height={100} orbSize={52} animated={!ending} />
              {/* Floating quote bubbles — the things an agent would
                  otherwise have to scribble. Each appears at its
                  appearAt tick, drifts up + fades over 14 ticks. */}
              {recording && quoteBubbles.map((qb) => {
                const localT = t - qb.appearAt;
                if (localT < 0 || localT > 14) return null;
                const progress = localT / 14;
                const opacity = progress < 0.15 ? progress / 0.15
                              : progress > 0.7 ? Math.max(0, (1 - progress) / 0.3) : 1;
                return (
                  <div key={qb.text} style={{
                    position: 'absolute',
                    left: '50%',
                    bottom: 10,
                    transform: `translateX(-50%) translateY(${-progress * 56}px)`,
                    opacity,
                    pointerEvents: 'none',
                    padding: '3px 9px',
                    borderRadius: 999,
                    background: 'rgba(0,0,0,0.72)',
                    border: '1px solid ' + (qb.kind === 'buyer' ? 'rgba(134,166,128,0.55)' : 'rgba(255,255,255,0.18)'),
                    fontSize: 9.5,
                    color: qb.kind === 'buyer' ? 'var(--sage)' : 'var(--cream-dim)',
                    whiteSpace: 'nowrap',
                    fontStyle: 'italic',
                    fontFamily: 'var(--serif)',
                  }}>
                    "{qb.text}"
                  </div>
                );
              })}
            </div>
            <div style={{ marginTop: 14, flex: 1 }}>
              <div className="mono" style={{
                fontSize: 8.5, color: 'var(--text-dim)',
                letterSpacing: '0.14em', textAlign: 'center',
              }}>
                WE'LL IDENTIFY EACH SPEAKER AT THE END
              </div>
              <div style={{
                marginTop: 10, padding: '10px 12px',
                borderRadius: 10,
                background: 'rgba(255,255,255,0.03)',
                border: '1px solid var(--hairline)',
                display: 'flex', alignItems: 'center', gap: 10,
              }}>
                <div style={{
                  width: 28, height: 28, borderRadius: '50%',
                  background: 'var(--terracotta-soft, rgba(202,80,71,0.12))',
                  border: '1px solid rgba(202,80,71,0.4)',
                  display: 'grid', placeItems: 'center',
                  flexShrink: 0,
                }}>
                  <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="var(--terracotta)" strokeWidth="2">
                    <rect x="9" y="2" width="6" height="11" rx="3"/>
                    <path d="M5 11a7 7 0 0 0 14 0M12 18v3"/>
                  </svg>
                </div>
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div style={{ fontSize: 11, color: 'var(--cream)', lineHeight: 1.3 }}>
                    Capturing every conversation
                  </div>
                  <div className="mono" style={{
                    fontSize: 8, color: 'var(--text-muted)',
                    marginTop: 2, letterSpacing: '0.08em',
                  }}>
                    AUTO-PAUSES ON SILENCE · 14 HRS BATTERY
                  </div>
                </div>
              </div>
            </div>
          </>
        )}

        {/* Status pill below the content. Saved during recording —
            briefly flips to "WORKS OFFLINE" so visitors catch the
            differentiator. "5 LEADS · SCORED" once transcript lands. */}
        {!transcribing && (
          <div style={{ marginTop: 10, display: 'flex', alignItems: 'center', gap: 8 }}>
            <div style={{
              display: 'inline-flex', alignItems: 'center', gap: 5,
              padding: '5px 9px', borderRadius: 999,
              background: showOfflineFlash ? 'rgba(196,162,82,0.16)' : 'rgba(134,166,128,0.12)',
              color: showOfflineFlash ? 'var(--gold)' : 'var(--sage)',
              fontSize: 9, fontWeight: 600,
              border: '1px solid ' + (showOfflineFlash ? 'rgba(196,162,82,0.45)' : 'transparent'),
              transition: 'background .2s, color .2s, border-color .2s',
            }}>
              {showOfflineFlash ? (
                <svg width="9" height="9" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5">
                  <path d="M1 1l22 22M16.72 11.06A10.94 10.94 0 0 1 19 12.55M5 12.55a10.94 10.94 0 0 1 5.17-2.39M10.71 5.05A16 16 0 0 1 22.58 9M1.42 9a15.91 15.91 0 0 1 4.7-2.88M8.53 16.11a6 6 0 0 1 6.95 0M12 20h.01"/>
                </svg>
              ) : (
                <svg width="9" height="9" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5"><polyline points="20 6 9 17 4 12"/></svg>
              )}
              <span className="mono" style={{ letterSpacing: '0.1em' }}>
                {ready ? `5 LEADS · SCORED`
                  : showOfflineFlash ? 'WORKS OFFLINE'
                  : `SAVED · ${savedPulse}m AGO`}
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

// One row in the transcript reveal — name + score ring + intent tag + quote.
// The score ring is the visual hit: a circular stroke around the avatar
// fills from 0 to the lead's score over ~400ms once the row mounts, and
// the number ticks up in lockstep. Sage for warm buyers, gold for
// sellers, terracotta-ish dim for low-intent browsers.
function SpeakerLeadRow({ ln, index }) {
  // Local 30ms tick — drives the score ring fill and number tick. Tied
  // to the row's mount, not the parent's master clock, so each row's
  // ring starts at 0 the moment it appears.
  const [n, setN] = useHD(0);
  useHDEf(() => {
    let id;
    let v = 0;
    id = setInterval(() => {
      v += 4;
      if (v >= ln.score) { v = ln.score; clearInterval(id); }
      setN(v);
    }, 22);
    return () => clearInterval(id);
  }, []);

  const ringColor = ln.score >= 70 ? 'var(--sage)'
                  : ln.score >= 50 ? 'var(--gold)'
                  : 'var(--text-muted)';
  const C = 2 * Math.PI * 13;             // circumference for r=13
  const dashOffset = C * (1 - n / 100);

  return (
    <div style={{
      animation: 'hdSlideIn .32s cubic-bezier(.22,1,.36,1) both',
      padding: '6px 8px', borderRadius: 8,
      background: 'rgba(255,255,255,0.03)',
      border: '1px solid var(--hairline)',
      display: 'flex', alignItems: 'center', gap: 9,
    }}>
      <div style={{ position: 'relative', width: 32, height: 32, flexShrink: 0 }}>
        <svg width="32" height="32" viewBox="0 0 32 32" style={{ position: 'absolute', inset: 0 }}>
          <circle cx="16" cy="16" r="13" fill="none" stroke="rgba(255,255,255,0.10)" strokeWidth="2" />
          <circle
            cx="16" cy="16" r="13" fill="none"
            stroke={ringColor} strokeWidth="2"
            strokeLinecap="round"
            strokeDasharray={C}
            strokeDashoffset={dashOffset}
            transform="rotate(-90 16 16)"
            style={{ transition: 'stroke-dashoffset .04s linear' }}
          />
        </svg>
        <div style={{
          position: 'absolute', inset: 0,
          display: 'grid', placeItems: 'center',
          fontFamily: 'var(--mono)', fontSize: 9, fontWeight: 700,
          color: ringColor,
        }}>
          {n}
        </div>
      </div>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 5, marginBottom: 1 }}>
          <span style={{ fontSize: 10.5, color: 'var(--cream)', fontWeight: 500 }}>{ln.name}</span>
          <span className={`tag tag-${ln.kind}`} style={{ fontSize: 7, padding: '1.5px 5px 2px' }}>
            <span className="tag-dot" style={{ width: 3.5, height: 3.5 }} />{ln.kind}
          </span>
        </div>
        <div style={{ fontSize: 9.5, lineHeight: 1.32, color: 'var(--cream-dim)', fontStyle: 'italic' }}>
          "{ln.line}"
        </div>
      </div>
    </div>
  );
}

// iPad LANDSCAPE — KIOSK in fullscreen guest mode. Side rail is hidden
// (locked kiosk), big listing photo on the left, sign-in form on the
// right. THREE guests sign in back-to-back so visitors see the
// throughput, not just one slow form-fill. Fields fill via a gold
// scan-line sweep (no letter-by-letter typing — TikTok pace).
const HDIPad = () => {
  // Three guests cycled through, in order. Counter ticks 6 → 9 across
  // the cycle so the listing photo's "N SIGNED IN" badge climbs.
  const guests = [
    { name: 'Sarah Chen',     email: 'sarah.chen@example.com', phone: '(212) 555-0101', hasAgent: 'no'  },
    { name: 'Mike Rodriguez', email: 'mike.r@example.com',     phone: '(212) 555-0142', hasAgent: 'yes' },
    { name: 'Jennifer Park',  email: 'jpark.nyc@example.com',  phone: '(212) 555-0173', hasAgent: 'yes' },
  ];

  // 60ms tick. Per-guest phase plan (27 ticks ≈ 1.62s):
  //   NAME   ticks 0..4  (0.30s)  — scan-line wipe + field fills
  //   EMAIL  ticks 5..9  (0.30s)
  //   PHONE  ticks 10..14 (0.30s)
  //   CHIP   ticks 15..16 (0.12s)  — agent chip clicks
  //   PRESS  ticks 17..18 (0.12s)  — submit button glows
  //   SUCCESS ticks 19..26 (0.48s) — overlay holds
  // After 3 guests (81 ticks) we hold for an additional ~10 ticks so
  // the final success card lingers for the carousel handoff.
  const PER_GUEST = 27;
  const TOTAL = PER_GUEST * 3;
  const tickFast = useCount(0, 60, 0);
  const t = Math.min(tickFast, TOTAL + 10);

  const guestIdx = Math.min(guests.length - 1, Math.floor(t / PER_GUEST));
  const guest = guests[guestIdx];
  const localT = t - guestIdx * PER_GUEST;

  const NAME_END   = 5;
  const EMAIL_END  = 10;
  const PHONE_END  = 15;
  const CHIP_END   = 17;
  const PRESS_END  = 19;
  const SUCCESS_END = PER_GUEST;

  const nameActive  = localT < NAME_END;
  const emailActive = localT >= NAME_END  && localT < EMAIL_END;
  const phoneActive = localT >= EMAIL_END && localT < PHONE_END;
  const chipSet     = localT >= PHONE_END;
  const pressing    = localT >= CHIP_END && localT < PRESS_END;
  const showSuccess = localT >= PRESS_END;

  // Scan-line progress for the currently-active field (0..1).
  const scanProgress = (start, end) => {
    if (localT < start) return 0;
    if (localT >= end)  return 1;
    return (localT - start) / (end - start);
  };

  // Listing badge counter — climbs each time a guest hits success.
  // Starts at 6 + offset for visual believability.
  let guestsIn = 6;
  for (let i = 0; i < guests.length; i++) {
    if (t >= i * PER_GUEST + PRESS_END) guestsIn += 1;
  }

  // Field value: empty until that field's scan-line has covered any of
  // it, then full once it's started (no per-char animation — the gold
  // sweep over the empty field implies "auto-filling from prior visit").
  const nameTyped  = (localT >= NAME_END  - 1) ? guest.name  : '';
  const emailTyped = (localT >= EMAIL_END - 1) ? guest.email : '';
  const phoneTyped = (localT >= PHONE_END - 1) ? guest.phone : '';
  const agentSet   = chipSet;
  const termsOK    = chipSet;

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

        {/* SIGN-IN FORM PANE — gold scan-line wipes each field instead
            of letter-by-letter typing. Keyed on guestIdx so each guest
            cycle starts from a fresh form (no half-old values
            bleeding across). */}
        <div key={`form-${guestIdx}`} style={{
          background: '#000', padding: '32px 28px',
          display: 'flex', flexDirection: 'column',
          position: 'relative',
          animation: 'hdFadeIn .25s ease both',
        }}>
          <div style={{ marginBottom: 18 }}>
            <div className="serif" style={{ fontSize: 22, color: 'var(--cream)', lineHeight: 1, letterSpacing: '-0.02em' }}>
              Welcome in
            </div>
            <div style={{ fontSize: 11, color: 'var(--text-dim)', marginTop: 4 }}>
              Quick sign-in so we can follow up.
            </div>
          </div>

          {/* Form fields — a gold scan-line wipes left→right across the
              active field, leaving the filled value behind it. */}
          <KioskField label="NAME"  value={nameTyped}  active={nameActive}
            progress={scanProgress(0, NAME_END)} />
          <KioskField label="EMAIL" value={emailTyped} active={emailActive}
            progress={scanProgress(NAME_END, EMAIL_END)} />
          <KioskField label="PHONE" value={phoneTyped} active={phoneActive}
            progress={scanProgress(EMAIL_END, PHONE_END)} />

          {/* Agent chip — clicks at PHONE_END. Briefly bumps when set. */}
          <div style={{ marginTop: 6, opacity: agentSet ? 1 : 0.3, transition: 'opacity .2s ease' }}>
            <div className="mono" style={{ fontSize: 8.5, color: 'var(--text-dim)', letterSpacing: '0.14em' }}>
              WORKING WITH AN AGENT?
            </div>
            <div style={{ marginTop: 6, display: 'flex', gap: 6 }}>
              {['no', 'yes'].map(opt => {
                const selected = agentSet && guest.hasAgent === opt;
                return (
                  <span key={opt} style={{
                    padding: '5px 11px', borderRadius: 999, fontSize: 10, fontWeight: 500,
                    background: selected ? 'var(--gold-soft)' : 'rgba(255,255,255,0.04)',
                    color:      selected ? 'var(--gold)'      : 'var(--text-dim)',
                    border: '1px solid ' + (selected ? 'var(--gold)' : 'var(--hairline)'),
                    transition: 'all .2s ease',
                    animation: selected ? 'hdPop .25s cubic-bezier(.22,1.4,.36,1) both' : 'none',
                  }}>{opt === 'no' ? 'Not yet' : 'Yes'}</span>
                );
              })}
            </div>
          </div>

          <div style={{ flex: 1 }} />

          {/* Submit button — visibly compresses on the press tick. */}
          <button style={{
            marginTop: 14,
            padding: '12px', border: 0,
            background: termsOK ? 'var(--gold)' : 'rgba(196, 162, 82, 0.35)',
            color: 'var(--ink-on-gold)',
            borderRadius: 12, fontFamily: 'var(--sans)', fontSize: 13, fontWeight: 600,
            boxShadow: termsOK ? '0 0 0 4px rgba(196,162,82,0.18)' : 'none',
            transform: pressing ? 'scale(0.96)' : 'scale(1)',
            transition: 'all .12s ease',
          }}>
            Sign in
          </button>

          {/* Success overlay — covers the form when each guest hits
              success. Unmounts when the next guest's form keys in. */}
          {showSuccess && (
            <div style={{
              position: 'absolute', inset: 0, background: '#000',
              display: 'flex', flexDirection: 'column',
              alignItems: 'center', justifyContent: 'center',
              animation: 'hdFadeIn .2s ease both',
              padding: 28,
            }}>
              <div style={{
                width: 64, height: 64, borderRadius: '50%',
                background: 'var(--gold-soft)', color: 'var(--gold)',
                display: 'grid', placeItems: 'center',
                boxShadow: '0 0 0 6px rgba(196,162,82,0.16)',
                animation: 'hdPop .35s cubic-bezier(.22,1.4,.36,1) both',
              }}>
                <svg width="30" height="30" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="3"><polyline points="20 6 9 17 4 12"/></svg>
              </div>
              <div className="serif" style={{ marginTop: 18, fontSize: 22, color: 'var(--cream)', textAlign: 'center', letterSpacing: '-0.02em' }}>
                Welcome, {guest.name.split(' ')[0]}
              </div>
              <div style={{ marginTop: 6, fontSize: 11, color: 'var(--text-dim)', textAlign: 'center' }}>
                Saved · ready to listen
              </div>
              <div style={{
                marginTop: 18, padding: '5px 10px', borderRadius: 999,
                background: 'rgba(134,166,128,0.14)',
                border: '1px solid rgba(134,166,128,0.4)',
                fontFamily: 'var(--mono)', fontSize: 9, color: 'var(--sage)',
                letterSpacing: '0.14em',
              }}>
                LEAD · {guest.hasAgent === 'no' ? 'BUYER (UNREPPED)' : 'BUYER (HAS AGENT)'}
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  );
};

// One labeled field in the kiosk form. While the parent says this row
// is "active", a gold scan-line sweeps left→right based on `progress`
// (0..1) and the filled value is revealed behind it. No human typing.
function KioskField({ label, value, active, progress = 0 }) {
  const showValue = value && value.length > 0;
  return (
    <div style={{ marginBottom: 12 }}>
      <div className="mono" style={{ fontSize: 8.5, color: 'var(--text-dim)', letterSpacing: '0.14em' }}>
        {label}
      </div>
      <div style={{
        position: 'relative', overflow: 'hidden',
        marginTop: 5, padding: '9px 12px',
        background: 'rgba(255,255,255,0.04)',
        border: '1px solid ' + (active ? 'var(--gold)' : 'var(--hairline)'),
        boxShadow: active ? '0 0 0 3px rgba(196, 162, 82, 0.14)' : 'none',
        borderRadius: 8,
        fontSize: 12, color: showValue ? 'var(--cream)' : 'var(--text-muted)',
        fontFamily: 'var(--sans)', minHeight: 16,
        transition: 'border-color .15s ease, box-shadow .15s ease',
      }}>
        <span style={{
          opacity: showValue ? 1 : 0.4,
          transition: 'opacity .15s ease',
        }}>
          {showValue ? value : '…'}
        </span>
        {active && (
          <>
            {/* Gold scan-line bar — wipes across the field. */}
            <span style={{
              position: 'absolute', top: 0, bottom: 0,
              left: `${Math.max(0, Math.min(100, progress * 100))}%`,
              width: 3, marginLeft: -1,
              background: 'linear-gradient(to bottom, transparent, var(--gold), transparent)',
              boxShadow: '0 0 12px 3px rgba(196,162,82,0.55)',
              pointerEvents: 'none',
            }} />
            {/* Soft gold trail behind the line. */}
            <span style={{
              position: 'absolute', top: 0, bottom: 0, left: 0,
              width: `${Math.max(0, Math.min(100, progress * 100))}%`,
              background: 'linear-gradient(90deg, transparent, rgba(196,162,82,0.10))',
              pointerEvents: 'none',
            }} />
          </>
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

  // Phase plan @ 50ms/tick — total 6.0s:
  //   PROMPT     ticks  0..7   (0.4s)  prompt fades in + cursor types
  //   BUILD      ticks  8..15  (0.4s)  "Building plan…" spinner
  //   CASCADE    ticks 16..63  (2.4s)  14 tiles cascade through states
  //   INSPECTOR  ticks 30..90  (3.0s)  personalization modal slides in
  //   STAT BAND  ticks 75..120 (2.25s) sage stat band slides up
  //   HOLD       remainder
  const T_PROMPT  = 8;
  const T_BUILD   = 8;
  const T_STAGGER = 3;    // ~150ms between tile starts
  const T_DRAFT   = 6;    // ~300ms drafting per tile
  const T_SEND    = 3;    // ~150ms sending per tile

  const PROMPT_START    = 0;
  const BUILD_START     = T_PROMPT;
  const PLAN_START      = BUILD_START + T_BUILD;
  const ALL_SENT_AT     = PLAN_START + (queue.length - 1) * T_STAGGER + T_DRAFT + T_SEND;
  const INSPECTOR_OPEN  = 30;
  const INSPECTOR_CLOSE = 90;
  const STAT_BAND_START = 75;
  const TOTAL_TICKS     = 120;

  const t = Math.min(tickFast, TOTAL_TICKS + 6);

  const showPrompt    = t >= PROMPT_START;
  const showBuild     = t >= BUILD_START && t < PLAN_START;
  const showPlan      = t >= PLAN_START;
  const showInspector = t >= INSPECTOR_OPEN && t < INSPECTOR_CLOSE;
  const showStatBand  = t >= STAT_BAND_START;

  // Prompt text — the cursor "types" by revealing characters. Looks
  // fast (~3 chars/tick) but matches a realistic prompt.
  const promptTarget = "Send @SpringBuyerCredit to all warm buyers from 412 W 78th";
  const promptLen = t < PROMPT_START ? 0
    : t >= PROMPT_START + T_PROMPT ? promptTarget.length
    : Math.ceil((t - PROMPT_START) / T_PROMPT * promptTarget.length);
  const promptTyped = promptTarget.slice(0, promptLen);
  const promptDone  = t >= PROMPT_START + T_PROMPT;

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
              openhousecopilot.com /#/leads
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
              position: 'relative',
              overflow: 'hidden',
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

              {/* Ask-your-inbox prompt — the bulk send trigger. The
                  cursor types the prompt, then "BUILDING PLAN…", then
                  the recipient count. */}
              <div style={{
                padding: '10px 12px', borderRadius: 10,
                background: 'rgba(196,162,82,0.08)',
                border: '1px solid rgba(196,162,82,0.30)',
                display: 'flex', alignItems: 'center', gap: 8,
                opacity: showPrompt ? 1 : 0,
                transform: showPrompt ? 'translateY(0)' : 'translateY(-4px)',
                transition: 'opacity .25s ease, transform .25s ease',
                minHeight: 32,
              }}>
                <svg width="11" height="11" viewBox="0 0 24 24" fill="var(--gold)" stroke="none">
                  <path d="M12 2v6m0 8v6M2 12h6m8 0h6M5.6 5.6l3.5 3.5M14.9 14.9l3.5 3.5M5.6 18.4l3.5-3.5M14.9 9.1l3.5-3.5"/>
                </svg>
                <span style={{ fontSize: 11, color: 'var(--cream)', flex: 1, minWidth: 0 }}>
                  {promptTyped.split('@SpringBuyerCredit').map((part, i, arr) => (
                    <React.Fragment key={i}>
                      {part}
                      {i < arr.length - 1 && (
                        <span className="mono" style={{ color: 'var(--gold)', fontWeight: 600 }}>@SpringBuyerCredit</span>
                      )}
                    </React.Fragment>
                  ))}
                  {!promptDone && (
                    <span style={{
                      display: 'inline-block', width: 1.5, height: 11, marginLeft: 1,
                      background: 'var(--gold)', verticalAlign: '-1px',
                      animation: 'hdBlink 0.5s steps(2) infinite',
                    }} />
                  )}
                </span>
                {showBuild && (
                  <span style={{
                    display: 'inline-flex', alignItems: 'center', gap: 5,
                    fontSize: 9, color: 'var(--gold)', fontWeight: 600,
                    flexShrink: 0,
                  }}>
                    <span style={{
                      width: 8, height: 8, borderRadius: '50%',
                      background: 'var(--gold)',
                      animation: 'hdPulse 0.5s ease-in-out infinite',
                    }} />
                    <span className="mono" style={{ letterSpacing: '0.1em' }}>BUILDING PLAN…</span>
                  </span>
                )}
                {showPlan && (
                  <span className="mono" style={{
                    padding: '3px 8px', borderRadius: 999,
                    background: 'rgba(196,162,82,0.18)', color: 'var(--gold)',
                    fontSize: 8.5, letterSpacing: '0.12em', fontWeight: 600,
                    flexShrink: 0,
                  }}>
                    {queue.length} RECIPIENTS · PERSONALIZED
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
                transition: 'opacity .25s ease',
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
                    transition: 'width .15s ease, background .2s ease',
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

              {/* PERSONALIZATION INSPECTOR — slides in from the right
                  mid-cascade. Shows ONE expanded draft with quote chips
                  pulled directly from the open-house transcript, so the
                  visitor sees this isn't boilerplate. */}
              {showInspector && (
                <div style={{
                  position: 'absolute',
                  top: 12, right: 12, bottom: 12,
                  width: '56%',
                  background: 'linear-gradient(165deg, rgba(20,20,24,0.98), rgba(8,8,10,0.98))',
                  border: '1px solid rgba(196,162,82,0.32)',
                  borderRadius: 12,
                  boxShadow: '0 24px 48px rgba(0,0,0,0.5), 0 0 0 1px rgba(0,0,0,0.4)',
                  padding: '14px 16px',
                  display: 'flex', flexDirection: 'column', gap: 10,
                  animation: 'hdInspectorIn .35s cubic-bezier(.22,1,.36,1) both',
                }}>
                  <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                    <span style={{
                      width: 28, height: 28, borderRadius: '50%',
                      background: 'var(--gold-soft)', color: 'var(--gold)',
                      display: 'grid', placeItems: 'center',
                      fontFamily: 'var(--sans)', fontSize: 11, fontWeight: 600,
                    }}>S</span>
                    <div style={{ flex: 1, minWidth: 0 }}>
                      <div style={{ fontSize: 12, color: 'var(--cream)', fontWeight: 500 }}>Sarah Chen</div>
                      <div className="mono" style={{ fontSize: 8, color: 'var(--text-muted)', letterSpacing: '0.1em' }}>
                        DRAFT · PERSONALIZED FROM TRANSCRIPT
                      </div>
                    </div>
                    <span className="mono" style={{
                      padding: '2px 7px', borderRadius: 999,
                      background: 'rgba(134,166,128,0.16)',
                      color: 'var(--sage)',
                      fontSize: 8, letterSpacing: '0.12em', fontWeight: 600,
                    }}>
                      INTENT 94
                    </span>
                  </div>
                  <div style={{ display: 'flex', flexWrap: 'wrap', gap: 4 }}>
                    {['Pre-approved $1.4M', '60-day close', 'Loves the kitchen'].map(chip => (
                      <span key={chip} className="mono" style={{
                        padding: '3px 7px', borderRadius: 6,
                        background: 'rgba(196,162,82,0.12)',
                        color: 'var(--gold)',
                        border: '1px solid rgba(196,162,82,0.32)',
                        fontSize: 8.5, letterSpacing: '0.06em',
                      }}>
                        {chip}
                      </span>
                    ))}
                  </div>
                  <div style={{
                    flex: 1,
                    padding: '10px 12px', borderRadius: 8,
                    background: 'rgba(255,255,255,0.025)',
                    border: '1px solid var(--hairline)',
                    fontSize: 10.5, lineHeight: 1.55, color: 'var(--cream-dim)',
                    overflow: 'hidden',
                  }}>
                    <div style={{ color: 'var(--cream)', fontWeight: 500, marginBottom: 4 }}>
                      Hi Sarah —
                    </div>
                    Thanks for stopping by <span style={{ color: 'var(--gold)' }}>412 W 78th</span> on Saturday. You mentioned wanting to <span style={{ color: 'var(--gold)' }}>close in 60 days</span> and that you're <span style={{ color: 'var(--gold)' }}>pre-approved at $1.4M</span> — wanted to send the Spring Buyer Credit summary that could shave ~30bps off your rate if we move this quarter.
                    <div style={{ marginTop: 6, color: 'var(--cream-dim)' }}>
                      Also: happy to walk you through the basement on a private — you didn't get to see it yesterday.
                    </div>
                  </div>
                  <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
                    <span className="mono" style={{
                      padding: '3px 7px', borderRadius: 999,
                      background: 'rgba(134,166,128,0.14)',
                      color: 'var(--sage)',
                      fontSize: 8, letterSpacing: '0.12em', fontWeight: 600,
                    }}>
                      ✓ APPROVED
                    </span>
                    <span className="mono" style={{
                      padding: '3px 7px', borderRadius: 999,
                      background: 'rgba(255,255,255,0.04)',
                      color: 'var(--text-dim)',
                      fontSize: 8, letterSpacing: '0.12em',
                    }}>
                      SENDS TOMORROW · 9:14 AM
                    </span>
                  </div>
                </div>
              )}

              {/* STAT BAND — slides up from the bottom at the climax.
                  The "four hours → 2.4 seconds" comparison is the
                  payoff stat that justifies the whole product. */}
              {showStatBand && (
                <div style={{
                  position: 'absolute',
                  left: 12, right: 12, bottom: 12,
                  padding: '10px 14px', borderRadius: 10,
                  background: 'linear-gradient(95deg, rgba(134,166,128,0.18), rgba(134,166,128,0.06))',
                  border: '1px solid rgba(134,166,128,0.42)',
                  display: 'flex', alignItems: 'center', gap: 14,
                  animation: 'hdStatBandIn .4s cubic-bezier(.22,1,.36,1) both',
                  boxShadow: '0 12px 28px rgba(0,0,0,0.4)',
                }}>
                  <div style={{ display: 'flex', alignItems: 'baseline', gap: 6 }}>
                    <span className="serif" style={{ fontSize: 18, color: 'var(--text-muted)', textDecoration: 'line-through' }}>
                      4 hrs
                    </span>
                    <span className="serif" style={{ fontSize: 24, color: 'var(--sage)', fontWeight: 500, letterSpacing: '-0.02em' }}>
                      → {completedAt.toFixed(1)}s
                    </span>
                  </div>
                  <span style={{ width: 1, height: 26, background: 'rgba(134,166,128,0.28)' }} />
                  <div className="mono" style={{
                    fontSize: 9, color: 'var(--sage)',
                    letterSpacing: '0.12em', lineHeight: 1.5,
                  }}>
                    14 PERSONALIZED ·<br/>EVERY QUOTE FROM THE ROOM
                  </div>
                  <span style={{ flex: 1 }} />
                  <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="var(--sage)" strokeWidth="2">
                    <polyline points="20 6 9 17 4 12"/>
                  </svg>
                </div>
              )}
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

  // Per-device dwell times — tuned to each device's full animation
  // length plus a small carry-over for the climax hold. Quick cuts
  // inside each device do the heavy lifting; the dwell just frames
  // the beats so the carousel doesn't cut off the payoff moment.
  const dwellMs = [5500, 5400, 6200];

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
        @keyframes hdInspectorIn {
          0%   { transform: translateX(40px); opacity: 0; }
          100% { transform: translateX(0); opacity: 1; }
        }
        @keyframes hdStatBandIn {
          0%   { transform: translateY(60px); opacity: 0; }
          100% { transform: translateY(0); opacity: 1; }
        }
      `}</style>
    </div>
  );
};

Object.assign(window, { HeroDevices, HDIPhone, HDIPad, HDLaptop, VoiceWave });
