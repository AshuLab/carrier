import Foundation

/// Writes and configures a local Zsh `ZDOTDIR` shim directory inside Carrier's app folder
/// so interactive Carrier shells anchor their prompt to the bottom of the viewport without altering
/// any user dotfiles (`~/.zshrc`, `~/.zshenv`, etc.).
public enum TerminalZshBottomPromptShim {
    public static let shimFolderComponents = ["app", "terminal", "zsh-bottom-prompt"]
    public static let userZdotdirEnvKey = "CARRIER_USER_ZDOTDIR"

    public static func defaultDirectory(carrierFolder: URL) -> URL {
        shimFolderComponents.reduce(carrierFolder) { url, component in
            url.appendingPathComponent(component, isDirectory: true)
        }
    }

    public static func isZshShell(_ shellPath: String?) -> Bool {
        guard let raw = shellPath?.trimmingCharacters(in: .whitespacesAndNewlines), raw.isEmpty == false else {
            return true
        }
        return URL(fileURLWithPath: raw).lastPathComponent == "zsh"
    }

    /// Creates or refreshes the shim scripts in `directory` only when their contents differ.
    @discardableResult
    public static func prepareDirectory(_ directory: URL) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])
        for (filename, content) in files {
            let fileURL = directory.appendingPathComponent(filename, isDirectory: false)
            let data = Data(content.utf8)
            if let existing = try? Data(contentsOf: fileURL), existing == data {
                continue
            }
            try data.write(to: fileURL, options: .atomic)
            try fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: fileURL.path)
        }
        return directory
    }

    /// Returns `baseEnvVars` augmented with `ZDOTDIR` pointing at `shimDirectory` (plus `CARRIER_USER_ZDOTDIR`
    /// if the user already had a custom `ZDOTDIR`) when bottom-prompt pinning applies.
    public static func mergedEnvironment(
        baseEnvVars: [String: String],
        processEnvironment: [String: String] = ProcessInfo.processInfo.environment,
        shimDirectory: URL,
        pinPromptToBottom: Bool,
        command: String?
    ) -> [String: String] {
        guard pinPromptToBottom, command == nil else {
            return baseEnvVars
        }
        let activeShell = baseEnvVars["SHELL"] ?? processEnvironment["SHELL"]
        guard isZshShell(activeShell) else {
            return baseEnvVars
        }

        var merged = baseEnvVars
        let standardizedShim = shimDirectory.standardizedFileURL.path
        let existingZdotdir = baseEnvVars["ZDOTDIR"] ?? processEnvironment["ZDOTDIR"]
        if let existingZdotdir,
           existingZdotdir.isEmpty == false,
           URL(fileURLWithPath: existingZdotdir).standardizedFileURL.path != standardizedShim {
            merged[userZdotdirEnvKey] = existingZdotdir
        } else {
            merged.removeValue(forKey: userZdotdirEnvKey)
        }
        merged["ZDOTDIR"] = shimDirectory.path
        return merged
    }

    public static let files: [String: String] = [
        ".zshenv": zshenvScript,
        ".zprofile": zprofileScript,
        ".zshrc": zshrcScript,
        ".zlogin": zloginScript,
    ]

    private static let zshenvScript = #"""
# Carrier Zsh bottom-prompt shim (.zshenv).
# Preserves Ghostty shell integration and the user's real ZDOTDIR & dotfiles.
typeset -g _CARRIER_SHIM_ZDOTDIR="${${(%):-%x}:A:h}"

if [[ -n "${CARRIER_USER_ZDOTDIR+set}" ]]; then
  typeset -g _CARRIER_USER_ZDOTDIR_DEFINED=1
  typeset -g _CARRIER_USER_ZDOTDIR="$CARRIER_USER_ZDOTDIR"
  export ZDOTDIR="$CARRIER_USER_ZDOTDIR"
  unset CARRIER_USER_ZDOTDIR
else
  typeset -g _CARRIER_USER_ZDOTDIR_DEFINED=0
  typeset -g _CARRIER_USER_ZDOTDIR=""
  unset ZDOTDIR
fi

if [[ -n "${ZDOTDIR:-}" && "${ZDOTDIR:A}" == "$_CARRIER_SHIM_ZDOTDIR" ]]; then
  _CARRIER_USER_ZDOTDIR_DEFINED=0
  _CARRIER_USER_ZDOTDIR=""
  unset ZDOTDIR
fi

if [[ -r "${ZDOTDIR:-$HOME}/.zshenv" ]]; then
  builtin source -- "${ZDOTDIR:-$HOME}/.zshenv"
fi

if [[ -n "${ZDOTDIR+set}" && "${ZDOTDIR:A}" != "$_CARRIER_SHIM_ZDOTDIR" ]]; then
  _CARRIER_USER_ZDOTDIR_DEFINED=1
  _CARRIER_USER_ZDOTDIR="$ZDOTDIR"
elif [[ -z "${ZDOTDIR+set}" ]]; then
  _CARRIER_USER_ZDOTDIR_DEFINED=0
  _CARRIER_USER_ZDOTDIR=""
fi

export ZDOTDIR="$_CARRIER_SHIM_ZDOTDIR"
"""#

    private static let zprofileScript = #"""
# Carrier Zsh bottom-prompt shim (.zprofile).
if (( ${_CARRIER_USER_ZDOTDIR_DEFINED:-0} )); then
  export ZDOTDIR="$_CARRIER_USER_ZDOTDIR"
else
  unset ZDOTDIR
fi

if [[ -r "${ZDOTDIR:-$HOME}/.zprofile" ]]; then
  builtin source -- "${ZDOTDIR:-$HOME}/.zprofile"
fi

if [[ -n "${ZDOTDIR+set}" && "$ZDOTDIR" != "${_CARRIER_SHIM_ZDOTDIR:-}" ]]; then
  _CARRIER_USER_ZDOTDIR_DEFINED=1
  _CARRIER_USER_ZDOTDIR="$ZDOTDIR"
elif [[ -z "${ZDOTDIR+set}" ]]; then
  _CARRIER_USER_ZDOTDIR_DEFINED=0
  _CARRIER_USER_ZDOTDIR=""
fi

if [[ -n "${_CARRIER_SHIM_ZDOTDIR:-}" ]]; then
  export ZDOTDIR="$_CARRIER_SHIM_ZDOTDIR"
fi
"""#

    private static let zshrcScript = #"""
# Carrier Zsh bottom-prompt shim (.zshrc).
# Clear login banner from row 1 and position cursor at the viewport bottom before user .zshrc runs.
if [[ -o interactive && -t 1 ]]; then
  builtin printf '\e[?2026h\e[H\e[2J\e[999;1H\e[?2026l'
fi

if (( ${_CARRIER_USER_ZDOTDIR_DEFINED:-0} )); then
  export ZDOTDIR="$_CARRIER_USER_ZDOTDIR"
else
  unset ZDOTDIR
fi

# /etc/zshrc initializes HISTFILE using ZDOTDIR before this script restores it, so redirect any
# default shim path back to the user's own history location before sourcing their .zshrc.
if [[ -z "${HISTFILE:-}" || "$HISTFILE" == "${_CARRIER_SHIM_ZDOTDIR:-}/"* || "${HISTFILE:A:h}" == "${_CARRIER_SHIM_ZDOTDIR:A}" ]]; then
  HISTFILE="${ZDOTDIR:-$HOME}/.zsh_history"
fi

if [[ -r "${ZDOTDIR:-$HOME}/.zshrc" ]]; then
  builtin source -- "${ZDOTDIR:-$HOME}/.zshrc"
fi

if [[ -n "${ZDOTDIR+set}" && "$ZDOTDIR" != "${_CARRIER_SHIM_ZDOTDIR:-}" ]]; then
  _CARRIER_USER_ZDOTDIR_DEFINED=1
  _CARRIER_USER_ZDOTDIR="$ZDOTDIR"
elif [[ -z "${ZDOTDIR+set}" ]]; then
  _CARRIER_USER_ZDOTDIR_DEFINED=0
  _CARRIER_USER_ZDOTDIR=""
fi

_carrier_pin_bottom_precmd() {
  if [[ -o interactive && -t 1 ]]; then
    # CUD 999 preserves cursor column while pinning to the viewport bottom row, avoiding
    # clobbering commands that ended without a trailing newline before Zsh PROMPT_SP runs.
    builtin printf '\e[?2026h\e[999B\e[?2026l'
  fi
}

if ! typeset -f clear >/dev/null 2>&1 && ! alias clear >/dev/null 2>&1; then
  function clear {
    if [[ $# -eq 0 && -t 1 ]]; then
      builtin printf '\e[?2026h\e[3J\e[H\e[2J\e[999;1H\e[?2026l'
    else
      command clear "$@"
    fi
  }
fi

if [[ -o zle ]]; then
  if [[ -z "${widgets[clear-screen]:-}" || "${widgets[clear-screen]}" == "builtin" ]]; then
    _carrier_clear_screen() {
      local tty_target="${TTY:-/dev/tty}"
      builtin printf '\e[?2026h\e[H\e[2J\e[999;1H' >"$tty_target"
      zle .redisplay
      builtin printf '\e[?2026l' >"$tty_target"
    }
    zle -N clear-screen _carrier_clear_screen
  fi
fi

typeset -ga precmd_functions
precmd_functions=(_carrier_pin_bottom_precmd ${precmd_functions:#_carrier_pin_bottom_precmd})

if [[ -o login && -n "${_CARRIER_SHIM_ZDOTDIR:-}" ]]; then
  export ZDOTDIR="$_CARRIER_SHIM_ZDOTDIR"
fi
"""#

    private static let zloginScript = #"""
# Carrier Zsh bottom-prompt shim (.zlogin).
if (( ${_CARRIER_USER_ZDOTDIR_DEFINED:-0} )); then
  export ZDOTDIR="$_CARRIER_USER_ZDOTDIR"
else
  unset ZDOTDIR
fi

if [[ -r "${ZDOTDIR:-$HOME}/.zlogin" ]]; then
  builtin source -- "${ZDOTDIR:-$HOME}/.zlogin"
fi

if [[ -o interactive && -t 1 ]]; then
  builtin printf '\e[?2026h\e[999;1H\e[?2026l'
fi
"""#
}
