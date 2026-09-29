<div align="center">
  <img src="./assets/images/text_logo_color.svg" alt="Chameleon" height="72" style="margin: 20px 0;">

  **A Jellyfin client that changes its colors to suit you.**

  Direct-play video, a home screen you build yourself, and a theme engine with shareable theme codes, on phones, tablets, TVs and desktops.

  ![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter&logoColor=white)
  ![Jellyfin](https://img.shields.io/badge/Jellyfin-client-00A4DC?logo=jellyfin&logoColor=white)
  ![Status](https://img.shields.io/badge/status-early%20development-orange)
</div>

---

## About

Chameleon is a free, open-source Jellyfin client built with Flutter and [forui](https://forui.dev). It plays your movies and shows exactly as they're stored, decoding them on your device with mpv so your server never has to transcode. And it lets you shape almost everything you see: which rows are on the home screen and in what order, whether titles appear as tall posters or wide thumbnails, which fonts the app uses, and the whole color scheme.

The name is the idea. Pick one of eight gem-toned themes, or build your own from four dials: base hue, accent hue, vibrance and depth. Every custom theme boils down to an eight-digit **theme code** you can share, so someone else can load your exact look in one step. If you want full control, switch to Advanced mode and set every color token by hand.

Chameleon adapts to the screen it's on, too. Phones get a bottom tab bar and a portrait layout that flips to full-screen landscape for video. Tablets, desktops and TVs get a top navigation bar, and the whole interface scales with the window so it looks right on a laptop or across the room. Everything can be driven with a mouse, touch, a keyboard or a TV remote's D-pad.

Your watch progress is reported back to Jellyfin as you play, so Continue Watching and Next Up stay in sync with every other Jellyfin app you use. Chameleon talks only to your own server: no accounts, no analytics, no third-party services.

> **Status:** Chameleon is in early development. Video playback works but is still being refined, and there are no published builds yet. See [Roadmap](#roadmap) for what's still to come.

---

## Features

### 🏠 A home screen you build

Select the ✏️ pencil to enter edit mode, then add, remove and reorder sections. Each row can switch between posters and 16:9 thumbnails, and **Reset to default layout** puts everything back. Your layout is saved on the device.

| Section | What it shows |
|---|---|
| **Featured** | A rotating banner of random titles with backdrop art, logo, Play and More info. Advances every 8 seconds; swipe, arrows or dots to move it yourself. |
| **Continue Watching** | Movies and episodes you've started, with a progress bar. |
| **Next Up** | The next episode of each show you're watching. |
| **Favorites** | Your favorited movies and shows. |
| **Recently Added** | The newest movies and shows on the server. |
| **Recently Added Movies** | Newest movies only. |
| **Recently Added Shows** | Shows with the newest episodes. |
| **Suggested For You** | Jellyfin's picks for you, or a random mix if you're new. |
| **Because You Watched…** | Titles sharing genres with the last thing you finished, e.g. *Because You Watched Dune*. |
| **Collection** | A collection you pick. Add as many as you like. |
| **Genre** | A genre you pick. Add as many as you like. |

New users start with Featured, Continue Watching, Next Up, Recently Added and Suggested For You.

### 🎨 Themes, fonts and theme codes

- **Eight built-in themes:** Prism, Ruby, Amber, Citrine, Emerald, Sapphire, Tanzanite and Amethyst. The logo shows its full colors on Prism and takes on a gradient of the theme's colors everywhere else.
- **Custom themes, simple mode:** four steppers (Base Hue, Accent Hue, Vibrance, Depth) generate a complete, balanced palette.
- **Theme codes:** every custom theme has a code like `270-280-8-1`. Paste one in (with or without dashes) and select **Load** to apply someone else's theme.
- **Custom themes, advanced mode:** edit every color token in an INI-style editor. Accepts `#RRGGBB`, `#AARRGGBB`, `hsl()` and `hsla()`, supports `;` comments, can switch between light and dark, and reports mistakes line by line before applying.

  ```ini
  [theme]
  brightness = dark
  background = #0B0A12
  primary    = hsl(280, 88%, 58%)
  border     = #FFFFFF1A   ; 10% white
  ```

- **Any Google Font:** pick separate header and body fonts from the full Google Fonts catalog, with live previews as you search. Unused font files are cleaned up automatically.

### ▶️ Direct-play video

- Streams the original file untouched (`static=true`) and decodes it on the device with **mpv** via [media_kit](https://github.com/media-kit/media-kit). No server transcoding.
- **Resumes where you left off**, opening directly at your saved position.
- **Syncs progress with Jellyfin** every 10 seconds and immediately on pause, resume and stop, so Continue Watching, Next Up and watched status stay current everywhere.
- **Audio and subtitle picker** listing every embedded track by name and language, with a subtitles Off option.
- **Fit or Fill** toggle to letterbox the whole picture or zoom to cover the screen.
- On-screen controls: 10-second skip back and forward, play/pause, and a seek bar showing the buffered range that you can tap or drag. Controls fade after 3 seconds of playback and stay up while paused.
- Title overlay with the movie's or show's logo and, for episodes, `S1:E2 · Episode name`.
- Phones switch to full-screen landscape for video and back to portrait for menus.
- Clear error messages if something can't be played.

### 🎬 Browsing and details

- **Libraries:** each Jellyfin library gets its own page, sorted by name and grouped into `#`, `A`–`Z` sections. A letter bar jumps straight to any letter (letters with no titles are disabled), and pages load more as you scroll. Coming back to a library returns you to where you were.
- **Poster or thumbnail view** toggle on library, search and favorites pages. Defaults to posters on phones and thumbnails on wider screens.
- **Watched badges and progress bars** on artwork.
- **Detail popouts:** selecting a movie, show, collection or person opens a large card over the current page, so you never lose your place.
  - **Movies:** parallax backdrop with logo, year, runtime, age rating, community score, Play, expandable description, genre buttons and the cast with character names.
  - **Shows:** year range (e.g. `2019–present` for shows still airing), season count, rating and score, a season picker, and an episode list with thumbnails, runtimes, air dates, descriptions and progress. A smart **Play S2:E5** button starts the next unwatched episode, or the first episode for a show you haven't started (skipping Specials).
  - **Collections:** title count, year span, age-rating range (e.g. `PG–R`), combined genres and every movie in the collection.
  - **People:** photo, biography, and every movie and show they appear in on your server.
- **Favorites:** a ♥ button on every detail page updates instantly, and a Favorites page groups your movies and shows.
- **Genres:** every genre on your server, each with a matching icon, opening a page of everything in it.

### 🔍 Search

- Searches movies, shows and actors as you type.
- Results split into **People** and **Movies & Shows**.
- An empty search shows **Suggested For You** instead of a blank page.

### 📺 Made for every screen

- **Phones:** bottom tab bar (Home, Search, Settings, Profile) with library shortcuts on the home screen.
- **Tablets, desktops and TVs:** a top bar with Home, Favorites, each library and Genres, plus search, settings and your profile picture.
- **Scales with the window**, from 80% to 250%, so the layout holds up on a small laptop and a 4K TV alike.
- **TV remote and keyboard ready:** artwork lifts and highlights when focused with a D-pad or Tab, and the player responds to arrows, Select, Enter, Space, Escape and media keys (play/pause, rewind, fast-forward).
- Android TV is recognised and never locked to portrait.

### 🔐 Sign-in and privacy

- Connect with a host and port. `https://` addresses and reverse proxies without a port work too. The address is checked to be a Jellyfin server before your password is sent.
- Stays signed in between launches, and stays signed in if the server is briefly offline. You're only signed out if the server revokes your session.
- Your Jellyfin profile picture (or initials) appears in the app.
- Media requests authenticate with a header, keeping your token out of URLs.
- No analytics or third-party services. The only network traffic is to your Jellyfin server, plus Google Fonts when you choose a new font.

### ⚡ Fast

- Pages show cached content instantly and refresh in the background after 10 minutes.
- A 200 MB image cache keeps posters from re-downloading as you scroll.
- After you stop watching, Home and the relevant detail pages refresh their progress automatically.

---

## Keyboard and remote controls

| Key | In the player |
|---|---|
| Space / Enter / Select / ⏯ | Play or pause |
| ← / ⏪ | Back 10 seconds |
| → / ⏩ | Forward 10 seconds |
| ↑ / ↓ | Show controls |
| Esc | Exit the player |

---

## Platforms

Chameleon is a Flutter app with targets for **Android**, **iOS**, **Windows**, **macOS**, **Linux** and **web**. Development so far has focused on Android phones, tablets and Android TV. No builds have been published yet; for now, [build it yourself](#building-from-source).

---

## Building from source

### Requirements

- [Flutter](https://docs.flutter.dev/get-started/install) with Dart SDK 3.13 or later
- The platform toolchain for your target (Android Studio and the Android SDK, Xcode, Visual Studio, etc.)
- **Linux only:** mpv development libraries, e.g. `sudo apt install libmpv-dev mpv`

### Steps

```bash
git clone https://github.com/jumpingfox-dev/chameleon.git
cd chameleon
flutter pub get
flutter run            # or: flutter run -d <device>
```

Release builds:

```bash
flutter build apk --release      # Android
flutter build windows            # Windows
flutter build linux              # Linux
flutter build macos              # macOS
```

### Project layout

```
lib/
├── main.dart           App startup and routes
├── screens/            Home, Library, Search, Player, Settings, Login, ...
├── widgets/            App shell, home sections, detail popouts, poster cards
├── utils/              Jellyfin session, playback reporting, themes, fonts, home layout, caches
└── theme/              forui theme, colors, typography
```

### Built with

[Flutter](https://flutter.dev) · [forui](https://forui.dev) · [dart_jellyfin](https://pub.dev/packages/dart_jellyfin) · [media_kit](https://github.com/media-kit/media-kit) (mpv) · [go_router](https://pub.dev/packages/go_router) · [Phosphor icons](https://phosphoricons.com) · [Google Fonts](https://fonts.google.com)

Default fonts: Space Grotesk (headers) and Instrument Sans (body).

---

## Roadmap

Planned or in progress:

- [ ] Account, Playback, Server and About settings (the tabs exist but are empty)
- [ ] Multiple users and servers (**Add User** currently opens Settings)
- [ ] Subtitle styling options
- [ ] Transcoding fallback for files a device can't play directly
- [ ] Playback for music, photos, books and home videos (these libraries can be browsed but not opened yet)
- [ ] Live TV
- [ ] Auto-play next episode
- [ ] Android TV launcher listing
- [ ] Published builds on the Releases page

---

## Contributing

Issues and pull requests are welcome. For larger changes, open an issue first so we can talk it through.
