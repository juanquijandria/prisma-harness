#!/bin/sh
# Prisma Harness. Sourced by every selftest before it reads a setting, so that no selftest sees the environment, the home or the configuration of whoever runs it.

if [ "${selftest_env_done:-0}" != "1" ]; then
  selftest_env_done=1
  for inherited in $(env | sed -n 's/^\(PRISMA_[A-Z_0-9]*\)=.*/\1/p') CLAUDE_PROJECT_DIR CLAUDE_PLUGIN_ROOT CLAUDE_PLUGIN_DATA; do
    unset "$inherited"
  done
  selftest_env_sandbox=$(mktemp -d 2>/dev/null)
  if [ -z "$selftest_env_sandbox" ] || [ ! -d "$selftest_env_sandbox" ]; then
    echo "SELFTEST NOT RUN: no temporary directory could be created, so the selftest could not be isolated from this machine. Check TMPDIR." >&2
    exit 1
  fi
  mkdir -p "$selftest_env_sandbox/project"
  : > "$selftest_env_sandbox/gitconfig"
  HOME="$selftest_env_sandbox"
  TMPDIR="$selftest_env_sandbox"
  CLAUDE_PROJECT_DIR="$selftest_env_sandbox/project"
  PRISMA_DOCS_ROOT="$selftest_env_sandbox/project"
  PRISMA_FORMAT_CONFIG="$selftest_env_sandbox/there-is-no-format-config-here"
  PRISMA_RECEIPT_FILE="$selftest_env_sandbox/receipts.log"
  GIT_CONFIG_GLOBAL="$selftest_env_sandbox/gitconfig"
  GIT_CONFIG_SYSTEM="$selftest_env_sandbox/gitconfig"
  export HOME TMPDIR CLAUDE_PROJECT_DIR PRISMA_DOCS_ROOT PRISMA_FORMAT_CONFIG PRISMA_RECEIPT_FILE GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM
fi
