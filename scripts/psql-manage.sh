#!/usr/bin/env bash
# Native PostgreSQL install & management (no Docker).
# Copy to any macOS / Linux machine and run directly.
#
# Usage:
#   ./psql-manage.sh install                         # install server, create admin user/db
#   ./psql-manage.sh status                          # check service + connectivity
#   ./psql-manage.sh backup [output_dir]             # dump database to a file
#   ./psql-manage.sh create-user <username>            # add another account
#
# Environment:
#   POSTGRES_USER         default: multica          (install creates this account)
#   POSTGRES_PASSWORD     default: multica
#   POSTGRES_DB           default: multica
#   POSTGRES_PORT         default: 5433             (non-default to avoid conflicts)
#   POSTGRES_HOST         default: localhost
#   POSTGRES_SUPERUSER    default: true             (install account is superuser)
#
# create-user extras:
#   NEW_PASSWORD          optional; random password generated when omitted
#   PG_SUPERUSER          default: false
#   NEW_DB                optional database to create/grant for the new user
#
set -euo pipefail

POSTGRES_USER="${POSTGRES_USER:-multica}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-multica}"
POSTGRES_DB="${POSTGRES_DB:-multica}"
POSTGRES_PORT="${POSTGRES_PORT:-5433}"
POSTGRES_HOST="${POSTGRES_HOST:-localhost}"
POSTGRES_SUPERUSER="${POSTGRES_SUPERUSER:-true}"

macos_superuser=""
if [ "$(uname -s)" = "Darwin" ]; then
  macos_superuser="$(whoami)"
fi

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
info()  { printf '==> %s\n' "$*"; }
ok()    { printf '✓ %s\n' "$*"; }
warn()  { printf '⚠ %s\n' "$*" >&2; }
fail()  { printf '✗ %s\n' "$*" >&2; exit 1; }

command_exists() { command -v "$1" >/dev/null 2>&1; }

# URL/SQL-safe random password (letters + digits only).
generate_random_password() {
  local len="${1:-24}"
  if command_exists openssl; then
    openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c "$len"
  else
    tr -dc 'A-Za-z0-9' </dev/urandom | head -c "$len"
  fi
}

detect_os() {
  case "$(uname -s)" in
    Darwin) echo "macos" ;;
    Linux)  echo "linux" ;;
    *)      echo "unknown" ;;
  esac
}

detect_linux_pkg() {
  if command_exists apt-get; then
    echo "apt"
  elif command_exists dnf; then
    echo "dnf"
  elif command_exists yum; then
    echo "yum"
  else
    echo "unknown"
  fi
}

ensure_pg_path() {
  if [ "$(detect_os)" != "macos" ] || ! command_exists brew; then
    return 0
  fi

  local formula prefix
  for formula in postgresql@17 postgresql@16 postgresql; do
    prefix="$(brew --prefix "$formula" 2>/dev/null || true)"
    if [ -n "$prefix" ] && [ -x "${prefix}/bin/psql" ]; then
      export PATH="${prefix}/bin:$PATH"
      echo "$formula"
      return 0
    fi
  done
  return 1
}

brew_postgresql_formula() {
  if [ "$(detect_os)" != "macos" ] || ! command_exists brew; then
    return 1
  fi

  local line formula
  line="$(brew services list 2>/dev/null | grep -E '^postgresql(@[0-9]+)?' | head -n 1 || true)"
  if [ -n "$line" ]; then
    formula="${line%% *}"
    echo "$formula"
    return 0
  fi

  local f
  for f in postgresql@17 postgresql@16 postgresql; do
    if brew list "$f" >/dev/null 2>&1; then
      echo "$f"
      return 0
    fi
  done
  echo "postgresql@17"
}

export_pgp_password() {
  export PGPASSWORD="$POSTGRES_PASSWORD"
}

# Admin psql: OS superuser via local socket (macOS) or postgres user (Linux).
psql_admin() {
  local db="${1:-postgres}"
  shift || true
  case "$(detect_os)" in
    macos)
      psql -d "$db" "$@"
      ;;
    linux)
      sudo -u postgres psql -d "$db" "$@"
      ;;
    *)
      fail "Unsupported OS"
      ;;
  esac
}

linux_run() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
  else
    sudo "$@"
  fi
}

pg_ready() {
  local port="${1:-$POSTGRES_PORT}"
  if command_exists pg_isready; then
    pg_isready -h "$POSTGRES_HOST" -p "$port" -q 2>/dev/null && return 0
    if [ "$(detect_os)" = "macos" ] && [ "$port" = "5432" ] && [ "$POSTGRES_HOST" = "localhost" ]; then
      pg_isready -q 2>/dev/null && return 0
    fi
  fi
  psql_admin postgres -Atqc "SELECT 1" >/dev/null 2>&1
}

wait_for_postgres() {
  local port="${1:-$POSTGRES_PORT}"
  local tries=0 max=60
  info "Waiting for PostgreSQL on port ${port}..."
  while [ "$tries" -lt "$max" ]; do
    if pg_ready "$port"; then
      ok "PostgreSQL is ready (port ${port})"
      return 0
    fi
    tries=$((tries + 1))
    sleep 1
  done
  fail "PostgreSQL did not become ready on port ${port} within ${max}s"
}

restart_postgres() {
  case "$(detect_os)" in
    macos)
      local formula
      formula="$(brew_postgresql_formula)"
      info "Restarting ${formula}..."
      brew services restart "$formula"
      ;;
    linux)
      info "Restarting postgresql service..."
      linux_run systemctl restart postgresql
      ;;
  esac
}

configure_listen_port() {
  local conf current_port
  conf="$(psql_admin postgres -Atqc "SHOW config_file")"
  [ -n "$conf" ] || fail "Cannot locate postgresql.conf"

  current_port="$(psql_admin postgres -Atqc "SHOW port")"
  if [ "$current_port" = "$POSTGRES_PORT" ]; then
    ok "Port already ${POSTGRES_PORT}"
    return 0
  fi

  info "Setting port ${current_port} -> ${POSTGRES_PORT} in ${conf}..."

  case "$(detect_os)" in
    macos)
      if grep -qE '^[[:space:]]*#?[[:space:]]*port[[:space:]]*=' "$conf"; then
        sed -i.bak -E "s/^[#[:space:]]*port[[:space:]]*=.*/port = ${POSTGRES_PORT}/" "$conf"
      else
        printf '\nport = %s\n' "$POSTGRES_PORT" >> "$conf"
      fi
      ;;
    linux)
      if grep -qE '^[[:space:]]*#?[[:space:]]*port[[:space:]]*=' "$conf"; then
        linux_run sed -i.bak -E "s/^[#[:space:]]*port[[:space:]]*=.*/port = ${POSTGRES_PORT}/" "$conf"
      else
        linux_run bash -c "printf '\nport = %s\n' '$POSTGRES_PORT' >> '$conf'"
      fi
      ;;
  esac

  restart_postgres
  wait_for_postgres "$POSTGRES_PORT"
}

role_privileges_sql() {
  local super_flag="${1:-false}"
  local attrs="LOGIN CREATEDB"
  if [ "$super_flag" = "true" ]; then
    printf '%s SUPERUSER' "$attrs"
  else
    printf '%s NOSUPERUSER' "$attrs"
  fi
}

ensure_role_and_database() {
  local attrs super_label
  attrs="$(role_privileges_sql "$POSTGRES_SUPERUSER")"
  if [ "$POSTGRES_SUPERUSER" = "true" ]; then
    super_label="superuser"
  else
    super_label="regular user (not superuser)"
  fi

  info "Ensuring role '${POSTGRES_USER}' (${super_label}) and database '${POSTGRES_DB}'..."

  local role_exists db_exists
  role_exists="$(psql_admin postgres -Atqc \
    "SELECT 1 FROM pg_roles WHERE rolname = '${POSTGRES_USER}'" 2>/dev/null || echo "")"
  db_exists="$(psql_admin postgres -Atqc \
    "SELECT 1 FROM pg_database WHERE datname = '${POSTGRES_DB}'" 2>/dev/null || echo "")"

  if [ "$role_exists" != "1" ]; then
    psql_admin postgres -v ON_ERROR_STOP=1 \
      -c "CREATE ROLE \"${POSTGRES_USER}\" WITH ${attrs} PASSWORD '${POSTGRES_PASSWORD}';"
    ok "Created role ${POSTGRES_USER} (${super_label})"
  else
    psql_admin postgres -v ON_ERROR_STOP=1 \
      -c "ALTER ROLE \"${POSTGRES_USER}\" WITH ${attrs} PASSWORD '${POSTGRES_PASSWORD}';"
    ok "Updated role ${POSTGRES_USER} (${super_label})"
  fi

  if [ "$db_exists" != "1" ]; then
    psql_admin postgres -v ON_ERROR_STOP=1 \
      -c "CREATE DATABASE \"${POSTGRES_DB}\" OWNER \"${POSTGRES_USER}\";"
    ok "Created database ${POSTGRES_DB}"
  else
    ok "Database ${POSTGRES_DB} already exists"
  fi
}

start_postgres_macos() {
  local formula
  formula="$(brew_postgresql_formula)"

  if ! brew services list 2>/dev/null | grep -qE "^${formula//\./\\.}.*started"; then
    info "Starting ${formula}..."
    brew services start "$formula"
  else
    ok "${formula} service already running"
  fi
}

# ---------------------------------------------------------------------------
# install
# ---------------------------------------------------------------------------
install_macos() {
  command_exists brew || fail "Homebrew required on macOS: https://brew.sh"

  local formula
  if ! command_exists psql; then
    formula="postgresql@17"
    info "Installing ${formula} via Homebrew..."
    brew install "$formula"
  else
    ok "psql already installed: $(command -v psql)"
    formula="$(brew_postgresql_formula)"
  fi

  ensure_pg_path >/dev/null || true
  start_postgres_macos
  wait_for_postgres 5432
  configure_listen_port
  ensure_role_and_database
}

install_linux_apt() {
  command_exists sudo || [ "$(id -u)" -eq 0 ] || fail "Root or sudo required on Linux"

  if ! command_exists psql; then
    info "Installing PostgreSQL via apt..."
    linux_run apt-get update -qq
    linux_run apt-get install -y postgresql postgresql-contrib
  else
    ok "psql already installed: $(command -v psql)"
  fi

  info "Enabling and starting postgresql service..."
  linux_run systemctl enable postgresql
  linux_run systemctl start postgresql

  wait_for_postgres 5432
  configure_listen_port
  ensure_role_and_database
}

install_linux_dnf() {
  command_exists sudo || [ "$(id -u)" -eq 0 ] || fail "Root or sudo required on Linux"

  if ! command_exists psql; then
    info "Installing PostgreSQL via dnf/yum..."
    if command_exists dnf; then
      linux_run dnf install -y postgresql-server postgresql-contrib
      if [ ! -d /var/lib/pgsql/data/base ]; then
        linux_run postgresql-setup --initdb
      fi
    else
      linux_run yum install -y postgresql-server postgresql-contrib
      if [ ! -d /var/lib/pgsql/data/base ]; then
        linux_run postgresql-setup initdb
      fi
    fi
  else
    ok "psql already installed: $(command -v psql)"
  fi

  info "Enabling and starting postgresql service..."
  linux_run systemctl enable postgresql
  linux_run systemctl start postgresql

  wait_for_postgres 5432
  configure_listen_port
  ensure_role_and_database
}

cmd_install() {
  ensure_pg_path >/dev/null || true

  info "Installing native PostgreSQL (user=${POSTGRES_USER}, db=${POSTGRES_DB}, port=${POSTGRES_PORT})"

  case "$(detect_os)" in
    macos) install_macos ;;
    linux)
      case "$(detect_linux_pkg)" in
        apt) install_linux_apt ;;
        dnf|yum) install_linux_dnf ;;
        *) fail "Unsupported package manager (need apt, dnf, or yum)" ;;
      esac
      ;;
    *) fail "Unsupported OS: $(uname -s)" ;;
  esac

  ok "Installation complete"
  if [ "$POSTGRES_SUPERUSER" = "true" ]; then
    ok "Account ${POSTGRES_USER} is a SUPERUSER (full admin)"
  else
    ok "Account ${POSTGRES_USER} is a regular user (NOSUPERUSER)"
  fi
  printf '\nConnection:\n'
  printf '  psql -h %s -p %s -U %s -d %s\n' "$POSTGRES_HOST" "$POSTGRES_PORT" "$POSTGRES_USER" "$POSTGRES_DB"
  printf '  DATABASE_URL=postgres://%s:%s@%s:%s/%s?sslmode=disable\n' \
    "$POSTGRES_USER" "$POSTGRES_PASSWORD" "$POSTGRES_HOST" "$POSTGRES_PORT" "$POSTGRES_DB"
  printf '\nAdd more accounts:\n'
  printf '  ./psql-manage.sh create-user app\n'
  printf '  NEW_DB=analytics ./psql-manage.sh create-user analyst\n'
  printf '  PG_SUPERUSER=true ./psql-manage.sh create-user admin2\n'
}

# ---------------------------------------------------------------------------
# create-user
# ---------------------------------------------------------------------------
cmd_create_user() {
  ensure_pg_path >/dev/null || true

  local username="${1:-}"
  local password="${NEW_PASSWORD:-}"
  local super="${PG_SUPERUSER:-false}"
  local new_db="${NEW_DB:-}"
  local attrs role_exists db_exists generated=0

  [ -n "$username" ] || fail "Usage: $0 create-user <username>"

  if [ -z "$password" ]; then
    password="$(generate_random_password)"
    generated=1
  fi

  pg_ready "$POSTGRES_PORT" || fail "PostgreSQL is not running on port ${POSTGRES_PORT}"

  attrs="$(role_privileges_sql "$super")"
  role_exists="$(psql_admin postgres -Atqc \
    "SELECT 1 FROM pg_roles WHERE rolname = '${username}'" 2>/dev/null || echo "")"

  if [ "$role_exists" = "1" ]; then
    psql_admin postgres -v ON_ERROR_STOP=1 \
      -c "ALTER ROLE \"${username}\" WITH ${attrs} PASSWORD '${password}';"
    ok "Updated existing user ${username}"
  else
    psql_admin postgres -v ON_ERROR_STOP=1 \
      -c "CREATE ROLE \"${username}\" WITH ${attrs} PASSWORD '${password}';"
    ok "Created user ${username}"
  fi

  if [ -n "$new_db" ]; then
    db_exists="$(psql_admin postgres -Atqc \
      "SELECT 1 FROM pg_database WHERE datname = '${new_db}'" 2>/dev/null || echo "")"
    if [ "$db_exists" != "1" ]; then
      psql_admin postgres -v ON_ERROR_STOP=1 \
        -c "CREATE DATABASE \"${new_db}\" OWNER \"${username}\";"
      ok "Created database ${new_db} (owner: ${username})"
    else
      psql_admin postgres -v ON_ERROR_STOP=1 \
        -c "GRANT ALL PRIVILEGES ON DATABASE \"${new_db}\" TO \"${username}\";"
      ok "Granted ${username} access to existing database ${new_db}"
    fi
  fi

  if [ "$super" = "true" ]; then
    ok "${username} is a SUPERUSER"
  else
    ok "${username} is a regular user (NOSUPERUSER)"
  fi

  printf '\n'
  if [ "$generated" -eq 1 ]; then
    ok "Random password generated — save it now (not stored elsewhere)"
  else
    ok "Account credentials"
  fi
  printf '  User:     %s\n' "$username"
  printf '  Password: %s\n' "$password"
  if [ -n "$new_db" ]; then
    printf '  Database: %s\n' "$new_db"
  else
    printf '  Database: %s\n' "$POSTGRES_DB"
  fi
  printf '  Connect:  psql -h %s -p %s -U %s -d %s\n' \
    "$POSTGRES_HOST" "$POSTGRES_PORT" "$username" "${new_db:-$POSTGRES_DB}"
}

# ---------------------------------------------------------------------------
# status
# ---------------------------------------------------------------------------
service_running() {
  pg_ready "$POSTGRES_PORT"
}

cmd_status() {
  ensure_pg_path >/dev/null || true

  info "Checking PostgreSQL (${POSTGRES_HOST}:${POSTGRES_PORT})"

  local client_ok=0 service_ok=0 conn_ok=0 super_flag

  if command_exists psql; then
    ok "psql: $(psql --version | head -n1)"
    client_ok=1
  else
    warn "psql not found in PATH"
  fi

  case "$(detect_os)" in
    macos)
      command_exists brew && brew services list 2>/dev/null | grep -E '^postgresql(@[0-9]+)?' || true
      ;;
    linux)
      command_exists systemctl && systemctl is-active postgresql 2>/dev/null || true
      ;;
  esac

  if service_running; then
    ok "PostgreSQL service is running on port ${POSTGRES_PORT}"
    service_ok=1
  else
    warn "PostgreSQL is not reachable on port ${POSTGRES_PORT}"
  fi

  if [ "$client_ok" -eq 1 ]; then
    export_pgp_password
    if psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Atqc "SELECT 1" >/dev/null 2>&1; then
      super_flag="$(psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d postgres -Atqc \
        "SELECT rolsuper FROM pg_roles WHERE rolname = '${POSTGRES_USER}'" 2>/dev/null || echo "")"
      if [ "$super_flag" = "t" ]; then
        ok "Login OK (${POSTGRES_USER}@${POSTGRES_DB}, SUPERUSER)"
      else
        ok "Login OK (${POSTGRES_USER}@${POSTGRES_DB}, regular user)"
      fi
      conn_ok=1
    else
      warn "Cannot connect as ${POSTGRES_USER}@${POSTGRES_DB}"
    fi
  fi

  if [ "$service_ok" -eq 1 ] && [ "$conn_ok" -eq 1 ]; then
    ok "Overall: healthy"
    exit 0
  fi

  warn "Overall: not ready (run: $0 install)"
  exit 1
}

# ---------------------------------------------------------------------------
# backup
# ---------------------------------------------------------------------------
cmd_backup() {
  ensure_pg_path >/dev/null || true
  command_exists pg_dump || fail "pg_dump not found. Run: $0 install"

  local out_dir="${1:-./backups}"
  local timestamp file

  mkdir -p "$out_dir"
  timestamp="$(date +%Y%m%d_%H%M%S)"
  file="${out_dir}/${POSTGRES_DB}_${timestamp}.sql.gz"

  service_running || fail "PostgreSQL is not running on port ${POSTGRES_PORT}"

  info "Backing up ${POSTGRES_DB}..."
  export_pgp_password
  pg_dump \
    -h "$POSTGRES_HOST" \
    -p "$POSTGRES_PORT" \
    -U "$POSTGRES_USER" \
    -d "$POSTGRES_DB" \
    --no-owner \
    --no-acl \
    | gzip > "$file"

  ok "Backup: ${file} ($(du -h "$file" | awk '{print $1}'))"
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
usage() {
  cat <<EOF
Usage: $(basename "$0") <command> [args]

Commands:
  install                 Install PostgreSQL, set port, create default user/db
  status                  Check service and database connectivity
  backup [output_dir]     Dump database to timestamped .sql.gz (default: ./backups)
  create-user <username>  Add or update another PostgreSQL account

Environment (install):
  POSTGRES_USER           default: multica
  POSTGRES_PASSWORD       default: multica
  POSTGRES_DB             default: multica
  POSTGRES_PORT           default: 5433
  POSTGRES_HOST           default: localhost
  POSTGRES_SUPERUSER      default: true   (install account gets SUPERUSER)

Environment (create-user):
  NEW_PASSWORD            optional; auto-generated when omitted
  PG_SUPERUSER            default: false  (set true for another admin)
  NEW_DB                  optional database to create or grant

Examples:
  ./psql-manage.sh install
  POSTGRES_PORT=5433 POSTGRES_PASSWORD=secret ./psql-manage.sh install
  POSTGRES_SUPERUSER=false ./psql-manage.sh install   # app user, not admin

  ./psql-manage.sh status
  ./psql-manage.sh backup /var/backups/postgres

  ./psql-manage.sh create-user app
  NEW_DB=analytics ./psql-manage.sh create-user analyst
  NEW_PASSWORD=my-own-secret ./psql-manage.sh create-user legacy
  PG_SUPERUSER=true ./psql-manage.sh create-user admin2
EOF
}

main() {
  local cmd="${1:-}"
  shift || true

  case "$cmd" in
    install)     cmd_install ;;
    status)      cmd_status ;;
    backup)      cmd_backup "${1:-}" ;;
    create-user) cmd_create_user "${1:-}" ;;
    -h|--help|help|"") usage ;;
    *) fail "Unknown command: $cmd (run --help)" ;;
  esac
}

main "$@"
