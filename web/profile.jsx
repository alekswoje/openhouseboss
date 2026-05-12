/* global React, AppShell, foyerApi, useFoyerData, Icon */

// ============================================================
// Profile / Settings — Gmail connect + future agent prefs. Matches
// the iPad Profile tab visually so cross-device parity is obvious.
// ============================================================

const PC = window.ProfileColors = {
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

function ProfilePage() {
  const { user, loading } = useFoyerData();
  const [gmail, setGmail] = React.useState(null);
  const [gmailLoading, setGmailLoading] = React.useState(true);
  const [error, setError] = React.useState(null);
  const [busy, setBusy] = React.useState(false);

  const refreshGmail = React.useCallback(async () => {
    setGmailLoading(true);
    try {
      const r = await foyerApi.get('/auth/gmail/status');
      setGmail(r);
      setError(null);
    } catch (e) {
      setError(e.message || String(e));
    } finally {
      setGmailLoading(false);
    }
  }, []);

  // Initial fetch + handle OAuth completion redirect. When the user lands
  // on /#/profile?gmail=connected, strip the query, refresh status, toast.
  React.useEffect(() => {
    refreshGmail();
    const params = new URLSearchParams(window.location.search);
    if (params.get('gmail') === 'connected') {
      window.history.replaceState({}, '', window.location.pathname + window.location.hash);
      setTimeout(() => {
        refreshGmail();
        window.foyerToast?.('Gmail connected');
      }, 300);
    }
  }, [refreshGmail]);

  const connect = () => {
    // Top-level navigation — Google's consent screen replaces this tab.
    // After /auth/gmail/callback finishes, we land back here with
    // ?gmail=connected (handled in the effect above).
    window.location.href = '/auth/gmail/start?platform=web';
  };

  const disconnect = async () => {
    if (!confirm('Disconnect Gmail? Scheduled sends will fail until you reconnect.')) return;
    setBusy(true);
    try {
      await foyerApi.post('/auth/gmail/disconnect');
      await refreshGmail();
      window.foyerToast?.('Gmail disconnected');
    } catch (e) {
      setError(e.message);
    } finally {
      setBusy(false);
    }
  };

  return (
    <AppShell active="profile">
      <div style={{ maxWidth: 720, margin: '0 auto', padding: '56px 56px 120px', display: 'flex', flexDirection: 'column', gap: 40 }}>
        {/* Header */}
        <div>
          <div className="mono" style={{ fontSize: 10, letterSpacing: '0.18em', color: PC.textDim, textTransform: 'uppercase', marginBottom: 8 }}>Profile</div>
          <div style={{ fontSize: 32, fontWeight: 500, color: PC.cream, letterSpacing: '-0.02em' }}>
            {user?.name || 'Signed in'}
          </div>
          <div style={{ fontSize: 14, color: PC.textDim, marginTop: 4 }}>{user?.email}</div>
        </div>

        {/* Gmail card */}
        <div>
          <SectionEyebrow title="Gmail" />
          <div style={{
            background: PC.card2, borderRadius: 14, padding: 24,
            display: 'flex', alignItems: 'center', gap: 18,
          }}>
            <div style={{
              width: 48, height: 48, borderRadius: 12,
              background: gmail?.connected ? PC.goldSoft : 'rgba(255,255,255,0.05)',
              color: gmail?.connected ? PC.gold : PC.textDim,
              display: 'grid', placeItems: 'center',
            }}>
              <Icon name="envelope" size={22} />
            </div>
            <div style={{ flex: 1 }}>
              {gmailLoading ? (
                <div style={{ color: PC.textDim, fontSize: 13 }}>Loading…</div>
              ) : gmail?.connected ? (
                <>
                  <div style={{ fontSize: 15, fontWeight: 500, color: PC.cream, display: 'inline-flex', alignItems: 'center', gap: 8 }}>
                    Connected
                    <span style={{ width: 7, height: 7, borderRadius: '50%', background: PC.sage, boxShadow: `0 0 8px ${PC.sage}` }} />
                  </div>
                  <div style={{ fontSize: 13, color: PC.textDim, marginTop: 2 }}>{gmail.email || 'Gmail account linked'}</div>
                  <div style={{ fontSize: 11, color: PC.textMuted, marginTop: 6 }}>
                    Used to send follow-ups. Persists across devices — same on the iPad app.
                  </div>
                </>
              ) : (
                <>
                  <div style={{ fontSize: 15, fontWeight: 500, color: PC.cream }}>Not connected</div>
                  <div style={{ fontSize: 13, color: PC.textDim, marginTop: 2 }}>
                    Connect Gmail to send follow-ups from the web. The same
                    connection works on the iPad — sign in there and it's
                    already linked.
                  </div>
                </>
              )}
            </div>
            <div>
              {gmail?.connected ? (
                <button onClick={disconnect} disabled={busy} style={{
                  padding: '10px 16px', fontFamily: 'var(--sans)', fontSize: 13, fontWeight: 500,
                  background: 'rgba(248,113,113,0.12)', color: PC.terracotta,
                  border: 0, borderRadius: 999, cursor: 'pointer',
                  opacity: busy ? 0.5 : 1,
                }}>{busy ? 'Disconnecting…' : 'Disconnect'}</button>
              ) : (
                <button onClick={connect} disabled={busy || gmailLoading} style={{
                  padding: '10px 18px', fontFamily: 'var(--sans)', fontSize: 13, fontWeight: 600,
                  background: PC.gold, color: 'var(--bg-deep)',
                  border: 0, borderRadius: 999, cursor: 'pointer',
                  display: 'inline-flex', alignItems: 'center', gap: 6,
                  opacity: (busy || gmailLoading) ? 0.5 : 1,
                }}><Icon name="envelope" size={12} />Connect Gmail</button>
              )}
            </div>
          </div>
          {error && <div style={{ fontSize: 12, color: PC.terracotta, marginTop: 10 }}>{error}</div>}
        </div>

        {/* Account card */}
        <div>
          <SectionEyebrow title="Account" />
          <div style={{
            background: PC.card2, borderRadius: 14, padding: 24,
            display: 'flex', alignItems: 'center', gap: 18,
          }}>
            {user?.picture
              ? <img src={user.picture} alt="" style={{ width: 48, height: 48, borderRadius: '50%', objectFit: 'cover' }} />
              : <div style={{ width: 48, height: 48, borderRadius: '50%', background: PC.goldSoft, color: PC.gold, display: 'grid', placeItems: 'center', fontSize: 18 }}>{(user?.name || '?').slice(0, 1).toUpperCase()}</div>
            }
            <div style={{ flex: 1 }}>
              <div style={{ fontSize: 15, fontWeight: 500, color: PC.cream }}>{user?.name || '—'}</div>
              <div style={{ fontSize: 13, color: PC.textDim, marginTop: 2 }}>{user?.email}</div>
            </div>
            <button onClick={() => window.foyerSignOut?.()} style={{
              padding: '10px 16px', fontFamily: 'var(--sans)', fontSize: 13, fontWeight: 500,
              background: 'rgba(255,255,255,0.05)', color: PC.creamDim,
              border: 0, borderRadius: 999, cursor: 'pointer',
              display: 'inline-flex', alignItems: 'center', gap: 6,
            }}><Icon name="logout" size={12} />Log out</button>
          </div>
        </div>
      </div>
    </AppShell>
  );
}

function SectionEyebrow({ title }) {
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginBottom: 14 }}>
      <div className="mono" style={{ fontSize: 10, letterSpacing: '0.18em', color: PC.textDim, textTransform: 'uppercase', fontWeight: 600 }}>{title}</div>
      <div style={{ height: 1, flex: 1, background: PC.hairline }} />
    </div>
  );
}

window.ProfilePage = ProfilePage;
