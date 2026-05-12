/* global React, AppShell, foyerApi, useFoyerData, fmtRelative, Icon, FoyerLoader */

// ============================================================
// Leads inbox — desktop port of the iPad lead-detail experience.
// Two-pane: searchable lead list (left) + lead detail with summary,
// drafted follow-up, scheduled card, sent-email history, notes,
// tasks, schedule + send actions (right).
// ============================================================

const C = window.ColorTokens = {
  bg: 'var(--bg-deep)',
  card: 'rgba(255,255,255,0.03)',
  card2: 'rgba(255,255,255,0.05)',
  hairline: 'var(--hairline)',
  gold: 'var(--gold)',
  goldSoft: 'var(--gold-soft)',
  cream: 'var(--cream)',
  creamDim: 'var(--cream-dim)',
  textDim: 'var(--text-dim)',
  textMuted: 'var(--text-muted)',
  terracotta: 'var(--terracotta)',
  sage: 'var(--sage)',
};

function statusPill(status) {
  const map = {
    drafted:  { label: 'Drafted',  color: C.gold },
    sent:     { label: 'Sent',     color: C.sage },
    replied:  { label: 'Replied',  color: C.sage },
    archived: { label: 'Archived', color: C.creamDim },
  };
  const v = map[status] || map.drafted;
  return (
    <span className="mono" style={{
      fontSize: 9, letterSpacing: '0.16em', textTransform: 'uppercase',
      color: v.color, padding: '3px 7px',
      borderRadius: 999, background: 'rgba(255,255,255,0.05)',
    }}>{v.label}</span>
  );
}

function tagColor(token) {
  switch ((token || '').toLowerCase()) {
    case 'buyer':   return C.gold;
    case 'seller':  return C.terracotta;
    case 'browser': return C.sage;
    default:        return C.creamDim;
  }
}

function SectionHeader({ title, count }) {
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginBottom: 14 }}>
      <div className="mono" style={{ fontSize: 10, letterSpacing: '0.18em', color: C.textDim, textTransform: 'uppercase', fontWeight: 600 }}>{title}</div>
      {!!count && count > 0 && (
        <div className="mono" style={{ fontSize: 10, color: C.creamDim, padding: '2px 8px', background: 'rgba(255,255,255,0.06)', borderRadius: 999 }}>{count}</div>
      )}
      <div style={{ height: 1, flex: 1, background: C.hairline }} />
    </div>
  );
}

// ------------------------------------------------------------
// Schedule send modal
// ------------------------------------------------------------

function ScheduleModal({ lead, onCancel, onScheduled }) {
  const session = lead._session;
  const v = lead;
  const draftInit = v.analysis?.follow_up_draft || '';
  const addr = session.address || 'the open house';
  const tomorrow9 = (() => {
    const d = new Date(); d.setDate(d.getDate() + 1); d.setHours(9, 0, 0, 0);
    return d;
  })();
  const toInput = (d) => {
    const pad = n => String(n).padStart(2, '0');
    return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
  };

  const [when, setWhen] = React.useState(() => toInput(tomorrow9));
  const [subject, setSubject] = React.useState(`Following up — ${addr}`);
  const [body, setBody] = React.useState(draftInit);
  const [submitting, setSubmitting] = React.useState(false);
  const [err, setErr] = React.useState(null);

  const setQuick = (offsetSec, absolute) => {
    let d;
    if (absolute) d = absolute;
    else { d = new Date(); d.setSeconds(d.getSeconds() + offsetSec); }
    setWhen(toInput(d));
  };
  const tomorrowAt = (h) => { const d = new Date(); d.setDate(d.getDate() + 1); d.setHours(h, 0, 0, 0); return d; };
  const nextMondayAt = (h) => {
    const d = new Date();
    for (let i = 1; i <= 8; i++) {
      d.setDate(d.getDate() + 1);
      if (d.getDay() === 1) break;
    }
    d.setHours(h, 0, 0, 0); return d;
  };

  const submit = async () => {
    setSubmitting(true); setErr(null);
    try {
      const sendAt = new Date(when).toISOString();
      const r = await foyerApi.post(`/sessions/${session.id}/visitors/schedule_email`, {
        name: v.visitor.name,
        speaker: v.visitor.speaker || '',
        send_at: sendAt,
        subject, body,
      });
      onScheduled(r.lead_state);
    } catch (e) {
      setErr(e.message || String(e));
    } finally {
      setSubmitting(false);
    }
  };

  const hasEmail = !!v.visitor.email;

  return (
    <div style={{
      position: 'fixed', inset: 0, background: 'rgba(0,0,0,0.65)', zIndex: 200,
      display: 'grid', placeItems: 'center', padding: 20,
    }} onClick={onCancel}>
      <div onClick={e => e.stopPropagation()} style={{
        width: 'min(640px, 100%)', maxHeight: '90vh', overflowY: 'auto',
        background: C.bg, border: `1px solid ${C.hairline}`, borderRadius: 16,
        boxShadow: '0 40px 100px -20px rgba(0,0,0,0.7)',
      }}>
        <div style={{ padding: '20px 24px', borderBottom: `1px solid ${C.hairline}`, display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
          <div style={{ fontSize: 17, fontWeight: 500, color: C.cream, letterSpacing: '-0.02em' }}>Schedule send</div>
          <button onClick={onCancel} style={{ background: 'transparent', border: 0, color: C.textDim, cursor: 'pointer' }}><Icon name="x" size={16} /></button>
        </div>

        <div style={{ padding: 24, display: 'flex', flexDirection: 'column', gap: 18 }}>
          <div>
            <div className="mono" style={{ fontSize: 9.5, letterSpacing: '0.16em', color: C.textDim, marginBottom: 6 }}>SEND TO</div>
            <div style={{ fontSize: 14, color: hasEmail ? C.cream : C.terracotta }}>{hasEmail ? v.visitor.email : 'No email on file'}</div>
          </div>

          <div>
            <div className="mono" style={{ fontSize: 9.5, letterSpacing: '0.16em', color: C.textDim, marginBottom: 6 }}>WHEN</div>
            <input type="datetime-local" value={when} onChange={e => setWhen(e.target.value)}
              style={{ width: '100%', background: 'rgba(255,255,255,0.05)', color: C.cream, border: `1px solid ${C.hairline}`, borderRadius: 8, padding: '10px 12px', fontFamily: 'var(--sans)', fontSize: 14, outline: 'none', colorScheme: 'dark' }} />
            <div style={{ display: 'flex', gap: 8, marginTop: 10, flexWrap: 'wrap' }}>
              <QuickChip label="In 1 hour" onClick={() => setQuick(3600)} />
              <QuickChip label="Tomorrow 9am" onClick={() => setQuick(0, tomorrowAt(9))} />
              <QuickChip label="Mon 9am" onClick={() => setQuick(0, nextMondayAt(9))} />
            </div>
          </div>

          <div>
            <div className="mono" style={{ fontSize: 9.5, letterSpacing: '0.16em', color: C.textDim, marginBottom: 6 }}>SUBJECT</div>
            <input value={subject} onChange={e => setSubject(e.target.value)}
              style={{ width: '100%', background: 'rgba(255,255,255,0.05)', color: C.cream, border: `1px solid ${C.hairline}`, borderRadius: 8, padding: '10px 12px', fontFamily: 'var(--sans)', fontSize: 14, outline: 'none' }} />
          </div>

          <div>
            <div className="mono" style={{ fontSize: 9.5, letterSpacing: '0.16em', color: C.textDim, marginBottom: 6 }}>EMAIL BODY</div>
            <textarea value={body} onChange={e => setBody(e.target.value)} rows={8}
              style={{ width: '100%', background: 'rgba(255,255,255,0.05)', color: C.cream, border: `1px solid ${C.hairline}`, borderRadius: 8, padding: 12, fontFamily: 'var(--sans)', fontSize: 14, lineHeight: 1.6, outline: 'none', resize: 'vertical' }} />
          </div>

          {err && <div style={{ fontSize: 12, color: C.terracotta }}>{err}</div>}
        </div>

        <div style={{ padding: '16px 24px', borderTop: `1px solid ${C.hairline}`, display: 'flex', gap: 10, justifyContent: 'flex-end' }}>
          <button onClick={onCancel} style={ghostBtnStyle}>Cancel</button>
          <button onClick={submit} disabled={submitting || !hasEmail} style={{ ...primaryBtnStyle, opacity: (submitting || !hasEmail) ? 0.5 : 1 }}>
            {submitting ? 'Scheduling…' : 'Schedule'}
          </button>
        </div>
      </div>
    </div>
  );
}

const ghostBtnStyle = {
  display: 'inline-flex', alignItems: 'center', gap: 6,
  padding: '8px 14px', fontFamily: 'var(--sans)', fontSize: 13, fontWeight: 500,
  background: 'rgba(255,255,255,0.05)', color: C.creamDim,
  border: 0, borderRadius: 999, cursor: 'pointer',
};
const primaryBtnStyle = {
  display: 'inline-flex', alignItems: 'center', gap: 6,
  padding: '10px 18px', fontFamily: 'var(--sans)', fontSize: 13, fontWeight: 600,
  background: C.gold, color: 'var(--bg-deep)',
  border: 0, borderRadius: 999, cursor: 'pointer',
};

function QuickChip({ label, onClick }) {
  return (
    <button onClick={onClick} style={{
      background: C.goldSoft, color: C.gold,
      border: 0, padding: '6px 12px', fontSize: 12, fontWeight: 500,
      borderRadius: 999, cursor: 'pointer',
      fontFamily: 'var(--sans)',
    }}>{label}</button>
  );
}

// ------------------------------------------------------------
// Lead detail panel
// ------------------------------------------------------------

function LeadDetail({ lead, onUpdate, onDelete, onShowToast }) {
  const session = lead._session;
  const v = lead;
  const ls = v.lead_state || {};
  const sched = ls.scheduled_email;
  const notes = ls.notes || [];
  const tasks = ls.tasks || [];
  const sentEmails = ls.sent_emails || [];

  const [sending, setSending] = React.useState(false);
  const [sendErr, setSendErr] = React.useState(null);
  const [scheduleOpen, setScheduleOpen] = React.useState(false);
  const [newNote, setNewNote] = React.useState('');
  const [newTask, setNewTask] = React.useState('');
  const [crmErr, setCrmErr] = React.useState(null);

  const currentDraft =
    ls.draft_override?.body || v.analysis?.follow_up_draft || '';
  const isOverridden = !!ls.draft_override?.body;
  const [editingDraft, setEditingDraft] = React.useState(false);
  const [draftBody, setDraftBody] = React.useState(currentDraft);
  const [draftSaving, setDraftSaving] = React.useState(false);

  // When the lead switches (different visitor selected), reset edit state so
  // we don't carry a stale buffer across leads.
  React.useEffect(() => {
    setEditingDraft(false);
    setDraftBody(currentDraft);
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [v.visitor.name, v.visitor.speaker, session.id]);

  const applyState = (state) => {
    if (state) onUpdate({ ...v, lead_state: state });
  };

  const saveDraft = async () => {
    if (!draftBody.trim()) { setCrmErr('Draft body can\'t be empty.'); return; }
    setDraftSaving(true); setCrmErr(null);
    try {
      const r = await foyerApi.patch(`/sessions/${session.id}/visitors/draft`, {
        name: v.visitor.name,
        speaker: v.visitor.speaker || '',
        body: draftBody.trim(),
      });
      applyState(r.lead_state);
      setEditingDraft(false);
    } catch (e) {
      setCrmErr(e.message || String(e));
    } finally {
      setDraftSaving(false);
    }
  };

  const resetDraft = async () => {
    setDraftSaving(true); setCrmErr(null);
    try {
      const r = await foyerApi.patch(`/sessions/${session.id}/visitors/draft`, {
        name: v.visitor.name,
        speaker: v.visitor.speaker || '',
        clear: true,
      });
      applyState(r.lead_state);
      setEditingDraft(false);
      // Re-seed buffer from the now-uneditied draft.
      setDraftBody(r.lead_state?.draft_override?.body || v.analysis?.follow_up_draft || '');
    } catch (e) {
      setCrmErr(e.message || String(e));
    } finally {
      setDraftSaving(false);
    }
  };

  const send = async () => {
    setSending(true); setSendErr(null);
    try {
      const r = await foyerApi.post(`/sessions/${session.id}/visitors/send_email`, {
        name: v.visitor.name,
        speaker: v.visitor.speaker || '',
      });
      applyState(r.lead_state);
      const first = (v.visitor.name || '').split(' ')[0] || v.visitor.name;
      onShowToast(`Email sent to ${first}`);
    } catch (e) {
      const msg = e.message || String(e);
      if (msg.includes('Gmail not connected')) {
        setSendErr('GMAIL_NOT_CONNECTED');
      } else if (msg.includes('No recipient')) {
        setSendErr('This lead has no email on file.');
      } else {
        setSendErr(msg);
      }
    } finally {
      setSending(false);
    }
  };

  const transition = async (status) => {
    try {
      const r = await foyerApi.post(`/sessions/${session.id}/visitors/state`, {
        name: v.visitor.name,
        speaker: v.visitor.speaker || '',
        status,
      });
      applyState(r);
    } catch (e) {
      setSendErr(e.message);
    }
  };

  const addNote = async () => {
    const body = newNote.trim();
    if (!body) return;
    try {
      const r = await foyerApi.post(`/sessions/${session.id}/visitors/notes`, {
        name: v.visitor.name, speaker: v.visitor.speaker || '', body,
      });
      applyState(r.lead_state);
      setNewNote('');
    } catch (e) { setCrmErr('Couldn\'t add note: ' + e.message); }
  };

  const deleteNote = async (id) => {
    try {
      const url = `/sessions/${session.id}/visitors/notes/${id}?name=${encodeURIComponent(v.visitor.name)}&speaker=${encodeURIComponent(v.visitor.speaker || '')}`;
      const res = await fetch(url, { method: 'DELETE', credentials: 'include' });
      if (!res.ok) throw new Error(`${res.status} ${res.statusText}`);
      const j = await res.json();
      applyState(j.lead_state);
    } catch (e) { setCrmErr('Couldn\'t delete note: ' + e.message); }
  };

  const addTask = async () => {
    const title = newTask.trim();
    if (!title) return;
    try {
      const r = await foyerApi.post(`/sessions/${session.id}/visitors/tasks`, {
        name: v.visitor.name, speaker: v.visitor.speaker || '', title,
      });
      applyState(r.lead_state);
      setNewTask('');
    } catch (e) { setCrmErr('Couldn\'t add task: ' + e.message); }
  };

  const toggleTask = async (task) => {
    try {
      const res = await fetch(`/sessions/${session.id}/visitors/tasks/${task.id}`, {
        method: 'PATCH', credentials: 'include',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ name: v.visitor.name, speaker: v.visitor.speaker || '', done: !task.done }),
      });
      if (!res.ok) throw new Error(`${res.status} ${res.statusText}`);
      const j = await res.json();
      applyState(j.lead_state);
    } catch (e) { setCrmErr('Couldn\'t update task: ' + e.message); }
  };

  const deleteTask = async (id) => {
    try {
      const url = `/sessions/${session.id}/visitors/tasks/${id}?name=${encodeURIComponent(v.visitor.name)}&speaker=${encodeURIComponent(v.visitor.speaker || '')}`;
      const res = await fetch(url, { method: 'DELETE', credentials: 'include' });
      if (!res.ok) throw new Error(`${res.status} ${res.statusText}`);
      const j = await res.json();
      applyState(j.lead_state);
    } catch (e) { setCrmErr('Couldn\'t delete task: ' + e.message); }
  };

  const cancelScheduled = async () => {
    try {
      const url = `/sessions/${session.id}/visitors/schedule_email?name=${encodeURIComponent(v.visitor.name)}&speaker=${encodeURIComponent(v.visitor.speaker || '')}`;
      const res = await fetch(url, { method: 'DELETE', credentials: 'include' });
      if (!res.ok) throw new Error(`${res.status} ${res.statusText}`);
      const j = await res.json();
      applyState(j.lead_state);
    } catch (e) { setCrmErr('Couldn\'t cancel: ' + e.message); }
  };

  const status = ls.status || 'drafted';
  const initials = (v.visitor.name || '')
    .split(' ').map(p => p[0]).filter(Boolean).slice(0, 2).join('').toUpperCase();

  return (
    <div style={{ maxWidth: 760, margin: '0 auto', padding: '56px 56px 120px', display: 'flex', flexDirection: 'column', gap: 36 }}>
      {/* Header */}
      <div style={{ display: 'flex', flexDirection: 'column', gap: 14 }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 16 }}>
          <div style={{ width: 64, height: 64, borderRadius: '50%', background: 'rgba(255,255,255,0.04)', display: 'grid', placeItems: 'center', color: C.gold, fontFamily: 'var(--sans)', fontWeight: 500, fontSize: 22 }}>{initials || '·'}</div>
          <div style={{ flex: 1 }}>
            <div style={{ fontSize: 30, fontWeight: 500, color: C.cream, letterSpacing: '-0.02em', lineHeight: 1.1 }}>{v.visitor.name}</div>
            <div style={{ display: 'flex', gap: 8, marginTop: 8, alignItems: 'center' }}>
              <span style={{ fontSize: 12, fontWeight: 500, color: tagColor(v.analysis?.tag), padding: '3px 9px', background: 'rgba(255,255,255,0.05)', borderRadius: 999 }}>{v.analysis?.tag}</span>
              <span style={{ fontSize: 12, color: C.creamDim }}>Score {v.analysis?.score}</span>
              {status !== 'drafted' && statusPill(status)}
            </div>
          </div>
          <button onClick={onDelete} title="Delete lead" style={{
            display: 'inline-flex', alignItems: 'center', gap: 6,
            padding: '8px 12px', borderRadius: 999,
            background: 'rgba(248,113,113,0.12)', color: C.terracotta, border: 0, cursor: 'pointer',
            fontFamily: 'var(--sans)', fontSize: 13, fontWeight: 500,
          }}>
            <Icon name="trash" size={12} />Delete
          </button>
        </div>
        <div style={{ display: 'flex', gap: 18, color: C.creamDim, fontSize: 13 }}>
          {v.visitor.email && (
            <span style={{ display: 'inline-flex', alignItems: 'center', gap: 6 }}>
              <Icon name="envelope" size={12} />{v.visitor.email}
            </span>
          )}
          {v.visitor.phone && (
            <span style={{ display: 'inline-flex', alignItems: 'center', gap: 6 }}>
              <Icon name="phone" size={12} />{v.visitor.phone}
            </span>
          )}
        </div>
      </div>

      {/* What we heard */}
      <div>
        <SectionHeader title="What we heard" />
        <div style={{ fontSize: 17, color: C.cream, lineHeight: 1.7 }}>{v.analysis?.summary}</div>
        {v.analysis?.signals?.length > 0 && (
          <div style={{ display: 'flex', flexWrap: 'wrap', gap: 6, marginTop: 14 }}>
            {v.analysis.signals.map((s, i) => (
              <span key={i} style={{ fontSize: 12, color: C.creamDim, padding: '5px 11px', background: 'rgba(255,255,255,0.04)', borderRadius: 999 }}>{s}</span>
            ))}
          </div>
        )}
      </div>

      {/* Drafted follow-up */}
      <div>
        <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginBottom: 14 }}>
          <div className="mono" style={{ fontSize: 10, letterSpacing: '0.18em', color: C.textDim, textTransform: 'uppercase', fontWeight: 600 }}>Drafted follow-up</div>
          {isOverridden && (
            <span className="mono" style={{
              fontSize: 9, letterSpacing: '0.12em', color: C.gold,
              padding: '2px 7px', background: C.goldSoft, borderRadius: 999,
            }}>EDITED</span>
          )}
          <div style={{ height: 1, flex: 1, background: C.hairline }} />
          {editingDraft ? (
            <>
              <button
                onClick={saveDraft}
                disabled={draftSaving || !draftBody.trim()}
                style={{ ...primaryBtnStyle, padding: '6px 14px', fontSize: 12, opacity: (draftSaving || !draftBody.trim()) ? 0.6 : 1 }}>
                {draftSaving ? 'Saving…' : 'Save draft'}
              </button>
              <button
                onClick={() => { setEditingDraft(false); setDraftBody(currentDraft); }}
                disabled={draftSaving}
                style={{ ...ghostBtnStyle, padding: '6px 12px', fontSize: 12 }}>
                Cancel
              </button>
            </>
          ) : (
            <>
              {isOverridden && (
                <button onClick={resetDraft} disabled={draftSaving} style={{ ...ghostBtnStyle, padding: '6px 12px', fontSize: 12 }}>
                  Reset to AI
                </button>
              )}
              <button
                onClick={() => { setDraftBody(currentDraft); setEditingDraft(true); }}
                style={{ ...ghostBtnStyle, padding: '6px 12px', fontSize: 12 }}>
                Edit
              </button>
            </>
          )}
        </div>
        {editingDraft ? (
          <textarea
            value={draftBody}
            onChange={e => setDraftBody(e.target.value)}
            rows={8}
            autoFocus
            style={{
              width: '100%', background: C.card2, color: C.cream,
              border: `1px solid ${C.gold}`, borderRadius: 14, padding: 18,
              fontFamily: 'var(--sans)', fontSize: 15, lineHeight: 1.7,
              outline: 'none', resize: 'vertical', boxSizing: 'border-box',
            }} />
        ) : (
          <div style={{ background: C.card2, padding: 20, borderRadius: 14, color: C.cream, fontSize: 15, lineHeight: 1.7, whiteSpace: 'pre-wrap' }}>
            {currentDraft}
          </div>
        )}
        <div style={{ display: 'flex', gap: 10, marginTop: 14, alignItems: 'center', flexWrap: 'wrap' }}>
          {status !== 'archived' && (
            <button onClick={() => transition('archived')} style={chipBtnStyle(C.creamDim)}>
              <Icon name="archive" size={11} />Archive
            </button>
          )}
          {status === 'archived' && (
            <button onClick={() => transition('drafted')} style={chipBtnStyle(C.gold)}>
              <Icon name="inbox" size={11} />Restore
            </button>
          )}
          {(status === 'drafted' || status === 'sent') && (
            <button onClick={() => transition('replied')} style={chipBtnStyle(C.sage)}>
              <Icon name="check" size={11} />Mark replied
            </button>
          )}
          <span style={{ flex: 1 }} />
          <button onClick={() => setScheduleOpen(true)} disabled={sending} style={ghostBtnStyle}>
            <Icon name="clock" size={12} />Schedule
          </button>
          <button onClick={send} disabled={sending} style={{ ...primaryBtnStyle, opacity: sending ? 0.6 : 1 }}>
            {sending
              ? <><span className="spinner" />Sending…</>
              : <><Icon name="send" size={12} />Send</>}
          </button>
        </div>
        {sendErr === 'GMAIL_NOT_CONNECTED' ? (
          <div style={{ display: 'flex', alignItems: 'center', gap: 12, marginTop: 12, padding: '12px 14px', background: 'rgba(248,113,113,0.08)', borderRadius: 10 }}>
            <Icon name="envelope" size={14} />
            <div style={{ flex: 1, fontSize: 13, color: C.cream }}>Gmail isn't connected yet.</div>
            <a href="#/profile" style={{ ...primaryBtnStyle, textDecoration: 'none', padding: '8px 14px', fontSize: 12 }}>Connect Gmail</a>
          </div>
        ) : sendErr ? (
          <div style={{ fontSize: 12, color: C.terracotta, marginTop: 10 }}>{sendErr}</div>
        ) : null}
      </div>

      {/* Scheduled card */}
      {sched && sched.send_at && (
        <div>
          <SectionHeader title="Scheduled" />
          <div style={{ background: C.goldSoft, padding: 16, borderRadius: 12, display: 'flex', alignItems: 'center', gap: 12 }}>
            <Icon name="clock" size={16} />
            <div style={{ flex: 1 }}>
              <div style={{ color: C.cream, fontSize: 14, fontWeight: 500 }}>Sending {fmtAbsolute(sched.send_at)}</div>
              {sched.error
                ? <div style={{ fontSize: 11, color: C.terracotta }}>Last attempt failed: {sched.error}</div>
                : <div style={{ fontSize: 12, color: C.textDim, marginTop: 2 }}>{sched.subject}</div>
              }
            </div>
            <button onClick={cancelScheduled} style={{ ...ghostBtnStyle, color: C.terracotta, background: 'rgba(248,113,113,0.12)' }}>Cancel</button>
          </div>
        </div>
      )}

      {/* Email history */}
      {sentEmails.length > 0 && (
        <div>
          <SectionHeader title="Email history" count={sentEmails.length} />
          <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
            {[...sentEmails].reverse().map(e => (
              <div key={e.id} style={{ background: C.card2, padding: 14, borderRadius: 12 }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 6 }}>
                  <Icon name="send" size={12} />
                  <div style={{ flex: 1, color: C.cream, fontSize: 13, fontWeight: 600, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{e.subject}</div>
                  {e.scheduled && <span className="mono" style={{ fontSize: 9, color: C.gold, padding: '2px 6px', background: C.goldSoft, borderRadius: 999, letterSpacing: '0.12em' }}>SCHEDULED</span>}
                  <span style={{ fontSize: 11, color: C.textDim }}>{fmtRelative(e.sent_at)}</span>
                </div>
                <div style={{ fontSize: 11, color: C.textDim, marginBottom: 6 }}>To {e.to}</div>
                <div style={{ fontSize: 13, color: C.creamDim, lineHeight: 1.6, whiteSpace: 'pre-wrap', display: '-webkit-box', WebkitLineClamp: 4, WebkitBoxOrient: 'vertical', overflow: 'hidden' }}>{e.body}</div>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Notes */}
      <div>
        <SectionHeader title="Notes" count={notes.length} />
        <div style={{ display: 'flex', alignItems: 'flex-start', gap: 8, marginBottom: 12 }}>
          <textarea
            value={newNote}
            onChange={e => setNewNote(e.target.value)}
            placeholder="Add a note — anything you want to remember…"
            rows={2}
            style={{ flex: 1, background: C.card2, color: C.cream, border: 0, borderRadius: 10, padding: 12, fontFamily: 'var(--sans)', fontSize: 14, lineHeight: 1.5, outline: 'none', resize: 'vertical' }} />
          <button onClick={addNote} disabled={!newNote.trim()} style={{
            width: 36, height: 36, borderRadius: '50%',
            background: C.gold, color: 'var(--bg-deep)', border: 0, cursor: 'pointer',
            display: 'grid', placeItems: 'center',
            opacity: newNote.trim() ? 1 : 0.4,
          }}><Icon name="plus" size={14} /></button>
        </div>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
          {[...notes].reverse().map(n => (
            <div key={n.id} style={{ display: 'flex', alignItems: 'flex-start', gap: 12, padding: '10px 14px', background: 'rgba(255,255,255,0.025)', borderRadius: 10 }}>
              <div style={{ width: 2, alignSelf: 'stretch', background: C.gold, borderRadius: 2 }} />
              <div style={{ flex: 1 }}>
                <div style={{ fontSize: 14, color: C.cream, lineHeight: 1.5, whiteSpace: 'pre-wrap' }}>{n.body}</div>
                <div style={{ fontSize: 11, color: C.textDim, marginTop: 4 }}>{fmtRelative(n.created_at)}</div>
              </div>
              <button onClick={() => deleteNote(n.id)} style={iconBtnStyle}><Icon name="x" size={11} /></button>
            </div>
          ))}
        </div>
      </div>

      {/* Tasks */}
      <div>
        <SectionHeader title="Tasks" count={tasks.filter(t => !t.done).length} />
        <form onSubmit={(e) => { e.preventDefault(); addTask(); }} style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 12 }}>
          <input
            value={newTask}
            onChange={e => setNewTask(e.target.value)}
            placeholder="Add a task — e.g. 'Send comps Thursday'"
            style={{ flex: 1, background: C.card2, color: C.cream, border: 0, borderRadius: 10, padding: '10px 14px', fontFamily: 'var(--sans)', fontSize: 14, outline: 'none' }} />
          <button type="submit" disabled={!newTask.trim()} style={{
            width: 36, height: 36, borderRadius: '50%',
            background: C.gold, color: 'var(--bg-deep)', border: 0, cursor: 'pointer',
            display: 'grid', placeItems: 'center',
            opacity: newTask.trim() ? 1 : 0.4,
          }}><Icon name="plus" size={14} /></button>
        </form>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
          {tasks.map(t => (
            <div key={t.id} style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '10px 14px', background: 'rgba(255,255,255,0.025)', borderRadius: 10 }}>
              <button onClick={() => toggleTask(t)} style={{ background: 'transparent', border: 0, padding: 0, cursor: 'pointer', display: 'inline-flex', color: t.done ? C.sage : C.textDim }}>
                <Icon name={t.done ? 'checkCircle' : 'circle'} size={18} active={t.done} />
              </button>
              <div style={{ flex: 1, fontSize: 14, color: t.done ? C.textDim : C.cream, textDecoration: t.done ? 'line-through' : 'none' }}>{t.title}</div>
              <button onClick={() => deleteTask(t.id)} style={iconBtnStyle}><Icon name="x" size={11} /></button>
            </div>
          ))}
        </div>
      </div>

      {crmErr && <div style={{ fontSize: 12, color: C.terracotta }}>{crmErr}</div>}

      {scheduleOpen && (
        <ScheduleModal
          lead={v}
          onCancel={() => setScheduleOpen(false)}
          onScheduled={(state) => { applyState(state); setScheduleOpen(false); onShowToast('Scheduled'); }}
        />
      )}
    </div>
  );
}

const chipBtnStyle = (color) => ({
  display: 'inline-flex', alignItems: 'center', gap: 6,
  padding: '8px 14px', fontFamily: 'var(--sans)', fontSize: 13, fontWeight: 500,
  background: 'rgba(255,255,255,0.05)', color,
  border: 0, borderRadius: 999, cursor: 'pointer',
});

const iconBtnStyle = {
  width: 24, height: 24, borderRadius: 6,
  background: 'transparent', border: 0, cursor: 'pointer',
  display: 'grid', placeItems: 'center', color: C.textDim,
};

function fmtAbsolute(iso) {
  if (!iso) return '';
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return '';
  return d.toLocaleString(undefined, { month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' });
}

// ------------------------------------------------------------
// Leads list (left rail)
// ------------------------------------------------------------

function LeadsList({ leads, activeId, onSelect, query, onQuery }) {
  return (
    <div style={{ display: 'flex', flexDirection: 'column', height: '100vh', position: 'sticky', top: 0 }}>
      <div style={{ padding: '24px 22px 12px', borderBottom: `1px solid ${C.hairline}` }}>
        <div style={{ fontSize: 24, fontWeight: 500, color: C.cream, letterSpacing: '-0.02em', marginBottom: 12 }}>Leads</div>
        <div style={{ display: 'flex', alignItems: 'center', gap: 8, background: 'rgba(255,255,255,0.04)', borderRadius: 8, padding: '8px 12px' }}>
          <Icon name="search" size={13} />
          <input value={query} onChange={e => onQuery(e.target.value)}
            placeholder="Search leads"
            style={{ flex: 1, background: 'transparent', color: C.cream, border: 0, outline: 'none', fontFamily: 'var(--sans)', fontSize: 13 }} />
        </div>
      </div>
      <div style={{ flex: 1, overflowY: 'auto', padding: '8px 0' }}>
        {leads.length === 0 && (
          <div style={{ padding: 22, color: C.textDim, fontSize: 13 }}>No leads yet.</div>
        )}
        {leads.map(l => {
          const isActive = activeId === l._id;
          const tag = l.analysis?.tag || '';
          const ls = l.lead_state || {};
          return (
            <div key={l._id} onClick={() => onSelect(l._id)} style={{
              cursor: 'pointer',
              padding: '12px 22px',
              borderLeft: `2px solid ${isActive ? C.gold : 'transparent'}`,
              background: isActive ? C.goldSoft : 'transparent',
            }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 4 }}>
                <div style={{ fontSize: 14, fontWeight: 500, color: isActive ? C.gold : C.cream, flex: 1, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{l.visitor.name}</div>
                {ls.status && ls.status !== 'drafted' && statusPill(ls.status)}
              </div>
              <div style={{ display: 'flex', alignItems: 'center', gap: 8, fontSize: 11, color: C.textDim }}>
                <span style={{ color: tagColor(tag) }}>{tag}</span>
                <span>·</span>
                <span style={{ flex: 1, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{l._session.address || 'No address'}</span>
                <span className="mono" style={{ fontSize: 9, letterSpacing: '0.1em' }}>{fmtRelative(l._session.created_at)}</span>
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
}

// ------------------------------------------------------------
// Top-level Leads page
// ------------------------------------------------------------

function LeadsInbox() {
  const { user, summaries, sessionsById, loading, error } = useFoyerData();
  const [allLeads, setAllLeads] = React.useState(null);
  const [activeId, setActiveId] = React.useState(null);
  const [query, setQuery] = React.useState('');
  const [pendingDelete, setPendingDelete] = React.useState(null);

  // Build the flat lead list every time the cache changes.
  React.useEffect(() => {
    if (loading) return;
    const rows = [];
    for (const session of Object.values(sessionsById)) {
      for (const v of (session.result?.visitors || [])) {
        const key = (v.visitor?.name || '') + ':' + (v.visitor?.speaker || '');
        rows.push({ ...v, _session: session, _id: `${session.id}:${key}` });
      }
    }
    rows.sort((a, b) => (b._session.created_at || '').localeCompare(a._session.created_at || ''));
    setAllLeads(rows);
    if (rows.length > 0 && !activeId) setActiveId(rows[0]._id);
  }, [loading, sessionsById]);

  const filtered = React.useMemo(() => {
    if (!allLeads) return [];
    const q = query.trim().toLowerCase();
    if (!q) return allLeads;
    return allLeads.filter(l =>
      (l.visitor.name || '').toLowerCase().includes(q) ||
      (l.visitor.email || '').toLowerCase().includes(q) ||
      (l.analysis?.summary || '').toLowerCase().includes(q) ||
      (l._session.address || '').toLowerCase().includes(q)
    );
  }, [allLeads, query]);

  const active = (filtered.find(l => l._id === activeId) || filtered[0]) || null;

  const onUpdate = (next) => {
    setAllLeads(curr => (curr || []).map(l => l._id === next._id ? next : l));
    // Push into the foyer cache so other pages see the update.
    const session = next._session;
    if (session?.result) {
      const visitors = session.result.visitors.map(v =>
        (v.visitor?.name === next.visitor.name && (v.visitor?.speaker || '') === (next.visitor?.speaker || ''))
          ? { ...v, lead_state: next.lead_state }
          : v
      );
      session.result.visitors = visitors;
    }
  };

  const onDelete = async () => {
    if (!active) return;
    if (!confirm(`Permanently remove ${active.visitor.name}? The session itself is kept.`)) return;
    setPendingDelete(active._id);
    try {
      const idx = (active._session.result.visitors || []).findIndex(
        v => v.visitor?.name === active.visitor.name && (v.visitor?.speaker || '') === (active.visitor?.speaker || '')
      );
      if (idx < 0) throw new Error('Could not locate this lead.');
      const res = await fetch(`/sessions/${active._session.id}/visitors/${idx}`, {
        method: 'DELETE', credentials: 'include',
      });
      if (!res.ok) throw new Error(`${res.status} ${res.statusText}`);
      setAllLeads(curr => (curr || []).filter(l => l._id !== active._id));
      setActiveId(null);
    } catch (e) {
      alert('Couldn\'t delete: ' + (e.message || e));
    } finally {
      setPendingDelete(null);
    }
  };

  return (
    <AppShell active="leads">
      <div style={{ display: 'grid', gridTemplateColumns: '320px 1fr', minHeight: '100vh', background: C.bg }}>
        <div style={{ borderRight: `1px solid ${C.hairline}`, background: 'rgba(0,0,0,0.25)' }}>
          <LeadsList
            leads={filtered}
            activeId={active?._id}
            onSelect={setActiveId}
            query={query}
            onQuery={setQuery}
          />
        </div>
        <div style={{ background: C.bg }}>
          {loading
            ? <div style={{ display: 'grid', placeItems: 'center', padding: 80 }}><FoyerLoader size={96} /></div>
            : error
              ? <div style={{ padding: 56, color: C.terracotta }}>{error}</div>
              : active
                ? <LeadDetail
                    key={active._id}
                    lead={active}
                    onUpdate={onUpdate}
                    onDelete={onDelete}
                    onShowToast={(m) => window.foyerToast?.(m)}
                  />
                : <div style={{ padding: 56, color: C.textDim }}>Pick a lead from the left.</div>
          }
        </div>
      </div>
    </AppShell>
  );
}

window.LeadsInbox = LeadsInbox;
