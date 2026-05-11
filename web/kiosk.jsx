/* global React, AppShell, Eyebrow, foyerApi, foyerLoad, useFoyerData */

// Two surfaces:
//   /#/kiosk      → agent-facing preview + "Launch kiosk" button.
//   /#/kiosk-live → guest-facing form, no sidebar, no nav, hardened
//                   against back-button + hash navigation, designed to
//                   be handed to a walk-in guest in a separate tab.

// ============================================================
// /#/kiosk — agent-facing setup
// ============================================================

const KioskForm = () => {
  const { user, summaries } = useFoyerData();
  const recentAddress = pickRecentAddress(summaries);

  const launch = () => {
    const url = '/#/kiosk-live';
    // Open in a new tab so the agent's dashboard stays put. The guest's
    // tab is fully sandboxed by the live route's hash trap.
    window.open(url, '_blank', 'noopener');
  };

  return (
    <AppShell active="kiosk">
      <div style={{ position: 'relative', minHeight: '100%', padding: '40px 56px 80px', maxWidth: 1100, margin: '0 auto' }}>
        <Eyebrow>Hand to a guest</Eyebrow>
        <h1 className="serif" style={{ fontSize: 56, margin: '14px 0 0', color: 'var(--cream)', lineHeight: 1 }}>
          Kiosk <span className="serif-it" style={{ color: 'var(--gold)' }}>sign-in.</span>
        </h1>
        <p style={{ marginTop: 14, color: 'var(--text-dim)', fontSize: 15, lineHeight: 1.6, maxWidth: 580 }}>
          Launches a locked-down, full-screen sign-in in a new tab. Guests can fill
          in their info but can't navigate back to your dashboard — no sidebar, no
          back button, no link out.
        </p>

        <div style={{ marginTop: 36, padding: 28, border: '1px solid var(--hairline)', borderRadius: 16, background: 'var(--bg-card)', maxWidth: 580 }}>
          <div className="eyebrow">Address shown to guests</div>
          <div className="serif" style={{ fontSize: 22, marginTop: 10, color: 'var(--cream)' }}>
            {recentAddress || <span style={{ color: 'var(--text-dim)' }}>No recent session — guests will see a generic welcome.</span>}
          </div>
          <p style={{ marginTop: 12, fontSize: 13, color: 'var(--text-dim)', lineHeight: 1.5 }}>
            Pulled from your most recent recorded session. To change it, start a new
            session at a different address from the iOS app first.
          </p>
        </div>

        <div style={{ marginTop: 32, display: 'flex', gap: 12, alignItems: 'center', flexWrap: 'wrap' }}>
          <button className="btn btn-primary" style={{ padding: '16px 28px', fontSize: 14 }} onClick={launch}>
            Launch kiosk in new tab →
          </button>
          <a href="#/kiosk-live" target="_blank" rel="noopener noreferrer" className="btn">
            Preview only
          </a>
        </div>

        <div style={{ marginTop: 48, display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 16 }}>
          <Tip
            num="01"
            title="Locked navigation"
            body="The live kiosk traps the back button and ignores URL changes. A guest can't accidentally land on your dashboard."
          />
          <Tip
            num="02"
            title="Fullscreen-ready"
            body="Once the new tab opens, press F (or ⌃⌘F on Mac) to make the browser fullscreen. The kiosk fills the screen with no chrome."
          />
          <Tip
            num="03"
            title="Real leads, instantly"
            body={"Every sign-in posts to /leads under your account. New names appear in this tab's Sessions and Leads inboxes in real time."}
          />
        </div>
      </div>
    </AppShell>
  );
};

function Tip({ num, title, body }) {
  return (
    <div style={{ padding: 20, border: '1px solid var(--hairline)', borderRadius: 12 }}>
      <div className="mono" style={{ fontSize: 10, color: 'var(--gold)', letterSpacing: '0.14em' }}>{num}</div>
      <div className="serif" style={{ fontSize: 18, marginTop: 6, color: 'var(--cream)' }}>{title}</div>
      <div style={{ fontSize: 13, marginTop: 8, color: 'var(--text-dim)', lineHeight: 1.55 }}>{body}</div>
    </div>
  );
}

function pickRecentAddress(summaries) {
  const recorded = (summaries || [])
    .filter(s => (s.kind || 'recorded') !== 'manual')
    .sort((a, b) => (b.created_at || '').localeCompare(a.created_at || ''));
  return recorded[0]?.address || '';
}


// ============================================================
// /#/kiosk-live — guest-facing, locked-down full-screen form
// ============================================================
//
// Hardened so a walk-in can't escape:
//   - No AppShell sidebar, no route-nav, no Foyer-crest link out
//   - popstate listener pushes state forward whenever back is pressed
//   - hashchange listener forces the hash back to #/kiosk-live
//   - No internal links other than the Sign in button
//
// The agent's session cookie still rides along automatically (same origin),
// so leads land under their account.

const KioskLive = () => {
  const { user, summaries } = useFoyerData();
  const recentAddress = pickRecentAddress(summaries);

  // Trap back-button + URL hash changes so the guest can't navigate out.
  React.useEffect(() => {
    if (typeof window === 'undefined') return;

    // Push an extra entry so the first Back press just re-fires popstate
    // here instead of leaving the page.
    try { window.history.pushState({ kiosk: true }, '', '#/kiosk-live'); } catch (e) {}

    const onPopState = () => {
      try { window.history.pushState({ kiosk: true }, '', '#/kiosk-live'); } catch (e) {}
    };
    const onHash = () => {
      if (window.location.hash !== '#/kiosk-live') {
        window.location.hash = '#/kiosk-live';
      }
    };
    window.addEventListener('popstate', onPopState);
    window.addEventListener('hashchange', onHash);
    return () => {
      window.removeEventListener('popstate', onPopState);
      window.removeEventListener('hashchange', onHash);
    };
  }, []);

  const [name, setName] = React.useState('');
  const [email, setEmail] = React.useState('');
  const [phone, setPhone] = React.useState('');
  const [tag, setTag] = React.useState('Buyer');
  const [submitting, setSubmitting] = React.useState(false);
  const [thanksFor, setThanksFor] = React.useState(null);
  const [err, setErr] = React.useState(null);
  const [signedInCount, setSignedInCount] = React.useState(0);

  const reset = () => {
    setName(''); setEmail(''); setPhone(''); setTag('Buyer'); setErr(null);
  };

  const submit = async (e) => {
    e?.preventDefault?.();
    if (!name.trim()) { setErr('Name is required.'); return; }
    setSubmitting(true); setErr(null);
    try {
      await foyerApi.post('/leads', {
        name: name.trim(),
        email: email.trim(),
        phone: phone.trim(),
        tag,
        address: recentAddress || undefined,
      });
      // Don't bother refreshing foyerLoad here — this tab won't show
      // the inbox anyway, and refreshing would slow each sign-in down.
      const first = name.trim().split(' ')[0];
      setThanksFor({ name: first, at: Date.now() });
      setSignedInCount(c => c + 1);
      reset();
      setTimeout(() => setThanksFor(null), 2200);
    } catch (e2) {
      setErr(e2.message || String(e2));
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <div data-screen-label="Kiosk live" style={{
      // Regular block, not fixed — the .route-frame wrapper above has
      // `transform`, which would otherwise become our containing block and
      // collapse `inset: 0` to a 0-tall frame.
      position: 'relative',
      minHeight: '100vh', width: '100%',
      background: 'var(--bg-deep)',
      color: 'var(--cream)',
      display: 'grid', placeItems: 'center',
      overflow: 'hidden',
    }}>
      {/* Decorative gold radial behind the form. */}
      <div aria-hidden="true" style={{
        position: 'absolute', inset: 0, pointerEvents: 'none',
        background: 'radial-gradient(ellipse at center top, rgba(196, 162, 82, 0.18) 0%, transparent 55%)',
      }} />

      {/* Brand mark — text only, NOT a link, so guests can't tap to home. */}
      <div style={{ position: 'absolute', top: 36, left: 56, display: 'flex', alignItems: 'center', gap: 12 }}>
        <span style={{
          display: 'inline-grid', placeItems: 'center',
          width: 32, height: 32, fontSize: 16, fontFamily: 'var(--serif)',
          color: 'var(--gold)', border: '1px solid var(--gold)', borderRadius: 6,
        }}>F</span>
        <span className="serif" style={{ fontSize: 20, color: 'var(--cream)' }}>Foyer</span>
      </div>

      <div style={{ position: 'absolute', top: 40, right: 56, fontSize: 11, color: 'var(--text-muted)', fontFamily: 'var(--mono)', letterSpacing: '0.14em' }}>
        {signedInCount > 0 ? `${signedInCount} SIGNED IN TODAY` : 'OPEN HOUSE · GUEST SIGN-IN'}
      </div>

      <form onSubmit={submit} style={{
        position: 'relative',
        width: 'min(560px, 90vw)',
        textAlign: 'center',
      }}>
        <div className="eyebrow" style={{ justifyContent: 'center' }}>Welcome in</div>
        <h1 className="serif" style={{ fontSize: 'clamp(38px, 6vw, 72px)', lineHeight: 1, margin: '18px 0 0', color: 'var(--cream)' }}>
          Sign in to see <span className="serif-it" style={{ color: 'var(--gold)' }}>the listing.</span>
        </h1>
        {recentAddress && (
          <div style={{ marginTop: 16, fontSize: 16, color: 'var(--cream-dim)', letterSpacing: '0.01em' }}>
            {recentAddress}
          </div>
        )}
        <p style={{ marginTop: 12, color: 'var(--text-dim)', fontSize: 14, lineHeight: 1.6 }}>
          Your contact info — so {(user?.name || 'the agent').split(' ')[0]} can follow up with notes and similar homes.
        </p>

        <div style={{ marginTop: 40, textAlign: 'left' }}>
          <KioskField label="Full name" value={name} onChange={setName} placeholder="Jane Marchetti" autoFocus required />
          <KioskField label="Email" value={email} onChange={setEmail} placeholder="jane@example.com" type="email" />
          <KioskField label="Phone" value={phone} onChange={setPhone} placeholder="555-0123" type="tel" />

          <div style={{ marginTop: 28, marginBottom: 14 }}>
            <div className="eyebrow" style={{ marginBottom: 10 }}>I'm a…</div>
            <div style={{ display: 'flex', gap: 8 }}>
              {['Buyer', 'Seller', 'Browser'].map(t => (
                <button key={t} type="button"
                        onClick={() => setTag(t)}
                        className="chip"
                        style={{
                          padding: '12px 20px', fontSize: 13, borderRadius: 999,
                          background: tag === t ? 'var(--gold-soft)' : 'transparent',
                          color: tag === t ? 'var(--gold)' : 'var(--text-dim)',
                          border: '1px solid ' + (tag === t ? 'var(--gold)' : 'var(--hairline)'),
                          cursor: 'pointer', letterSpacing: '0.04em',
                        }}>{t}</button>
              ))}
            </div>
          </div>

          {err && (
            <div style={{ marginTop: 18, padding: 14, border: '1px solid var(--terracotta)', color: 'var(--terracotta)', fontSize: 13, borderRadius: 8 }}>
              {err}
            </div>
          )}

          <button type="submit"
                  className="btn btn-primary"
                  disabled={submitting || !name.trim()}
                  style={{
                    marginTop: 34, padding: '22px 28px', fontSize: 16,
                    width: '100%', justifyContent: 'center',
                    opacity: (submitting || !name.trim()) ? 0.5 : 1,
                  }}>
            {submitting ? 'Signing in…' : 'Sign in →'}
          </button>
        </div>
      </form>

      {thanksFor && (
        <div style={{
          position: 'fixed', inset: 0, pointerEvents: 'none',
          display: 'grid', placeItems: 'center', zIndex: 1000,
          background: 'rgba(10, 10, 12, 0.5)',
          backdropFilter: 'blur(6px)', WebkitBackdropFilter: 'blur(6px)',
        }}>
          <div style={{
            background: 'var(--bg-card)',
            border: '1px solid var(--gold)',
            borderRadius: 22, padding: '44px 64px',
            boxShadow: '0 30px 80px -20px rgba(196, 162, 82, 0.55)',
            animation: 'toastIn 0.32s ease both',
            textAlign: 'center',
            maxWidth: 'min(520px, 84vw)',
          }}>
            <div className="eyebrow" style={{ color: 'var(--gold)' }}>Thanks</div>
            <div className="serif" style={{ fontSize: 'clamp(28px, 4vw, 44px)', marginTop: 12, color: 'var(--cream)' }}>
              See you around, <span className="serif-it" style={{ color: 'var(--gold)' }}>{thanksFor.name}.</span>
            </div>
            <div style={{ marginTop: 10, fontSize: 13, color: 'var(--text-dim)' }}>
              Hand the laptop back when you're ready.
            </div>
          </div>
        </div>
      )}

      <div style={{ position: 'absolute', bottom: 28, fontSize: 10, color: 'var(--text-muted)', fontFamily: 'var(--mono)', letterSpacing: '0.16em' }}>
        FOYER · NEVER SHARED · NEVER SPAMMED
      </div>
    </div>
  );
};

function KioskField({ label, value, onChange, placeholder, type = 'text', autoFocus = false, required = false }) {
  return (
    <div style={{ marginTop: 22 }}>
      <div className="eyebrow" style={{ marginBottom: 8 }}>{label}</div>
      <input
        autoFocus={autoFocus}
        required={required}
        type={type}
        value={value}
        onChange={e => onChange(e.target.value)}
        placeholder={placeholder}
        autoComplete="off"
        style={{
          width: '100%', background: 'transparent',
          border: 0, borderBottom: '1px solid var(--border-strong)',
          padding: '12px 0',
          color: 'var(--cream)', fontSize: 20,
          fontFamily: 'var(--sans)', outline: 'none',
        }}
      />
    </div>
  );
}

Object.assign(window, { KioskForm, KioskLive });
