# Changelog

## 0.3.1 - 2026-03-21

- refactored the main CLI into `libexec/` modules to make the codebase easier to navigate and maintain
- `pvm global <version>` now links the selected Homebrew PHP for external tools like Valet, and skips redundant relinking when the requested version is already linked
- added a safety guard to prevent running `pvm` with `sudo` or as root, avoiding root-owned state under `~/.pvm`
- expanded CI and development lint/syntax coverage to include the new `libexec/*.sh` modules
- hardened the Composer test runtime detection so it never auto-selects a `pvm` shim

## 0.3.0 - 2026-03-09

- first public release of `pvm`
- Homebrew-backed PHP install, uninstall, local/global version selection, and shim-based tool resolution
- Bash, Zsh, and Fish shell integration
- `pvm composer` support with official installer verification
- `pvm ext` support for managed extension enable/disable overrides
- improved `pvm doctor` coverage for active ini files and broken extension directives
- bootstrap installer, shell tests, and CI-ready project setup
