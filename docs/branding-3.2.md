# Sin Rial 3.2 brand assets

The user supplied the ribbon S emblem and full Sin Rial lockup, then approved
cleaning their texture while retaining the design. The clean black-background
master was restored with the built-in image generation tool, not an API script.

Final restoration prompt:

> Restore the provided Sin Rial logo. Output full horizontal lockup, emblem at
> left and exact bold sans serif text 'Sin Rial' at right. Preserve the ribbon S
> outline, relative sizing and font. Remove all speckled white residue in the
> empty spaces in and around the emblem and letters. Background, counters and
> ribbon gaps must be solid black; ribbon faces and letters solid white, with
> smooth boundaries and no texture, grain or shading. Preserve the composition.

The tool's transparent-background outputs introduced artifacts and were rejected.
The user explicitly approved preparing transparency and Android sizes in code.
`scripts/prepare_branding.ps1` derives alpha from the clean master luminance,
extracts the emblem, and generates the full logo, adaptive foreground, monochrome
mask and five legacy launcher sizes. It does not redraw the mark.

- Master: `assets/app_logo_sources/sinrial-3.2-clean-on-black.png`
- In-app lockup: `assets/logos/sinrial_full.png`
- In-app emblem: `assets/logos/sinrial_mark.png`
- Cestaticket: `assets/logos/logo_cestaticket.png`, supplied by the user unchanged

The monochrome layer uses the same transparent silhouette as the normal foreground.
Android's launcher supplies the themed color; the in-app logo uses the current
accent color in light and dark modes.
