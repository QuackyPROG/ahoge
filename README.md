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

1. On Windows: `wsl --install Ubuntu-24.04`, and the Apple Devices app (or iTunes) so Windows sees the iPhone. Keep the phone plugged into Windows: usbipd passthrough hangs installs ([xtool#19](https://github.com/xtool-org/xtool/issues/19)).
2. In Linux: install the Swift toolchain xtool's guide names (via swiftly), and `sudo apt-get install libimobiledevice-utils ideviceinstaller socat zip`.
3. Download the Xcode `.xip` the guide names from developer.apple.com in your browser.
4. Install the `xtool` AppImage from its latest release, then run `xtool setup`: log in (password mode for a free Apple ID) and give it the path to the `.xip`.

Then, in WSL, start the relay that hands Windows' Apple service to WSL, and leave it running:

    bash Scripts/wsl-usbmux.sh

In a second WSL shell, from the repo root (`ideviceinfo` checks the phone is reachable):

    xtool dev

A free Apple ID allows three sideloaded apps per device; remove one if the install fails at `[Verifying]`.

The version and Info.plist keys live in both `project.yml` and `Info-xtool.plist`; keep them in sync.
