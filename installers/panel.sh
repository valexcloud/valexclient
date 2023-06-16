#!/bin/bash

set -e

# Check if script is loaded, load if not or fail otherwise.
fn_exists() { declare -F "$1" >/dev/null; }
if ! fn_exists lib_loaded; then
  # shellcheck source=lib/lib.sh
  source /tmp/lib.sh || source <(curl -sSL https://raw.githubusercontent.com/valexcloud/valexclient/main/lib.sh)
  ! fn_exists lib_loaded && echo "* ERROR: Could not load lib script" && exit 1
fi

# ------------------ Variables ----------------- #

# Domain name / IP
FQDN="${FQDN:-localhost}"
LICENSE="${LICENSE}"
# Default MySQL credentials
MYSQL_DB="${MYSQL_DB:-faliactyl}"
MYSQL_USER="${MYSQL_USER:-faliactyl}"
MYSQL_PASSWORD="${MYSQL_PASSWORD:-$(gen_passwd 64)}"

# Environment
timezone="${timezone:-Europe/Stockholm}"

# Assume SSL, will fetch different config if true
CONFIGURE_LETSENCRYPT="${CONFIGURE_LETSENCRYPT:-false}"

# Firewall
CONFIGURE_FIREWALL="${CONFIGURE_FIREWALL:-false}"

# Must be assigned to work, no default values
email="${email:-}"
if [[ -z "${email}" ]]; then
  error "Email is required"
  exit 1
fi
# --------- Main installation functions -------- #
install_node() {
  output "Installing Node JS.."
  curl -sL https://deb.nodesource.com/setup_16.x | sudo -E bash -
  install_packages "nodejs"
  success "NodeJS installed!"
}

install_hct() {
  output "Installing Hydra Cloud Software Manager.."
  curl -s https://cdn.hct.digital/script.deb.sh | sudo bash
  install_packages "hct"
  success "Hydra Cloud Software Manager installed!"
}

valex_dl() {
  output "Downloading Faliactyl files .. "
  mkdir -p /var/www/faliactyl
  cd /var/www/faliactyl
  wget https://raw.githubusercontent.com/valexcloud/valexclient/main/ValexClient-Release-V$FALIACTYL_VERSION.zip
  unzip ValexClient-Release-V$FALIACTYL_VERSION.zip
  rm ValexClient-Release-V$FALIACTYL_VERSION.zip
  npm install
  npm install -g pm2
  pm2 start index.js --name "Faliactyl"
  success "Downloaded Faliactyl files!"
}

# -------- OS specific install functions ------- #

enable_services() {
  case "$OS" in
  ubuntu | debian)
    systemctl enable redis-server
    systemctl start redis-server
    ;;
  rocky | almalinux)
    systemctl enable redis
    systemctl start redis
    ;;
  esac
  systemctl enable nginx
  systemctl enable mariadb
  systemctl start mariadb
}

selinux_allow() {
  setsebool -P httpd_can_network_connect 1 || true # these commands can fail OK
  setsebool -P httpd_execmem 1 || true
  setsebool -P httpd_unified 1 || true
}

ubuntu_dep() {
  # Install deps for adding repos
  install_packages "software-properties-common apt-transport-https ca-certificates gnupg"

  # Add Ubuntu universe repo
  add-apt-repository universe -y

  # Add the MariaDB repo (bionic has mariadb version 10.1 and we need newer than that)
  [ "$OS_VER_MAJOR" == "18" ] && curl -sS https://downloads.mariadb.com/MariaDB/mariadb_repo_setup | bash

  # Add PPA for PHP (we need 8.1)
  LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php
}

debian_dep() {
  # Install deps for adding repos
  install_packages "dirmngr ca-certificates apt-transport-https lsb-release"

  # Install PHP 8.1 using sury's repo
  curl -o /etc/apt/trusted.gpg.d/php.gpg https://packages.sury.org/php/apt.gpg
  echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" | tee /etc/apt/sources.list.d/php.list
}

alma_rocky_dep() {
  # SELinux tools
  install_packages "policycoreutils selinux-policy selinux-policy-targeted \
    setroubleshoot-server setools setools-console mcstrans"

  # add remi repo (php8.1)
  install_packages "epel-release http://rpms.remirepo.net/enterprise/remi-release-$OS_VER_MAJOR.rpm"
  dnf module enable -y php:remi-8.1
}

dep_install() {
  output "Installing dependencies for $OS $OS_VER..."

  # Update repos before installing
  update_repos

  [ "$CONFIGURE_FIREWALL" == true ] && install_firewall && firewall_ports

  case "$OS" in
  ubuntu | debian)
    [ "$OS" == "ubuntu" ] && ubuntu_dep
    [ "$OS" == "debian" ] && debian_dep

    update_repos

    # Install dependencies
    install_packages " php-curl php8.1 php8.1-{cli,common,gd,mysql,mbstring,bcmath,xml,curl,zip} \
      mariadb-common mariadb-server mariadb-client \
      nginx \
      redis-server \
      zip unzip tar \
      git cron"

    [ "$CONFIGURE_LETSENCRYPT" == true ] && install_packages "certbot python3-certbot-nginx"

    ;;
  rocky | almalinux)
    alma_rocky_dep

    # Install dependencies
    install_packages "php php-{common,cli,json,mysqlnd,mcrypt,gd,mbstring,pdo,zip,bcmath,dom,opcache,posix} \
      mariadb mariadb-server \
      nginx \
      redis \
      zip unzip tar \
      git cronie"

    [ "$CONFIGURE_LETSENCRYPT" == true ] && install_packages "certbot python3-certbot-nginx"

    # Allow nginx
    selinux_allow
    ;;
  esac

  enable_services

  success "Dependencies installed!"
}

# --------------- Other functions -------------- #

firewall_ports() {
  output "Opening ports: 22 (SSH), 80 (HTTP) 443 (HTTPS) 3070 (Faliactyl)"

  firewall_allow_ports "22 80 443 3070"

  success "Firewall ports opened!"
}

letsencrypt() {
  FAILED=false

  output "Configuring Let's Encrypt..."

  systemctl stop nginx

  # Obtain certificate
  certbot certonly --standalone --no-eff-email --email "$email" -d "$FQDN" || FAILED=true

  # Check if it succeded
  if [ ! -d "/etc/letsencrypt/live/$FQDN/" ] || [ "$FAILED" == true ]; then
    warning "The process of obtaining a Let's Encrypt certificate failed!"
    echo -n "* Still assume SSL? (y/N): "
    read -r CONFIGURE_SSL

    if [[ "$CONFIGURE_SSL" =~ [Yy] ]]; then
      ASSUME_SSL=true
      CONFIGURE_LETSENCRYPT=false
      configure_nginx
    else
      ASSUME_SSL=false
      CONFIGURE_LETSENCRYPT=false
    fi
  else
    success "The process of obtaining a Let's Encrypt certificate succeeded!"
  fi
}

# ------ Webserver configuration functions ----- #

configure_nginx() {
  output "Configuring nginx .."

  apt -y purge apache2
  apt -y purge apache2-bin
  if [ $ASSUME_SSL == true ] && [ $CONFIGURE_LETSENCRYPT == false ]; then
    DL_FILE="nginx_ssl.conf"
  else
    DL_FILE="nginx.conf"
  fi

  case "$OS" in
  ubuntu | debian)
    CONFIG_PATH_AVAIL="/etc/nginx/sites-available"
    CONFIG_PATH_ENABL="/etc/nginx/sites-enabled"
    ;;
  rocky | almalinux)
    CONFIG_PATH_AVAIL="/etc/nginx/conf.d"
    CONFIG_PATH_ENABL="$CONFIG_PATH_AVAIL"
    ;;
  esac

  rm -rf $CONFIG_PATH_ENABL/default
  rm -rf $CONFIG_PATH_AVAIL/default

  curl -o $CONFIG_PATH_AVAIL/faliactyl.conf https://raw.githubusercontent.com/valexcloud/valexclient/main/configs/$DL_FILE

  sed -i -e "s@<DOMAIN>@${FQDN}@g" $CONFIG_PATH_AVAIL/faliactyl.conf

  case "$OS" in
  ubuntu | debian)
    ln -sf $CONFIG_PATH_AVAIL/faliactyl.conf $CONFIG_PATH_ENABL/faliactyl.conf
    ;;
  esac

  if [ "$ASSUME_SSL" == false ] && [ "$CONFIGURE_LETSENCRYPT" == false ]; then
    systemctl restart nginx
  fi

  success "Nginx configured!"
}

configure_env(){
cd /var/www/faliactyl
SECRET=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 30 | head -n 1)
cat >.env <<EOL
# License Key
LICENSE_KEY=${LICENSE}


# App Configuration
APP_NAME=Faliactyl

# Cookie Signing Secret Key. Put a very random string! Like This: Bfi3bmf4bq37xbm3f7qxebymdwyexyfbd
APP_SECRET=${SECRET}
APP_HOST=${HTTP}${FQDN}
APP_PORT=3070
APP_THEME=default
APP_PANEL=pterodactyl


# MySQL Server (User and Settings Storage)
MYSQL_HOST=127.0.0.1
MYSQL_PORT=3306
MYSQL_DATABASE=${MYSQL_DB}
MYSQL_USERNAME=${MYSQL_USER}
MYSQL_PASSWORD=${MYSQL_PASSWORD}


# Redis Session Server (Session Storage)
REDIS_HOST=127.0.0.1
REDIS_PORT=6379
REDIS_DBNUMBER=0


# Advanced Configuration
# Interval between execution of tasks like leaderboards and renew checker
TASK_INTERVAL=500


# SMTP (Email Server)
SMTP_MAILFROM=
SMTP_HOST=
SMTP_PORT=
SMTP_SECURE=true
SMTP_USERNAME=
SMTP_PASSWORD=


# Panel
PANEL_URL=https://panel.example.com
PANEL_API_KEY=ptla_yourpanelapikey
EOL
}
finish() {
  if [ $ASSUME_SSL == true ] && [ $CONFIGURE_LETSENCRYPT == false ]; then
    HTTP="https://"
  else
    HTTP="http://"
  fi
  success "Installation Finished!"
  output "Configure .env in /var/www/faliactyl and fillout the empty fields."
  output "The fields like mysql and redis have already been filled for you."
  output "You need to configure SMTP."
}
# --------------- Main functions --------------- #

perform_install() {
  output "Starting installation.. this might take a while!"
  dep_install
  install_node
  #install_hct
  valex_dl
  create_db_user "$MYSQL_USER" "$MYSQL_PASSWORD"
  create_db "$MYSQL_DB" "$MYSQL_USER"
  [ "$CONFIGURE_LETSENCRYPT" == true ] && letsencrypt
  configure_nginx
  configure_env
  apt -y autoremove
  finish
  return 0
}

# ------------------- Install ------------------ #

perform_install