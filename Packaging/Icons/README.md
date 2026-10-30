# Tidy app icon

`Tidy-source.png` is the approved original raccoon artwork. `Tidy.png` is the
1024px macOS master with transparent padding; `Tidy.icns` includes standard and
Retina representations from 16px through 1024px.

Regenerate the derived assets on macOS, without additional dependencies:

```sh
swift scripts/build-app-icon.swift
```

Both app packaging scripts copy the icon before signing and validate the finished
bundle with `scripts/check-app-icon.py`. Changing the icon changes the signed app;
existing notarized downloads must not be modified in place. Build and separately
notarize a new artifact when an updated download is needed.
