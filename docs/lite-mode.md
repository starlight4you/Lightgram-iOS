# Lite Mode for older iPads

This document describes the runtime "Lite Mode" added to this fork to make
Telegram-iOS usable on older iPads (iPad Air 2 / iPad mini 4 / iPad Pro 1st
generation class hardware).

## What it does

When Lite Mode is on, the app:

- Disables `UIVisualEffectView` blur (navigation bar, sheet headers,
  context-menu backdrops, peer-info dynamic-island area).
- Stops chat-wallpaper gradient animations and freezes the gradient on a
  single static frame.
- Hides the Stories carousel from the chat-list header and short-circuits
  every entry point that would open `StoryContainerScreen` (peer avatar
  taps, "My Stories" buttons, story camera, story notifications, profile
  Stories pane, story-upload progress events). Stories sync stops fetching
  from the network.
- Skips the Metal-based `DustEffectLayer` message-deletion effect.
- Skips the `ConfettiEffect` particle system.
- Disables the iOS 17 fluid-glass mesh transform in `LegacyGlassView`.
- Forces `EnergyUsageSettings.powerSavingDefault` for the running session,
  which kills sticker/emoji looping, GIF/video autoplay and translucency
  saturation work.
- Persists the user's actual `EnergyUsageSettings` untouched, so toggling
  Lite Mode off restores their previous behaviour.

### Pass 2 (scroll / GPU tuning, Lite Mode only)

When `sharedLiteModeEnabled` is true, the app additionally:

- Caps display-link frame rate at **60 Hz** on iPad (no 120 Hz preferred range).
- Shrinks `ListView` off-screen preload from **500 pt** to **200 pt** (`liteModeListPreloadInset`).
- Skips CPU wallpaper thumbnail blur (`telegramFastBlurMore`) and gradient keyframe generation.
- Disables blur on secondary UI (undo toast, overlay player, minimized container, context-menu sliders).
- Limits simultaneous custom-emoji decoders to **10** and inline GIF software decodes to **4**.
- Disables layer shadows on chat input chrome (send button, record button, reaction labels).
- Uses **Application Support** as the data container when App Groups are unavailable (required for free Personal Team builds without the App Groups entitlement).

Constants live in [`submodules/Display/Source/LiteModeFlags.swift`](../submodules/Display/Source/LiteModeFlags.swift).

### Pass 3 (keyboard show, Lite Mode only)

When the system keyboard animates up, `UIKeyboardWillChangeFrameNotification`
fires on every animation frame and drives a full chat relayout. The largest
remaining cost is the **synchronous message-list inset relayout**
(`.Synchronous | .LowLatency` in `ChatHistoryListNode`); Pass 3 deliberately
does **not** change that path to avoid the input panel and history list
getting out of sync.

Pass 3 instead removes per-frame GPU work on the input chrome:

- **`GlassBackgroundView`** — keeps the original static glass appearance
  (foreground glass image + shadow, regenerated only when params change, not
  every keyboard frame). In Lite Mode it hides `LegacyGlassView` (private
  `CABackdropLayer` live blur) and clears `foregroundView.mask` so the
  `luminanceToAlpha` offscreen mask is not composited each frame
  ([`GlassBackgroundComponent.swift`](../submodules/TelegramUI/Components/GlassBackgroundComponent/Sources/GlassBackgroundComponent.swift)).
  `GlassBackgroundContainerView` is unchanged from stock on iOS &lt; 26 (no
  extra fill layer).
- **Send/mic button crossfade** — skips `setBlur` on the send container when
  `sharedDisableBlur` is set
  ([`ChatTextInputPanelNode.swift`](../submodules/TelegramUI/Components/Chat/ChatTextInputPanelNode/Sources/ChatTextInputPanelNode.swift)).

**First-tap warmup** is already handled: `ChatController.viewDidAppear` calls
`loadInputPanels` → `loadTextInputNodeIfNeeded()` so `UITextView` is created
before the user taps the field.

If keyboard jank persists after Pass 3, the next lever is async or throttled
list inset updates during keyboard animation (higher risk).

### Pass 4 (long-press context menu, Lite Mode only)

- **Menu backdrop** — `ContextSourceContainer` sets
  `keepTransparentWhenBlurDisabled` on its `NavigationBackgroundNode`, so Lite
  Mode keeps `theme.contextMenu.dimColor` alpha (~0.2 day / ~0.6 dark) instead
  of the global `withAlphaComponent(1.0)` opaque fill
  ([`NavigationBackgroundView.swift`](../submodules/Display/Source/NavigationBackgroundView.swift),
  [`ContextSourceContainer.swift`](../submodules/TelegramUI/Components/ContextControllerImpl/Sources/ContextSourceContainer.swift)).
- **Reaction bar** — preset reactions use `hasAppearAnimation: false` so the
  still frame shows immediately (no wait for appear `.tgs` decode). `animateIn`
  uses `effectiveReduceMotion` (includes `sharedLiteModeEnabled`) to skip
  staggered delays and spring pop-in
  ([`ReactionContextNode.swift`](../submodules/ReactionSelectionNode/Sources/ReactionContextNode.swift)).
- **Stars slot** — `CAEmitterLayer` particles are not added in Lite Mode
  ([`ReactionSelectionNode.swift`](../submodules/ReactionSelectionNode/Sources/ReactionSelectionNode.swift)).

### Pass 5 (reaction bar load + tap, Lite Mode only)

- **Static frame source** — when `hasAppearAnimation` is false, Lite Mode still uses
  `stillAnimation` (`selectAnimation`) instead of the heavier `activateAnimation`
  file, so thumbnails appear immediately and first-frame decode is faster
  ([`ReactionSelectionNode.swift`](../submodules/ReactionSelectionNode/Sources/ReactionSelectionNode.swift)).
- **Tap before decode** — `isAnimationLoaded` treats setup/placeholder as loaded so
  reactions can be selected without waiting for `.tgs` first-frame decode.
- **Tap fly-out** — skips `aroundAnimation` / Lottie burst effects and forces
  `switchToInlineImmediately` so the icon jumps to the message without heavy
  effect playback ([`ReactionContextNode.swift`](../submodules/ReactionSelectionNode/Sources/ReactionContextNode.swift)).
- **Standalone reaction** — `StandaloneReactionAnimation.animateReactionSelection`
  completes immediately and reveals the target icon (no center/burst animations).
- **Static icon fast path** — `ReactionItem.staticIcon` (pre-fetched server
  `staticIcon`) is passed from `TopMessageReactions` and rendered via
  `TransformImageNode` + synchronous sticker load in Lite Mode, bypassing
  `.tgs` decode for the reaction bar entirely.

### Pass 6 (sticker/emoji panel open, Lite Mode only)

- **Async first-frame loads** — visible keyboard cells no longer call
  `loadFirstFrameSynchronously` on first paint; placeholders show immediately
  and stickers/emojis fill in asynchronously
  ([`EmojiPagerContentComponent.swift`](../submodules/TelegramUI/Components/EntityKeyboard/Sources/EmojiPagerContentComponent.swift)).
- **Earlier data preload** — `loadInputPanels` runs in `viewWillAppear` (not
  only `viewDidAppear`) so sticker/emoji `inputData` is ready before the user
  taps the panel button
  ([`ChatController.swift`](../submodules/TelegramUI/Sources/ChatController.swift)).
- **No trending section** — `hasTrending: false` skips featured/trending pack
  assembly and related network refresh on the critical path
  ([`ChatControllerNode.swift`](../submodules/TelegramUI/Sources/ChatControllerNode.swift)).
- **Drop unused premium list** — `CloudAllPremiumStickers` is removed from the
  sticker ordered-list subscription (it was never consumed in the item builder)
  ([`ChatEntityKeyboardInputNode.swift`](../submodules/TelegramUI/Components/ChatEntityKeyboardInputNode/Sources/ChatEntityKeyboardInputNode.swift)).

### Pass 7 (cold start, Lite Mode only)

- **Launch timing probes** — `ColdStart[T0/T1/T2_*]` logs in
  [`AppDelegate.swift`](../submodules/TelegramUI/Sources/AppDelegate.swift) measure
  launch-to-ready and post-first-frame warmup start.
- **Deferred launch I/O** — legacy log cleanup, directory diagnostics, and cache
  reindex move to after the root controller is attached (`T2`).
- **Primary account first** — non-primary accounts open after first frame via
  [`SharedAccountContext.swift`](../submodules/TelegramUI/Sources/SharedAccountContext.swift).
- **Deferred warmups** — story preload skipped (Lite) or delayed; chat history
  preload delayed 1s
  ([`ChatListController.swift`](../submodules/ChatListUI/Sources/ChatListController.swift),
  [`ChatListControllerNode.swift`](../submodules/ChatListUI/Sources/ChatListControllerNode.swift)).
- **Lazy Contacts/Calls tabs** — placeholder tab items first; real controllers
  materialize ~1.5s after first frame
  ([`TelegramRootController.swift`](../submodules/TelegramUI/Sources/TelegramRootController.swift)).
- **Deferred services** — device contact/location managers, call manager, and
  animated-emoji pack subscription initialize after first frame
  ([`SharedAccountContext.swift`](../submodules/TelegramUI/Sources/SharedAccountContext.swift),
  [`AccountContext.swift`](../submodules/TelegramUI/Sources/AccountContext.swift)).

### Pass 8 (chat list → chat open latency, Lite Mode only)

Symptom: the tapped row highlights immediately, but the chat screen appears only
after several seconds because `NavigationContainer` waits for `ChatController.ready`.

- **Open timing probes** — `ChatOpen[T0]` … `ChatOpen[T4]` in
  [`LiteModeFlags.swift`](../submodules/Display/Source/LiteModeFlags.swift) (logged
  when Lite Mode is on). Filter Console with `ChatOpen[` on device.
- **Tap / highlight preload** — `addAdditionalPreloadHistoryPeerId` on row highlight
  ([`ChatListItem.swift`](../submodules/ChatListUI/Sources/Node/ChatListItem.swift))
  and on `peerSelected` ([`ChatListController.swift`](../submodules/ChatListUI/Sources/ChatListController.swift)).
- **Faster history preload scheduling** — `sharedReducedHistoryPreloadDelays` in
  [`PerformanceFlags.swift`](../submodules/TelegramCore/Sources/PerformanceFlags.swift)
  shortens list preload update delay (1s → 0.1s) and hole start delay; priority
  (user-tapped) peers start immediately
  ([`ChatHistoryPreloadManager.swift`](../submodules/TelegramCore/Sources/State/ChatHistoryPreloadManager.swift)).
- **Earlier list preload hookup** — history preload attaches after **0.1s** instead
  of 1s when Lite defer warmups are active
  ([`ChatListControllerNode.swift`](../submodules/ChatListUI/Sources/ChatListControllerNode.swift));
  preload item cap **45** vs 30
  ([`ChatListNode.swift`](../submodules/ChatListUI/Sources/Node/ChatListNode.swift)).
- **Fast `peerSelected` path** — most peers navigate without waiting for
  `cachedPeerData`; forum “view as messages” and saved-messages-chats still use the
  cached gate ([`ChatListController.swift`](../submodules/ChatListUI/Sources/ChatListController.swift)).
- **Lite fast `ready`** — chat push no longer waits for wallpaper or full
  `ContentData` initialData / persistent state; only peer info + history first frame
  ([`ChatControllerLoadDisplayNode.swift`](../submodules/TelegramUI/Sources/Chat/ChatControllerLoadDisplayNode.swift),
  [`ChatControllerContentData.swift`](../submodules/TelegramUI/Sources/ChatControllerContentData.swift)).
- **Highlight UX** — list highlight clears when navigation starts (push), not only
  after `ready` completion.

The data layer (Postbox `StorySubscriptionsTable`, `StoryStatesTable`,
`TelegramCore/Sources/TelegramEngine/Messages/Stories.swift`) is left
intact, so future upstream merges keep working.

## How it turns on

1. **Auto-detection** — `DeviceMetrics.performance.isLowEndDevice` is `true`
   when the device has fewer than 4 CPU cores OR less than 3 GB of RAM
   (read once at app launch via `sysctlbyname` on `hw.ncpu` / `hw.memsize`).
2. **Manual override** — open the in-app Debug menu → Experiments → "Lite
   Mode". Tapping the toggle cycles through three states:
   - "Auto (On)" / "Auto (Off)" — follows the device-class auto-detect.
   - "On" — force enable.
   - "Off" — force disable.

The state is persisted in `ExperimentalUISettings.liteMode` (`Bool?`,
`nil` = auto).

## Build

This fork uses the standard Telegram-iOS build flow. There is no separate
"lite" target — the same `Telegram/Telegram` Bazel target builds with
Lite Mode embedded.

### `api_id` / `api_hash`

You need a personal API key from <https://my.telegram.org/apps>. Telegram's
own AppStore key (`api_id = 8`, `api_hash = 7245de8e747a0d6fbe11f7cc14fcc0bb`)
is committed to the repo for reference but **must not** be used for builds
you will distribute or sign with your own provisioning profile.

The credentials flow through:

```
build-system/<your-config>.json         (you edit this)
    │
    ▼   (Make.py reads this)
@build_configuration//:variables.bzl     (Make.py rewrites)
    │
    ▼   (BUILD reads telegram_api_id / telegram_api_hash)
submodules/BuildConfig/BUILD             (defines APP_CONFIG_API_ID / APP_CONFIG_API_HASH)
    │
    ▼   (compile-time defines)
submodules/BuildConfig/Sources/BuildConfig.m    (BuildConfig.apiId / .apiHash)
```

Copy the example config and fill in your own credentials (never commit the
real file):

```sh
cp build-system/lite-development-configuration.json.example \
   build-system/lite-development-configuration.json
```

Edit `build-system/lite-development-configuration.json` with your
`bundle_id`, `api_id`, `api_hash`, and `team_id`.

If you change **Apple account** or **bundle ID** in Xcode only, Bazel will still
look for the old provisioning profile until you update this JSON and regenerate:

```sh
# Edit build-system/lite-development-configuration.json (bundle_id + team_id)
python3 build-system/Make/Make.py --overrideXcodeVersion \
    --cacheDir ~/telegram-bazel-cache \
    generateProject \
    --configurationPath build-system/lite-development-configuration.json \
    --xcodeManagedCodesigning \
    --disableExtensions \
    --buildNumber=10
```

Then quit Xcode, clear DerivedData (`chmod -R u+w …` + `rm -rf …/Telegram-*`),
reopen `Telegram/Telegram.xcodeproj`, and confirm **Signing & Capabilities**
uses the same Team and bundle ID as the JSON file.

### Simulator build (lowest friction, no codesigning)

```sh
python3 build-system/Make/Make.py --overrideXcodeVersion \
    --cacheDir ~/telegram-bazel-cache \
    build \
    --configurationPath build-system/lite-development-configuration.json \
    --xcodeManagedCodesigning \
    --buildNumber=1 \
    --configuration=debug_sim_arm64
```

Add `--continueOnError` to surface every error in one pass when verifying
big changes (per the upstream `CLAUDE.md` guidance).

### Real-device build (development)

For a **free Apple Developer (Personal Team)** account, use Xcode-managed
signing and disable extensions:

```sh
python3 build-system/Make/Make.py --overrideXcodeVersion \
    --cacheDir ~/telegram-bazel-cache \
    build \
    --configurationPath build-system/lite-development-configuration.json \
    --xcodeManagedCodesigning \
    --disableExtensions \
    --buildNumber=1 \
    --configuration=debug_arm64
```

The first device build can take **1–2 hours**. Install the resulting IPA with
Xcode (Window → Devices and Simulators → drag `bazel-bin/Telegram/Telegram.ipa`)
or `xcrun devicectl device install app --device <UDID> <path-to-app>`.

### Xcode build troubleshooting

#### `BazelDependencies` / `no such package … Telegram_xcodeproj` / `BUILD file not found`

This happens when the Xcode project is out of sync with Bazel (common after
`Make.py build` or pulling new commits). The **Generate Bazel Dependencies**
phase looks for generated files that do not exist yet.

Fix (from `Telegram-iOS/`):

```sh
python3 build-system/Make/Make.py --overrideXcodeVersion \
    --cacheDir ~/telegram-bazel-cache \
    generateProject \
    --configurationPath build-system/lite-development-configuration.json \
    --xcodeManagedCodesigning \
    --disableExtensions \
    --buildNumber=10
```

Then open **`Telegram/Telegram.xcodeproj`** (the script may open it for you),
quit and reopen Xcode if it was already open, and build again.

#### `Permission denied` when processing `Info.plist` under `bazel-out`

Example:

```text
unable to write file '.../DerivedData/Telegram-.../bazel-out/.../SwiftSignalKitFramework.framework/Info.plist': Permission denied (13)
```

Bazel marks outputs under `bazel-out` as **read-only**. Xcode then fails if it tries
to rewrite those plists during **Process Info.plist** (often after a prior
`Make.py build` left stale artifacts in DerivedData).

Fix:

1. Quit Xcode.
2. Clear DerivedData:

```sh
chmod -R u+w ~/Library/Developer/Xcode/DerivedData/Telegram-* 2>/dev/null
rm -rf ~/Library/Developer/Xcode/DerivedData/Telegram-*
```

If `rm` reports `Permission denied`, run the `chmod` line first, then `rm` again.

3. Reopen `Telegram/Telegram.xcodeproj` and build (⌘B). Let Xcode run its own
   Bazel steps; do not copy `bazel-bin` outputs into DerivedData manually.
4. If it still fails, regenerate the project (`generateProject` command above),
   then build again.

Avoid alternating **Make.py build** and **Xcode build** within seconds on the
same machine without clearing DerivedData first.

#### `SwiftSignalKit.swiftmodule` / `.swiftdoc` / `.swiftsourceinfo`: No such file or directory

If Xcode fails with `copy … SwiftSignalKit.swiftmodule` (or `.swiftdoc`,
`.swiftsourceinfo`) from a path under `DerivedData/.../bazel-out/.../Objects-normal/arm64/`,
and the build finishes in **under ~5 minutes** on a clean machine, the **Bazel
compile step did not run** — only empty placeholder `.d` files were created (~58 s
total is a typical symptom).

Fix:

1. Quit Xcode.
2. Clear DerivedData (include `chmod` if needed — see Permission denied section above).
3. Reopen `Telegram/Telegram.xcodeproj`.
4. **Scheme → Build → uncheck “Parallelize Build”.** This is important for
   `rules_xcodeproj`; parallel builds often copy modules before Bazel produces them.
5. **Product → Clean Build Folder** (⇧⌘K), then **Build** (⌘B).
6. Watch the build log: you must see many lines like `Compiling Swift module …`
   and Bazel actions for **minutes** (first device build often **30–90+ minutes**).
   Do not stop after ~1 minute.

Optional pre-warm (from `Telegram-iOS/`, same flags as Xcode project):

```sh
./build-input/bazel-8.4.2-darwin-arm64 build //Telegram:SwiftSignalKitFramework \
  --disk_cache=~/telegram-bazel-cache \
  --define=buildNumber=10 \
  --//Telegram:disableExtensions \
  --//Telegram:disableStripping \
  -c dbg --ios_multi_cpus=arm64
```

That does not replace a full Xcode build, but it can populate the disk cache before
you retry in Xcode.

If you only need a device build and cold-start timing, **`Make.py build` + IPA**
remains the reliable path; use Xcode when you need the debug console or breakpoints.

Ensure provisioning profiles are visible to Bazel (Xcode 15+ stores them under
`~/Library/Developer/Xcode/UserData/Provisioning Profiles/`). Symlink to the
legacy path if needed:

```sh
ln -sfn "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles" \
  "$HOME/Library/MobileDevice/Provisioning Profiles"
```

### Viewing cold-start timing logs

Pass 7 adds `ColdStart[…]` lines and the existing `Launch to ready took … ms`
message. How to see them:

**Xcode Run (recommended after `generateProject`)**

1. Connect the iPad, select the **Telegram** scheme, destination = your device.
2. Run (⌘R). Open the **debug console** (View → Debug Area → Activate Console).
3. Filter for `ColdStart` or `Launch to ready`. Example sequence:
   - `ColdStart[T0_didFinishLaunching]: …`
   - `ColdStart[AccountManager_ready]: …`
   - `ColdStart[SharedAccountContext_ready]: …`
   - `ColdStart[T1_rootControllerAttached]: …`
   - `Launch to ready took … ms`
   - `ColdStart[T2_postFirstFrameWorkStart]: …`

**IPA install without Xcode**

Install the IPA from `Make.py build`, then on the Mac open **Console.app**,
select the iPad, filter process **Telegram** (or your bundle id), reproduce a
cold start (swipe away the app, relaunch). `print()` output appears only if the
build is **Debug**; release/IPA builds may omit console logs unless you attach
a debugger.

For comparable numbers, cold-start the app **10 times** and note **T1 − T0**
from `ColdStart[T1_rootControllerAttached]` minus `ColdStart[T0_didFinishLaunching]`.

## Verifying Lite Mode is active

In Debug builds you can check at runtime via the Debug menu. To verify
auto-detection on a particular device, add a one-line `print()` to
`SharedAccountContext.applyLiteModeFlags` (or set a breakpoint).

The implementation is intentionally a set of `if sharedLiteModeEnabled` /
`sharedDisableBlur` gates spread across a modest number of files, so disabling
Lite Mode at runtime restores upstream behaviour on capable hardware. The flag
definition lives in
[`submodules/Display/Source/LiteModeFlags.swift`](../submodules/Display/Source/LiteModeFlags.swift).

### Tuning preload inset on device

If chat-list scroll still drops frames, try lowering `liteModeListPreloadInset` in
`LiteModeFlags.swift` (e.g. 150). If you see blank rows while flinging, raise it
(e.g. 250–300) and rebuild.
