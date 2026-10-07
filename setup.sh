#!/usr/bin/env bash
#
# setup.sh — AI Security Workshop environment installer
#
# Installs uv, builds the shared virtual environment, pulls every dependency
# (CPU-only PyTorch), scaffolds .env, then verifies the whole thing.
#
#   ./setup.sh                 install everything, then verify
#   ./setup.sh --verify        verify an existing install, change nothing
#   ./setup.sh --help          all options
#
set -Eeuo pipefail

# ─────────────────────────────────────────────────────────────── constants ────
readonly VERSION='1.0.0'
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
readonly ROOT
readonly VENV_DIR="$ROOT/.venv"
readonly VENV_PY="$VENV_DIR/bin/python"
readonly TORCH_INDEX='https://download.pytorch.org/whl/cpu'
readonly UV_INSTALLER='https://astral.sh/uv/install.sh'

# ───────────────────────────────────────────────────────────────── options ────
PYTHON_VERSION=${WORKSHOP_PYTHON:-3.12}
OPT_COLOR=auto
OPT_VERBOSE=0
OPT_VERIFY_ONLY=0
OPT_SKIP_VERIFY=0
OPT_RECREATE=0

# ─────────────────────────────────────────────────────────────────── state ────
LOG_FILE=''
SPIN_PID=''
DIED=0
STEP=0
TOTAL_STEPS=6
declare -a SUMMARY=()
declare -i WARNINGS=0

# ──────────────────────────────────────────────────────── style and glyphs ────
style_init() {
  local want=1
  [[ -n ${NO_COLOR:-} ]] && want=0
  case $OPT_COLOR in
    never)  want=0 ;;
    always) want=1 ;;
    *)      [[ -t 1 ]] || want=0 ;;
  esac

  if ((want)); then
    BOLD=$'\e[1m'; DIM=$'\e[2m'; RESET=$'\e[0m'
    RED=$'\e[38;5;203m'; GREEN=$'\e[38;5;114m'; YELLOW=$'\e[38;5;221m'
    BLUE=$'\e[38;5;75m';  CYAN=$'\e[38;5;80m';   GREY=$'\e[38;5;245m'
  else
    BOLD='' DIM='' RESET='' RED='' GREEN='' YELLOW='' BLUE='' CYAN='' GREY=''
  fi

  if [[ $(locale charmap 2>/dev/null) == *UTF-8* ]]; then
    OK_MARK='✔'; FAIL_MARK='✖'; WARN_MARK='▲'; STEP_MARK='▸'; INFO_MARK='·'; SEP='·'
    TL='╭'; TR='╮'; BL='╰'; BR='╯'; HZ='─'; VT='│'
    FRAMES=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
  else
    OK_MARK='+'; FAIL_MARK='x'; WARN_MARK='!'; STEP_MARK='>'; INFO_MARK='-'; SEP='-'
    TL='+'; TR='+'; BL='+'; BR='+'; HZ='-'; VT='|'
    FRAMES=('|' '/' '-' '\')
  fi
}

# ───────────────────────────────────────────────────────────────── printing ────
rule() { local n=${1:-66} s=''; while ((${#s} < n)); do s+=$HZ; done; printf '%s' "$s"; }

# printf's %-*s pads by bytes, so a multibyte glyph like · would shorten the row.
# ${#s} counts characters, so pad by hand to keep every box edge aligned.
pad_to() { local n=$(($2 - ${#1})); ((n < 0)) && n=0; printf '%s%*s' "$1" "$n" ''; }

# box_row <border-colour> <rendered-text> <visible-width> <inner-width>
box_row() {
  local fill=$(($4 - 4 - $3)); ((fill < 0)) && fill=0
  printf '  %s%s%s  %s%*s  %s%s%s\n' "$1" "$VT" "$RESET" "$2" "$fill" '' "$1" "$VT" "$RESET"
}

banner() {
  local pad=62
  local title="AI Security Workshop  $SEP  environment setup"
  local sub="uv $SEP python $PYTHON_VERSION $SEP cpu-only torch"
  printf '\n  %s%s%s%s%s\n' "$BLUE" "$TL" "$(rule $pad)" "$TR" "$RESET"
  box_row "$BLUE" "$BOLD$title$RESET" "${#title}" "$pad"
  box_row "$BLUE" "$DIM$sub$RESET"     "${#sub}"   "$pad"
  printf '  %s%s%s%s%s\n' "$BLUE" "$BL" "$(rule $pad)" "$BR" "$RESET"
}

step()   { STEP=$((STEP + 1))
           printf '\n  %s%s%s %s%s%s %s(%d/%d)%s\n' \
             "$BLUE" "$STEP_MARK" "$RESET" "$BOLD" "$1" "$RESET" "$DIM" "$STEP" "$TOTAL_STEPS" "$RESET"; }
ok()     { printf '     %s%s%s %s%s\n' "$GREEN" "$OK_MARK"   "$RESET" "$1" "$(detail "${2-}")"; }
warn()   { printf '     %s%s%s %s%s\n' "$YELLOW" "$WARN_MARK" "$RESET" "$1" "$(detail "${2-}")"; WARNINGS+=1; }
bad()    { printf '     %s%s%s %s%s\n' "$RED" "$FAIL_MARK"   "$RESET" "$1" "$(detail "${2-}")"; }
info()   { printf '     %s%s %s%s\n'   "$GREY" "$INFO_MARK"  "$1"     "$RESET"; }
detail() { [[ -n ${1-} ]] && printf '  %s%s%s' "$DIM" "$1" "$RESET"; }

die() {
  DIED=1
  printf '\n  %s%s %s%s\n' "$RED$BOLD" "$FAIL_MARK" "$1" "$RESET"
  [[ -n ${2-} ]] && printf '     %s%s%s\n' "$DIM" "$2" "$RESET"
  log_hint
  exit 1
}

log_hint() {
  [[ -n $LOG_FILE && -s $LOG_FILE ]] || return 0
  printf '\n  %slast lines of %s%s\n' "$DIM" "$LOG_FILE" "$RESET"
  printf '  %s%s%s\n' "$DIM" "$(rule 66)" "$RESET"
  tail -n 15 -- "$LOG_FILE" | sed "s/^/  $DIM/; s/\$/$RESET/"
  printf '  %s%s%s\n' "$DIM" "$(rule 66)" "$RESET"
}

# ─────────────────────────────────────────────────────── spinner / tasking ────
cursor_hide() { [[ -t 1 ]] && printf '\e[?25l' || true; }
cursor_show() { [[ -t 1 ]] && printf '\e[?25h' || true; }

spinner_stop() {
  [[ -n $SPIN_PID ]] || return 0
  kill "$SPIN_PID" 2>/dev/null || true
  wait "$SPIN_PID" 2>/dev/null || true
  SPIN_PID=''
  [[ -t 1 ]] && printf '\r\e[2K' || true
  cursor_show
}

spinner_start() {
  local label=$1
  [[ -t 1 ]] || { info "$label …"; return 0; }
  cursor_hide
  (
    local i=0
    while :; do
      printf '\r     %s%s%s %s%s' "$CYAN" "${FRAMES[i % ${#FRAMES[@]}]}" "$RESET" "$label" "$DIM"
      i=$((i + 1))
      sleep 0.08
    done
  ) &
  SPIN_PID=$!
}

# task <label> <command...> — run it, spin while it works, keep the output in the log
task() {
  local label=$1; shift
  local rc=0
  printf '\n### %s\n$ %s\n' "$label" "$*" >>"$LOG_FILE"

  if ((OPT_VERBOSE)); then
    info "$label"
    printf '     %s$ %s%s\n' "$GREY" "$*" "$RESET"
    set +e; "$@" 2>&1 | tee -a "$LOG_FILE"; rc=${PIPESTATUS[0]}; set -e
  else
    spinner_start "$label"
    set +e; "$@" >>"$LOG_FILE" 2>&1; rc=$?; set -e
    spinner_stop
  fi
  return "$rc"
}

# ───────────────────────────────────────────────────────────────── plumbing ────
have()    { command -v -- "$1" >/dev/null 2>&1; }
record()  { SUMMARY+=("$1"$'\t'"$2"); }

on_err() {
  local rc=$1 line=$2
  ((DIED)) && exit "$rc"
  spinner_stop
  printf '\n  %s%s unexpected failure%s %s(exit %s, line %s)%s\n' \
    "$RED$BOLD" "$FAIL_MARK" "$RESET" "$DIM" "$rc" "$line" "$RESET"
  log_hint
  exit "$rc"
}
trap 'on_err "$?" "$LINENO"' ERR
trap 'spinner_stop' EXIT
trap 'spinner_stop; printf "\n  %sinterrupted%s\n" "$YELLOW" "$RESET"; exit 130' INT TERM

usage() {
  style_init
  cat <<EOF

  ${BOLD}setup.sh${RESET} ${DIM}v$VERSION${RESET} — install and verify the workshop environment

  ${BOLD}USAGE${RESET}
     ./setup.sh [options]

  ${BOLD}OPTIONS${RESET}
     ${CYAN}-V, --verify${RESET}        verify only; install nothing, change nothing
     ${CYAN}-S, --skip-verify${RESET}   install, then stop before verification
     ${CYAN}-r, --recreate${RESET}      delete and rebuild .venv from scratch
     ${CYAN}-p, --python${RESET} ${DIM}VER${RESET}    python for the venv ${DIM}(default: $PYTHON_VERSION)${RESET}
     ${CYAN}-v, --verbose${RESET}       stream command output instead of a spinner
     ${CYAN}    --color${RESET} ${DIM}WHEN${RESET}    auto ${DIM}(default)${RESET} | always | never
     ${CYAN}-h, --help${RESET}          this text
     ${CYAN}    --version${RESET}       print the version

  ${BOLD}ENVIRONMENT${RESET}
     ${CYAN}WORKSHOP_PYTHON${RESET}     same as --python
     ${CYAN}NO_COLOR${RESET}            disable colour

  ${BOLD}WHAT IT DOES${RESET}
     1. preflight  — bash, curl, git, disk space
     2. uv         — install via astral.sh if missing
     3. venv       — .venv on python $PYTHON_VERSION
     4. deps       — uv sync against the CPU-only torch index
     5. config     — .env.example, .env, .gitignore entries
     6. verify     — uv, venv, lockfile, then verify-environment.py

EOF
}

parse_args() {
  while (($#)); do
    case $1 in
      -V|--verify)       OPT_VERIFY_ONLY=1 ;;
      -S|--skip-verify)  OPT_SKIP_VERIFY=1 ;;
      -r|--recreate)     OPT_RECREATE=1 ;;
      -v|--verbose)      OPT_VERBOSE=1 ;;
      -p|--python)       [[ ${2-} ]] || { style_init; die 'missing value' '--python needs a version, e.g. --python 3.12'; }
                         PYTHON_VERSION=$2; shift ;;
      --python=*)        PYTHON_VERSION=${1#*=} ;;
      --color)           OPT_COLOR=${2-auto}; shift ;;
      --color=*)         OPT_COLOR=${1#*=} ;;
      --no-color)        OPT_COLOR=never ;;
      -h|--help)         usage; exit 0 ;;
      --version)         printf '%s\n' "$VERSION"; exit 0 ;;
      *)                 style_init; die "unknown option: $1" 'run ./setup.sh --help' ;;
    esac
    shift
  done
}

# ═══════════════════════════════════════════════════════════════════ steps ════

step_preflight() {
  step 'Preflight'

  ((BASH_VERSINFO[0] >= 4)) \
    && ok 'bash' "$BASH_VERSION" \
    || die "bash 4+ required (found $BASH_VERSION)" 'run this with bash, not sh'

  case $OSTYPE in
    linux*)  ok 'platform' 'linux' ;;
    darwin*) ok 'platform' 'macos' ;;
    *)       warn 'platform' "$OSTYPE — untested, continuing" ;;
  esac

  local missing=()
  for bin in curl git; do
    have "$bin" && ok "$bin" "$(command -v "$bin")" || missing+=("$bin")
  done
  ((${#missing[@]})) && die "missing required tool(s): ${missing[*]}" \
    'install them with your package manager, then re-run'

  [[ -f $ROOT/pyproject.toml ]] \
    && ok 'project root' "$ROOT" \
    || die 'pyproject.toml not found' "expected it in $ROOT — run setup.sh from the repo"

  local free_kb
  free_kb=$(df -Pk "$ROOT" | awk 'NR==2 {print $4}')
  if ((free_kb > 4194304)); then
    ok 'disk space' "$((free_kb / 1048576)) GiB free"
  else
    warn 'disk space' "$((free_kb / 1048576)) GiB free — torch and friends want ~4 GiB"
  fi

  info "log: $LOG_FILE"
}

step_uv() {
  step 'Package manager (uv)'

  if have uv; then
    ok 'uv' "$(uv --version 2>/dev/null)"
    record uv 'already installed'
    return 0
  fi

  info 'uv not found — installing from astral.sh'
  task 'downloading uv installer' bash -c \
    "set -o pipefail; curl --proto '=https' --tlsv1.2 -LsSf '$UV_INSTALLER' | sh" \
    || die 'uv installation failed' "see $LOG_FILE"

  # the installer drops uv in one of these; make it usable right now
  local candidate
  for candidate in "${XDG_BIN_HOME:-}" "${CARGO_HOME:-$HOME/.cargo}/bin" "$HOME/.local/bin"; do
    [[ -n $candidate && -x $candidate/uv ]] && PATH="$candidate:$PATH" && break
  done
  hash -r 2>/dev/null || true

  have uv || die 'uv installed but not on PATH' \
    "add it by hand, e.g.  export PATH=\"\$HOME/.local/bin:\$PATH\""

  ok 'uv' "$(uv --version 2>/dev/null)"
  warn 'PATH' 'uv was added to PATH for this run only'
  info 'persist it:  echo '\''export PATH="$HOME/.local/bin:$PATH"'\'' >> ~/.bashrc'
  record uv 'installed'
}

step_venv() {
  step 'Virtual environment'

  if [[ -d $VENV_DIR ]] && ((OPT_RECREATE)); then
    task 'removing old .venv' rm -rf -- "$VENV_DIR" || die 'could not remove .venv'
    ok 'old .venv' 'removed'
  fi

  if [[ -x $VENV_PY ]]; then
    ok '.venv' "$("$VENV_PY" -V 2>&1)"
    record venv 'reused'
    return 0
  fi

  task "creating .venv on python $PYTHON_VERSION" \
    uv venv "$VENV_DIR" --python "$PYTHON_VERSION" \
    || die "could not create a venv on python $PYTHON_VERSION" \
           'try another version:  ./setup.sh --python 3.11'

  ok '.venv' "$("$VENV_PY" -V 2>&1)"
  record venv "created (python $PYTHON_VERSION)"
}

step_deps() {
  step 'Dependencies'
  "$VENV_PY" -c 'import torch' 2>/dev/null \
    || info 'first run pulls ~2 GiB of wheels — torch, transformers, scikit-learn'

  task 'syncing from uv.lock (cpu-only torch)' \
    env VIRTUAL_ENV="$VENV_DIR" uv sync --extra-index-url "$TORCH_INDEX" \
    || die 'dependency sync failed' \
           "re-run with --verbose to watch it, or read $LOG_FILE"

  local count
  count=$(uv pip list --python "$VENV_PY" 2>/dev/null | tail -n +3 | wc -l | tr -d ' ')
  ok 'packages installed' "$count"
  record deps "$count packages"
}

step_config() {
  step 'Configuration'

  local example="$ROOT/.env.example" envfile="$ROOT/.env"

  cat >"$example" <<'ENVEXAMPLE'
# ── Groq ──────────────────────────────────────────────────────────────────────
# https://console.groq.com/keys
GROQ_API_KEY=your_groq_api_key_here

# ── Supabase ──────────────────────────────────────────────────────────────────
# Dashboard → your project → Settings → API
# Only needed for llm/rag-data-leak and agents/rag-injection
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_KEY=your_supabase_anon_key_here
ENVEXAMPLE
  ok '.env.example' 'written'

  if [[ -f $envfile ]]; then
    ok '.env' 'already exists — left untouched'
    local mode
    mode=$(stat -c '%a' -- "$envfile" 2>/dev/null || stat -f '%Lp' -- "$envfile" 2>/dev/null || echo 600)
    if [[ $mode != 600 ]]; then
      chmod 600 -- "$envfile" 2>/dev/null &&
        warn '.env permissions' "were $mode — tightened to 600 (it holds API keys)" ||
        warn '.env permissions' "are $mode — consider chmod 600 .env"
    fi
  else
    cp -- "$example" "$envfile"
    chmod 600 -- "$envfile" 2>/dev/null || true
    warn '.env' 'created from template — fill in your keys'
    record .env 'created, keys pending'
  fi

  # a .env full of real keys must never be committable
  local gitignore="$ROOT/.gitignore" added=()
  [[ -f $gitignore ]] || : >"$gitignore"
  local pattern
  for pattern in '.env' '.venv/' '__pycache__/' '*.pyc'; do
    grep -qxF -- "$pattern" "$gitignore" || { printf '%s\n' "$pattern" >>"$gitignore"; added+=("$pattern"); }
  done
  ((${#added[@]})) \
    && ok '.gitignore' "added ${added[*]}" \
    || ok '.gitignore' 'already covers .env and .venv'
}

step_verify() {
  step 'Verification'

  have uv && ok 'uv on PATH' "$(uv --version 2>/dev/null)" \
          || { bad 'uv on PATH' 'not found'; return 1; }

  [[ -x $VENV_PY ]] && ok 'venv interpreter' "$("$VENV_PY" -V 2>&1)" \
                    || { bad 'venv interpreter' "missing — expected $VENV_PY"; return 1; }

  local py_minor
  py_minor=$("$VENV_PY" -c 'import sys; print("%d.%d" % sys.version_info[:2])')
  "$VENV_PY" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 11) else 1)' \
    && ok 'python 3.11+' "$py_minor" \
    || { bad 'python 3.11+' "found $py_minor"; return 1; }

  if task 'checking dependency tree' uv pip check --python "$VENV_PY"; then
    ok 'dependency tree' 'consistent'
  else
    warn 'dependency tree' 'uv pip check reported conflicts — see the log'
  fi

  local torch_ver
  if torch_ver=$("$VENV_PY" -c 'import torch; print(torch.__version__)' 2>>"$LOG_FILE"); then
    ok 'torch imports' "$torch_ver"
    [[ $torch_ver == *+cpu* ]] || warn 'torch build' "$torch_ver is not the +cpu wheel"
  else
    bad 'torch imports' 'failed — see the log'
    return 1
  fi

  # by far the most common stumble: running the system python, which sees none
  # of these packages — sklearn, torch and friends live only inside .venv
  if [[ ${VIRTUAL_ENV:-} == "$VENV_DIR" ]]; then
    ok 'venv active in shell' "$VIRTUAL_ENV"
  else
    warn 'venv active in shell' 'no — a bare `python` will not find these packages'
    info 'activate it:  source .venv/bin/activate'
    info 'or skip that: uv run python verify-environment.py'
  fi

  [[ -f $ROOT/.env ]] && ok '.env present' || { bad '.env present' 'missing'; return 1; }

  local keys_pending=0
  grep -qE '^GROQ_API_KEY=(your_|\s*$)' "$ROOT/.env" && keys_pending=1
  if ((keys_pending)); then
    warn 'api keys' 'GROQ_API_KEY is still the placeholder'
  else
    ok 'api keys' 'GROQ_API_KEY looks filled in'
  fi

  # hand off to the project's own deep check (packages + live Groq call)
  printf '\n     %srunning verify-environment.py%s\n\n' "$DIM" "$RESET"
  local rc=0
  set +e
  ( cd -- "$ROOT" && "$VENV_PY" verify-environment.py ) 2>&1 | tee -a "$LOG_FILE" | sed 's/^/     /'
  rc=${PIPESTATUS[0]}
  set -e

  if ((rc == 0)); then
    record verify 'all checks passed'
    return 0
  elif ((keys_pending)); then
    record verify 'packages ok, api keys pending'
    warn 'verify-environment.py' 'failed on API keys only — expected until .env is filled in'
    return 0
  else
    record verify 'failed'
    return 1
  fi
}

# ═════════════════════════════════════════════════════════════════ summary ════

finish() {
  local failed=$1 elapsed=$2
  local pad=62

  if ((${#SUMMARY[@]})); then
    printf '\n  %s%s%s%s%s\n' "$GREY" "$TL" "$(rule $pad)" "$TR" "$RESET"
    local row name value
    for row in "${SUMMARY[@]}"; do
      name=${row%%$'\t'*}; value=${row#*$'\t'}
      local label; label=$(pad_to "$name" 14)
      box_row "$GREY" "$BOLD$label$RESET$DIM$value$RESET" "$((${#label} + ${#value}))" "$pad"
    done
    printf '  %s%s%s%s%s\n' "$GREY" "$BL" "$(rule $pad)" "$BR" "$RESET"
  fi

  if ((failed)); then
    printf '\n  %s%s setup incomplete%s %sin %ss %s log: %s%s\n\n' \
      "$RED$BOLD" "$FAIL_MARK" "$RESET" "$DIM" "$elapsed" "$SEP" "$LOG_FILE" "$RESET"
    return 1
  fi

  printf '\n  %s%s environment ready%s %sin %ss' \
    "$GREEN$BOLD" "$OK_MARK" "$RESET" "$DIM" "$elapsed"
  ((WARNINGS)) && printf ' %s %d warning(s)' "$SEP" "$WARNINGS"
  printf '%s\n' "$RESET"

  printf '\n  %snext%s\n' "$BOLD" "$RESET"
  printf '     %s1%s activate   %ssource .venv/bin/activate%s\n' "$CYAN" "$RESET" "$DIM" "$RESET"
  printf '     %s2%s add keys   %s$EDITOR .env%s\n'              "$CYAN" "$RESET" "$DIM" "$RESET"
  printf '     %s3%s re-verify  %s./setup.sh --verify%s\n'       "$CYAN" "$RESET" "$DIM" "$RESET"
  printf '     %s%s%s no activate? %sprefix commands with: uv run%s\n' \
    "$DIM" "$INFO_MARK" "$RESET" "$DIM" "$RESET"
  printf '     %s4%s attack     %ssee the README in ml-models/, llm/, agents/%s\n\n' \
    "$CYAN" "$RESET" "$DIM" "$RESET"
  return 0
}

main() {
  parse_args "$@"
  style_init

  local log_dir=${TMPDIR:-/tmp}/workshop-setup
  mkdir -p -- "$log_dir"
  LOG_FILE="$log_dir/setup-$(date +%Y%m%d-%H%M%S).log"
  printf 'setup.sh %s — %s\n' "$VERSION" "$(date)" >"$LOG_FILE"

  banner
  SECONDS=0
  local failed=0

  if ((OPT_VERIFY_ONLY)); then
    TOTAL_STEPS=2
    step_preflight
    step_verify || failed=1
  else
    ((OPT_SKIP_VERIFY)) && TOTAL_STEPS=5
    step_preflight
    step_uv
    step_venv
    step_deps
    step_config
    if ((OPT_SKIP_VERIFY)); then
      info 'verification skipped (--skip-verify)'
      record verify 'skipped'
    else
      step_verify || failed=1
    fi
  fi

  finish "$failed" "$SECONDS"
}

# `if` keeps a non-zero main out of the ERR trap, so failures report once
if main "$@"; then
  exit 0
else
  exit $?
fi
