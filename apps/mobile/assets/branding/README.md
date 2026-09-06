# TS Phone brand assets

`ts-phone-logo-source.png` is the single authoritative artwork for the TS Phone
character. Run `../../tool/generate_app_icons.sh` after changing it.

The generator produces:

- `ts-phone-icon.png`, the opaque app-icon source;
- `ts-phone-mark.png`, the transparent in-app mark;
- `ts-phone-mark-monochrome.png`, the mask used for monochrome rendering;
- Android launcher resources and the iOS AppIcon set.

The SVG files in this directory are legacy design references. They are not
application inputs and must not be used to regenerate release assets. They are
kept only until the next deliberate brand redesign can either replace the PNG
master with a verified vector source or archive them outside the asset tree.
