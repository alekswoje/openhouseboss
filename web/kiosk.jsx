/* global React, AppShell, Eyebrow, foyerApi, foyerLoad, useFoyerData */

// /#/kiosk — guest-facing sign-in form, web counterpart to the iPad's
// KioskSignInView. Big type, brass accents, single column. The agent
// hands the laptop to a guest who fills out their info and taps Sign in.
// Each submission creates a kind="manual" lead under the agent's account
// so it lands in the same inbox as everything else.

const KioskForm = () => {
  const { user, summaries, sessionsById } = useFoyerData();

  // The "current address" defaults to whichever recorded session was most
  // recently created — usually the open house the agent is hosting today.
  const recentAddress = React.useMemo(() => {
    const recorded = (summaries || [])
      .filter(s => (s.kind || 'recorded') !== 'manual')
      .sort((a, b) => (b.created_at || '').localeCompare(a.created_at || ''));
    return recorded[0]?.address || '';
  }, [summaries]);

  const [address, setAddress] = React.useState('');
  const [name, setName] = React.useState('');
  const [email, setEmail] = React.useState('');
  const [phone, setPhone] = React.useState('');
  const [tag, setTag] = React.useState('Buyer');
  const [submitting, setSubmitting] = React.useState(false);
  const [signedInGuests, setSignedInGuests] = React.useState([]);
  const [thanksFor, setThanksFor] = React.useState(null);
  const [err, setErr] = React.useState(null);

  // Pre-fill the address once we know the recent session.
  React.useEffect(() => {
    if (!address && recentAddress) setAddress(recentAddress);
  }, [recentAddress]);

  const reset = () => {
    setName(''); setEmail(''); setPhone(''); setTag('Buyer'); setErr(null);
  };

  const submit = async (e) => {
    e?.preventDefault?.();
    if (!name.trim()) { setErr('Name is required.'); return; }
    setSubmitting(true);
    setErr(null);
    try {
      const newSession = await foyerApi.post('/leads', {
        name: name.trim(),
        email: email.trim(),
        phone: phone.trim(),
        tag,
        address: address.trim() || undefined,
      });
      // Refresh the cached sessions so the rest of the app sees the new lead.
      await foyerLoad({ force: true });
      setThanksFor({ name: name.trim(), at: Date.now() });
      setSignedInGuests(g => [{ name: name.trim(), tag, signedAt: new Date() }, ...g].slice(0, 8));
      reset();
      setTimeout(() => setThanksFor(null), 2400);
    } catch (e) {
      setErr(e.message || String(e));
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <AppShell active="kiosk">
      <div style={{ position: 'relative', minHeight: '100%', padding: '40px 56px 80px' }}>
        {/* Decorative gold radial behind the form. */}
        <div style={{
          position: 'absolute', inset: 0, pointerEvents: 'none',
          background: 'radial-gradient(ellipse at top, rgba(196, 162, 82, 0.10) 0%, transparent 50%)',
        }} />

        <div style={{ position: 'relative', display: 'grid', gridTemplateColumns: '1.2fr 0.8fr', gap: 48, maxWidth: 1100, margin: '0 auto' }}>

          <section>
            <Eyebrow>Welcome in</Eyebrow>
            <h1 className="serif" style={{ fontSize: 64, lineHeight: 1, margin: '14px 0 0', color: 'var(--cream)' }}>
              Sign in to see <span className="serif-it" style={{ color: 'var(--gold)' }}>the listing.</span>
            </h1>
            <p style={{ marginTop: 16, color: 'var(--text-dim)', fontSize: 15, maxWidth: 480, lineHeight: 1.6 }}>
              Your contact info — so {(user?.name || 'the agent').split(' ')[0]} can follow up with notes and similar homes.
              Takes 15 seconds, never shared, never spammed.
            </p>

            <form onSubmit={submit} style={{ marginTop: 40, maxWidth: 520 }}>
              <KioskField label="Address" value={address} onChange={setAddress} placeholder="412 W 78th St" />
              <KioskField label="Full name" value={name} onChange={setName} placeholder="Jane Marchetti" autoFocus />
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
                        marginTop: 34, padding: '20px 28px', fontSize: 16,
                        width: '100%', justifyContent: 'center',
                        opacity: (submitting || !name.trim()) ? 0.5 : 1,
                      }}>
                {submitting ? 'Signing in…' : 'Sign in →'}
              </button>
            </form>

            {thanksFor && (
              <div style={{
                position: 'fixed', inset: 0, pointerEvents: 'none',
                display: 'grid', placeItems: 'center', zIndex: 20,
              }}>
                <div style={{
                  background: 'var(--bg-card)',
                  border: '1px solid var(--gold)',
                  borderRadius: 18, padding: '36px 56px',
                  boxShadow: '0 30px 80px -20px rgba(196, 162, 82, 0.5)',
                  animation: 'toastIn 0.32s ease both',
                  textAlign: 'center',
                }}>
                  <div className="eyebrow" style={{ color: 'var(--gold)' }}>Thanks</div>
                  <div className="serif" style={{ fontSize: 36, marginTop: 10, color: 'var(--cream)' }}>
                    See you around, <span className="serif-it" style={{ color: 'var(--gold)' }}>{thanksFor.name.split(' ')[0]}.</span>
                  </div>
                </div>
              </div>
            )}
          </section>

          <aside style={{ paddingTop: 44 }}>
            <Eyebrow>Already signed in</Eyebrow>
            <div style={{ marginTop: 16 }}>
              {signedInGuests.length === 0 ? (
                <div style={{ padding: '20px 0', color: 'var(--text-dim)', fontSize: 13, lineHeight: 1.6 }}>
                  No one yet. Hand the laptop over — every guest sign-in lands as a fresh lead in your inbox.
                </div>
              ) : signedInGuests.map((g, i) => (
                <div key={i} style={{ padding: '14px 0', borderBottom: '1px solid var(--hairline)' }}>
                  <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                    <span style={{ fontSize: 14, color: 'var(--cream)' }}>{g.name}</span>
                    <span className="mono" style={{ fontSize: 9.5, color: 'var(--gold)', letterSpacing: '0.14em' }}>{g.tag.toUpperCase()}</span>
                  </div>
                  <div className="mono" style={{ fontSize: 9.5, color: 'var(--text-muted)', marginTop: 4, letterSpacing: '0.12em' }}>
                    SIGNED · {g.signedAt.toLocaleTimeString(undefined, { hour: 'numeric', minute: '2-digit' })}
                  </div>
                </div>
              ))}
            </div>

            <div className="serif-it" style={{ marginTop: 36, fontSize: 12, color: 'var(--text-muted)', lineHeight: 1.6, maxWidth: 280 }}>
              Tip — for richer leads, record the open house from the iOS app.
              Foyer will diarize each guest and match them to the kiosk sign-ins automatically.
            </div>
          </aside>
        </div>
      </div>
    </AppShell>
  );
};

function KioskField({ label, value, onChange, placeholder, type = 'text', autoFocus = false }) {
  return (
    <div style={{ marginTop: 22 }}>
      <div className="eyebrow" style={{ marginBottom: 8 }}>{label}</div>
      <input
        autoFocus={autoFocus}
        type={type}
        value={value}
        onChange={e => onChange(e.target.value)}
        placeholder={placeholder}
        style={{
          width: '100%', background: 'transparent',
          border: 0, borderBottom: '1px solid var(--border-strong)',
          padding: '12px 0',
          color: 'var(--cream)', fontSize: 18,
          fontFamily: 'var(--sans)', outline: 'none',
        }}
      />
    </div>
  );
}

Object.assign(window, { KioskForm });
