# Portable Backup Format, Version 1

Device storage remains encrypted with Android Keystore. Portable copies use a
separate user password and contain no device PIN hash, salt, biometric settings,
or update-prompt state. Export does not change the original data.

The UTF-8 JSON envelope contains `format: sin-rial-portable`, `version: 1`,
`kdf: pbkdf2-sha256`, `iterations: 600000`, `cipher: aes-256-gcm`, and standard
Base64 `salt` (32 random bytes), `nonce` (12 bytes), `mac` (16 bytes), `data`.
PBKDF2 takes the exact UTF-8 password, without trimming or normalization, and
derives a 256-bit key. AES-GCM authenticates the UTF-8 AAD string:

`sin-rial-portable:1:pbkdf2-sha256:600000:aes-256-gcm`

Plaintext JSON contains `createdAt` (UTC ISO 8601), `appVersion`, and `state`.
Unknown state fields are preserved for forward compatibility. Unknown envelope
versions or algorithms are rejected, not guessed. Maximum file size is 32 MiB.
Password length is 10 to 256 Dart UTF-16 code units.

Import authenticates and validates before showing a preview. Only explicit
confirmation replaces financial state in one native transaction. Pending writes
are flushed, concurrent UI mutations are blocked during replacement, and the
destination device retains its own security settings. Cancelled, malformed, or
unauthenticated copies never write financial data. Copies are portable data,
not raw encrypted database files. Other-platform clients must implement this
format; this change does not provide an iOS app.
