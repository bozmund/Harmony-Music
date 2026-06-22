# Integration tests

These tests run the real Flutter UI with fake app service boundaries for
network, platform, file picker, downloader, update, and audio behavior.

Run locally with:

```sh
flutter test integration_test
```

They are intentionally not part of required PR checks yet. Keep PR CI on
`flutter test` until the emulator/device workflow is stable enough to trust.
