<p align="center">
  <img src="screenshots/preview.png" alt="Orbit radial launcher" width="600">
</p>

<h1 align="center">Orbit</h1>

<p align="center">
  A radial app launcher for macOS — open apps, files, links, and run scripts with a flick of your mouse or a keyboard shortcut.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-13%2B-blue?logo=apple" alt="macOS 13+">
  <img src="https://img.shields.io/badge/Swift-5.9-orange?logo=swift" alt="Swift 5.9">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="MIT">
  <img src="https://img.shields.io/github/v/release/Mahmutakin99/Orbit" alt="Latest release">
  <img src="https://img.shields.io/github/stars/Mahmutakin99/Orbit?style=flat" alt="Stars">
</p>

---

## Features

- **Radial launcher** — up to 12 items per page, arranged in a circle around your cursor
- **Multiple item types** — apps, files, folders, web links, system actions, shortcuts, shell scripts
- **Submenus** — group items into folders with their own 12-item radial
- **Context-aware sets** — different items appear automatically based on the frontmost app
- **Clipboard ring** — last 10 copied texts available instantly in the radial
- **Usage intensity** — green/yellow/red dot shows how much you use each app today
- **Multi-language** — English, Turkish, Spanish, German, French, Chinese, Japanese, Russian, Korean
- **Triggers** — `⌘⇧D` hotkey or Option + mouse shake

## Requirements

- macOS 13 Ventura or later
- Xcode 15 or later *(only required to build from source)*

## Install

### Option 1 — Download (no Xcode needed)

Go to [Releases](https://github.com/Mahmutakin99/Orbit/releases) and download the latest `Orbit.app.zip`.

Unzip and drag `Orbit.app` to your `/Applications` folder.

### Option 2 — Build from source

```bash
git clone https://github.com/Mahmutakin99/Orbit.git
cd Orbit
bash install.sh
```

This builds a Release binary and copies it to `/Applications` automatically.

## First Launch

1. Open Orbit — a small dot icon appears in your menu bar
2. Press `⌘⇧D` or hold `⌥` and shake your mouse to open the radial
3. Go to **Settings → Items** to add your first apps
4. Grant **Accessibility** permission when prompted *(required for mouse shake trigger)*

## Settings

| Tab | What it does |
|-----|-------------|
| **Items** | Add/remove/reorder items. Click a folder to edit its contents. Drag files from Finder to add them. |
| **Context** | Define per-app item sets that appear automatically when that app is in front. |
| **General** | Language, launch at login, shake sensitivity. |

## Contributing

Pull requests are welcome. For major changes, please open an issue first to discuss what you'd like to change.

1. Fork the repo
2. Create your branch: `git checkout -b feature/my-feature`
3. Commit your changes: `git commit -m "Add my feature"`
4. Push: `git push origin feature/my-feature`
5. Open a pull request

## License

MIT © [Mahmut Akın](https://github.com/Mahmutakin99)
