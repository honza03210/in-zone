# TestFlight signing — fixed certificate, no Mac

The `iOS TestFlight` workflow signs **manually** with one Apple Distribution
certificate and one App Store provisioning profile that you create **once** and
store as GitHub secrets. This avoids `-allowProvisioningUpdates` / automatic
signing, which generates a *new* distribution certificate on every CI run and
quickly hits Apple's certificate limit (the "No profiles for 'com.inzoned.app'
were found" failure).

You do **not** need a Mac. Everything below runs in **Git Bash** on Windows
(it ships with `openssl`) plus the Apple Developer **web** portal.

## 0. Clear the dead certificates first

Automatic signing already created a couple of distribution certificates whose
private keys are gone (they lived on throwaway CI runners). Apple allows only a
few, so revoke them to make room:

- developer.apple.com → Certificates → delete the existing **Apple
  Distribution** / "iOS Distribution" certificates. (They're unusable anyway.)

## 1. Create a private key + CSR (Git Bash)

```bash
openssl genrsa -out dist.key 2048
MSYS_NO_PATHCONV=1 openssl req -new -key dist.key -out dist.csr \
  -subj "/CN=InZone Distribution/O=InZone/C=US"
```

`MSYS_NO_PATHCONV=1` is required in Git Bash — without it, Git Bash rewrites the
leading `/` in `-subj` into a Windows path and openssl errors with
"subject name is expected to be in the format ...". Keep `dist.key` safe — it's
the private half of your certificate.

## 2. Get the distribution certificate from Apple

- developer.apple.com → Certificates → **+** → **Apple Distribution** → Continue.
- Upload `dist.csr` → Continue → **Download** the resulting `distribution.cer`.

## 3. Bundle cert + key into a .p12 (Git Bash)

```bash
openssl x509 -inform DER -in distribution.cer -out dist.crt
openssl pkcs12 -export -inkey dist.key -in dist.crt \
  -name "Apple Distribution" -out dist.p12 -passout pass:CHOOSE_A_PASSWORD
```

Remember `CHOOSE_A_PASSWORD` — it becomes the `P12_PASSWORD` secret.

## 4. Create the App Store provisioning profile

- developer.apple.com → Profiles → **+** → **App Store Connect** (distribution).
- App ID: **com.inzoned.app** (create the App ID first if it doesn't exist).
- Certificate: select the one from step 2.
- **Name it** something memorable, e.g. `InZone AppStore` — this exact string is
  the `PROVISIONING_PROFILE_NAME` secret.
- Download `InZone_AppStore.mobileprovision`.

## 5. Base64-encode both files (Git Bash)

```bash
openssl base64 -A -in dist.p12                        -out dist.p12.b64
openssl base64 -A -in InZone_AppStore.mobileprovision -out profile.b64
```

## 6. Add the GitHub secrets

Repo → Settings → Secrets and variables → Actions → New repository secret:

| Secret                           | Value                                            |
|----------------------------------|--------------------------------------------------|
| `BUILD_CERTIFICATE_BASE64`       | contents of `dist.p12.b64`                        |
| `P12_PASSWORD`                   | the password from step 3                          |
| `BUILD_PROVISION_PROFILE_BASE64` | contents of `profile.b64`                         |
| `PROVISIONING_PROFILE_NAME`      | the profile name from step 4 (e.g. `InZone AppStore`) |
| `KEYCHAIN_PASSWORD`              | any throwaway string                              |
| `APPLE_TEAM_ID`                  | your 10-char team id (already set)                |

Keep the existing `ASC_KEY_ID` / `ASC_ISSUER_ID` / `ASC_KEY_P8` — they're still
used, but only to authenticate the **upload**, not to sign.

## 7. Run it

Actions → **iOS TestFlight** → Run workflow. It imports your fixed cert +
profile, archives with manual signing, and uploads to TestFlight — the same
certificate every run, so it won't exhaust Apple's limit again.

The cert is valid for a year; renew by repeating steps 1–6. **Don't commit
`dist.key` / `dist.p12` / the `.cer` / `.mobileprovision`** — they're secrets.
