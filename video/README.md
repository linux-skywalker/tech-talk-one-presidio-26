# Demo video (Remotion)

Cuts the before/after terminal recordings (MPS, Kueue, DRA) into one video: a title slide, a system slide, then each demo with the "without" terminal playing first, the "with" terminal second, and a result slide that names the technique's strength.

The finished video is `final/all-demos.mp4` (125 s, 1080p, 30 fps). The raw recordings are large and are not in git. Put them in `public/demo/` as `without-mps.mp4`, `with-mps.mp4`, `without-kueue.mp4`, `with-kueue.mp4`, `without-dra.mp4`, `with-dra.mp4`. The record scripts are in `scripts/demo/{mps,kueue,dra}/video/`.

```console
npm install
npm run dev                          # Remotion Studio
npx remotion render AllDemos out/all-demos.mp4
```

- `src/scenes/SeqDemo.tsx` builds one demo from a small config (crop, playback segments and rates, result lines, strength line).
- `MpsBeforeAfter.tsx`, `KueueBeforeAfter.tsx`, `DraBeforeAfter.tsx` hold each demo's config; `AllDemos.tsx` joins everything.
- `public/brand/` has the background images; colours and the Poppins font live in `src/scenes/ui.tsx`.
