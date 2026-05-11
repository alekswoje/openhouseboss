/* global React */

// ============================================================
// Shared brand components
// ============================================================

const Crest = ({ size = 22, name = 'Foyer' }) => (
  <div className="crest" style={{ fontSize: size, gap: size * 0.4 }}>
    <span className="crest-mark" style={{ width: size * 1.3, height: size * 1.3, fontSize: size * 0.75 }}>F</span>
    <span>{name}</span>
  </div>
);

const Eyebrow = ({ children, num }) => (
  <div className="eyebrow" style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
    {num && <span style={{ display: 'inline-block', width: 22, height: 1, background: 'var(--gold)' }}></span>}
    <span>{children}</span>
  </div>
);

const Tag = ({ kind = 'buyer', children }) => (
  <span className={`tag tag-${kind}`}>
    <span className="tag-dot"></span>
    {children || kind}
  </span>
);

const Stat = ({ value, label, suffix }) => (
  <div>
    <div className="serif" style={{ fontSize: 56, lineHeight: 1, color: 'var(--cream)' }}>
      {value}
      {suffix && <span style={{ color: 'var(--gold)', fontStyle: 'italic' }}>{suffix}</span>}
    </div>
    <div className="eyebrow" style={{ marginTop: 10 }}>{label}</div>
  </div>
);

const Hairline = ({ vertical = false, style = {} }) => (
  <div style={{
    background: 'var(--hairline)',
    ...(vertical ? { width: 1, alignSelf: 'stretch' } : { height: 1, width: '100%' }),
    ...style,
  }}></div>
);

// Sample visitor data (from results.json)
const SAMPLE_VISITORS = [
  {
    id: 1,
    name: 'Sarah Chen',
    email: 'sarah@example.com',
    phone: '555-0101',
    signedAt: '2:05 PM',
    speaker: 'B',
    tag: 'buyer',
    score: 94,
    summary: 'Actively house-hunting on the West Side with her husband Tom. Sold their Queens home last year, currently renting. Drawn by the kitchen photos. Needs 3+ bedrooms for two kids. Pre-approved to $1.4M, ready to close in 60 days.',
    signals: ['Pre-approved $1.4M', 'Close in 60 days', '3+ bedrooms', '6 months searching'],
    spokeWords: 142,
    followUp: "Hi Sarah, it was so great meeting you today at the open house! I love how prepared you and Tom are — pre-approved and ready to move in 60 days is exactly the kind of position that gives buyers a real edge in this market. The home at $1.295M has been generating serious interest, so please don't hesitate to reach out if you'd like to schedule a private showing. I'd also be happy to send you comparable West Side listings that check your boxes — three bedrooms, great kitchen, the location you love.\n\nLooking forward to helping you and Tom find the perfect fit.\n\nWarm regards,\nJohn",
  },
  {
    id: 2,
    name: 'Mike Rodriguez',
    email: 'mike@example.com',
    phone: '555-0102',
    signedAt: '2:22 PM',
    speaker: 'C',
    tag: 'seller',
    score: 88,
    summary: 'Lives two blocks away on Riverside, in his home for 15 years. Kids heading to college; considering downsizing within six months. Came primarily to gauge the market. Explicitly requested a complimentary comp analysis on his property.',
    signals: ['Owner 15 yrs', 'Downsizing 6mo', 'Requested comp analysis', 'Riverside, 2 blocks'],
    spokeWords: 98,
    followUp: "Hi Mike, it was great meeting you at the open house today — glad you stopped in. As promised, I'd love to put together a complimentary comparative market analysis for your place on Riverside so you have a clear picture of what your home could list for in today's market. Given the activity we're already seeing at this listing, I think you'd be pleasantly surprised by where values are right now in the neighborhood.\n\nWhen's a good time this week for a quick call or walkthrough?\n\nWarm regards,\nJohn",
  },
  {
    id: 3,
    name: 'Jennifer Park',
    email: 'jen@example.com',
    phone: '555-0103',
    signedAt: '2:35 PM',
    speaker: 'D',
    tag: 'browser',
    score: 42,
    summary: 'Local renter with a lease running until next year. Walked in out of curiosity after passing the building regularly. Loves the neighborhood but undecided between buying and continuing to rent. Open to low-pressure listing updates.',
    signals: ['Lease until 2027', 'Neighborhood loyal', 'No urgency', 'Curious browser'],
    spokeWords: 64,
    followUp: "Hi Jennifer, it was so great meeting you at the open house today! I totally understand you're in the early stages of figuring out what makes sense for you, and there's absolutely no rush. As promised, I'll keep you on a low-key list so you can get a feel for what's available in the neighborhood whenever something similar comes up.\n\nIf you ever want to chat through the rent-vs-buy decision, I'm always happy to help — no strings attached.\n\nWarm regards,\nJohn",
  },
];

const SAMPLE_TRANSCRIPT = [
  { who: 'agent', name: 'John', t: '0:00', text: "Welcome in, glad you stopped by! I'm John, I'm hosting today for the seller. What's your name?" },
  { who: 'visitor', vid: 1, name: 'Sarah Chen', t: '0:06', text: "Hi, I'm Sarah. My husband Tom couldn't make it today, but I wanted to come check it out." },
  { who: 'agent', name: 'John', t: '0:12', text: "Nice to meet you Sarah. Have you been looking long?" },
  { who: 'visitor', vid: 1, name: 'Sarah Chen', t: '0:15', highlight: true, text: "About six months actually. We've been all over the West Side. We sold our place in Queens last year and we've been renting until we find the right thing." },
  { who: 'agent', name: 'John', t: '0:24', text: "Got it. What drew you to this one?" },
  { who: 'visitor', vid: 1, name: 'Sarah Chen', t: '0:27', highlight: true, text: "The kitchen looks amazing in the photos. And we need at least three bedrooms, we have two kids." },
  { who: 'agent', name: 'John', t: '0:32', text: "Yeah the kitchen is the centerpiece, fully renovated last year. Three beds, two and a half baths. What's your timeframe like?" },
  { who: 'visitor', vid: 1, name: 'Sarah Chen', t: '0:39', highlight: true, text: "Honestly we're ready now. Pre-approved up to one point four. We'd close in 60 days if it's the right house." },
  { who: 'agent', name: 'John', t: '0:46', text: "Perfect. Take your time looking around. I'll be here if you have any questions." },
  { who: 'gap', t: '2:00', text: '— 70 seconds of ambient room tone —' },
  { who: 'agent', name: 'John', t: '2:00', text: "Hey, welcome! I'm John." },
  { who: 'visitor', vid: 2, name: 'Mike Rodriguez', t: '2:02', text: "Mike, nice to meet you." },
  { who: 'agent', name: 'John', t: '2:04', text: "Hey Mike, you live in the neighborhood?" },
  { who: 'visitor', vid: 2, name: 'Mike Rodriguez', t: '2:07', highlight: true, text: "Yeah, two blocks over on Riverside. Actually, I was curious what's going on with this market. We've been in our place fifteen years. Kids are off to college. Thinking about downsizing maybe in the next six months." },
  { who: 'agent', name: 'John', t: '2:20', text: "Interesting. Have you talked to anyone about what your place might list for?" },
  { who: 'visitor', vid: 2, name: 'Mike Rodriguez', t: '2:24', text: "Not seriously. I figured I'd start by seeing what's selling. This one's asking one point three, right?" },
  { who: 'agent', name: 'John', t: '2:30', text: "Yeah, one point two nine five. We've had multiple showings already. Listen, if you're thinking about it, I'd love to do a free comp analysis on your place. No pressure." },
  { who: 'visitor', vid: 2, name: 'Mike Rodriguez', t: '2:40', highlight: true, text: "Yeah that would actually be helpful. Can you email me?" },
];

Object.assign(window, { Crest, Eyebrow, Tag, Stat, Hairline, SAMPLE_VISITORS, SAMPLE_TRANSCRIPT });
