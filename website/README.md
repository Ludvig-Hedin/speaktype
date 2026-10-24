# SpeakType marketing site

Next.js site in English and Swedish: home, pricing, Wispr Flow comparison and downloads.

| Page | English | Swedish |
|---|---|---|
| Home | `/` | `/sv` |
| Pricing | `/pricing` | `/sv/priser` |
| vs Wispr Flow | `/wispr-flow-alternative` | `/sv/wispr-flow-alternativ` |
| Downloads | `/downloads` | `/sv/nedladdningar` |

Each language has its own root layout (`src/app/(en)`, `src/app/(sv)`) so `<html lang>` is right. All copy lives in `src/i18n/en.ts` and `src/i18n/sv.ts`; prices live in `src/lib/pricing.ts`.

## Develop

```bash
cd website
npm install
npm run dev
```

## Environment

- `NEXT_PUBLIC_SITE_URL` — public origin for canonical URLs, sitemap and Open Graph.
- `NEXT_PUBLIC_CHECKOUT_PRO_MONTHLY`, `NEXT_PUBLIC_CHECKOUT_PRO_YEARLY`, `NEXT_PUBLIC_CHECKOUT_LIFETIME` — Polar checkout links. Without them, paid buttons point to the free download (the app starts a 14-day Pro trial) and the pricing page says checkout opens soon.
- `NEXT_PUBLIC_GITHUB_REPO_URL` or `NEXT_PUBLIC_GITHUB_REPOSITORY` — repo for downloads.
- `NEXT_PUBLIC_LATEST_DMG_URL`, `NEXT_PUBLIC_DMG_FILENAME`, `NEXT_PUBLIC_RELEASES_URL` — optional download overrides.
- `GITHUB_TOKEN` — optional, raises the GitHub API rate limit for the release list.

## Deploy on Vercel

Import the repo, set **Root Directory** to `website`, framework **Next.js**.
