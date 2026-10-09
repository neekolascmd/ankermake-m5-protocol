# macOS App

`ankerctl.app` is a native macOS app that bundles the `ankerctl` webserver and
shows the web interface in its own window. You do not need to install Python
or use the terminal.

## Features

- Starts the bundled `ankerctl` webserver automatically and stops it when you quit.
- Shows the full web interface (login, printer status, camera, temperature
  controls, G-code upload) in a native window.
- Keeps running in the menu bar after you close the window, so slicers can
  keep sending print jobs to `http://127.0.0.1:4470`.
- **File ▸ Print G-code File…** (⌘O), dragging a `.gcode` file onto the Dock
  icon, or **Open With ▸ ankerctl** in Finder sends the file to the printer and
  starts printing after you confirm.
- **Server ▸ Show Server Log** shows the server output for troubleshooting.
- Settings for the port, network access, printer number, TLS validation and
  opening at login.

The app uses the same configuration directory as the command-line tool
(`~/Library/Application Support/ankerctl`), so logging in with either one
works for both.

## Installing

1. Download `ankerctl-macos-app-arm64.dmg` (Apple silicon) or
   `ankerctl-macos-app-x86_64.dmg` (Intel) from the
   [Releases page](https://github.com/neekolascmd/ankermake-m5-protocol/releases).
2. Open the disk image and drag **ankerctl** to **Applications**.
3. The app is not notarized by Apple. The first time you open it, macOS blocks
   it. Open **System Settings ▸ Privacy & Security**, scroll down and click
   **Open Anyway** next to the message about ankerctl. Alternatively, run:

   ```sh
   xattr -dr com.apple.quarantine /Applications/ankerctl.app
   ```

4. When macOS asks whether ankerctl may find devices on your local network,
   click **Allow**. The app needs local network access to reach the printer.

## First run

1. Open **ankerctl**. The setup page appears.
2. Enter your AnkerMake email address, password and country, then click
   **Fetch**. Solve the CAPTCHA if one is shown. See the
   [Login Instructions](login-instructions.md) for details.
3. If the page says that the printer IP address is not set, click
   **Update Printer IP Addresses** on the **Setup** tab to search the local
   network for printers.

To print from PrusaSlicer, OrcaSlicer or a similar slicer, follow the
**Instructions** tab in the app and use `127.0.0.1:4470` as the host.

## Settings

Open **ankerctl ▸ Settings…** (⌘,).

| Setting | Description |
| --- | --- |
| Port | Port of the webserver (default `4470`). Change it in your slicer too. |
| Allow other devices on the network to connect | Binds the server to all network interfaces instead of only this Mac. Anyone on your network can then control the printer. |
| Printer number | Which printer to use when your account has more than one (starts at 0). |
| Disable TLS certificate validation | Same as the `--insecure` command-line flag. Only use this for troubleshooting. |
| Keep running in the menu bar | Keeps the server available to slicers after the window closes. |
| Open at login | Starts ankerctl when you log in. |

Click **Apply and Restart Server** after changing server settings.

If another `ankerctl webserver` (for example the command-line version or the
Docker container) is already running on the same port, the app uses that
server instead of starting its own.

## Using the command-line tool from the app

The app contains a complete build of the command-line tool:

```sh
/Applications/ankerctl.app/Contents/Resources/ankerctl/ankerctl --help
```

## Building the app

Requirements:

- macOS 14 or later with Xcode or the Xcode Command Line Tools (Swift 5.10+)
- Python 3.10 or later (for example `brew install python@3.12`)

From the repository root, run:

```sh
macos/build-app.sh
```

The script creates a virtual environment in `macos/build/`, builds the server
with PyInstaller, compiles the Swift app, signs it ad hoc and writes the
following files to `macos/dist/`:

- `ankerctl.app`
- `ankerctl-macos-app-<arch>.zip`
- `ankerctl-macos-app-<arch>.dmg` (skip with `SKIP_DMG=1`)

The app only runs on the CPU architecture of the Mac (and Python) it was built
with. Set `CODESIGN_IDENTITY` to a Developer ID Application identity to sign
for distribution; the script then enables the hardened runtime.

To work on the Swift code, open `macos/Package.swift` in Xcode. When running
from Xcode or `swift run`, set the `ANKERCTL_SERVER` environment variable to
the path of a built server executable, for example
`macos/build/server/ankerctl/ankerctl`.

The server honors `ANKERCTL_CONFIG_DIR` to use a configuration directory other
than the default, which is useful for testing.
