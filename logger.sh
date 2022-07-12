#!/usr/bin/env bash
Logger() {
    local LogLevel
    Entry() {
        log.debug() {
            LogLevel=debug
            format.print "$@"
        }
        log.info() {
            LogLevel=info
            format.print "$@"
        }
        log.warn() {
            LogLevel=warn
            format.print "$@"
        }
        log.error() {
            LogLevel=error
            format.print "$@"
        }
        log.fatal() {
            LogLevel=fatal
            format.print "$@"
        }
    }
    Formatter() {
        format.leveltext() {
            local leveltext=${LogLevel^^}
            # Fixed width.
            printf "[%-5s]$*" "$leveltext"
        }
        format.print() {
            local leveltext=$(format.leveltext)
            echo >&2 "$leveltext" "$*"
        }
    }
    self.init() {
        # Load submodule
        Entry
        Formatter
        # Set default log level
        LogLevel=debug
    }
    # Initialize this module
    self.init
}
init() {
    # Load module
    Logger
}
main() {
    init
    log.debug Debug level
    log.info  Info level
    log.warn  Warn level
    log.error Error level
}
[[ "${BASH_SOURCE[0]:-}" == "$0" ]] && main
