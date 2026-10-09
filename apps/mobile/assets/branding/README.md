# CoRHub brand assets

The versioned SVG files are the editable sources of the approved crab identity:

- `corhub-mark.svg`: full-color mark with teal/blue folded body and a golden ring.
- `corhub-mark-small.svg`: small-size variant without eye highlights or small facets.
- `corhub-mark-monochrome.svg`: single-color variant with transparent eye cutouts.

Keep the common silhouette aligned when editing these three variants. Their PNG
counterparts are generated application inputs. `corhub-icon.png` is an opaque
1024 × 1024 app-icon source; platforms apply their own icon masks.

Install `../../tool/requirements-icons.txt` into a private Python environment,
then regenerate from this directory:

```bash
CORHUB_PYTHON=/path/to/private/venv/bin/python ../../tool/generate_app_icons.sh
```

The generator also updates Android legacy, adaptive and themed icons and all
iOS AppIcon sizes. Adaptive artwork stays inside Android's central safe region;
the icon background is `#F6F9FC`. In-app marks retain transparent backgrounds.

Local development environments and caches must stay under
`/home/iaw/project/TSPi/local_debug/`. Generated app assets are public source
assets, not private test evidence. The former raster master and obsolete SVG
references have been replaced by this vector source set.
