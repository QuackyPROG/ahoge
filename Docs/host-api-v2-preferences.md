# Proposal: host API v2, source preferences

Status: **proposed, not agreed.** Nothing in `ahoge-extension` changes until the user approves this.
The app already carries the host side, but it only switches on for a script that defines
`preferences`, so every current extension behaves exactly as before.

## Why

Some sources need settings: image quality, a mirror, a content language, whether to show
adult titles. Mihon extensions have `setupPreferenceScreen`; Ahoge sources have nothing.

## The contract change (for `docs/HOST_API.md`)

### 1. `preferences()` (optional)

A source may define a `preferences` method. It returns (or resolves to) an array of entries:

```js
source.preferences = function () {
  return [
    { key: "quality", type: "list", title: "Image quality",
      options: [{ value: "hd", title: "High" }, { value: "sd", title: "Data saver" }],
      default: "hd" },
    { key: "mirror", type: "text", title: "Mirror", summary: "Base URL without a trailing slash",
      default: "https://example.org" },
    { key: "adult", type: "toggle", title: "Show 18+ titles", default: false }
  ];
};
```

| Field | Required | Meaning |
|---|---|---|
| `key` | yes | Stable identifier. Never rename it: saved values live under it. |
| `type` | yes | `"toggle"` (boolean), `"list"` (one of `options`), `"text"` (free string). |
| `title` | yes | Row label. |
| `summary` | no | Help text under the row. |
| `options` | for `list` | `[{ value, title }]`; `value` is a string. |
| `default` | no | Boolean for `toggle`, string otherwise. |

The host ignores entries with a `type` it doesn't know, so new types can be added later
without breaking older apps.

`preferences()` must not make network requests; the host may call it any time the settings
screen opens.

### 2. `this.prefs`

Before any call, the host sets `this.prefs` on the source object to a plain object holding
**only the values the user changed**, keyed by `key`. A key the user never touched is absent, so
the script falls back to its own default:

```js
var quality = (this.prefs && this.prefs.quality) || "hd";
```

When the user changes a setting, the host updates `this.prefs` on the running instance; no
reload happens. Scripts must therefore read `this.prefs` inside each call, not once at load.

The host sets `this.prefs` only for scripts that define `preferences`.

### 3. Versioning

`runtime` stays `1`: the change is additive and optional. A source that relies on preferences
still works on an app without this support, it just always sees its defaults (`this.prefs` is
`undefined`). Bump `runtime` to `2` only if a source cannot work without settings.

## Host side (already in the app, inert until a source opts in)

- `ScriptSource.preferences()` returns the schema, or `[]` when `JSHost.hasMethod("preferences")`
  is false.
- Values are stored per source id in UserDefaults (`source.prefs.<id>`, a JSON object) by
  `SourcePreferenceStore`.
- `SourceManager` injects them as `this.prefs` when it creates a source and again when a value
  changes (`JSHost.setSourceProperty`).
- Browse → Extensions → a source → Extension details shows a **Settings** row only for such a
  source, with a form generated from the schema.

Not covered yet: source settings are not included in backups (their keys are per source, not in
`Pref.backupNames`).

## To do once agreed

1. Add sections 1–3 to `ahoge-extension/docs/HOST_API.md`.
2. Teach the Node test runtime in `ahoge-extension` to set `this.prefs` from a fixture.
3. Add `preferences()` to one source as the first user.
