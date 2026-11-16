# Sin Rial 3.6.0 / build 105

## Scope

- Separate cardholder name from the optional card alias. Display the bank with the alias in parentheses; retain the bank default when there is no alias.
- Limit the last-four input to four numeric digits, including pasted text. Save validation still rejects incomplete nonempty identifiers. No PAN or CVV is collected.
- Account artwork uses the bank name without Debit; refined chip and open contactless arcs.
- Automatic verified bank-app launch with exact Google Play fallback, browser fallback, and provider-name search for uncatalogued apps. No selector, installed-app enumeration, financial extras or imported package overrides.
- Retain hidden tab state without rebuilding inactive tabs on every revision. Covered routes resume with current data. Avoid a full-page opacity layer on navigation and cache date/revision-specific movement rate lookups.
- Includes the existing 3.6 card, UVC, backup, automation and shared-interface work described in the release notes and credit-card contract document.

## Automated checks

- Full Flutter suite: 573 passed, 1 skipped (`build/full-105.log`). The opt-in benchmark was subsequently run separately and passed.
- Android/JVM: 175 tests in 14 suites, no failures, errors or skips (`build/native-105.log`). Bank shortcut tests exercise Android SDK 30 and 36.
- Analyzer: 0 errors, 0 warnings, 478 informational findings (`flutter analyze --no-fatal-infos`, `build/analyze-105.log`).
- Real-font visual pass after image decoding: 31 tests passed, including 264 main/account/design captures and eight franchise captures (`build/visual-105.log`, `build/design-qa`, `build/credit-qa`).
- Sizes: 320x640, 412x915, 768x1024, light/dark and enlarged text. Card faces also include a long bank alias and cardholder name. Inspected small-screen expense, bank artwork, Visa Signature and Mastercard Black captures.
- Updater candidate 105 tested using installed pubspec builds 89, 97, 98, 100, 101, 104 and 105. Prior builds offer the candidate; 105 does not offer itself. Each run passed both tests (`build/upgrade-from-*.log`).
- Repository/staging parity: 282 source, test, asset and Android files checked, zero mismatches. GeneratedPluginRegistrant.java is excluded because Flutter regenerates it; release DEX is inspected separately.
- `git diff --check` passed. Unrelated pre-existing staged documentation and Windows generated-file changes are excluded from this release commit.

## Performance check

Host benchmark with 10,000 synthetic movements (`build/performance-105.log`): repeated category scans 377.05 ms, single-pass budget 239.09 ms, cached budget read 0.0015 ms; uncached home calculation 876.79 ms and cached read 0.0003 ms. These are host computation measurements, not Android frame timings or startup guarantees.

## Boundaries

- No Android device or emulator was connected. Physical OEM layout, real bank launches, notification delivery, SAF interaction, installation and animation frame timing still need device testing.
- No banking conditions or unconfirmed fees were changed. UVC still requires a confirmed positive IDI and its date, not a substituted USD rate. No automatic interest formula is assumed.
- Periodic encrypted backups run when the app is active, not as guaranteed background jobs. Card artwork is an in-app adaptation of references, not a claim of official artwork or product eligibility.
- Update over the existing app without uninstalling. Export a portable backup first.

## Release artifact

- Release APK compiled in 74.2 seconds: `release/sin-rial-3.6.0-build105.apk`, 70,528,468 bytes.
- Package `com.lacaprichosa.app`, version name `3.6.0`, version code `105`, min SDK 24, target SDK 36; ARM32, ARM64 and x86_64.
- Bundled Manrope weights 400/500/600/700/800 and Visa/Mastercard assets verified. No IntegrationTestPlugin reference in release DEX.
- APK v2 signature verified; certificate SHA-256 `6e0965ff509debd2db0a5b628f6d55441457cf2fff320b44e70d2d33e62aa2a3` matches the public build 101 identity. Signing identity was not changed.
- `zipalign -c -P 16 4` passed.
- APK SHA-256: `8696d5ab761a89ad4598ab3139c528a9575663f710cca028bbe7be9725580d21`.
- Updater manifest and standalone checksum identify build 105. Publication uses a draft release so asset verification precedes the latest-release switch.
