# iOS multi-app monorepo → TestFlight (GitHub Actions)

A blueprint for a repository that holds **several iOS apps, each in its own
subdirectory**, with a single GitHub Actions workflow that builds each app and
uploads it to **TestFlight** automatically. No developer Mac is required —
signing is fully automatic via an App Store Connect API key, and builds install
over the air through the TestFlight app.

This generalises the single-app setup used elsewhere in this repo
(`.github/workflows/ios-testflight.yml`, `ios/`); the gotchas noted at the end
are all things that actually bit during that bring-up.

---

## How it works

- Each app is a **self-contained subdirectory** under `apps/`, described by an
  [XcodeGen](https://github.com/yonaskolb/XcodeGen) `project.yml`. The
  `.xcodeproj` is **not** committed — it's generated in CI, which avoids merge
  conflicts and "future project format" breakage.
- A workflow on **macOS runners** discovers the apps, and for each one (or only
  the changed ones on a push) it: generates the project, archives with
  automatic signing, and uploads to TestFlight.
- Credentials are **repo secrets**. One App Store Connect API key covers every
  app in your team, so you set it up once for the whole monorepo.

---

## 1. Repository layout

```
.
├── apps/
│   ├── AppOne/
│   │   ├── project.yml            # XcodeGen config (name: AppOne)
│   │   └── AppOne/                # sources
│   │       ├── AppOneApp.swift …
│   │       ├── Info.plist
│   │       └── AppOne.entitlements
│   └── AppTwo/
│       ├── project.yml            # name: AppTwo
│       └── AppTwo/ …
└── .github/workflows/
    └── testflight.yml
```

**Conventions the workflow relies on** (keep them and adding an app needs zero
workflow edits):
- One app per `apps/<Name>/`, each containing a `project.yml`.
- In each `project.yml`, the project `name:`, the app target, and a shared
  scheme are all `<Name>` (matching the directory). The workflow builds
  `-project <Name>.xcodeproj -scheme <Name>`.

---

## 2. Per-app `project.yml`

```yaml
name: AppOne
options:
  bundleIdPrefix: com.yourorg
  deploymentTarget: { iOS: "16.0" }
settings:
  base:
    SWIFT_VERSION: "5.9"
    TARGETED_DEVICE_FAMILY: "1"
    MARKETING_VERSION: "1.0.0"          # human version; bump per release
targets:
  AppOne:
    type: application
    platform: iOS
    sources:
      - path: AppOne
        excludes: ["*.entitlements"]
    settings:
      base:
        INFOPLIST_FILE: AppOne/Info.plist
        CODE_SIGN_ENTITLEMENTS: AppOne/AppOne.entitlements
        CODE_SIGN_STYLE: Automatic
        PRODUCT_BUNDLE_IDENTIFIER: com.yourorg.appone
schemes:
  AppOne:
    build:
      targets: { AppOne: all }
```

Each app needs a **unique bundle id** and its own **App Store Connect app
record** (see §4).

### Info.plist essentials

Supply the standard keys (a missing `CFBundleIdentifier` means the build won't
install). Use build-setting substitution so they track `project.yml`:

```xml
<key>CFBundleIdentifier</key>     <string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
<key>CFBundleExecutable</key>     <string>$(EXECUTABLE_NAME)</string>
<key>CFBundleShortVersionString</key><string>$(MARKETING_VERSION)</string>
<key>CFBundleVersion</key>        <string>$(CURRENT_PROJECT_VERSION)</string>
<key>LSRequiresIPhoneOS</key>     <true/>
<key>UILaunchScreen</key>         <dict/>
<!-- plus any usage-description strings your capabilities need -->
```

### Capabilities / entitlements

Declare capabilities in `AppOne/AppOne.entitlements`. Automatic signing with
`-allowProvisioningUpdates` (below) **registers them on the App ID for you** —
no manual capability toggling. Use the exact Apple entitlement keys, e.g.
`com.apple.developer.nearby-interaction`, `com.apple.developer.healthkit`, etc.

---

## 3. App Store Connect / Developer setup (one-time)

1. Join the **Apple Developer Program** ($99/yr).
2. For **each app**: App Store Connect → Apps → **+** → create an app record
   with that app's bundle id (the bundle id must already be reachable; with
   automatic signing the App ID is auto-created on first archive, or create it
   under Certificates, IDs & Profiles → Identifiers).
3. Create **one App Store Connect API key** (team-wide): Users and Access →
   Integrations → **App Store Connect API** → generate a key with **App
   Manager** (or Developer) access. Download the `.p8` **once**; record the
   **Key ID** and **Issuer ID**.
4. Note your **Team ID** (10 chars, Membership page).

## 4. Repository secrets

Settings → Secrets and variables → Actions:

| Secret | Value |
|---|---|
| `ASC_KEY_ID` | App Store Connect API key id |
| `ASC_ISSUER_ID` | issuer id (UUID) |
| `ASC_KEY_P8` | full contents of the `AuthKey_<id>.p8` file, pasted as-is |
| `APPLE_TEAM_ID` | 10-char team id |

---

## 5. The workflow — `.github/workflows/testflight.yml`

A cheap **discover** job (Ubuntu) builds the app list — all apps on manual run,
only **changed** apps on push — and a **matrix** of macOS jobs builds + uploads
each. Adding an app under `apps/` is picked up automatically.

```yaml
name: TestFlight

on:
  workflow_dispatch:
    inputs:
      app:
        description: "App subdir to build (or 'all')"
        default: all
  push:
    branches: [main]
    paths: ["apps/**"]

concurrency:
  group: testflight-${{ github.ref }}
  cancel-in-progress: false

jobs:
  discover:
    runs-on: ubuntu-latest
    outputs:
      apps: ${{ steps.list.outputs.apps }}
    steps:
      - uses: actions/checkout@v5
        with: { fetch-depth: 0 }
      - id: list
        run: |
          all=$(for d in apps/*/project.yml; do basename "$(dirname "$d")"; done)
          if [ "${{ github.event_name }}" = "workflow_dispatch" ] && [ "${{ inputs.app }}" != "all" ]; then
            sel="${{ inputs.app }}"
          elif [ "${{ github.event_name }}" = "push" ]; then
            changed=$(git diff --name-only "${{ github.event.before }}" "${{ github.sha }}" 2>/dev/null \
                      | grep '^apps/' | cut -d/ -f2 | sort -u)
            sel=$(comm -12 <(echo "$all" | sort) <(echo "$changed" | sort))
          else
            sel="$all"
          fi
          json=$(printf '%s\n' $sel | grep . | jq -R . | jq -cs .)
          echo "apps=$json" >> "$GITHUB_OUTPUT"
          echo "Selected apps: $json"

  testflight:
    needs: discover
    if: needs.discover.outputs.apps != '[]'
    runs-on: macos-15
    strategy:
      fail-fast: false
      matrix:
        app: ${{ fromJSON(needs.discover.outputs.apps) }}
    defaults:
      run:
        working-directory: apps/${{ matrix.app }}
    steps:
      - uses: actions/checkout@v5

      - name: Select Xcode
        uses: maxim-lobanov/setup-xcode@v1
        with: { xcode-version: latest-stable }

      - name: Install tools
        run: brew install xcodegen xcbeautify

      - name: Generate Xcode project
        run: xcodegen generate

      - name: Write App Store Connect API key
        env:
          ASC_KEY_P8: ${{ secrets.ASC_KEY_P8 }}
        run: |
          mkdir -p "$RUNNER_TEMP/keys"
          printf '%s' "$ASC_KEY_P8" > "$RUNNER_TEMP/keys/AuthKey.p8"

      - name: Archive
        env:
          TEAM_ID: ${{ secrets.APPLE_TEAM_ID }}
          ASC_KEY_ID: ${{ secrets.ASC_KEY_ID }}
          ASC_ISSUER_ID: ${{ secrets.ASC_ISSUER_ID }}
        run: |
          set -o pipefail
          xcodebuild archive \
            -project "${{ matrix.app }}.xcodeproj" \
            -scheme "${{ matrix.app }}" \
            -configuration Release \
            -destination 'generic/platform=iOS' \
            -archivePath "$RUNNER_TEMP/${{ matrix.app }}.xcarchive" \
            -allowProvisioningUpdates \
            -authenticationKeyPath "$RUNNER_TEMP/keys/AuthKey.p8" \
            -authenticationKeyID "$ASC_KEY_ID" \
            -authenticationKeyIssuerID "$ASC_ISSUER_ID" \
            DEVELOPMENT_TEAM="$TEAM_ID" \
            CODE_SIGN_STYLE=Automatic \
            CURRENT_PROJECT_VERSION=${{ github.run_number }} \
            | xcbeautify

      - name: Export & upload to TestFlight
        env:
          TEAM_ID: ${{ secrets.APPLE_TEAM_ID }}
          ASC_KEY_ID: ${{ secrets.ASC_KEY_ID }}
          ASC_ISSUER_ID: ${{ secrets.ASC_ISSUER_ID }}
        run: |
          set -o pipefail
          PLIST="$RUNNER_TEMP/ExportOptions.plist"
          printf '%s\n' \
            '<?xml version="1.0" encoding="UTF-8"?>' \
            '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
            '<plist version="1.0"><dict>' \
            '<key>method</key><string>app-store-connect</string>' \
            '<key>destination</key><string>upload</string>' \
            "<key>teamID</key><string>${TEAM_ID}</string>" \
            '<key>signingStyle</key><string>automatic</string>' \
            '</dict></plist>' > "$PLIST"
          xcodebuild -exportArchive \
            -archivePath "$RUNNER_TEMP/${{ matrix.app }}.xcarchive" \
            -exportOptionsPlist "$PLIST" \
            -allowProvisioningUpdates \
            -authenticationKeyPath "$RUNNER_TEMP/keys/AuthKey.p8" \
            -authenticationKeyID "$ASC_KEY_ID" \
            -authenticationKeyIssuerID "$ASC_ISSUER_ID" \
            | xcbeautify
```

---

## 6. Adding a new app

1. Create `apps/<Name>/project.yml` (project + target + scheme all named
   `<Name>`) and the sources/Info.plist/entitlements.
2. Create the app record in App Store Connect with its bundle id.
3. Push. The `discover` job finds it; the matrix builds and uploads it. No
   workflow change needed.

## 7. Installing the result

The first time, add yourself as an **internal tester** in App Store Connect →
your app → TestFlight. Internal testing needs **no App Review**; a build is
usable minutes after processing and lasts **90 days**. Install via the
**TestFlight** app on the device — over the air, no cable.

---

## 8. Gotchas worth knowing (learned the hard way)

- **Pin the newest stable Xcode** (`maxim-lobanov/setup-xcode@v1`,
  `latest-stable`). Homebrew installs the newest XcodeGen, which emits the
  newest project format; an older default Xcode then rejects it with "future
  Xcode project file format".
- **Define a scheme in `project.yml`.** XcodeGen doesn't auto-generate one, and
  `xcodebuild -scheme` needs it.
- **Build number must be unique and increasing per app.** `CURRENT_PROJECT_VERSION
  = github.run_number` does this; App Store Connect rejects duplicate build
  numbers. Each app has its own record, so the shared run number is fine.
- **`Info.plist` must carry the standard `CFBundle*` keys.** With an explicit
  `INFOPLIST_FILE`, Xcode does not synthesize them; a missing `CFBundleIdentifier`
  produces an app the simulator/device refuses to install.
- **Automatic signing via the API key registers capabilities for you.** With
  `-allowProvisioningUpdates` + the `-authenticationKey*` args, you don't manage
  certificates or provisioning profiles, and entitlements declared in the app
  get registered on the App ID. (Some entitlements require a paid account — and
  cannot be granted by free-provisioning / AltStore sideloads.)
- **Export method string** is `app-store-connect` on Xcode 15.3+. On older Xcode
  it's `app-store`.
- **macOS minutes bill at 10×.** Building only changed apps on push (the
  `discover` diff) keeps cost down; the manual `workflow_dispatch` with an `app`
  input lets you target one app on demand.
- **`fail-fast: false`** in the matrix so one app's failure doesn't cancel the
  others.
