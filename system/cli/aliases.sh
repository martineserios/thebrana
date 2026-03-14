#!/usr/bin/env bash
# Shell aliases for brana CLI — source this in .bashrc/.zshrc
# Usage: source /path/to/system/cli/aliases.sh
#    or: eval "$(brana aliases)" (when implemented)

# Backlog shortcuts
alias bq='brana backlog query'
alias bn='brana backlog next'
alias bf='brana backlog focus'
alias bs='brana backlog status'
alias bb='brana backlog blocked'
alias bsearch='brana backlog search'
alias bdiff='brana backlog diff'
alias bstale='brana backlog stale'
alias bburn='brana backlog burndown'
alias bctx='brana backlog context'
alias bgraph='brana backlog graph'

# Ops shortcuts
alias bo='brana ops status'
alias boh='brana ops health'
alias bol='brana ops logs'
alias bor='brana ops run'
alias bod='brana ops drift'
alias boc='brana ops collisions'
alias bosync='brana ops sync'
alias boreindex='brana ops reindex'

# Root shortcuts
alias bd='brana doctor'
alias bv='brana version'
