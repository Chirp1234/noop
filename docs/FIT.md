# Fit tab (iOS)

The **Fit** tab sits where Coach used to (Coach is still under **More** while it's switched on).
It has two halves, picked with the switch at the top:

**Workouts**
- This week's progress against a weekly goal, the last 28 days as a strip, and a week streak.
- Today's planned workout from your weekly plan, with a one-tap Start.
- Other options for the day: a suggestion (the muscle group you've neglected longest) plus every
  day option: Push, Pull, Legs, Upper, Lower, Chest, Back, Shoulders, Arms, Biceps, Triceps, Abs,
  Full body, Cardio, and your own workouts.
- Weekly plan: apply a split (Push/Pull/Legs, Upper/Lower, Bro split, Full body) or set any day.
- My workouts: build your own from 60+ exercises, or add custom exercises.
- Live logging: weight × reps per set, last time's numbers alongside, rest timer, personal bests.
- History: every session, workouts per week, personal bests.

**Food**
- Calories left today (ring), protein / carbs / fat against your goals.
- Breakfast, lunch, dinner and snacks; add from a ~100-item food list, recent foods, your own
  foods, or a quick calorie entry. Tap an entry to change the amount or meal, or delete it.
- The last 7 days as a chart, and earlier days via the arrows.

Everything is stored on the iPhone only (`Application Support/Fit/fit.json`), separate from strap
data. Export a backup from the Fit settings button (top right).

## Install on iPhone

### Option A: `.ipa` from GitHub (no Mac needed)

1. Fork this repo on GitHub, push your branch, then open **Actions** in your fork and enable
   workflows.
2. Run **Testing build (fork)** (`Run workflow`, pick your branch). When the `ios` job finishes,
   the release **testing-latest** in your fork has `NOOP-ios-unsigned-v….ipa`.
3. On Windows or Mac, install it with **Sideloadly** or **AltStore/SideStore** using your own
   free Apple ID (see [IOS.md](IOS.md)). Free Apple IDs re-sign every 7 days; AltStore/SideStore
   can do that automatically.
4. On the iPhone: Settings → General → VPN & Device Management → trust your Apple ID, and turn on
   Developer Mode (Settings → Privacy & Security) if asked.

The workflow's ipa uses the production bundle id, so it replaces an installed NOOP build and keeps
its data.

### Option B: Xcode (needs a Mac)

```bash
brew install xcodegen
cp Config/BundleIdSecrets.example.xcconfig Config/BundleIdSecrets.xcconfig
# edit Config/BundleIdSecrets.xcconfig: set BUNDLE_ID_PREFIX to something of your own, e.g. com.yourname
xcodegen generate
open Strand.xcodeproj
```

In Xcode: sign in with your Apple ID (Settings → Accounts), choose the **NOOPiOS** scheme and your
iPhone as the destination, and select your Personal Team under Signing & Capabilities for both
**NOOPiOS** and **NOOPiOSWidgets**. Then press **Run**. See [IOS.md](IOS.md) for the full notes on
signing and the App Group.
