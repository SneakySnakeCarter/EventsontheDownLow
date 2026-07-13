# App Store Readiness Checklist

A working pass over what's done and what's left before submitting
EventsontheDownLow to the App Store.

## ✅ Already in place

- **App icon** — 1024×1024, no alpha channel (this specifically broke
  notification icons during development — see git history / conversation
  notes if this ever regresses)
- **Display name** set separately from the internal product name
- **Camera permission string** (`NSCameraUsageDescription`)
- **Photo library add-only permission string** (`NSPhotoLibraryAddUsageDescription`)
- **Background task identifiers** declared (`BGTaskSchedulerPermittedIdentifiers`)
- **Notification permission** requested at first launch
- **Privacy manifest** (`PrivacyInfo.xcprivacy`) — declares no tracking, no
  data collection; double-check the "required reason API" section stays
  accurate as Apple's list evolves (see comments in that file)
- **Debug logging** wrapped in `#if DEBUG` throughout, so none of the verbose
  diagnostic prints added during development ship in the Release build
- **Multi-reminder notifications capped at 60 pending**, staying safely
  under iOS's actual 64-per-app limit even with several reminders on
  several recurring events — see NotificationScheduler.swift's doc comment
- **Force-casts removed** from BackgroundTaskManager's task handlers,
  replaced with guarded casts that fail safely instead of crashing in the
  (unlikely) event of a type mismatch
- **NotificationContentExtension set up** (if you completed the SETUP.md
  walkthrough) — full-size expanded photo, correct app icon, title/body
  all confirmed working together on a real device

## ⚠️ Needs your attention before submitting

- [ ] **App Store Connect listing**: name, subtitle, description, keywords,
      support URL, marketing URL (optional), privacy policy URL (required
      even for a no-collection app — a one-page "we don't collect anything"
      page satisfies this)
- [ ] **Screenshots** for each required device size (6.9", 6.5" iPhone
      minimum; iPad if you mark the app as supporting iPad)
- [ ] **App category** (likely Productivity or Lifestyle)
- [ ] **Age rating questionnaire** in App Store Connect
- [ ] **Version number & build number** — set a real starting version
      (e.g. 1.0.0 / build 1) in the target's General tab
- [ ] **Bundle identifier** — confirm it's a real reverse-DNS identifier
      registered to your Apple Developer account, not a placeholder
- [ ] **Signing & Capabilities** — confirm a real distribution certificate
      and provisioning profile are set up (Automatically manage signing is
      fine for most solo-developer cases)
- [ ] **App Review notes**: since this app requests Camera, Photos
      (add-only), and Notifications permissions, consider adding a short
      note in the App Review Information section explaining what each is
      for — reviewers sometimes flag permission requests they can't
      immediately trace to a feature
- [ ] **Test on a real device one more time end-to-end**: create event →
      attach photo (picker + camera) → save to Photos → add multiple
      reminders at different intervals → recurring daily reminder with
      "Never" end → notification fires with correct icon/image/timing →
      edit → delete (covers everything we debugged together)
- [ ] **TestFlight pass** — even a single internal TestFlight build/install
      cycle catches a surprising number of issues Xcode's simulator/debug
      builds don't (we hit exactly this class of issue with the app icon
      alpha channel bug, and separately with a simulator-only nav bar
      rendering quirk on iOS 26 that didn't reproduce on a real device)
- [ ] **NotificationContentExtension target** — if you didn't end up setting
      this up (it was optional/deferred at one point), decide before
      submission whether to include it or remove the unused files from the
      project
- [ ] **Remove any remaining test/dummy events** created during development
      before you consider the app "done" for your own use, if this matters
      to you (not an App Store requirement, just good hygiene)
- [ ] **Source control**: if you've set up the GitHub repo, make sure this
      final cleanup pass gets committed and pushed as a clean baseline
      before you start the App Store Connect submission process

## Not required for personal/single-developer apps, but worth knowing

- No account/login system exists in this app, so Apple's "Sign in with
  Apple" requirement (which only applies if you offer *other* third-party
  logins) doesn't apply here.
- No in-app purchases or subscriptions exist, so no App Store Connect
  in-app purchase setup is needed.
