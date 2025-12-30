# Offline identification eval set

This folder holds a tiny, offline-friendly eval set for the watch identifier. Each case specifies an image path plus the expected brand/reference. Add your own real photos to grow coverage.

- `fixtures/rolex_sub.png` → expected `Rolex 126610LN`
- `fixtures/tudor_bb58.png` → expected `Tudor M79030B`
- Dataset format: see `evalset.json` (array of `{id,imagePath,expectedBrand,expectedReference}`).

You can run the evaluator in a playground or unit test by loading `OfflineEvalRunner`.
