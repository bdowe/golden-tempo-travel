# Golden Tempo brand mark

A black horse head inside an omega-shaped gold horseshoe. The company is named
after Golden Tempo, the horse whose Kentucky Derby win (a $100 bet returning
$700) seeded the business — the horseshoe doubles as an Ω for the "winning
streak" it started.

`mark.svg` is the icon; `lockup.svg` adds the GOLDEN / TEMPO wordmark
(Playfair Display SemiBold, from `src/packages/flutter-app/assets/fonts/`).
These are the editable sources for every raster brand asset in the app:

| Rendered from | File | Size |
|---|---|---|
| mark.svg | `flutter-app/assets/images/golden_tempo_mark.png` | 540 |
| mark.svg | `flutter-app/web/splash/golden_tempo_mark.png` | 540 |
| mark.svg | `flutter-app/web/favicon.png` | 64 |
| mark.svg (84%, transparent) | `flutter-app/web/icons/Icon-192/512.png` | 384 / 1024 |
| mark.svg (64%, white bg) | `flutter-app/web/icons/Icon-maskable-192/512.png` | 384 / 1024 |
| lockup.svg | `flutter-app/assets/images/golden_tempo_logo.png` | 1024 |

To regenerate after editing an SVG, render with any SVG rasterizer that can
load the Playfair Display font file, e.g. `@resvg/resvg-js`:

```js
const { Resvg } = require('@resvg/resvg-js');
const png = new Resvg(fs.readFileSync('mark.svg', 'utf8'), {
  fitTo: { mode: 'width', value: 540 },
  font: { fontFiles: ['.../PlayfairDisplay-SemiBold.ttf'], loadSystemFonts: false },
}).render().asPng();
```
