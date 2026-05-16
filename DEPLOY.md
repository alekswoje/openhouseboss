# Deploy

Everything below assumes the repo is on GitHub (or any Git provider Render/Cloudflare can pull from). If it isn't yet:

```
cd /Users/alekswojewoda/OpenHouseCopilot
git init
git add .
git commit -m "Initial commit"
gh repo create openhouseboss --public --source=. --push
```

---

## 1. Backend → Render (free)

The repo already has [render.yaml](render.yaml) at the root, which tells Render everything it needs.

1. Go to https://dashboard.render.com → **New +** → **Blueprint**.
2. Connect the GitHub repo. Render reads `render.yaml` and proposes the `openhouseboss-api` service.
3. Click **Apply**. Render builds (~2 min on first deploy).
4. Open the service → **Environment** → add the two secrets (marked `sync: false` in render.yaml so they don't live in Git):
   - `ASSEMBLYAI_API_KEY` — copy from your `.env`
   - `ANTHROPIC_API_KEY` — copy from your `.env`
5. After the env vars save, hit **Manual deploy → Deploy latest commit** so they take effect.

You'll get a URL like `https://openhouseboss-api.onrender.com`. Test it:

```
curl https://openhouseboss-api.onrender.com/healthz
# → {"ok":true}
```

**Free-tier caveat:** the service sleeps after 15 minutes of inactivity. First request after idle takes ~30 s to spin back up. Subsequent requests are normal speed. For demos, hit `/healthz` before showing the app to warm it up.

---

## 2. Web frontend → Cloudflare Pages (free)

Cloudflare Pages serves static files from a Git branch. Since [web/](web/) is pure HTML/CSS/JSX with no build step, this is one click:

1. https://dash.cloudflare.com → **Workers & Pages** → **Create** → **Pages** → **Connect to Git**.
2. Pick the repo. Production branch: `main` (or whatever).
3. Build settings:
   - **Framework preset:** None
   - **Build command:** *(leave empty)*
   - **Build output directory:** `web`
4. Save and deploy. You get `https://<project>.pages.dev`.

Free tier: unlimited bandwidth, unlimited requests, custom domains for $0 if you transfer DNS to Cloudflare.

---

## 3. iOS app → point at Render

[ios/OpenHouseCopilot/Config.swift](ios/OpenHouseCopilot/Config.swift) flips automatically:

- **Debug builds** (running from Xcode) → `http://127.0.0.1:8000`. Keep `uvicorn backend.server:app --reload` running locally.
- **Release builds** (Archive → TestFlight / App Store) → the Render URL.

Replace the placeholder Render URL in `Config.swift` with the one Render gave you, then archive. Phone on cellular or different Wi-Fi will work fine since it's HTTPS to a public URL.

---

## What happens end-to-end (sanity check)

1. iPhone opens app → taps **+** → SetupView → **Begin recording**.
2. LiveView starts AVAudioRecorder, shows the live mic-level waveform.
3. **End session** → `POST /sessions` with the `.m4a` (no CSV).
4. Backend writes the file under `sessions/<id>/`, runs `_process` in a thread:
   - `transcribe_with_speakers` → AssemblyAI Universal-2 with `speaker_labels=True`.
   - `identify_agent_and_visitors` (no CSV) → longest-speaker = agent; Claude extracts each other speaker's first name from the conversation; each non-agent speaker becomes a Visitor with `name` = extracted first name (title-cased) or `"Visitor B"` fallback.
   - `analyze_visitor` per visitor → Claude Sonnet 4.6 returns `{summary, tag, tag_reason, score, signals, follow_up_draft}`, plus we count `words_spoken` from the transcript.
5. iPhone polls `GET /sessions/<id>` every 2 s, shows the "Reading the room…" card while `status=processing`.
6. When `status=ready`, SummaryView renders one card per visitor. Tap → VisitorDetailView (real signals, summary, tag reason). Tap **Review follow-up →** → FollowupView with the real drafted email; edit inline; tap **Send now** to fire a confirmation toast.

---

## Cost expectations (rough)

- **Render free tier:** $0 forever for the API (sleep + cold-start tradeoff). $7/mo for the always-on Starter plan if you outgrow it.
- **Cloudflare Pages:** $0 forever for the web.
- **AssemblyAI:** ~$0.27/hr of audio on `best` (Universal-2). A 2-hour open house ≈ $0.55. First $50 of credit is free on signup.
- **Anthropic:** Claude Sonnet 4.6 with prompt caching is roughly $0.01–0.05 per visitor analyzed. A typical open house ≈ $0.10–0.20.

Total per open house, real audio: about **$0.65–0.80**. Plenty cheap for early users.
