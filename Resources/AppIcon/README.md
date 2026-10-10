# herdrm application icon

`herdrm-icon.svg` and `herdrm-icon-1024.png` are the existing Mac artwork.
Both applications use that composition; the mobile icon is a generated resource,
not separately designed artwork. The formal display name is `herdrm` on both
platforms. Bundle identifiers are independent of this branding and remain unchanged.

Mac keeps `Sources/HerdrM/AppIcon.icon` and its existing Icon Composer presentation.
The mobile asset catalog supports iOS 18 and lets the system apply its icon mask;
its full-square 1024-pixel PNG has no alpha channel. No rounded mask is baked in.

After updating the canonical PNG, regenerate the mobile copy from the repository
root using the system image framework:

```sh
swift Resources/AppIcon/generate-mobile-icon.swift
```

The current artwork is fully opaque. This preserves its sRGB composition and
removes the redundant alpha channel. If future artwork introduces transparency, fill
its background in the canonical source before generating the mobile icon.
