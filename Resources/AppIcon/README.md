# herdrm application icon

`herdrm-icon.svg` is the canonical D design: three compact TUI status rows,
a green terminal prompt and a white block cursor. The selected concept was
redrawn in the existing editable vector resource; the generated concept board
is not cropped or used as an application asset.

Both applications use the same full-bleed composition. Mac keeps
`Sources/HerdrM/AppIcon.icon` and its existing Icon Composer presentation.
The mobile asset catalog supports iOS 18 and lets the system apply its icon mask;
its full-square 1024-pixel PNG has no alpha channel. No rounded mask is baked in.
The formal display name remains `herdrm`; bundle identifiers remain unchanged.

After editing the SVG, regenerate all native assets on macOS from the repository
root using the system image frameworks:

```sh
swift Resources/AppIcon/generate-mobile-icon.swift
```

The script renders the SVG to sRGB, writes identical canonical and Mac source
PNGs, and removes the redundant alpha channel for the iOS copy. Every pixel in
the square source is opaque. `herdrm-icon-rounded.png` is a 256-pixel documentation
preview only; it is not an input to either platform's application icon.

The green application icon identifies herdrm independently of the selected UI
theme. Switching a theme does not select an alternate application icon.
