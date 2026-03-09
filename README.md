# pvm

`pvm` is a PHP version manager for the terminal. It installs PHP from Homebrew, switches versions with shell-native hooks, and routes PHP tools through stable shims in `~/.pvm/shims`.

## Features

- install and uninstall PHP versions with Homebrew
- switch PHP per shell, per project, or globally
- support Bash, Zsh, and Fish
- use `.php-version` files for project-local selection
- keep `php`, `phpize`, `php-config`, `pecl`, and related tools stable through shims
- install Composer through the official installer so it follows the active PHP version
- manage per-version extension overrides with `pvm ext`
- inspect PHP config and broken extension directives with `pvm doctor`

## Requirements

- Homebrew
- Bash, Zsh, or Fish for interactive shell integration

If Homebrew is missing, `pvm` can prompt to install it using the official Homebrew installer.

## Install

### Homebrew

```bash
brew tap AtefR/pvm
brew install pvm
```

Then add `pvm` to your shell:

```bash
echo 'eval "$(pvm init bash)"' >> ~/.bashrc
echo 'eval "$(pvm init zsh)"' >> ~/.zshrc
echo 'pvm init fish | source' >> ~/.config/fish/config.fish
```

Reload your shell after updating the config.

### Bootstrap Installer

```bash
curl -fsSL https://raw.githubusercontent.com/AtefR/pvm/main/bootstrap.sh | bash
```

The bootstrap installer copies `pvm` into `~/.local/share/pvm`, creates `~/.local/bin/pvm`, and updates the current shell config.

### From Source

```bash
git clone https://github.com/AtefR/pvm.git
cd pvm
./install.sh
```

## Quick Start

```bash
pvm install 8.4 --use
php -v

pvm install 8.3
pvm local 8.3
php -v

pvm global 8.4
pvm current
```

## Usage

### Versions

```bash
pvm install 8.4
pvm install latest --use
pvm use 8.3
pvm deactivate
pvm local 8.2
pvm local --unset
pvm global 8.4
pvm global --unset
pvm list
pvm list-remote
pvm current
```

### Tool Resolution

```bash
pvm which php
php -v
phpize --version
pecl version
```

### Composer

```bash
pvm composer install
composer --version
pvm composer update-self
pvm composer which
```

### Extensions

```bash
pvm ext list
pvm ext disable opcache
pvm ext enable opcache
pvm doctor
```

`pvm ext` manages only the `pvm`-owned override layer. It does not rewrite the stock Homebrew PHP config.

## How Version Resolution Works

`pvm` resolves PHP in this order:

1. `PVM_VERSION` from `pvm use`
2. nearest `.php-version`
3. `~/.pvm/default-version`
4. system PHP outside `pvm` shims

## Commands

- `pvm install <version> [--use]`
- `pvm uninstall <version>`
- `pvm use [version]`
- `pvm deactivate`
- `pvm local <version>`
- `pvm local --unset`
- `pvm global <version>`
- `pvm global --unset`
- `pvm list`
- `pvm list-remote`
- `pvm current`
- `pvm which <tool>`
- `pvm ext <list|enable|disable> [extension] [--version <version>]`
- `pvm composer <install|update-self|which>`
- `pvm exec <version> <command...>`
- `pvm reshim`
- `pvm doctor`
- `pvm init <bash|zsh|fish>`

## Troubleshooting

### `pvm use` says it must run through the shell hook

Add the output of `pvm init <shell>` to your shell config and reload the shell.

### Composer installed through Homebrew uses the wrong PHP

Use `pvm composer install` instead of `brew install composer`. The `pvm` install follows the active PHP version.

### PHP shows a startup warning for a missing extension `.so`

Run:

```bash
pvm doctor
```

That helps identify broken `php.ini` or `conf.d` entries.

## Development

```bash
bash -n bin/pvm install.sh bootstrap.sh test/*.sh
shellcheck bin/pvm install.sh bootstrap.sh test/*.sh
test/smoke.sh
```
