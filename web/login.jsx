/* global React, Crest, Eyebrow, Hairline */

const Login = () => {
  const handleContinue = (e) => {
    e?.preventDefault?.();
    window.foyerToast('Welcome back, John.');
    setTimeout(() => window.foyerGo('#/app'), 350);
  };
  return (
    <div className="foyer" data-screen-label="Login" style={{ background: 'var(--bg-deep)', minHeight: '100%', display: 'grid', gridTemplateColumns: '1fr 1fr' }}>

      {/* left — editorial pane */}
      <div style={{ padding: '48px 56px', display: 'flex', flexDirection: 'column', justifyContent: 'space-between', borderRight: '1px solid var(--hairline)', background: 'var(--bg)', position: 'relative', overflow: 'hidden' }}>
        {/* decorative gold corner */}
        <div style={{ position: 'absolute', top: 40, right: 40, color: 'var(--gold)', opacity: 0.6 }}>
          <svg width="60" height="60" viewBox="0 0 60 60" fill="none">
            <path d="M0 1 L40 1 M1 0 L1 40" stroke="currentColor"/>
          </svg>
        </div>
        <a
          href="#/"
          aria-label="Home"
          style={{ textDecoration: 'none', color: 'inherit', display: 'inline-flex' }}
        ><Crest /></a>

        <div>
          <Eyebrow num="1">Field notes</Eyebrow>
          <blockquote className="serif" style={{ fontSize: 38, lineHeight: 1.2, margin: '24px 0 0', color: 'var(--cream)', maxWidth: 520, fontWeight: 400 }}>
            <span className="serif-it" style={{ color: 'var(--gold)' }}>"</span>The art of selling a house begins
            the moment the door opens. Foyer keeps
            every quiet detail of that moment, so
            nothing of value goes unremembered<span className="serif-it" style={{ color: 'var(--gold)' }}>."</span>
          </blockquote>
          <div style={{ marginTop: 28 }}>
            <div style={{ fontSize: 14, color: 'var(--cream)' }}>Eliana Morales</div>
            <div className="eyebrow" style={{ marginTop: 4 }}>Top producer · UWS</div>
          </div>
        </div>

        <div className="mono" style={{ fontSize: 10, color: 'var(--text-muted)', letterSpacing: '0.14em' }}>
          NEW YORK · LONDON · SAN FRANCISCO
        </div>
      </div>

      {/* right — form pane */}
      <div style={{ padding: '48px 56px', display: 'flex', flexDirection: 'column', justifyContent: 'space-between' }}>
        <div style={{ textAlign: 'right' }}>
          <span style={{ fontSize: 12, color: 'var(--text-dim)' }}>No account? </span>
          <a
            className="serif-it"
            style={{ fontSize: 14, color: 'var(--gold)', cursor: 'pointer' }}
            onClick={() => window.foyerToast('Request received · we’ll reach out within 24h')}
          >Request access →</a>
        </div>

        <div style={{ maxWidth: 380, margin: '0 auto', width: '100%' }}>
          <Eyebrow>Sign in</Eyebrow>
          <h1 className="serif" style={{ fontSize: 56, lineHeight: 1, margin: '14px 0 0', color: 'var(--cream)' }}>
            Welcome <span className="serif-it" style={{ color: 'var(--gold)' }}>back.</span>
          </h1>
          <p style={{ marginTop: 14, color: 'var(--text-dim)', fontSize: 14, lineHeight: 1.6 }}>
            Pick up Saturday's open house from your desk.
          </p>

          <form onSubmit={handleContinue} style={{ marginTop: 40 }}>
            <Field label="Email" placeholder="agent@brokerage.com" defaultValue="john@halloran.realty" />
            <Field label="Password" placeholder="••••••••••••" type="password" defaultValue="hunter2sample" />
            <div style={{ display: 'flex', justifyContent: 'space-between', marginTop: 14, alignItems: 'center' }}>
              <label style={{ display: 'flex', alignItems: 'center', gap: 8, fontSize: 12, color: 'var(--text-dim)' }}>
                <input type="checkbox" defaultChecked style={{ accentColor: 'var(--gold)' }}/> Keep me signed in
              </label>
              <a
                className="serif-it"
                style={{ fontSize: 13, color: 'var(--gold)', cursor: 'pointer' }}
                onClick={() => window.foyerToast('Reset link sent to john@halloran.realty')}
              >Forgot →</a>
            </div>
            <button
              type="submit"
              className="btn btn-primary"
              style={{ width: '100%', justifyContent: 'center', marginTop: 28, padding: '16px' }}
            >
              Continue
            </button>
          </form>

          <div className="divider" style={{ margin: '36px 0' }}>or</div>

          <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
            <button
              className="btn"
              style={{ width: '100%', justifyContent: 'center' }}
              onClick={() => window.foyerToast('Signing in with Apple…')}
            >Sign in with Apple</button>
            <button
              className="btn"
              style={{ width: '100%', justifyContent: 'center' }}
              onClick={() => window.foyerToast('Code sent · check your phone')}
            >Continue with phone</button>
          </div>
        </div>

        <div style={{ textAlign: 'center' }}>
          <div className="mono" style={{ fontSize: 10, color: 'var(--text-muted)', letterSpacing: '0.14em' }}>
            END-TO-END ENCRYPTED · SOC 2 II
          </div>
        </div>
      </div>
    </div>
  );
};

const Field = ({ label, placeholder, type = 'text', defaultValue }) => (
  <div style={{ marginBottom: 22 }}>
    <div className="eyebrow" style={{ marginBottom: 8 }}>{label}</div>
    <input
      type={type}
      placeholder={placeholder}
      defaultValue={defaultValue}
      style={{
        width: '100%',
        background: 'transparent',
        border: 0, borderBottom: '1px solid var(--border-strong)',
        padding: '8px 0', color: 'var(--cream)', fontSize: 15,
        fontFamily: 'var(--sans)', outline: 'none',
      }}
    />
  </div>
);

Object.assign(window, { Login });
