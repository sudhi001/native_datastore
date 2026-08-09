# site/

Source for <https://sudhi001.github.io/native_datastore/>.

Static files, no build tooling and no dependencies:

| File | What it is |
|------|------------|
| `index.html` | The whole page, including the inline platform-logo sprite |
| `styles.css` | Tokens and layout, light and dark |
| `app.js` | The live demo store, Dart syntax colouring, copy buttons |
| `favicon.svg` | Tab icon |
| `apple-touch-icon.png` | iOS home-screen icon, 180×180 |
| `social-card.png` | `og:image` / `twitter:image`, 1200×630 |
| `robots.txt` | Crawl policy plus the sitemap pointer |
| `sitemap.xml` | `/` and `/api/` |

Both PNGs are generated — run `python3 tool/generate_social_card.py` after
changing the wordmark, headline or palette. It rasterises the logos straight out
of the `<symbol>` sprite in `index.html`, so the card cannot drift from the page.

## How it gets published

`.github/workflows/pages.yml` runs on every push to `main` that touches `site/`,
`lib/`, `doc/assets/` or `pubspec.yaml`. It assembles:

```
/            site/*
/assets/     doc/assets/*   (the demo GIFs the page embeds)
/api/        dart doc output
```

…substitutes the package version for `__VERSION__` in `index.html` (the header
chip and the JSON-LD `softwareVersion`) and the build date for `__BUILDDATE__`
in `sitemap.xml`, then deploys. The version chip hides itself when the
placeholder is still present, so opening the file locally never shows a fake
version.

## Previewing locally

The page needs `assets/` next to it, so serve an assembled copy rather than
`site/` itself:

```bash
mkdir -p /tmp/nds-site/assets
cp -R site/. /tmp/nds-site/
cp -R doc/assets/. /tmp/nds-site/assets/
python3 -m http.server 8000 --directory /tmp/nds-site
```

To preview the API reference too: `dart doc --output /tmp/nds-site/api`.

## Notes for editing

- **Colours are validated, not chosen by eye.** The teal/amber pair carries
  meaning — amber is your Dart code, teal is what the native store holds — and
  both light and dark steps pass a colour-vision-deficiency separation and
  contrast check against their own surface. Changing a hex means re-checking it.
- The benchmark numbers mirror the table in the root `README.md`. Update both
  together, and keep the bar widths proportional to the largest ops/sec value.
- The type-mapping table mirrors **Storage Details** in the root `README.md`,
  and the two platform panels mirror **Platform Details**. Keep them in step.
- The demo panel in the hero writes to `localStorage`, not to any real store. It
  exists to make the reload prove the point.
- Platform marks are inline `<symbol>`s, not image files, so they cost no extra
  request and follow the theme. The Apple mark takes `currentColor` — Apple asks
  for a solid one-colour mark, so it must stay black on light and white on dark.
  Trademark attribution for all three lives in the footer; keep it there.

## SEO

Anything added to the page should keep these intact: one `<h1>`, a `<title>`
under ~60 characters, a description near 155, `rel=canonical`, complete
Open Graph and Twitter card tags pointing at `social-card.png`, `width`/`height`
on every image (no layout shift), alt text on every image, and the
`SoftwareSourceCode` JSON-LD block. New pages need a `sitemap.xml` entry.
