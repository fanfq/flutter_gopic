# Cloud configuration naming migration

## Purpose

Make the cloud-service configuration surface explicit throughout GoPic. The
page is named `CloudScreen`, and its state and persistence collaborators use
the `CloudSettings` name rather than the generic `Settings` name.

## Scope

- Rename `SettingsScreen` and `settings_screen.dart` to `CloudScreen` and
  `cloud_screen.dart`.
- Rename `SettingsModel` / `SettingsService` and their files to
  `CloudSettingsModel` / `CloudSettingsService`.
- Rename home-screen cloud-navigation state, callback, and sidebar property
  names from `settings` to `cloud`.
- Remove the inactive sidebar `设置` item. `云服务` remains the only entry to
  this configuration page.
- Keep compression preferences in `CloudSettingsModel`; this migration does
  not change upload or compression behavior.
- Persist future data under a cloud-specific preference key, while loading
  data written with the legacy key and migrating it on the next save.

## Compatibility and validation

Existing cloud profiles and compression options must remain available after
the rename. Tests will cover legacy preference-key loading and will be updated
to use the new model/service symbols. Flutter analysis and the existing test
suite will be run after the migration.

## Non-goals

This does not change cloud provider fields, upload protocols, gallery
behavior, or the on-disk structure of individual cloud profiles.
