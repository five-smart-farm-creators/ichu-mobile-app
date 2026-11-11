# Bundled assets

These assets ship with the application and require no runtime download.

## Product imagery

- `images/login_andean_herd.webp` is the mobile-sized `public/assets/images/login-andean-herd-small.webp` from `ichu-web-app` (reference snapshot `b458540`).
- `images/ichu_mark.png` is a cropped, downsampled cow mark from the same repository's `public/assets/images/ichu-logo.png`. The crop removes the embedded Spanish wordmark/tagline so the interface can render its own brand text in either language. The crop uses source-relative x/y/width/height of 0.30/0.06/0.54/0.58, resized proportionally to 224 pixels wide. The original 2.5 MB logo is not bundled.
- Product imagery remains subject to SmartFarm's proprietary terms; do not redistribute it independently.

## Fonts

The web application uses Outfit for headings and Plus Jakarta Sans for body text. Their variable TrueType versions are bundled here because browser WOFF2 assets are not used as Flutter fonts.

| Family | Upstream asset | License |
| --- | --- | --- |
| Outfit | [Google Fonts](https://github.com/google/fonts/blob/main/ofl/outfit/Outfit%5Bwght%5D.ttf) | `fonts/outfit/OFL.txt` |
| Plus Jakarta Sans | [Google Fonts](https://github.com/google/fonts/blob/main/ofl/plusjakartasans/PlusJakartaSans%5Bwght%5D.ttf) | `fonts/plus_jakarta_sans/OFL.txt` |

Both font families use the SIL Open Font License 1.1. The fonts are unmodified, the original copyright/license notices are retained, and bootstrap registers those notices with Flutter's license registry. They are not relicensed under the application's proprietary license. Verify weight rendering on Android and iOS when testing the native app.
