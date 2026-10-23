# Homebrew and npm package management

The Homebrew and npm pages manage the current user's existing package-manager installations. They share the app's native page and card components and inherit the global visual direction in [DESIGN-DIRECTION-2026.md](DESIGN-DIRECTION-2026.md).

- **Homebrew:** installed formulae and casks, installed/available versions, name filtering, pinned indicators, metadata refresh, individual installation/uninstallation/upgrades, and upgrading all eligible outdated packages.
- **npm:** global tools across detected Node/npm environments, including scoped names. Select an environment to inspect or change its global inventory. Upgrades install `@latest`, including major releases, as stated in the confirmation. Project dependencies are outside this page's scope.
- **Environment:** inspect the interactive login PATH, Homebrew and installed nvm/fnm/Volta/asdf/mise runtimes. Each entry binds npm, its matching Node executable and its canonical global prefix. The selected prefix stays visible; environment details disclose executable paths and discovery warnings. Confirmations and manual recovery commands retain the same environment. Bun and pnpm direct packages are identified separately for management with their own tools.
- **Operations:** explicit package confirmation, one operation per provider at a time, progress, bounded live output, stderr/exit-code reporting, and an automatic list refresh after both successful and failed changes. Failed refreshes disable changes until the user refreshes successfully.

Homebrew immediately displays upgrades already known in its local installed metadata, with an explicit local-metadata explanation. Check for Updates refreshes the upstream metadata; failure preserves known local upgrades and shows the error. npm automatically checks for updates after loading each environment. Unknown, checking, successful and failed states remain distinct, and unknown availability never appears as a zero update count. A scrollable sheet shows exact names, versions, environment and package counts for individual and batch changes.

The package list and installation entry come before expanded environment details and operation logs. npm dependency diagnostics (`ELSPROBLEMS`) preserve readable installed packages with a warning instead of hiding the entire inventory. Environment selection is disabled during commands; a confirmation bound to another environment cannot execute.

The main window keeps operation progress, current package and completed/total counts in a fixed bottom status area; package rows retain their individual outcome. Failed batch retries exclude completed packages and require a new confirmation. Error guidance distinguishes interactive administrator prompts, directory ownership/write access, registry authentication, network failure and undiagnosed CLI errors. Command copying and opening Terminal are manual recovery options; the app never executes the copied shell command. Directory/admin issues link to the shared Permissions page without inferring Full Disk Access is missing.

Only exact package identifiers are accepted. Names reach `Process.arguments` directly, with an option terminator; user text is never executed as shell code. Homebrew's dependency checks and pinned versions remain respected. The app does not add `--force`, `--zap`, `--ignore-dependencies`, automatic removal, or automatic cleanup. It does not elevate privileges. Casks that require interactive administrator authorization may fail; the actual CLI error remains visible. Missing managers link to their installation guides.

Installed-list refreshes use `brew info --json=v2 --installed` and `npm ls --global --depth=0 --json`. Homebrew's explicit update check runs `brew update` before rereading installed metadata; npm uses `npm outdated --global --depth=0 --json`, accepting its update-available exit code of 1. Registry and CLI failures remain separate from a successful empty update response. Homebrew's current cask update policy determines which apps appear outdated.

Package-manager commands can contact the configured registries and upstream download servers. Installations can run package installation scripts. Homebrew analytics and unsolicited npm update notifications are disabled for these child processes. The app does not change the user's registry settings or upload its own package inventory. Temporary command output is private to the user and removed after each command; the last operation log remains in memory.

## Verification

Current evidence and remaining acceptance items are recorded in [package validation](PACKAGES-VALIDATION.md).

Run `./build.sh` and `./test.sh` for the app and shared regression checks. Package checks include identifier rejection, formula/cask JSON, scoped npm packages, pinned packages, command construction, stderr separation, output volume, timeouts, registry errors, and a disposable Homebrew command fixture.

Run `./test.sh --packages-integration` for the real npm CLI lifecycle. Python's standard library serves a loopback registry containing generated packages at versions 1.0.0 and 2.0.0. A temporary global prefix, npm cache and npm configuration isolate the test from the user's packages. This verifies installation, detection of a major update, upgrading to latest, uninstallation and a registry failure. It requires local npm and Python 3 and downloads no external package.

The Homebrew fixture verifies process integration and refresh behavior; it does not claim to install or remove real Homebrew packages. Native rendering and manual interaction acceptance must be recorded separately from these CLI checks.

Command references: [Homebrew manual](https://docs.brew.sh/Manpage), [Homebrew JSON queries](https://docs.brew.sh/Querying-Brew), [npm outdated](https://docs.npmjs.com/cli/v11/commands/npm-outdated/), [npm install](https://docs.npmjs.com/cli/v11/commands/npm-install/).
