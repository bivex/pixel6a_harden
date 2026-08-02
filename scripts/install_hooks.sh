#!/usr/bin/env bash
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
HOOKS_DIR="${PROJECT_ROOT}/.git/hooks"

if [ ! -d "${HOOKS_DIR}" ]; then
  echo "[ERROR] .git/hooks directory not found. Is this a git repository?"
  exit 1
fi

PRE_COMMIT_HOOK="${HOOKS_DIR}/pre-commit"

cat << 'EOF' > "${PRE_COMMIT_HOOK}"
#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

echo "[PRE-COMMIT] Running Python unit test suite..."
python3 "${PROJECT_ROOT}/tests/test_config.py"

if command -v shellcheck >/dev/null 2>&1; then
  echo "[PRE-COMMIT] Running shellcheck on scripts/*.sh..."
  shellcheck "${PROJECT_ROOT}"/scripts/*.sh
else
  echo "[PRE-COMMIT] shellcheck CLI tool not found in PATH; skipping static shell analysis."
fi

echo "[PRE-COMMIT] All pre-commit checks completed successfully!"
EOF

chmod +x "${PRE_COMMIT_HOOK}"
echo "[SUCCESS] Pre-commit hook installed at ${PRE_COMMIT_HOOK}"
