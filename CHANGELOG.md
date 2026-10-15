# Changelog

All notable changes to this project are listed here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [0.3.0] - 2026-10-14

### Added
- Japanese, Simplified Chinese, and French, covering every screen, alert, menu, and error message.
- **Language** menu (Claude Sign-In Helper ▸ Language) with System Default, English, 日本語, 简体中文, and Français.
- **File ▸ Backups…** (⌘B) and **Help ▸ How It Works** (⌘?).
- Preview renderer: new scenes, Retina output with `--scale 2`, and rendering of the sheets and alerts.

### Changed
- Redesigned interface: one small window that shows one step at a time, with a single main button and progress dots.
- New look inspired by Claude's own apps: warm neutral colors, serif headings, and a clay accent, in light and dark mode.
- Backups and How it works open as sheets. Import and restore are confirmed with standard macOS alerts.
- New app icon in clay and ivory.

### Fixed
- The app icon's bottom-right corner was left unpainted.

## [0.2.0]

### Added
- First native macOS version (SwiftUI and AppKit), replacing the earlier Python helper. It can restore backups made by that helper.

[0.3.0]: https://github.com/hibari233/claude-sign-in-helper/releases/tag/v0.3.0
