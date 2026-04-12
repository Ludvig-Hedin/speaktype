# SpeakType marketing site

Minimal Next.js landing page: hero, download CTA, waveform / typing animation, two feature blocks, footer.

## Develop

```bash
cd website
npm install
npm run dev
```

Open [http://localhost:3000](http://localhost:3000).

## Deploy on Vercel

1. Import this repo in Vercel.
2. Set **Root Directory** to `website`.
3. Framework preset: **Next.js** (default).
4. Deploy.

Environment variables (see `.env.example`):

- `NEXT_PUBLIC_GITHUB_REPO_URL` — `https://github.com/owner/repo` (no `.git`)
- or `NEXT_PUBLIC_GITHUB_REPOSITORY` — `owner/repo`
- `NEXT_PUBLIC_RELEASES_URL` — optional override for the “latest” button
- `GITHUB_TOKEN` — optional; GitHub PAT for higher API rate limits when listing releases

The home page fetches releases server-side (revalidates every 5 minutes).

## Build

```bash
npm run build
npm start
```
