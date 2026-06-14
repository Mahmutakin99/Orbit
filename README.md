# Orbit

A radial app launcher for macOS — open apps, files, links, and run scripts with a flick of your mouse or a keyboard shortcut.

![macOS](https://img.shields.io/badge/macOS-13%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5.9-orange)
![License](https://img.shields.io/badge/license-MIT-green)

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
- Xcode 15 or later (to build from source)

## Install

### Option 1 — Build from source (Terminal)

```bash
git clone https://github.com/Mahmutakin99/Orbit.git
cd Orbit
xcodebuild -scheme Orbit -configuration Release -derivedDataPath build
open build/Build/Products/Release/Orbit.app
```

To install permanently (move to /Applications):

```bash
cp -R build/Build/Products/Release/Orbit.app /Applications/
```

### Option 2 — Download release

Go to [Releases](https://github.com/Mahmutakin99/Orbit/releases) and download the latest `Orbit.app.zip`.

## First launch

1. Open Orbit — a small dot icon appears in your menu bar
2. Press `⌘⇧D` or hold `⌥` and shake your mouse to open the radial
3. Click **Settings → Items** to add your first apps
4. Grant **Accessibility** permission when prompted (required for mouse shake trigger)

## Settings

| Tab | What it does |
|-----|-------------|
| **Items** | Add/remove/reorder items. Click a folder to edit its contents. Drag files from Finder to add them. |
| **Context** | Define per-app item sets that appear automatically when that app is in front. |
| **General** | Language, launch at login, shake sensitivity. |

## License

MIT
