/* global React, Crest, AppShell, Tag, Eyebrow, Hairline, useFoyerData, foyerApi, foyerLoad, fmtRelative, fmtClock */

const SessionDetail = () => {
  const { user, summaries, sessionsById, loading, error } = useFoyerData();
  const [search, setSearch] = React.useState('');
  const [filter, setFilter] = React.useState('all');
  const [editing, setEditing] = React.useState(false);
  const [draft, setDraft] = React.useState('');
  // We can't change the AI's tag — keep filter local, drop the tag-swap UI.
  const [activeVisitorKey, setActiveVisitorKey] = React.useState(null);
  const [sending, setSending] = React.useState(false);
  const [savedDraftKey, setSavedDraftKey] = React.useState(null);
  // Visitor-swap crossfade. Mirrors the route-frame transition in index.html
  // so clicking a different lead in the rail doesn't snap-cut the detail
  // pane. Local because session-detail handles its own intra-page nav.
  const [visitorPhase, setVisitorPhase] = React.useState('idle');
  const [shownVisitorKey, setShownVisitorKey] = React.useState(null);

  // Audio playback
  const audioRef = React.useRef(null);
  const [isPlaying, setIsPlaying] = React.useState(false);
  const [audioTime, setAudioTime] = React.useState(0);
  const [audioDuration, setAudioDuration] = React.useState(0);

  // Pick which session to show. Set by the Sessions list / Dashboard via
  // window.foyerActiveSessionId before navigating here. If nothing's set
  // (e.g. agent typed /#/session directly), bounce to the list page so
  // they can pick rather than getting dropped into something arbitrary.
  const targetId = window.foyerActiveSessionId;
  React.useEffect(() => {
    if (!targetId) {
      window.foyerGo('#/sessions');
    }
  }, [targetId]);
  const session = targetId ? sessionsById[targetId] : null;
  const result = session?.result;
  const allVisitors = result?.visitors || [];

  // Initial active visitor: name passed from dashboard, else first by score.
  React.useEffect(() => {
    if (!result || allVisitors.length === 0) return;
    if (activeVisitorKey && allVisitors.some(v => keyOf(v) === activeVisitorKey)) return;
    const target = window.foyerActiveVisitorName
      ? allVisitors.find(v => v.visitor.name === window.foyerActiveVisitorName)
      : null;
    const initial = target || allVisitors.slice().sort((a, b) =>
      (b.analysis?.score || 0) - (a.analysis?.score || 0)
    )[0];
    setActiveVisitorKey(keyOf(initial));
    setShownVisitorKey(keyOf(initial));
    setDraft(initial?.analysis?.followUpDraft || initial?.analysis?.follow_up_draft || '');
  }, [result]);

  // Crossfade when activeVisitorKey changes: fade out the current detail
  // pane, swap to the new visitor, fade back in. ~380ms total.
  React.useEffect(() => {
    if (!activeVisitorKey) return;
    if (activeVisitorKey === shownVisitorKey) return;
    setVisitorPhase('out');
    const t1 = setTimeout(() => {
      setShownVisitorKey(activeVisitorKey);
      requestAnimationFrame(() => setVisitorPhase('in'));
    }, 180);
    return () => clearTimeout(t1);
  }, [activeVisitorKey]);
  React.useEffect(() => {
    if (visitorPhase !== 'in') return;
    const t = setTimeout(() => setVisitorPhase('idle'), 220);
    return () => clearTimeout(t);
  }, [visitorPhase]);

  // Search / tag-filter narrows the left rail.
  const filteredVisitors = allVisitors.filter(v => {
    const t = (v.analysis?.tag || '').toLowerCase();
    if (filter !== 'all' && t !== filter) return false;
    if (search && !v.visitor.name.toLowerCase().includes(search.toLowerCase())) return false;
    return true;
  });

  // For the left rail we want immediate feedback (highlight tracks the
  // clicked row right away). For the detail pane we render `shown` so the
  // fade-out shows the previous visitor's content until the swap.
  const v = allVisitors.find(x => keyOf(x) === shownVisitorKey)
         || allVisitors.find(x => keyOf(x) === activeVisitorKey);

  if (loading) {
    return <AppShell active="sessions"><Centered>LOADING SESSION…</Centered></AppShell>;
  }
  if (error) {
    return <AppShell active="sessions"><Centered>Couldn't load: {error}</Centered></AppShell>;
  }
  if (!targetId) {
    // Effect above is bouncing to /#/sessions — render an empty placeholder
    // so we don't flash the previous content while the route changes.
    return <AppShell active="sessions"><Centered>OPENING SESSIONS…</Centered></AppShell>;
  }
  if (!session || !result) {
    return <AppShell active="sessions"><Centered>This session is still processing — pull up the list and try again in a moment.</Centered></AppShell>;
  }
  if (!v) {
    return <AppShell active="sessions"><Centered>This session has no guests detected.</Centered></AppShell>;
  }

  const tag = (v.analysis?.tag || '').toLowerCase();
  const followUpDraft = v.analysis?.followUpDraft || v.analysis?.follow_up_draft || '';
  const utterances = result.utterances || [];
  const visitorSpeaker = v.visitor.speaker;
  const agentSpeaker = result.agent_speaker;
  const visitorTurns = utterances.filter(u =>
    u.speaker === visitorSpeaker || u.speaker === agentSpeaker
  );

  return (
    <AppShell active="sessions">
      <div data-screen-label="Session detail" style={{ display: 'grid', gridTemplateColumns: '320px 1fr', minHeight: '100vh' }}>

        {/* "Back to all sessions" + lead list (left rail of the inner pane) */}
        <section style={{ borderRight: '1px solid var(--hairline)', display: 'flex', flexDirection: 'column' }}>
          <div style={{ padding: '24px 28px 0' }}>
            <a href="#/sessions" className="serif-it" style={{ fontSize: 13, color: 'var(--gold)', textDecoration: 'none' }}>
              ← All sessions
            </a>
          </div>
          {/* LEAD LIST */}
          <div style={{ display: 'flex', flexDirection: 'column', flex: 1 }}>
        <div style={{ padding: '32px 28px 0' }}>
          <Eyebrow>Session</Eyebrow>
          <div className="serif" style={{ fontSize: 24, color: 'var(--cream)', marginTop: 8, lineHeight: 1.1 }}>
            {session.address || 'Untitled session'}<br/>
            <span className="serif-it" style={{ color: 'var(--gold)', fontSize: 16 }}>
              {new Date(session.created_at).toLocaleDateString(undefined, { weekday: 'long', month: 'long', day: 'numeric' })}
            </span>
          </div>
          <div className="mono" style={{ fontSize: 10, color: 'var(--text-muted)', marginTop: 8, letterSpacing: '0.14em' }}>
            {allVisitors.length} GUEST{allVisitors.length === 1 ? '' : 'S'} · {(session.kind || 'recorded').toUpperCase()}
          </div>

          {/* search */}
          <div style={{ marginTop: 24, position: 'relative' }}>
            <input
              value={search}
              onChange={e => setSearch(e.target.value)}
              placeholder="Search guests…"
              style={{
                width: '100%', background: 'transparent', border: 0, borderBottom: '1px solid var(--hairline)',
                padding: '10px 0', color: 'var(--cream)', fontSize: 13, fontFamily: 'var(--sans)',
                outline: 'none',
              }}
            />
          </div>

          {/* filter chips */}
          <div style={{ marginTop: 18, display: 'flex', gap: 6, flexWrap: 'wrap' }}>
            {['all', 'buyer', 'seller', 'browser'].map(t => (
              <button key={t}
                      onClick={() => setFilter(t)}
                      className={'mono chip' + (filter === t ? ' is-active' : '')}
                      style={{
                padding: '4px 12px',
                background: filter === t ? 'var(--gold-soft)' : 'transparent',
                color: filter === t ? 'var(--gold)' : 'var(--text-dim)',
                border: '1px solid ' + (filter === t ? 'var(--gold)' : 'var(--hairline)'),
                fontSize: 10, letterSpacing: '0.12em', textTransform: 'uppercase', cursor: 'pointer',
                borderRadius: 999,
              }}>{t}</button>
            ))}
          </div>
        </div>

        <div style={{ marginTop: 24, flex: 1, overflowY: 'auto', padding: '0 0 28px' }}>
          {filteredVisitors.map(vis => {
            const isActive = keyOf(vis) === activeVisitorKey;
            const visTag = (vis.analysis?.tag || '').toLowerCase();
            const visDraft = vis.analysis?.followUpDraft || vis.analysis?.follow_up_draft || '';
            return (
              <div key={keyOf(vis)}
                   className={'session-row' + (isActive ? ' is-active' : '')}
                   onClick={() => { setActiveVisitorKey(keyOf(vis)); setDraft(visDraft); setEditing(false); }}
                   style={{
                     padding: '16px 28px',
                     borderLeft: isActive ? '2px solid var(--gold)' : '2px solid transparent',
                     background: isActive ? 'var(--gold-soft)' : 'transparent',
                     borderBottom: '1px solid var(--hairline)',
                     borderRadius: 0,
                     margin: 0,
                   }}>
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                  <span className="serif" style={{ fontSize: 18, color: isActive ? 'var(--gold)' : 'var(--cream)' }}>{vis.visitor.name}</span>
                  <Tag kind={visTag}>{vis.analysis?.score ?? '—'}</Tag>
                </div>
                <div className="mono" style={{ fontSize: 10, color: 'var(--text-muted)', marginTop: 4, letterSpacing: '0.1em' }}>
                  {(vis.analysis?.tag || '').toUpperCase()} · SPOKE {vis.analysis?.wordsSpoken ?? vis.analysis?.words_spoken ?? 0}W
                </div>
                <div style={{ fontSize: 12, color: 'var(--text-dim)', marginTop: 8, lineHeight: 1.5, overflow: 'hidden', display: '-webkit-box', WebkitLineClamp: 2, WebkitBoxOrient: 'vertical' }}>
                  {vis.analysis?.summary}
                </div>
              </div>
            );
          })}
        </div>
        </div>
      </section>

      {/* DETAIL PANE */}
      <section style={{ overflowY: 'auto', position: 'relative' }}>
        {session.kind !== 'manual' && (
          <AudioBar
            sessionId={session.id}
            audioRef={audioRef}
            isPlaying={isPlaying}
            setIsPlaying={setIsPlaying}
            time={audioTime}
            setTime={setAudioTime}
            duration={audioDuration}
            setDuration={setAudioDuration}
          />
        )}
        <div className="visitor-frame" data-phase={visitorPhase} style={{ padding: '32px 48px 60px' }}>

          {/* header */}
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start' }}>
            <div>
              <div className="eyebrow">{(v.analysis?.tag || '').toUpperCase()} · {leadStateLabel(v.lead_state)}</div>
              <h1 className="serif" style={{ fontSize: 56, margin: '14px 0 0', color: 'var(--cream)', lineHeight: 1 }}>{v.visitor.name}</h1>
              <div className="mono" style={{ fontSize: 11, color: 'var(--text-muted)', marginTop: 10, letterSpacing: '0.14em' }}>
                {(v.visitor.email || '—').toUpperCase()}{v.visitor.phone ? ` · ${v.visitor.phone}` : ''}
              </div>
            </div>
            <div style={{ display: 'flex', gap: 10, alignItems: 'center' }}>
              <span className="serif" style={{ fontSize: 56, lineHeight: 1, color: 'var(--gold)' }}>
                {v.analysis?.score ?? '—'}<span className="serif-it" style={{ fontSize: 24, color: 'var(--text-dim)' }}>/100</span>
              </span>
            </div>
          </div>

          {/* summary */}
          <div style={{ marginTop: 36 }}>
            <Eyebrow>The read</Eyebrow>
            <p className="serif" style={{ fontSize: 22, lineHeight: 1.5, marginTop: 16, color: 'var(--cream)', fontWeight: 400, letterSpacing: '-0.005em' }}>
              {v.analysis?.summary}
            </p>
            {v.analysis?.tagReason || v.analysis?.tag_reason ? (
              <p style={{ marginTop: 12, fontSize: 13, color: 'var(--text-dim)', lineHeight: 1.6 }}>
                <span className="serif-it" style={{ color: 'var(--gold)' }}>Why {v.analysis?.tag}:</span> {v.analysis?.tagReason || v.analysis?.tag_reason}
              </p>
            ) : null}
          </div>

          {/* signals */}
          {Array.isArray(v.analysis?.signals) && v.analysis.signals.length > 0 && (
            <div style={{ marginTop: 32, display: 'grid', gridTemplateColumns: 'repeat(2, 1fr)', gap: 1, background: 'var(--hairline)', border: '1px solid var(--hairline)' }}>
              {v.analysis.signals.map((s, i) => (
                <div key={s} style={{ background: 'var(--bg-card)', padding: '18px 22px' }}>
                  <div className="mono" style={{ fontSize: 10, color: 'var(--gold)', letterSpacing: '0.14em', textTransform: 'uppercase' }}>Signal {String(i + 1).padStart(2, '0')}</div>
                  <div className="serif" style={{ fontSize: 20, color: 'var(--cream)', marginTop: 6 }}>{s}</div>
                </div>
              ))}
            </div>
          )}

          {/* transcript */}
          {visitorTurns.length > 0 && (
            <div style={{ marginTop: 56 }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline' }}>
                <Eyebrow>Conversation</Eyebrow>
                <span className="mono" style={{ fontSize: 11, color: 'var(--text-muted)', letterSpacing: '0.14em' }}>
                  YOU + {v.visitor.name.toUpperCase()} · {visitorTurns.length} TURNS
                </span>
              </div>
              <div style={{ marginTop: 20 }}>
                {visitorTurns.map((line, i) => {
                  const isAgent = line.speaker === agentSpeaker;
                  const playheadMs = audioTime * 1000;
                  const isActive = isPlaying
                    && line.start_ms != null && line.end_ms != null
                    && playheadMs >= line.start_ms && playheadMs <= line.end_ms;
                  return (
                    <div
                      key={i}
                      className={'turn-row' + (isActive ? ' is-active' : '')}
                      onClick={() => {
                        const a = audioRef.current;
                        if (a) {
                          a.currentTime = Math.max(0, (line.start_ms || 0) / 1000);
                          if (!isPlaying) a.play().catch(() => {});
                        }
                      }}
                      style={{ display: 'grid', gridTemplateColumns: '60px 1fr', gap: 16, padding: '12px 0', cursor: 'pointer' }}
                    >
                      <div className="mono" style={{ fontSize: 10, color: isActive ? 'var(--gold)' : 'var(--text-muted)', letterSpacing: '0.1em', paddingTop: 4 }}>
                        {fmtTimestamp(line.start_ms || 0)}
                      </div>
                      <div>
                        <div className="eyebrow" style={{ color: isAgent ? 'var(--text-muted)' : 'var(--gold)' }}>
                          {isAgent ? `${(user?.name || 'You').split(' ')[0]} (you)` : v.visitor.name}
                        </div>
                        <div style={{ marginTop: 4, fontSize: 14, lineHeight: 1.6, color: isAgent ? 'var(--text-dim)' : 'var(--cream)' }}>
                          {line.text}
                        </div>
                      </div>
                    </div>
                  );
                })}
              </div>
            </div>
          )}

          {/* follow-up */}
          <div style={{ marginTop: 64, padding: 36, border: '1px solid var(--border-strong)', background: 'var(--bg-card)' }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline' }}>
              <Eyebrow>Drafted follow-up</Eyebrow>
              <span className="mono" style={{ fontSize: 10, color: 'var(--gold)', letterSpacing: '0.14em' }}>
                {leadStateLabel(v.lead_state)}
              </span>
            </div>
            <div className="mono" style={{ fontSize: 11, color: 'var(--text-muted)', marginTop: 14, letterSpacing: '0.06em' }}>
              <span style={{ color: 'var(--cream)' }}>To:</span> {v.visitor.email || '—'}<br/>
              <span style={{ color: 'var(--cream)' }}>Subject:</span> Great meeting you{session.address ? ` at ${session.address}` : ''}
            </div>
            <Hairline style={{ margin: '20px 0' }}/>
            {editing ? (
              <textarea
                value={draft}
                onChange={e => setDraft(e.target.value)}
                style={{
                  width: '100%', minHeight: 280,
                  background: 'var(--bg-deep)', border: '1px solid var(--gold)',
                  padding: 18, fontFamily: 'var(--sans)', fontSize: 14, lineHeight: 1.7,
                  color: 'var(--cream)', resize: 'vertical', outline: 'none',
                }}
              />
            ) : (
              <div className="serif" style={{ fontSize: 17, lineHeight: 1.7, color: 'var(--cream-dim)', whiteSpace: 'pre-wrap', fontWeight: 400 }}>
                {draft || followUpDraft}
              </div>
            )}

            <div style={{ marginTop: 28, display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
              <div style={{ fontSize: 12, color: 'var(--text-dim)' }}>
                {savedDraftKey === keyOf(v) && <span className="serif-it" style={{ color: 'var(--gold)' }}>Saved locally · open Mail to send.</span>}
              </div>
              <div style={{ display: 'flex', gap: 10 }}>
                <button className="btn" onClick={() => {
                  if (editing) setSavedDraftKey(keyOf(v));
                  setEditing(e => !e);
                }}>{editing ? 'Done' : 'Edit'}</button>
                <button className="btn" onClick={() => snooze(v, 3, session.id)}>Snooze 3 days</button>
                <button
                  className="btn btn-primary"
                  disabled={sending}
                  onClick={async () => {
                    setSending(true);
                    try {
                      const subject = encodeURIComponent(`Great meeting you${session.address ? ` at ${session.address}` : ''}`);
                      const body = encodeURIComponent(draft || followUpDraft);
                      const to = encodeURIComponent(v.visitor.email || '');
                      // Open the user's mail client with everything prefilled.
                      if (v.visitor.email) {
                        window.open(`mailto:${to}?subject=${subject}&body=${body}`, '_self');
                      } else {
                        alert('No email on file for this lead.');
                      }
                      // Mark as sent on the backend regardless — same UX as iOS.
                      await foyerApi.post(`/sessions/${session.id}/visitors/state`, {
                        name: v.visitor.name,
                        speaker: v.visitor.speaker || '',
                        status: 'sent',
                      });
                      await foyerLoad({ force: true });
                    } catch (e) {
                      alert('Could not mark as sent: ' + (e.message || e));
                    } finally {
                      setSending(false);
                    }
                  }}
                >{sending ? 'Sending…' : 'Send via Mail'}</button>
              </div>
            </div>
          </div>

          {/* footer actions */}
          <div style={{ marginTop: 32, display: 'flex', gap: 24, justifyContent: 'space-between', alignItems: 'center', paddingBottom: 20 }}>
            <div className="serif-it" style={{ fontSize: 13, color: 'var(--text-muted)' }}>
              Captured {fmtRelative(session.created_at)}{session.completed_at ? ` · processed ${fmtRelative(session.completed_at)}` : ''}.
            </div>
            <div style={{ display: 'flex', gap: 12 }}>
              <button className="btn" onClick={() => markState(v, 'archived', session.id)}>Archive</button>
              <button className="btn" onClick={() => markState(v, 'replied', session.id)}>Mark replied</button>
            </div>
          </div>
        </div>
      </section>
    </div>
    </AppShell>
  );
};

function keyOf(v) {
  return (v?.visitor?.name || '') + ':' + (v?.visitor?.speaker || '');
}

function leadStateLabel(s) {
  if (!s) return 'NEEDS DRAFT';
  if (s.snoozed_until) {
    const t = Date.parse(s.snoozed_until);
    if (!Number.isNaN(t) && t > Date.now()) return `SNOOZED · ${new Date(t).toLocaleDateString(undefined, { month: 'short', day: 'numeric' }).toUpperCase()}`;
  }
  switch (s.status) {
    case 'drafted':  return 'DRAFT';
    case 'sent':     return s.sent_at ? `SENT · ${fmtRelative(s.sent_at)}` : 'SENT';
    case 'replied':  return 'REPLIED';
    case 'archived': return 'ARCHIVED';
    default:         return (s.status || '').toUpperCase();
  }
}

function fmtTimestamp(ms) {
  const total = Math.max(0, Math.floor(ms / 1000));
  const m = Math.floor(total / 60);
  const s = total % 60;
  return `${m}:${String(s).padStart(2, '0')}`;
}

async function markState(v, status, sessionId) {
  try {
    await foyerApi.post(`/sessions/${sessionId}/visitors/state`, {
      name: v.visitor.name,
      speaker: v.visitor.speaker || '',
      status,
    });
    await foyerLoad({ force: true });
  } catch (e) {
    alert('Could not update state: ' + (e.message || e));
  }
}

async function snooze(v, days, sessionId) {
  const until = new Date(Date.now() + days * 24 * 60 * 60 * 1000).toISOString();
  try {
    await foyerApi.post(`/sessions/${sessionId}/visitors/state`, {
      name: v.visitor.name,
      speaker: v.visitor.speaker || '',
      status: v.lead_state?.status || 'sent',
      snoozed_until: until,
    });
    await foyerLoad({ force: true });
  } catch (e) {
    alert('Could not snooze: ' + (e.message || e));
  }
}

function Centered({ children }) {
  return (
    <div style={{ minHeight: '100vh', display: 'grid', placeItems: 'center', color: 'var(--text-muted)', fontFamily: 'var(--mono)', letterSpacing: '0.14em', fontSize: 12 }}>
      {children}
    </div>
  );
}

// Sticky audio bar pinned to the top of the detail pane. Streams from
// /sessions/{id}/audio — the same-origin <audio> element automatically
// sends the fb_session cookie so it's allowed past the auth gate.
function AudioBar({ sessionId, audioRef, isPlaying, setIsPlaying, time, setTime, duration, setDuration }) {
  const trackRef = React.useRef(null);
  const [available, setAvailable] = React.useState(true);

  // Reset on session change so we don't carry one recording's playhead
  // into a different session.
  React.useEffect(() => {
    setIsPlaying(false);
    setTime(0);
    setDuration(0);
    setAvailable(true);
  }, [sessionId]);

  const onPlayPause = () => {
    const a = audioRef.current;
    if (!a) return;
    if (a.paused) a.play().catch(() => {});
    else a.pause();
  };

  const onSeek = (e) => {
    const a = audioRef.current;
    const track = trackRef.current;
    if (!a || !track || !duration) return;
    const rect = track.getBoundingClientRect();
    const ratio = Math.max(0, Math.min(1, (e.clientX - rect.left) / rect.width));
    a.currentTime = ratio * duration;
    setTime(ratio * duration);
  };

  const pct = duration > 0 ? Math.min(100, (time / duration) * 100) : 0;

  return (
    <div className="audio-bar">
      <button className="audio-play" onClick={onPlayPause} disabled={!available} title={isPlaying ? 'Pause' : 'Play'}>
        {isPlaying ? '❚❚' : '▶'}
      </button>
      <span className="audio-time">{fmtClockSecs(time)}</span>
      <div className="audio-track" ref={trackRef} onClick={onSeek}>
        <div className="audio-track-bg"></div>
        <div className="audio-track-fill" style={{ width: pct + '%' }}></div>
        <div className="audio-track-knob" style={{ left: pct + '%', top: '50%', marginTop: -5 }}></div>
      </div>
      <span className="audio-time" style={{ color: 'var(--text-muted)' }}>
        {available ? fmtClockSecs(duration) : '—'}
      </span>
      <audio
        ref={audioRef}
        src={`/sessions/${sessionId}/audio`}
        preload="metadata"
        onLoadedMetadata={(e) => setDuration(e.target.duration || 0)}
        onTimeUpdate={(e) => setTime(e.target.currentTime || 0)}
        onPlay={() => setIsPlaying(true)}
        onPause={() => setIsPlaying(false)}
        onError={() => setAvailable(false)}
        style={{ display: 'none' }}
      />
    </div>
  );
}

function fmtClockSecs(secs) {
  if (!Number.isFinite(secs) || secs < 0) return '0:00';
  const m = Math.floor(secs / 60);
  const s = Math.floor(secs % 60);
  return `${m}:${String(s).padStart(2, '0')}`;
}

Object.assign(window, { SessionDetail });
