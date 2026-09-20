# Ethnir - Space (modified Space v2.3.1 → 2.4.0)

Modified build of [eliwoahzja/Space](https://github.com/eliwoahzja/Space)
(`com.gspace.android`, a virtual-container app), rebuilt as **Ethnir - Space**.

Final artifact: `public/ethnir-space-v2.4.0.apk` (signed, zipaligned, ~17.6 MB)
Rebuild pipeline: `scripts/ethnir-mod.sh` (idempotent)

## Install-over compatibility
This is **not a new app** — same package (`com.gspace.android`) and signed with
the **same AOSP testkey** (`SHA256 A4:0D:A8:0A:…:F5:DC`) as prior Space builds,
so it installs directly **over** the original Space v2.3.1 and any earlier
rebuilt version (versionCode 50 → 51). No uninstall, no data loss.

## What was changed

### 1. Rename
- `app_name` in every locale's `strings.xml` and the `AndroidManifest.xml`
  launcher label → **Ethnir - Space** (verified across all 95 locales).
- `versionName 2.3.1 → 2.4.0`, `versionCode 50 → 51`.

### 2. Black & white theme
- Rewrote the brand palette in `res/values/colors.xml`: greens
  (`#2aa05a`, `#03c27c`, `#41bf3e`), blues (`#11a1fd`, `#046eb2`, `#248bff`),
  pink accent (`#ff4081`) and red (`#e40e1d`) → white / grayscale.
- Existing `*_black` dark-mode twins were kept (their resource IDs are pinned
  in `public.xml`; deleting them breaks aapt2 linking) — they already fit B&W.
- Grayscaled Pangle SDK bitmap assets under `res/`.

### 3. Performance / stability (the FPS-drop & crash fixes)
The stock app runs two heavy subsystems that conflict with games inside the
container (reported: mid-game FPS drops in CoD Mobile, OOM crashes):

| Subsystem | What it does | Patch |
|---|---|---|
| Pangle (ByteDance) ads | SDK init, splash/banner/fullscreen ad fetches | `TTAdSdk.init` no-op'd; `TTAdNative` getter returns null; splash/banner/fullscreen loaders no-op'd |
| Huawei HMS ads | `HwAds.init` + preload pipeline | no-op'd at the master init site |
| WatchDog keep-alive | silent music player, dual-process daemon, wallpaper service, 1-pixel activity, account-sync keepalive | `WatchDog.startWatch()` → immediate `return-void` |

All patches are app-side call-site cuts (SDK classes untouched), so null-safe
dispatch helpers keep the UI flow intact — no NPEs, splash proceeds instantly.

### 4. Build pipeline
- Decoded: apktool 3.0.3 (matches the decode in `apktool.yml`).
- Rebuilt with the system aapt/aapt2 from apktool 2.5 (2020) — too old for
  this APK (arsc overlap errors); use `/tmp/apktool.jar` v3.0.3 as in the script.
- `zipalign -f -p 4`, signed with the **AOSP testkey** (`testkey.pk8` /
  `testkey.x509.pem` in the repo root) — the same key prior Space builds used,
  which is what makes over-install work. Don't switch keys, or the chain breaks.

## Rebuilding
```bash
bash scripts/ethnir-mod.sh   # idempotent; safe to re-run
```

## Verification performed
- `apksigner verify` → OK; cert SHA256 matches the original chain:
  `A4:0D:A8:0A:59:D1:70:CA:A9:50:CF:15:C1:8C:45:4D:47:A3:9B:26:98:9D:8B:64:0E:CD:74:5B:A7:1B:F5:DC`.
- Badge/label: `aapt dump badging` shows `Ethnir - Space` in all locales.
- Re-decoded the signed APK and confirmed in smali:
  `startWatch()` = `return-void`, TTAdNative getter = `const/4 v0, 0x0`,
  no `TTAdSdk.init` / `HwAds.init` / `loadSplashAd` / `loadBannerExpressAd` /
  `loadFullScreenVideoAd` call sites remain in app code.

## Note on scope
The `com.gspace.virtual.*` container core (stub activities/services, VPN
plumbing, dex2c-protected loaders) was left untouched — that's the machinery
that actually runs the cloned games; only the ad + keep-alive layers around it
were disabled.
