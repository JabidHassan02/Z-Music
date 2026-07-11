# Z-Music: The Ultimate Hybrid Audio Player

A feature-rich, beautiful, and robust music application built with Flutter. Z-Music seamlessly integrates local device library management with online streaming and downloading capabilities via YouTube. Designed with a premium aesthetic and background playback support for a complete listening experience.

## 🚀 Overview

**[Repository Link](https://github.com/JabidHassan02/Z-Music)**

**📱 [Download Latest APK (One-Click)](https://github.com/JabidHassan02/Z-Music/releases/download/v1.0.0-build2/Z.Music.apk)**

---

## ✨ Features

- **Hybrid Audio Playback** — Play local tracks from your device and stream music directly from YouTube.
- **Integrated Downloader** — Easily search and download your favorite songs from YouTube directly into your library.
- **Background Playback** — True background audio support with media notifications and lock-screen controls.
- **Advanced Playlist Management** — Create, edit, and organize custom playlists on the fly.
- **Dynamic Theming** — Beautiful user interface with dynamic theme support, cached imagery, and sleek animations.
- **Library Organization** — Auto-scans local storage for audio files and organizes them elegantly.
- **Premium UI Elements** — Features circular progress sliders, marquee text for long song titles, and smooth transitions.

---

## 🛠 Tech Stack

| Technology | Version | Purpose |
|---|---|---|
| Flutter / Dart | 3.8.x | Core Framework & Language |
| Just Audio | ^0.9.36 | Robust Audio Engine & Background Playback |
| On Audio Query | ^2.9.0 | Local Device Audio Discovery |
| YouTube Explode Dart | ^2.5.1 | YouTube Search, Streaming & Downloading |
| Sleek Circular Slider | ^2.1.0 | Premium Audio Progress UI |
| Shared Preferences & Secure Storage | latest | Local Data & State Persistence |
| Cached Network Image | ^3.4.1 | Optimized Image Loading |

---

## 📁 Folder Structure

```text
lib/
├── screens/                  # Application UI views
│   ├── full_player/          # Full-screen audio player UI
│   ├── library/              # Local device music library
│   ├── playlist/             # Playlist management screens
│   └── song_downloader_screen.dart # YouTube search & download interface
├── services/                 # Core logic and API integration
│   ├── app_theme_state.dart  # Dynamic theming logic
│   ├── music_state.dart      # Global audio playback state
│   └── youtube_api_service.dart # YouTube Explode integration
├── widgets/                  # Reusable UI components
└── main.dart                 # Application entry point
```

---

## 🔧 Installation & Setup

### Prerequisites
- Flutter SDK (3.8.1+)
- Android Studio / VS Code
- Android Device or Emulator

### 1. Clone the Repository

```bash
git clone https://github.com/JabidHassan02/Z-Music.git
cd Z-Music
```

### 2. Fetch Dependencies

```bash
flutter pub get
```

### 3. Run the Application

```bash
flutter run
```
*Note: For the best experience testing local audio and background playback, test on a physical Android device.*

---

## 🎨 UI & Theming

Z-Music comes pre-configured with a highly customized dark theme (`#121212`) out-of-the-box. The splash screen and launcher icons have been meticulously designed and generated via `flutter_native_splash` and `flutter_launcher_icons` to provide a premium feel from the moment you launch the app.

---

## 📄 License

MIT License — feel free to use as a template with attribution.

---

Built with ❤️ by **Jabid Hassan Khan**.
