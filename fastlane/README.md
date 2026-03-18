fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## iOS

### ios list_localizations_all

```sh
[bundle exec] fastlane ios list_localizations_all
```

Diagnostic lane to list ALL existing localizations

### ios upload_aso

```sh
[bundle exec] fastlane ios upload_aso
```

Upload screenshots and metadata (20 languages) to App Store Connect

### ios add_locales_and_upload

```sh
[bundle exec] fastlane ios add_locales_and_upload
```

Add missing locales via Spaceship then push metadata

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
