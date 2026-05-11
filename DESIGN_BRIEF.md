# Design Brief — OpenHouseBoss iOS App

> Copy everything below this line into Claude (or any design AI) to get a full app design back.

---

You are designing **OpenHouseBoss**, a native iOS app for real estate agents. I need a complete visual design for every screen, in light and dark mode, with all relevant states (empty, loading, success, error). Deliver as high-fidelity mockups (SVG, PNG, or HTML/CSS — your call), one screen per artifact, plus a short style guide describing colors, typography, and component patterns.

## Product

OpenHouseBoss records audio during a real estate open house, then uses speaker diarization + an LLM to:
1. Identify each visitor by voice (matched to a sign-in list)
2. Tag each visitor (`Seller` / `Buyer` / future custom tags)
3. Generate a personalized follow-up email for each visitor
4. Surface a summary so the agent can act fast after the showing

The agent records on their iPhone, fills in visitor names (pasted from the Compass sign-in form for now), and a minute later sees a list of tagged leads with drafted follow-ups. No CRM integration in MVP.

## Target user

- Real-estate agent, late 20s to 50s
- Stylish, premium-feeling brand expectations (clients are buying $1M+ homes)
- Hands-busy and short on time during open houses
- Tech comfort varies — app must be dead simple, one-thumb operable
- Cares about: looking polished to clients, converting open-house visitors into buyers/sellers, never losing a warm lead

## Voice & feel

- Confident, premium, calm — "built for the closer"
- iOS-native first: SF Pro, SF Symbols, system materials, native nav patterns
- Generous spacing, never cramped — this is a premium tool, not a CRM data-entry form
- Tactile micro-interactions: subtle haptics, smooth spring animations, satisfying button feedback

**Reference apps for vibe/quality:**
- **Linear** — clarity, information hierarchy, micro-interactions
- **Things 3** — tactile, delightful, no clutter
- **Apple Voice Memos** — the recording-UX patterns to learn from
- **Compass mobile app** — premium real estate feel
- **Stripe Dashboard** — data density without overwhelm

## Aesthetic

- Light mode + dark mode, both first-class
- Primary accent: confident blue (around HSL 215, 90%, 55%) — trustworthy, professional
- Seller tag: warm orange/coral (signals action/urgency)
- Buyer tag: the primary blue
- Custom tags later (user picks color)
- Typography: SF Pro Display for headlines, SF Pro Text for body
- Materials: liberal use of `.regularMaterial` / `.thinMaterial` for cards
- Imagery: minimal. SF Symbols only. Maybe one custom illustration for empty-state and first-launch.

## Information architecture

Tab bar with three tabs:
1. **Home** — session list + record CTA
2. **Visitors** — every visitor across every session (lightweight CRM)
3. **Settings** — profile, tags, preferences

## Screens to design

### 1. First-launch onboarding (3 swipeable screens)
- a. Welcome + one-line value prop ("Turn every open house into closed deals")
- b. Permissions: microphone, notifications
- c. Agent setup: name, email signature (for follow-ups), brokerage name

### 2. Home / session list
- Hero: big "Start New Open House" CTA at top, immediately tappable
- Below: list of past sessions, most recent first
  - Each row: property address (or "Untitled session"), date, visitor count, mini distribution chip ("3 Buyers · 1 Seller")
  - Swipe actions: archive, delete
- Empty state when no sessions: warm illustration + "Record your first open house"

### 3. New session setup (sheet)
- Property address (text, optional)
- Property notes (optional — asking price, key features the agent wants to mention)
- "Start Recording" CTA

### 4. Recording
- Massive timer in center
- Live audio level visualizer (bars or waveform)
- Big red stop button at bottom
- Pause button (smaller, secondary)
- Quick-note button — agent taps to add timestamped text notes mid-recording ("John just walked in")
- Cancel (top-left) with confirmation dialog

### 5. Post-recording visitor entry
Three input modes (toggle/segmented at top):
- a. Manual entry — add rows: name (required), email, phone, notes
- b. Paste from clipboard — auto-detect Compass-style sign-in email format and parse
- c. Skip — proceed with anonymous Speaker A/B/C labels

CTA: "Process Open House"

### 6. Processing / loading
- Inline progress, not a blocking modal — user can navigate elsewhere and come back
- Three labeled stages: "Transcribing audio" → "Identifying speakers" → "Analyzing visitors"
- Estimated time remaining
- Smooth animation, no spinners

### 7. Session result
- Top: session header (property name, date, duration, visitor count)
- Below: one VisitorCard per visitor
  - Avatar (initials), name, tag pill
  - One-line key insight ("Pre-approved $1.4M · ready in 60 days")
  - Tap to expand → full detail, or tap "Follow-up" chip → goes to follow-up screen
- Collapsible audio player at bottom — jump to "Mike's section," etc.
- Unmatched-speakers section if any (with action: "Tag manually")
- Bottom action bar: "Send all follow-ups" (review sheet), "Export"

### 8. Visitor detail
- Visitor profile header (name, contact info, tag with edit-on-tap)
- Drafted follow-up — editable text view, "Copy," "Open in Mail" buttons
- Summary section
- Transcript: only this visitor's utterances + the agent's questions that prompted them
- Audio scrubber: tap any transcript line to jump to that moment

### 9. Visitors tab (lightweight CRM)
- Searchable list of all visitors across all sessions
- Filter chips: All / Sellers / Buyers / custom tags
- Each row: name, tag, last seen date, last source property
- Tap → visitor detail with history of every session they've appeared in

### 10. Settings
- Agent profile (name, email signature, brokerage, photo)
- Tags — manage list:
  - Each row: color dot, name, short description, count of leads tagged
  - Reorder, edit, delete, add new
- Recording quality (Good / Better / Best)
- Privacy: auto-delete recordings after N days
- Account / sign out
- About / version

### 11. Tag editor (sheet)
- Name field
- Description field — long-form. Placeholder explains: "Describe when the AI should use this tag. The AI reads this exactly as written."
- Color picker
- Live preview: "AI will tag visitors as **{name}** when…"

## Key components

- **TagPill** — capsule, color-coded, three sizes (sm/md/lg), supports light + dark
- **VisitorCard** — material background, soft shadow, avatar + content stack
- **RecordingButton** — circular, two states (idle blue / recording red), pulse animation, haptic on tap
- **AudioPlayer** — mini (bottom-docked, collapsed) + expanded (waveform with speaker-color overlays along the timeline)
- **EmptyState** — illustration + headline + subhead + CTA
- **ProgressStages** — three-step inline progress used during processing

## States to cover

For every screen:
- Empty (where applicable)
- Loading
- Success
- Error (network, AI failure, permissions denied)
- Light + dark mode

## Interactions & polish

- Pull-to-refresh on session and visitor lists
- Swipe actions: delete, archive, share
- Haptics: recording start/stop (medium), tag selection (light), processing complete (success)
- Card expand: spring animation, content cross-fade
- Tag selection: subtle bounce
- Sound feedback: subtle "recording started" tone, configurable in settings

## Accessibility

- Dynamic Type at every size
- VoiceOver labels for every control
- WCAG AA contrast minimum
- All tap targets ≥ 44pt
- Reduce-motion alternative for all animations

## Deliverables

For each of the 11 screens above:
1. Final layout in light and dark mode
2. All applicable states (loading, empty, error, success)
3. One-paragraph interaction notes (what taps do, what transitions feel like)

Plus a one-page style guide: color tokens (with hex values), type scale, spacing scale, component patterns.

Use your judgment for any detail not specified. Don't ask clarifying questions — make confident decisions and document them.
