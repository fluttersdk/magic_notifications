---
path: "{lib/src/cli/**/*.dart,bin/**/*.dart}"
---

# CLI Domain

- Commands extend `Command` from `magic_cli` — implement `name`, `description`, `configure(ArgParser)`, `handle()`
- `configure()` registers flags/options via `ArgParser` — `addFlag()` for booleans, `addOption()` for strings, `addMultiOption()` for lists
- `handle()` is `Future<void>` — read args from `arguments['key']`, cast to expected type
- Entry point (`bin/magic_notifications.dart`): create `Kernel()`, `registerMany([commands])`, `await kernel.handle(args)`
- CLI barrel (`lib/src/cli/cli.dart`): re-export `magic_cli` with `hide InstallCommand` to avoid name clash, export own commands
- File operations: use `FileHelper.findProjectRoot()`, `FileHelper.readFile()`, `FileHelper.writeFile()`, `FileHelper.fileExists()`
- Stub loading: `StubLoader.load('install/notification_config', searchPaths: paths)` — searches `assets/stubs/` directory
- Code injection: `ConfigEditor.addImportToFile()`, `ConfigEditor.insertCodeBeforePattern()` — idempotent (check before inserting)
- Testability: make `getProjectRoot()` and `getStubSearchPaths()` overridable methods — test subclasses override to use temp dirs
