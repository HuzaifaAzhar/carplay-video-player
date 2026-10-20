# Car Video

Watch your own videos and YouTube on the **CarPlay** screen. iPhone app, iOS 17+, installed with **TrollStore**.

- **Your videos in the car:** a grid of thumbnails sized for your car's screen, paged with big buttons (many head units only report taps, not swipes). Tap to play full screen; tap again for controls: play/pause, skip, previous/next, a position bar you can tap or drag, Fit/Fill and speed.
- **YouTube button:** opens YouTube's website full screen on the car, laid out at the car screen's real resolution so it isn't a stretched phone page. Floating toolbar with back, home, search and reload (iOS adds CarPlay scroll arrows to the page for cars that only report taps), and an on-screen keyboard for searching. Ads are skipped (can be turned off).
- **Fits any car screen:** everything scales from the area CarPlay gives the app and stays clear of the CarPlay dock. Video can optionally go behind the dock.
- **Add videos** from Files, Photos or a link (download, or save the link and stream). The app's folder also shows in the Files app as *Car Video*, so you can copy videos straight in. MP4, MOV and M4V play; MKV/WebM/AVI need converting first.
- **Remembers where you stopped** in every video, with watched/unwatched, sorting (date added, name, length, size, recently played), filters and folders.
- **From the iPhone:** remote controls while the car plays; a YouTube tab with a real keyboard and your account, and "Play on CarPlay" to send a video to the car. Steering-wheel buttons work too.
- **Safety:** video on the car screen is hidden while the car is moving (from GPS speed) and comes back when it stops; sound keeps playing. You can turn this off in Settings. It's meant for passengers and parked cars.

## Install and update

Add this source in **TrollApps** (or AltStore/SideStore). It updates on every build:

```
https://huzaifaazhar.github.io/carplay-video-player/apps.json
```

Each build is also on the [latest release](../../releases/latest) as `CarVideo.ipa`.

**TrollStore is required for the car screen.** Third-party CarPlay apps normally only get Apple's fixed templates (lists, grids, now playing), with no video. This app instead declares the private `SBStarkCapable` entitlement, which gives it its own window on the car screen like Apple's own CarPlay apps. Only TrollStore can install an app with that entitlement. Signed any other way, the app works on the iPhone but never appears in CarPlay. (iOS 26.4 added an official CarPlay video entitlement that uses the same kind of window, but Apple grants it per developer account.)

## How it works

- **Two scenes:** the iPhone window, and a plain `UIWindowScene` on the car display (role `UIWindowSceneSessionRoleCarPlay`), not a CarPlay template scene, so video and a web view can draw there and take touches. See `CarVideo/App/CarSceneDelegate.swift`.
- **Layout:** `CarMetrics` and `CarGridLayout` (`CarVideo/Car/CarMetrics.swift`) size text, buttons and tiles from the shorter side of the car area. The grid picks the columns × rows that fit whole tiles with readable thumbnails.
- **YouTube at native resolution:** iOS hands the car window a point size (a 1280×720 screen can arrive as about 467×263 pt). The web view is laid out at the pixel size and scaled down (`ScaledWebContainer`), with a page-size setting on top.
- **One player:** a single `AVPlayer` is shared between the iPhone and the car. The newest player layer shows the picture, so video moves to the car when it connects.
- **Diagnostics:** Settings → Diagnostics Log records the car screen's size, scale and safe area, plus playback and web events.

## Building

There's no Xcode project in the repo. GitHub Actions generates it with [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`project.yml`), builds an unsigned archive, signs it ad hoc with `CarVideo/CarVideo.entitlements`, and publishes the IPA and the source.

**CarPlay Simulator Test** (`.github/workflows/carplay-sim.yml`) checks the car screen without a car:

1. It runs the app in the iOS Simulator with CarPlay displays at several scales (800×480 px at @2, @3 and @1, so 400×240, 267×160 and 800×480 pt; other sizes can be chosen when running it by hand). The simulator's CarPlay only uses an 800×480 px area, so scale is what changes the layout.
2. The app's demo mode (`-CarVideoDemo YES`) walks through every screen: the home grid, a real tap on the YouTube button, YouTube, the keyboard, and four sample videos in different shapes.
3. The screenshots and the app's log are published to the `carplay-test` pre-release.
