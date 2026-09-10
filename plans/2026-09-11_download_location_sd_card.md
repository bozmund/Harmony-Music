# Download location can be set to an SD card or USB drive (#78)

**Devices:** Android

## Context

Choosing a folder on an SD card as the download (or export) location failed. file_selector's
Android implementation only turns a picked folder into a path on the primary (internal) volume and
throws for any other volume. On Android, folder picking now goes through file_picker, which maps
other volumes to `/storage/<volume-id>/<path>`. Windows and the other platforms are unchanged.

The S23+ has no SD slot; a USB drive on an OTG adapter shows up as the same kind of volume.

## Manual verification

- Settings → Download location → pick a folder on internal storage: it is saved and a download lands there.
- Plug in a USB drive (OTG), pick a folder on it: the location is saved, no error.
- Download a song with that location set: the file appears on the drive and plays.
- Pick the drive for Export location too: it is saved.
