# Finder extension

FileMailer uses `FIFinderSync` and registers `/` plus visible mounted volumes.
It does not scan those roots. Finder calls `menu(for:)`; the extension builds
one native parent item and a simple submenu from an in-memory recipient
snapshot.

If the app heartbeat is older than ten seconds, only Open FileMailer is shown.
After opening the app, reopen the Finder context menu so it can receive a fresh
snapshot.

Enable the extension from FileMailer onboarding or Settings > Diagnostic. The
button calls `FIFinderSyncController.showExtensionManagementInterface()`.

Finder controls item placement. Some iCloud Drive and File Provider locations
can suppress or delay Finder Sync menus. A Finder restart or macOS logout can
be required after changing extension state.

The extension target is sandboxed and declares no network, file-read or App
Group entitlement. Its only payloads are bounded paths and local action IDs.
