# Harmony Flutter/Dart MCP Server

This folder contains a small dependency-free MCP stdio server that exposes the
repository-local Flutter SDK from `../.flutter`.

## Tools

- `flutter`: runs `../.flutter/bin/flutter(.bat)`
- `dart`: runs `../.flutter/bin/dart(.bat)`

Both tools accept:

```json
{
  "args": ["analyze"],
  "working_directory": ".",
  "timeout_ms": 120000,
  "max_output_chars": 60000
}
```

`working_directory` is workspace-relative and must stay inside the repository.

## Example MCP Client Config

Use this as the server command in MCP-capable clients:

```json
{
  "mcpServers": {
    "harmony-flutter-dart": {
      "command": "node",
      "args": [
        "C:/MyRepositories/Harmony-Music/mcp/flutter_dart_server.js"
      ]
    }
  }
}
```

## Example Calls

```json
{
  "name": "flutter",
  "arguments": {
    "args": ["analyze"],
    "timeout_ms": 300000
  }
}
```

```json
{
  "name": "flutter",
  "arguments": {
    "args": ["test", "test/media_item_builder_test.dart"],
    "timeout_ms": 300000
  }
}
```

```json
{
  "name": "dart",
  "arguments": {
    "args": ["format", "--set-exit-if-changed", "lib/ui/widgets/song_list_tile.dart"]
  }
}
```
