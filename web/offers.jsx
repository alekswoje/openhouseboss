/* global React, AppShell, foyerApi, Icon, FoyerLoader */

// ============================================================
// Offers — CRUD library of marketing offers / campaigns.
//
// Mirrors the iPad Offers tab exactly: a list of cards with name +
// body preview, an enabled toggle per offer, "New offer" pill at the
// top, and an inline editor sheet for creating / editing.
//
// Offers participate in the AI follow-up pipeline two ways:
//   1. Free-form @mention in any prompt ("send the @Spring Buyer
//      credit blast to all buyers") — the AI loads the offer body and
//      uses it as context.
//   2. Default library access — even WITHOUT an explicit @mention, the
//      AI may pull from the enabled offer pool when picking the best
//      angle for a lead. Disabled offers are excluded.
//
// Backend: /me/offers (GET/POST), /me/offers/{id} (PATCH/DELETE),
// /me/offers/{id}/enabled (POST). Same wire as the iPad app — both
// surfaces see the same library because it's stored server-side.
// ============================================================

function OffersPage() {
  const [offers, setOffers] = React.useState([]);
  const [loading, setLoading] = React.useState(true);
  const [error, setError] = React.useState(null);
  // editing is one of:
  //   null      — no sheet open
  //   {}        — sheet open for a new offer
  //   { id, … } — sheet open for editing an existing offer
  const [editing, setEditing] = React.useState(null);
  const [pendingDelete, setPendingDelete] = React.useState(null);

  const refresh = React.useCallback(async () => {
    setLoading(true);
    try {
      const r = await foyerApi.get('/me/offers');
      setOffers(r.offers || []);
      setError(null);
    } catch (e) {
      setError(e.message || String(e));
    } finally {
      setLoading(false);
    }
  }, []);

  React.useEffect(() => { refresh(); }, [refresh]);

  const toggleEnabled = async (offer) => {
    // Optimistic flip so the toggle feels instant. Revert on error.
    const next = !offer.enabled;
    setOffers(curr => curr.map(o => o.id === offer.id ? { ...o, enabled: next } : o));
    try {
      await foyerApi.post(`/me/offers/${offer.id}/enabled`, { enabled: next });
    } catch (e) {
      setOffers(curr => curr.map(o => o.id === offer.id ? { ...o, enabled: !next } : o));
      window.foyerToast({ message: 'Could not save toggle: ' + (e.message || e), kind: 'error' });
    }
  };

  const onSaved = (offer) => {
    setOffers(curr => {
      const idx = curr.findIndex(o => o.id === offer.id);
      if (idx === -1) return [...curr, offer];
      const next = [...curr];
      next[idx] = offer;
      return next;
    });
    setEditing(null);
    window.foyerToast('Offer saved');
  };

  const performDelete = async (offer) => {
    setPendingDelete(null);
    try {
      await foyerApi.del(`/me/offers/${offer.id}`);
      setOffers(curr => curr.filter(o => o.id !== offer.id));
      window.foyerToast('Offer deleted');
    } catch (e) {
      window.foyerToast({ message: 'Delete failed: ' + (e.message || e), kind: 'error' });
    }
  };

  return (
    <AppShell active="offers">
      <div style={{ padding: '40px 44px 80px', maxWidth: 960, margin: '0 auto' }}>
        {/* Header */}
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-end' }}>
          <div>
            <h1 className="serif" style={{ fontSize: 44, margin: 0, color: 'var(--cream)', letterSpacing: '-0.02em' }}>
              Offers
            </h1>
            <p style={{ marginTop: 10, color: 'var(--text-dim)', fontSize: 14, maxWidth: 540, lineHeight: 1.55 }}>
              Marketing offers and campaigns the AI can reference. Mention
              one in any prompt with <span className="mono" style={{ color: 'var(--gold)' }}>@name</span>, or leave it
              enabled and the AI will pull from the library on its own.
            </p>
          </div>
          <button
            onClick={() => setEditing({})}
            className="btn btn-primary"
            style={{ padding: '11px 18px', fontSize: 13 }}>
            <Icon name="plus" size={14} />
            <span style={{ marginLeft: 6 }}>New offer</span>
          </button>
        </div>

        {/* Body */}
        <div style={{ marginTop: 36 }}>
          {loading && offers.length === 0 ? (
            <div style={{ padding: '60px 0', display: 'flex', justifyContent: 'center' }}>
              <FoyerLoader size={72} label="Loading offers…" />
            </div>
          ) : error ? (
            <div style={{
              padding: 16, borderRadius: 10,
              border: '1px solid var(--terracotta)',
              color: 'var(--terracotta)', fontSize: 13,
            }}>
              Couldn't load offers: {error}
            </div>
          ) : offers.length === 0 ? (
            <EmptyOffers onCreate={() => setEditing({})} />
          ) : (
            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(280px, 1fr))', gap: 14 }}>
              {offers.map(offer => (
                <OfferCard
                  key={offer.id}
                  offer={offer}
                  onEdit={() => setEditing(offer)}
                  onToggle={() => toggleEnabled(offer)}
                  onDelete={() => setPendingDelete(offer)}
                />
              ))}
            </div>
          )}
        </div>
      </div>

      {editing && (
        <OfferEditor
          existing={editing.id ? editing : null}
          onCancel={() => setEditing(null)}
          onSaved={onSaved}
        />
      )}
      {pendingDelete && (
        <DeleteConfirm
          offer={pendingDelete}
          onCancel={() => setPendingDelete(null)}
          onConfirm={() => performDelete(pendingDelete)}
        />
      )}
    </AppShell>
  );
}

function EmptyOffers({ onCreate }) {
  return (
    <div style={{
      padding: '56px 28px',
      textAlign: 'center',
      border: '1px dashed var(--hairline)',
      borderRadius: 14,
      background: 'rgba(255,255,255,0.02)',
    }}>
      <div style={{
        margin: '0 auto', width: 56, height: 56, borderRadius: 14,
        background: 'var(--gold-soft)', color: 'var(--gold)',
        display: 'grid', placeItems: 'center',
      }}>
        <Icon name="tag" size={22} />
      </div>
      <div className="serif" style={{ marginTop: 18, fontSize: 22, color: 'var(--cream)' }}>
        No offers yet
      </div>
      <p style={{ marginTop: 10, color: 'var(--text-dim)', fontSize: 13, lineHeight: 1.6, maxWidth: 420, marginLeft: 'auto', marginRight: 'auto' }}>
        Create your first campaign — Open House Copilot can drop it into follow-ups
        when the lead is a fit, or you can call it out by name in a
        prompt.
      </p>
      <button
        onClick={onCreate}
        className="btn btn-primary"
        style={{ marginTop: 18, padding: '11px 18px', fontSize: 13 }}>
        <Icon name="plus" size={14} />
        <span style={{ marginLeft: 6 }}>New offer</span>
      </button>
    </div>
  );
}

function OfferCard({ offer, onEdit, onToggle, onDelete }) {
  return (
    <div
      onClick={onEdit}
      className="lead-row"
      style={{
        background: 'rgba(255,255,255,0.04)',
        border: '1px solid var(--hairline)',
        borderRadius: 14,
        padding: '18px 18px 14px',
        cursor: 'pointer',
        display: 'flex', flexDirection: 'column',
        gap: 10,
        minHeight: 168,
      }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', gap: 10 }}>
        <div style={{ flex: 1 }}>
          <div style={{
            display: 'inline-block',
            fontSize: 10, letterSpacing: '0.16em', fontFamily: 'var(--mono)',
            color: offer.enabled ? 'var(--gold)' : 'var(--text-muted)',
            marginBottom: 6,
          }}>
            {offer.enabled ? 'ACTIVE' : 'DISABLED'}
          </div>
          <div className="serif" style={{
            fontSize: 18, lineHeight: 1.2,
            color: 'var(--cream)',
            opacity: offer.enabled ? 1 : 0.5,
          }}>
            {offer.name}
          </div>
        </div>
        <Toggle on={offer.enabled} onChange={(e) => { e.stopPropagation(); onToggle(); }} />
      </div>
      <div style={{
        fontSize: 12.5, lineHeight: 1.55, color: 'var(--text-dim)',
        opacity: offer.enabled ? 1 : 0.5,
        display: '-webkit-box',
        WebkitLineClamp: 4,
        WebkitBoxOrient: 'vertical',
        overflow: 'hidden',
      }}>
        {offer.body || <span style={{ fontStyle: 'italic', color: 'var(--text-muted)' }}>No body yet</span>}
      </div>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginTop: 4 }}>
        <span className="mono" style={{ fontSize: 10, color: 'var(--text-muted)', letterSpacing: '0.1em' }}>
          @{(offer.name || '').toLowerCase().split(/\s+/)[0] || 'offer'}
        </span>
        <button
          onClick={(e) => { e.stopPropagation(); onDelete(); }}
          aria-label="Delete offer"
          style={{
            background: 'transparent', border: 0, color: 'var(--terracotta)',
            cursor: 'pointer', padding: 6, opacity: 0.7,
            display: 'inline-flex',
          }}>
          <Icon name="trash" size={13} />
        </button>
      </div>
    </div>
  );
}

function Toggle({ on, onChange }) {
  return (
    <button
      onClick={onChange}
      role="switch"
      aria-checked={on}
      style={{
        position: 'relative',
        width: 38, height: 22, borderRadius: 999,
        background: on ? 'var(--gold)' : 'rgba(255,255,255,0.12)',
        border: 0, padding: 0,
        cursor: 'pointer',
        transition: 'background 180ms ease',
        flexShrink: 0,
      }}>
      <span style={{
        position: 'absolute',
        top: 2, left: on ? 18 : 2,
        width: 18, height: 18, borderRadius: '50%',
        background: '#fff',
        transition: 'left 180ms cubic-bezier(0.4, 0, 0.2, 1)',
        boxShadow: '0 1px 3px rgba(0,0,0,0.4)',
      }} />
    </button>
  );
}

function OfferEditor({ existing, onCancel, onSaved }) {
  const [name, setName] = React.useState(existing?.name || '');
  const [body, setBody] = React.useState(existing?.body || '');
  const [saving, setSaving] = React.useState(false);
  const [error, setError] = React.useState(null);

  const trimmedName = name.trim();
  const canSave = trimmedName.length > 0 && body.trim().length > 0 && !saving;

  const save = async () => {
    if (!canSave) return;
    setSaving(true);
    setError(null);
    try {
      let offer;
      if (existing?.id) {
        offer = await foyerApi.patch(`/me/offers/${existing.id}`, {
          name: trimmedName, body: body.trim(),
        });
      } else {
        offer = await foyerApi.post('/me/offers', {
          name: trimmedName, body: body.trim(),
        });
      }
      // Backend returns the persisted offer with id+enabled. The endpoint
      // shape is {offer: {...}} for some routes — be defensive.
      onSaved(offer.offer || offer);
    } catch (e) {
      setError(e.message || String(e));
    } finally {
      setSaving(false);
    }
  };

  return (
    <SheetOverlay onClose={onCancel}>
      <div style={{ padding: '28px 28px 24px' }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline' }}>
          <h2 className="serif" style={{ margin: 0, fontSize: 24, color: 'var(--cream)' }}>
            {existing ? 'Edit offer' : 'New offer'}
          </h2>
          <button
            onClick={onCancel}
            aria-label="Close"
            style={{ background: 'transparent', border: 0, color: 'var(--text-dim)', cursor: 'pointer', padding: 6, display: 'inline-flex' }}>
            <Icon name="x" size={18} />
          </button>
        </div>

        <div style={{ marginTop: 20 }}>
          <Label>Name</Label>
          <input
            type="text"
            value={name}
            onChange={(e) => setName(e.target.value)}
            placeholder="e.g. $2,500 buyer credit"
            autoFocus
            style={inputStyle}
          />
          <div className="mono" style={{ marginTop: 6, fontSize: 10, letterSpacing: '0.08em', color: 'var(--text-muted)' }}>
            REFERENCE THIS OFFER WITH @{(trimmedName || 'name').toLowerCase().split(/\s+/)[0]}
          </div>
        </div>

        <div style={{ marginTop: 18 }}>
          <Label>Offer body</Label>
          <textarea
            value={body}
            onChange={(e) => setBody(e.target.value)}
            rows={8}
            placeholder="What the offer is, who it's for, and what the lead should do next."
            style={{ ...inputStyle, minHeight: 160, fontFamily: 'var(--sans)', resize: 'vertical', lineHeight: 1.55 }}
          />
        </div>

        {error && (
          <div style={{
            marginTop: 14, fontSize: 12,
            color: 'var(--terracotta)',
          }}>
            {error}
          </div>
        )}

        <div style={{ marginTop: 22, display: 'flex', gap: 10, justifyContent: 'flex-end' }}>
          <button onClick={onCancel} className="btn" disabled={saving}>Cancel</button>
          <button onClick={save} disabled={!canSave} className="btn btn-primary">
            {saving ? 'Saving…' : (existing ? 'Save changes' : 'Create offer')}
          </button>
        </div>
      </div>
    </SheetOverlay>
  );
}

function DeleteConfirm({ offer, onCancel, onConfirm }) {
  return (
    <SheetOverlay onClose={onCancel} maxWidth={420}>
      <div style={{ padding: 24 }}>
        <h3 className="serif" style={{ margin: 0, fontSize: 22, color: 'var(--cream)' }}>
          Delete this offer?
        </h3>
        <p style={{ marginTop: 10, fontSize: 13, color: 'var(--text-dim)', lineHeight: 1.55 }}>
          <span style={{ color: 'var(--cream)' }}>{offer.name}</span> will be removed from your
          library. The AI won't suggest it anymore. This can't be undone.
        </p>
        <div style={{ marginTop: 18, display: 'flex', gap: 10, justifyContent: 'flex-end' }}>
          <button onClick={onCancel} className="btn">Cancel</button>
          <button onClick={onConfirm} className="btn"
            style={{ background: 'rgba(202, 80, 71, 0.14)', color: 'var(--terracotta)', borderColor: 'transparent' }}>
            Delete permanently
          </button>
        </div>
      </div>
    </SheetOverlay>
  );
}

function SheetOverlay({ children, onClose, maxWidth = 560 }) {
  React.useEffect(() => {
    const onKey = (e) => { if (e.key === 'Escape') onClose(); };
    document.addEventListener('keydown', onKey);
    return () => document.removeEventListener('keydown', onKey);
  }, [onClose]);
  return (
    <div
      onClick={(e) => { if (e.target === e.currentTarget) onClose(); }}
      style={{
        position: 'fixed', inset: 0,
        background: 'rgba(0,0,0,0.55)',
        backdropFilter: 'blur(6px)',
        WebkitBackdropFilter: 'blur(6px)',
        zIndex: 100,
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        padding: 24,
        animation: 'foyerFadeIn 200ms ease',
      }}>
      <div style={{
        width: '100%', maxWidth,
        background: 'var(--bg-card)',
        border: '1px solid var(--border)',
        borderRadius: 14,
        boxShadow: '0 30px 80px -20px rgba(0,0,0,0.8)',
        maxHeight: '90vh', overflowY: 'auto',
      }}>
        {children}
      </div>
    </div>
  );
}

function Label({ children }) {
  return (
    <div className="mono" style={{
      fontSize: 10, letterSpacing: '0.12em',
      color: 'var(--text-muted)', marginBottom: 8,
    }}>
      {String(children).toUpperCase()}
    </div>
  );
}

const inputStyle = {
  width: '100%',
  padding: '12px 14px',
  background: 'var(--bg-deep)',
  border: '1px solid var(--hairline)',
  borderRadius: 10,
  color: 'var(--cream)',
  fontSize: 14,
  fontFamily: 'var(--sans)',
  outline: 'none',
  boxSizing: 'border-box',
};

Object.assign(window, { OffersPage });
