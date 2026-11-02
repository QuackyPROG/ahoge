# Ahoge

A free, open-source manga reader for iOS modeled on [Mihon](https://github.com/mihonapp/mihon).
Sources are JavaScript extensions from [ahoge-extension](https://github.com/QuackyPROG/ahoge-extension).

## Install (sideload)

1. Open the latest successful [iOS workflow run](https://github.com/QuackyPROG/ahoge/actions/workflows/ios.yml) and download the `Ahoge-ipa-*` artifact.
2. Unzip it and install `Ahoge.ipa` with Sideloadly. A free Apple ID signs apps for 7 days.

## Develop

There is no checked-in Xcode project; it is generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen):

    brew install xcodegen
    xcodegen generate
    open Ahoge.xcodeproj

CI (`.github/workflows/ios.yml`) generates the project, runs the tests on a simulator, and packages an unsigned IPA.

### Without a Mac (xtool on Linux or WSL)

[xtool](https://github.com/xtool-org/xtool) builds from `Package.swift` and `xtool.yml`, signs with your Apple ID and installs on a USB-connected iPhone. Tests still need CI, since there is no simulator on Linux.

One-time setup, following [xtool's Linux guide](https://github.com/xtool-org/xtool/blob/main/Documentation/xtool.docc/Installation-Linux.md):

1. On Windows: `wsl --install Ubuntu`, then [usbipd-win](https://learn.microsoft.com/en-us/windows/wsl/connect-usb) to attach the iPhone to WSL (`usbipd bind` / `usbipd attach --wsl`).
2. In Linux: install the Swift toolchain xtool's guide names, and `sudo apt-get install usbmuxd libimobiledevice-utils`. Check the phone shows up with `ideviceinfo`.
3. Download the Xcode `.xip` the guide names from developer.apple.com in your browser.
4. Install the `xtool` AppImage from its latest release, then run `xtool setup`: log in (password mode for a free Apple ID) and give it the path to the `.xip`.

Then, from the repo root:

    xtool dev

The version and Info.plist keys live in both `project.yml` and `Info-xtool.plist`; keep them in sync.
