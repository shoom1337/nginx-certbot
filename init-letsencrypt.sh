#!/bin/bash
set -e

# ─── Load .env ─────────────────────────────────────────────
if [ ! -f .env ]; then
  echo '[ERROR] .env file not found. Run setup.sh first.' >&2
  exit 1
fi
while IFS= read -r line; do export "$line"; done < <(grep -v '^#' .env | grep -v '^$')

# ─── Variables ─────────────────────────────────────────────
domain="$DOMAIN_NAME"
rsa_key_size=4096
data_path="./data/certbot"
email="$CERTBOT_EMAIL"
staging="${CERTBOT_STAGING:-0}"

if [[ -z "$domain" ]]; then
  echo '[ERROR] DOMAIN_NAME is not set in .env' >&2
  exit 1
fi

# ─── TLS params ────────────────────────────────────────────
if [ ! -e "$data_path/conf/options-ssl-nginx.conf" ] || [ ! -e "$data_path/conf/ssl-dhparams.pem" ]; then
  echo "### Downloading recommended TLS parameters ..."
  mkdir -p "$data_path/conf"
  curl -s https://raw.githubusercontent.com/certbot/certbot/master/certbot-nginx/certbot_nginx/_internal/tls_configs/options-ssl-nginx.conf > "$data_path/conf/options-ssl-nginx.conf"
  curl -s https://raw.githubusercontent.com/certbot/certbot/master/certbot/certbot/ssl-dhparams.pem > "$data_path/conf/ssl-dhparams.pem"
  echo
fi

# ─── Dummy cert (nginx needs a cert to start) ─────────────
echo "### Creating dummy certificate for $domain ..."
path="/etc/letsencrypt/live/$domain"
mkdir -p "$data_path/conf/live/$domain"
docker compose run --rm --entrypoint "\
  openssl req -x509 -nodes -newkey rsa:$rsa_key_size -days 1\
    -keyout '$path/privkey.pem' \
    -out '$path/fullchain.pem' \
    -subj '/CN=localhost'" certbot
echo

# ─── Start nginx with dummy cert ───────────────────────────
echo "### Starting nginx ..."
docker compose up --force-recreate -d nginx
echo

# ─── Delete dummy cert ─────────────────────────────────────
echo "### Deleting dummy certificate for $domain ..."
docker compose run --rm --entrypoint "\
  rm -Rf /etc/letsencrypt/live/$domain && \
  rm -Rf /etc/letsencrypt/archive/$domain && \
  rm -Rf /etc/letsencrypt/renewal/$domain.conf" certbot
echo

# ─── Request real cert ─────────────────────────────────────
echo "### Requesting Let's Encrypt certificate for $domain ..."

domain_args="-d $domain"

case "$email" in
  "") email_arg="--register-unsafely-without-email" ;;
  *) email_arg="--email $email" ;;
esac

staging_arg=""
if [ "$staging" != "0" ]; then staging_arg="--staging"; fi

docker compose run --rm --entrypoint "\
  certbot certonly --webroot -w /var/www/certbot \
    $staging_arg \
    $email_arg \
    $domain_args \
    --rsa-key-size $rsa_key_size \
    --agree-tos \
    --force-renewal" certbot
echo

echo "### Reloading nginx ..."
docker compose exec nginx nginx -s reload
