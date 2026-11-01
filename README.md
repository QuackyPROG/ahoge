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
