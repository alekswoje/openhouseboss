/* global React, AppShell, Icon */

// ============================================================
// Listings — Open-house properties the agent is hosting / has hosted.
//
// Mirrors the iPad Listings tab visually: grid of large image-forward
// cards with address overlay, price/specs, and a click-to-open action
// that lands on Kiosk pre-loaded with that listing.
//
// Storage: localStorage('foyer.listings'), JSON-encoded array of
// { id, address, neighborhood, price, beds, baths, sqft, photoData }.
// The iPad app uses UserDefaults for the same data; both surfaces are
// local-only — listings don't currently sync between devices.
// (Same parity decision as the iPad app — agents who want the same
// listings on web + iPad re-enter them; the kiosk flow doesn't depend
// on the listing existing, so it's a soft pref.)
// ============================================================

const LISTINGS_KEY = 'foyer.listings';

function loadListings() {
  try {
    const raw = localStorage.getItem(LISTINGS_KEY);
    if (!raw) return [];
    const parsed = JSON.parse(raw);
    return Array.isArray(parsed) ? parsed : [];
  } catch { return []; }
}

function persistListings(listings) {
  try {
    localStorage.setItem(LISTINGS_KEY, JSON.stringify(listings));
  } catch (e) {
    // Quota exceeded — usually means a giant photoData. Strip photos
    // and retry so at least the text fields persist.
    try {
      const trimmed = listings.map(l => ({ ...l, photoData: undefined }));
      localStorage.setItem(LISTINGS_KEY, JSON.stringify(trimmed));
    } catch {}
  }
}

function uuid() {
  return 'l_' + Math.random().toString(36).slice(2, 10) + Date.now().toString(36);
}

function displayPrice(price) {
  if (!price || price <= 0) return '';
  if (price >= 1_000_000) {
    const m = price / 1_000_000;
    return ('$' + m.toFixed(2) + 'M').replace('.00M', 'M');
  }
  return '$' + price.toLocaleString();
}

function displaySpecs(l) {
  const bathLabel = (l.baths || 0) % 1 === 0 ? `${l.baths | 0}` : (l.baths || 0).toFixed(1);
  return `${l.beds || 0} Beds · ${bathLabel} Baths · ${(l.sqft || 0).toLocaleString()} SF`;
}

function ListingsPage() {
  const [listings, setListings] = React.useState(() => loadListings());
  const [editing, setEditing] = React.useState(null);  // {} = new, {id,...} = edit
  const [pendingDelete, setPendingDelete] = React.useState(null);

  React.useEffect(() => { persistListings(listings); }, [listings]);

  const onSaved = (listing) => {
    setListings(curr => {
      const idx = curr.findIndex(l => l.id === listing.id);
      if (idx === -1) return [listing, ...curr];
      const next = [...curr];
      next[idx] = listing;
      return next;
    });
    setEditing(null);
    window.foyerToast('Listing saved');
  };

  const performDelete = (id) => {
    setListings(curr => curr.filter(l => l.id !== id));
    setPendingDelete(null);
    window.foyerToast('Listing removed');
  };

  const openKioskFor = (listing) => {
    // Stash the chosen listing so the kiosk page picks it up. The iPad
    // uses an in-memory @State; on web we round-trip through window.
    window.foyerActiveListing = listing;
    window.foyerGo('#/kiosk');
  };

  return (
    <AppShell active="listings">
      <div style={{ padding: '40px 44px 80px', maxWidth: 1100, margin: '0 auto' }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-end' }}>
          <div>
            <h1 className="serif" style={{ fontSize: 44, margin: 0, color: 'var(--cream)', letterSpacing: '-0.02em' }}>
              Listings
            </h1>
            <p style={{ marginTop: 10, color: 'var(--text-dim)', fontSize: 14, maxWidth: 540, lineHeight: 1.55 }}>
              Properties you're hosting. Tap a card to launch the kiosk
              with that listing's address and photo pre-loaded.
            </p>
          </div>
          <button
            onClick={() => setEditing({})}
            className="btn btn-primary"
            style={{ padding: '11px 18px', fontSize: 13 }}>
            <Icon name="plus" size={14} />
            <span style={{ marginLeft: 6 }}>Add listing</span>
          </button>
        </div>

        <div style={{ marginTop: 36 }}>
          {listings.length === 0 ? (
            <EmptyListings onCreate={() => setEditing({})} />
          ) : (
            <div style={{
              display: 'grid',
              gridTemplateColumns: 'repeat(auto-fill, minmax(300px, 1fr))',
              gap: 18,
            }}>
              {listings.map(l => (
                <ListingCard
                  key={l.id}
                  listing={l}
                  onOpen={() => openKioskFor(l)}
                  onEdit={() => setEditing(l)}
                  onDelete={() => setPendingDelete(l)}
                />
              ))}
            </div>
          )}
        </div>
      </div>

      {editing && (
        <ListingEditor
          existing={editing.id ? editing : null}
          onCancel={() => setEditing(null)}
          onSaved={onSaved}
        />
      )}
      {pendingDelete && (
        <DeleteConfirm
          listing={pendingDelete}
          onCancel={() => setPendingDelete(null)}
          onConfirm={() => performDelete(pendingDelete.id)}
        />
      )}
    </AppShell>
  );
}

function EmptyListings({ onCreate }) {
  return (
    <div style={{
      padding: '60px 28px',
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
        <Icon name="listings" size={22} />
      </div>
      <div className="serif" style={{ marginTop: 18, fontSize: 22, color: 'var(--cream)' }}>
        No listings yet
      </div>
      <p style={{ marginTop: 10, color: 'var(--text-dim)', fontSize: 13, lineHeight: 1.6, maxWidth: 420, marginLeft: 'auto', marginRight: 'auto' }}>
        Add the properties you're hosting open houses for and the kiosk
        will pre-fill the address + photo when a guest signs in.
      </p>
      <button
        onClick={onCreate}
        className="btn btn-primary"
        style={{ marginTop: 18, padding: '11px 18px', fontSize: 13 }}>
        <Icon name="plus" size={14} />
        <span style={{ marginLeft: 6 }}>Add your first listing</span>
      </button>
    </div>
  );
}

function ListingCard({ listing, onOpen, onEdit, onDelete }) {
  return (
    <div
      onClick={onOpen}
      className="stat-card"
      style={{
        background: 'var(--bg-card)',
        border: '1px solid var(--hairline)',
        borderRadius: 14,
        overflow: 'hidden',
        cursor: 'pointer',
        display: 'flex', flexDirection: 'column',
      }}>
      <div style={{ position: 'relative', height: 180, overflow: 'hidden' }}>
        {listing.photoData ? (
          <img src={listing.photoData} alt={listing.address}
               style={{ width: '100%', height: '100%', objectFit: 'cover', display: 'block' }} />
        ) : (
          <div style={{
            width: '100%', height: '100%',
            background: 'linear-gradient(135deg, #20262f, #0c0e12)',
            display: 'grid', placeItems: 'center',
            color: 'rgba(255,255,255,0.16)',
          }}>
            <Icon name="listings" size={42} />
          </div>
        )}
        <div style={{
          position: 'absolute', inset: 0,
          background: 'linear-gradient(to bottom, transparent 40%, rgba(0,0,0,0.7) 100%)',
        }} />
        {listing.price > 0 && (
          <div style={{
            position: 'absolute', top: 12, right: 12,
            background: 'var(--gold)', color: 'var(--ink-on-gold)',
            padding: '5px 12px', borderRadius: 999,
            fontSize: 12, fontWeight: 600,
            fontFamily: 'var(--sans)',
          }}>
            {displayPrice(listing.price)}
          </div>
        )}
      </div>
      <div style={{ padding: '14px 16px 16px' }}>
        <div className="serif" style={{ fontSize: 18, color: 'var(--cream)', lineHeight: 1.2 }}>
          {listing.address || 'Untitled'}
        </div>
        {listing.neighborhood && (
          <div style={{ fontSize: 12, color: 'var(--text-dim)', marginTop: 4 }}>
            {listing.neighborhood}
          </div>
        )}
        <div className="mono" style={{ fontSize: 10, color: 'var(--text-muted)', letterSpacing: '0.08em', marginTop: 10 }}>
          {displaySpecs(listing).toUpperCase()}
        </div>
        <div style={{ display: 'flex', justifyContent: 'space-between', marginTop: 14, paddingTop: 12, borderTop: '1px solid var(--hairline)' }}>
          <button
            onClick={(e) => { e.stopPropagation(); onEdit(); }}
            style={{
              background: 'transparent', border: 0,
              color: 'var(--text-dim)', cursor: 'pointer',
              fontSize: 12, padding: 0,
              display: 'inline-flex', alignItems: 'center', gap: 5,
            }}>
            <Icon name="pencil" size={11} />
            <span>Edit</span>
          </button>
          <button
            onClick={(e) => { e.stopPropagation(); onDelete(); }}
            style={{
              background: 'transparent', border: 0,
              color: 'var(--terracotta)', cursor: 'pointer',
              fontSize: 12, padding: 0, opacity: 0.7,
              display: 'inline-flex', alignItems: 'center', gap: 5,
            }}>
            <Icon name="trash" size={11} />
            <span>Delete</span>
          </button>
        </div>
      </div>
    </div>
  );
}

function ListingEditor({ existing, onCancel, onSaved }) {
  const [address, setAddress] = React.useState(existing?.address || '');
  const [neighborhood, setNeighborhood] = React.useState(existing?.neighborhood || '');
  const [price, setPrice] = React.useState(existing?.price ? String(existing.price) : '');
  const [beds, setBeds] = React.useState(existing?.beds ? String(existing.beds) : '');
  const [baths, setBaths] = React.useState(existing?.baths ? String(existing.baths) : '');
  const [sqft, setSqft] = React.useState(existing?.sqft ? String(existing.sqft) : '');
  const [photoData, setPhotoData] = React.useState(existing?.photoData || null);

  const canSave = address.trim().length > 0;

  const handlePhoto = async (e) => {
    const file = e.target.files?.[0];
    if (!file) return;
    // Downscale to a reasonable size before storing — localStorage has a
    // 5-10 MB ceiling per origin and a single iPhone photo will blow
    // through that on its own. 1200px wide JPEG at q=0.7 keeps it small.
    const img = new Image();
    img.onload = () => {
      const maxW = 1200;
      const scale = Math.min(1, maxW / img.width);
      const canvas = document.createElement('canvas');
      canvas.width = img.width * scale;
      canvas.height = img.height * scale;
      const ctx = canvas.getContext('2d');
      ctx.drawImage(img, 0, 0, canvas.width, canvas.height);
      setPhotoData(canvas.toDataURL('image/jpeg', 0.72));
    };
    img.src = URL.createObjectURL(file);
  };

  const save = () => {
    if (!canSave) return;
    const listing = {
      id: existing?.id || uuid(),
      address: address.trim(),
      neighborhood: neighborhood.trim(),
      price: Number(price) || 0,
      beds: Number(beds) || 0,
      baths: Number(baths) || 0,
      sqft: Number(sqft) || 0,
      photoData: photoData || undefined,
    };
    onSaved(listing);
  };

  return (
    <SheetOverlay onClose={onCancel}>
      <div style={{ padding: '28px 28px 24px' }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline' }}>
          <h2 className="serif" style={{ margin: 0, fontSize: 24, color: 'var(--cream)' }}>
            {existing ? 'Edit listing' : 'Add listing'}
          </h2>
          <button
            onClick={onCancel}
            aria-label="Close"
            style={{ background: 'transparent', border: 0, color: 'var(--text-dim)', cursor: 'pointer', padding: 6, display: 'inline-flex' }}>
            <Icon name="x" size={18} />
          </button>
        </div>

        {/* Photo */}
        <div style={{ marginTop: 20 }}>
          <Label>Photo</Label>
          <label style={{
            display: 'block', position: 'relative',
            height: 180, borderRadius: 12,
            background: photoData ? 'transparent' : 'rgba(255,255,255,0.04)',
            border: '1px dashed var(--hairline)',
            overflow: 'hidden',
            cursor: 'pointer',
          }}>
            {photoData ? (
              <img src={photoData} alt="" style={{ width: '100%', height: '100%', objectFit: 'cover' }} />
            ) : (
              <div style={{
                position: 'absolute', inset: 0,
                display: 'grid', placeItems: 'center',
                color: 'var(--text-dim)', fontSize: 13,
              }}>
                Click to upload a photo
              </div>
            )}
            <input
              type="file"
              accept="image/*"
              onChange={handlePhoto}
              style={{ position: 'absolute', inset: 0, opacity: 0, cursor: 'pointer' }}
            />
            {photoData && (
              <button
                onClick={(e) => { e.preventDefault(); setPhotoData(null); }}
                aria-label="Remove photo"
                style={{
                  position: 'absolute', top: 10, right: 10,
                  width: 28, height: 28, borderRadius: '50%',
                  background: 'rgba(0,0,0,0.6)', border: 0,
                  color: '#fff', cursor: 'pointer',
                  display: 'grid', placeItems: 'center',
                }}>
                <Icon name="x" size={14} />
              </button>
            )}
          </label>
        </div>

        <div style={{ marginTop: 18 }}>
          <Label>Address</Label>
          <input type="text" value={address} onChange={(e) => setAddress(e.target.value)}
                 placeholder="1936 17th Ave NE" autoFocus style={inputStyle} />
        </div>

        <div style={{ marginTop: 14 }}>
          <Label>Neighborhood</Label>
          <input type="text" value={neighborhood} onChange={(e) => setNeighborhood(e.target.value)}
                 placeholder="Issaquah Highlands" style={inputStyle} />
        </div>

        <div style={{ marginTop: 14, display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12 }}>
          <div>
            <Label>Price ($)</Label>
            <input type="number" value={price} onChange={(e) => setPrice(e.target.value)}
                   placeholder="850000" style={inputStyle} />
          </div>
          <div>
            <Label>Square feet</Label>
            <input type="number" value={sqft} onChange={(e) => setSqft(e.target.value)}
                   placeholder="2400" style={inputStyle} />
          </div>
        </div>

        <div style={{ marginTop: 14, display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12 }}>
          <div>
            <Label>Beds</Label>
            <input type="number" value={beds} onChange={(e) => setBeds(e.target.value)}
                   placeholder="3" style={inputStyle} />
          </div>
          <div>
            <Label>Baths</Label>
            <input type="number" step="0.5" value={baths} onChange={(e) => setBaths(e.target.value)}
                   placeholder="2.5" style={inputStyle} />
          </div>
        </div>

        <div style={{ marginTop: 22, display: 'flex', gap: 10, justifyContent: 'flex-end' }}>
          <button onClick={onCancel} className="btn">Cancel</button>
          <button onClick={save} disabled={!canSave} className="btn btn-primary">
            {existing ? 'Save changes' : 'Create listing'}
          </button>
        </div>
      </div>
    </SheetOverlay>
  );
}

function DeleteConfirm({ listing, onCancel, onConfirm }) {
  return (
    <SheetOverlay onClose={onCancel} maxWidth={420}>
      <div style={{ padding: 24 }}>
        <h3 className="serif" style={{ margin: 0, fontSize: 22, color: 'var(--cream)' }}>
          Remove this listing?
        </h3>
        <p style={{ marginTop: 10, fontSize: 13, color: 'var(--text-dim)', lineHeight: 1.55 }}>
          <span style={{ color: 'var(--cream)' }}>{listing.address}</span> will be removed
          from this browser. Sessions you've already recorded for it are
          kept untouched.
        </p>
        <div style={{ marginTop: 18, display: 'flex', gap: 10, justifyContent: 'flex-end' }}>
          <button onClick={onCancel} className="btn">Cancel</button>
          <button onClick={onConfirm} className="btn"
            style={{ background: 'rgba(202, 80, 71, 0.14)', color: 'var(--terracotta)', borderColor: 'transparent' }}>
            Remove
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

Object.assign(window, { ListingsPage });
