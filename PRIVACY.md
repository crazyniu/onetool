# Privacy policy

Effective date: October 23, 2026

1Tool does not require an account, collect analytics, display advertising, track users, or send app activity to a server. There are no bundled third-party analytics or advertising SDKs.

Preferences are stored locally using macOS preferences. Input-source rules include the applications and input sources you choose. 1Tool also stores your Finder action preferences, favorite folder paths, templates and display preferences locally. These settings are used only to provide the requested functions.

1Tool accesses selected files or folders for Finder actions, controls supported hardware when you request it, and may ask macOS for file or Automation permission. Input-source rules observe app activation locally to apply your selected input source; no keystrokes or typed content are recorded.

The Permissions page queries local Automation status without requesting access. An explicit action can open a target app for checking or ask macOS for permission. Opening settings or changing permission never automatically retries a Finder command, cleanup, uninstall or package operation. Full Disk Access is managed in System Settings; the app does not claim a reliable global authorization query.

Storage Cleanup inspects an explicit list of local cache and log directories, file metadata and the current user’s open-file list. It does not upload scan results. No files are selected automatically. Trash cleanup stores a recovery manifest alongside the moved files with the original path; permanent deletion requires an explicit choice and confirmation. Documents, login stores, chat histories and installed apps are outside the cleanup rules.

App Uninstaller inspects local installed application metadata, selected app bundles, related paths in the current user’s Library and local process/open-file information. Results stay on the device. Only the application is selected initially; associated data requires explicit selection and may contain personal settings, sessions or saved work. Confirmed items move to the Trash with a manifest of original paths; failed Trash operations retain the recovery directory. Shared app groups and system-wide helpers are outside its scope.

Opening Support or this policy opens GitHub in your browser. GitHub's own privacy policy then applies. macOS and Apple may separately process system diagnostics or store information according to your Apple settings.

Package management invokes your local Homebrew or npm executable. Requested commands may contact your configured registries and upstream download servers and run package installation scripts. 1Tool does not upload its own package inventory. It disables Homebrew analytics for its child processes, preserves your registry configuration, and keeps the last operation log in memory. See [package management](docs/PACKAGES.md).

You can remove rules within the app. Removing the app and its local preferences removes its settings; macOS may retain app containers or preferences until you delete them. No server-side account or stored user dataset exists to delete.

For privacy questions, open an issue at https://github.com/natefox2017/onetool/issues. Do not post private files, passwords or personal information in public issues. Report security issues using SECURITY.md.
