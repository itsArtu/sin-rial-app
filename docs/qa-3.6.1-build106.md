# Sin Rial 3.6.1 / build 106

Validated on 2026-11-17. Release APK built from the isolated staging checkout with Flutter 3.47.2 and Android Studio JBR 21.0.10 (Java/Kotlin target 17).

## Changes covered

- Liquid account totals and currency overviews exclude credit-card liabilities. Selecting a bank account opens that account, not a same-bank credit card.
- Home credit-card widgets appear only when cards exist, preserve the selected design, display available credit, respect hidden amounts and open the selected card.
- Card purchases change card debt without debiting a bank account. Linked Pago TDC payments debit the source once and reduce card debt without counting a second expense. No-card legacy behavior remains available.
- Indexed cards store debt and limit in UVC. Official BCV IDI valuations update balances without creating transactions; parsing rejects invalid/future quotes and does not substitute the USD rate.
- Portable backups preserve index history and card data. Partner designs enforce supported networks, with updated logos, chip and contactless artwork.

## Automated validation

| Check | Result |
| --- | --- |
| Full Flutter suite | 585 passed, 1 skipped |
| Android native tests | 175 passed across 14 suites; no failures or errors |
| Flutter analyzer | 0 errors, 0 warnings; 493 informational diagnostics |
| Shared visual suite | 6 passed |
| Installed-build updater matrix | 89, 97, 98, 100, 101, 105 and 106 passed |
| Source/staging parity | 292 source, test, asset and Android files matched before packaging |
| Whitespace validation | git diff --check passed |

Focused tests cover immediate available-credit updates after purchases/payments, empty-state visibility, hidden amounts, card-specific navigation, VES/USD liquid totals, UVC valuation, payment conversion and backup round trips. Responsive widget checks include 320x640, 412x915 and 768x1024, light/dark themes and enlarged text. Inspected real-font captures include the compact Home card, Bancamiga account, Zona Tech card and Mastercard Gold.

## APK verification

- Package: `com.lacaprichosa.app`
- Version: `3.6.1`; versionCode: `106`
- minSdk: 24; targetSdk: 36
- Architectures: armeabi-v7a, arm64-v8a, x86_64
- Size: 73,795,895 bytes
- SHA-256: `bfde20b0ea8aa67bb6dad561f6c79521b412998bc2296ecaf33112e073145503`
- APK Signature Scheme v2 verified. Certificate matches the existing public installation identity: `6e0965ff509debd2db0a5b628f6d55441457cf2fff320b44e70d2d33e62aa2a3`.
- ZIP alignment passed with 16 KiB page alignment.
- Release DEX contains no `IntegrationTestPlugin`; all three new partner assets are packaged.

The initial no-pub build encountered a stale generated integration-test registration. Rebuilding with normal plugin regeneration succeeded; no source workaround or signing change was needed.

## Limits

No physical Android device or emulator was connected. Widget layout checks and native tests do not establish frame-time performance, notification delivery or installation behavior on every manufacturer. No new device performance benchmark was run for this patch. Existing user data is not rewritten to guess past bank transactions; the correction separates account types and fixes new payment handling.

Staging logs: `build/full-106.log`, `build/native-106.log`, `build/analyze-106.log`, `build/visual-106.log`, `build/upgrade-from-*-106.log`, `build/release-106.log`.
