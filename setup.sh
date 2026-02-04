#!/bin/bash
set -e

# ─── Colors ────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ─── Helpers ───────────────────────────────────────────────
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
prompt()  { echo -e "${CYAN}$*${NC}"; }

# ─── Prereqs ───────────────────────────────────────────────
check_prereqs() {
  info "Checking prerequisites..."

  if ! command -v docker &>/dev/null; then
    error "Docker is not installed or not in PATH."
    error "Install Docker: https://docs.docker.com/get-docker/"
    exit 1
  fi
  success "Docker found"

  if ! docker info &>/dev/null; then
    error "Docker daemon is not running. Start Docker and try again."
    exit 1
  fi
  success "Docker daemon is running"

  if ! docker compose version &>/dev/null; then
    error "Docker Compose plugin is not installed."
    error "Install it: https://docs.docker.com/compose/install/"
    exit 1
  fi
  success "Docker Compose found"

  if ! command -v curl &>/dev/null; then
    error "curl is not installed or not in PATH."
    exit 1
  fi
  success "curl found"

  # Ports 80 and 443
  for port in 80 443; do
    if command -v lsof &>/dev/null; then
      if lsof -i :"$port" &>/dev/null; then
        warn "Port $port is already in use. Proceeding anyway..."
      fi
    fi
  done

  echo
}

# ─── Input ─────────────────────────────────────────────────
collect_input() {
  info "Fill in the configuration (press Enter to accept defaults)"
  echo

  # Domain
  while true; do
    prompt "  Domain name (e.g. example.com):"
    read -r DOMAIN_NAME
    if [[ -z "$DOMAIN_NAME" ]]; then
      error "Domain name is required."
      continue
    fi
    # Strip protocol if pasted
    DOMAIN_NAME=$(echo "$DOMAIN_NAME" | sed -E 's|^https?://||' | sed 's|/.*||')
    break
  done

  # Email
  prompt "  Email for Let's Encrypt notifications (leave empty to skip):"
  read -r CERTBOT_EMAIL

  # Staging
  prompt "  Use staging certificates? (y/N) — use 'y' for testing to avoid rate limits:"
  read -r staging_input
  if [[ "$staging_input" =~ ^[Yy]$ ]]; then
    CERTBOT_STAGING=1
    warn "Staging mode enabled — certificate will NOT be trusted by browsers."
  else
    CERTBOT_STAGING=0
  fi

  echo
}

# ─── Generate .env ─────────────────────────────────────────
generate_env() {
  if [[ -f .env ]]; then
    warn ".env already exists."
    prompt "  Overwrite? (y/N):"
    read -r overwrite
    if [[ ! "$overwrite" =~ ^[Yy]$ ]]; then
      warn "Keeping existing .env. Using its values."
      while IFS='=' read -r key value; do export "$key=$value"; done < <(grep -v '^#' .env | grep -v '^$')
      return
    fi
  fi

  info "Generating .env..."
  cat > .env <<EOF
NGINX_VERSION=1.21-alpine
NGINX_CONF_DIR=./data/nginx/conf.d
DOMAIN_NAME=${DOMAIN_NAME}
CERTBOT_EMAIL=${CERTBOT_EMAIL}
CERTBOT_STAGING=${CERTBOT_STAGING}

CERTBOT_CONF_DIR=./data/certbot/conf
CERTBOT_WWW_DIR=./data/certbot/www

SITES_DIR=./sites
EOF

  success ".env created"
  echo
}

# ─── Patch index.html ──────────────────────────────────────
patch_index() {
  sed -i "s|{{DOMAIN_NAME}}|${DOMAIN_NAME}|g" sites/index.html
  success "index.html updated with domain"
  echo
}

# ─── Confirm ───────────────────────────────────────────────
confirm() {
  echo
  info "Configuration summary:"
  echo -e "  Domain:   ${GREEN}${DOMAIN_NAME}${NC}"
  echo -e "  Email:    ${GREEN}${CERTBOT_EMAIL:-not set}${NC}"
  echo -e "  Staging:  ${GREEN}$([ "$CERTBOT_STAGING" = "1" ] && echo Yes || echo No)${NC}"
  echo

  prompt "  Start setup? (y/N):"
  read -r confirm_input
  if [[ ! "$confirm_input" =~ ^[Yy]$ ]]; then
    info "Aborted."
    exit 0
  fi
  echo
}

# ─── Run init ──────────────────────────────────────────────
run_init() {
  info "Obtaining SSL certificate..."
  echo

  if ! bash ./init-letsencrypt.sh; then
    error "Certificate setup failed."
    error "Check the output above for details."
    error "Common issues:"
    error "  - Domain does not resolve to this server's IP"
    error "  - Port 80 is blocked by firewall"
    error "  - Let's Encrypt rate limit reached (use staging mode)"
    exit 1
  fi

  success "SSL certificate obtained"
  echo
}

# ─── Start server ──────────────────────────────────────────
start_server() {
  info "Starting server..."
  echo

  if ! docker compose up --force-recreate -d; then
    error "Failed to start containers."
    error "Run 'docker compose logs' to see details."
    exit 1
  fi

  echo
  success "Server is running!"
  echo
  if [[ "$CERTBOT_STAGING" = "1" ]]; then
    warn "Using staging certificate — browser will show a security warning. This is normal for testing."
  fi
  echo -e "  Visit: ${GREEN}https://${DOMAIN_NAME}${NC}"
  echo
  info "Logs: docker compose logs -f"
  info "Stop:  docker compose down"
  echo
}

# ─── Main ──────────────────────────────────────────────────
main() {
  echo
  echo -e "${GREEN}=====================================${NC}"
  echo -e "${GREEN}   nginx + Let's Encrypt SSL Setup    ${NC}"
  echo -e "${GREEN}=====================================${NC}"
  echo -e "  ${CYAN}https://github.com/shoom1337/nginx-certbot${NC}"
  echo

  check_prereqs
  collect_input
  generate_env
  patch_index
  confirm
  run_init
  start_server
}

main
