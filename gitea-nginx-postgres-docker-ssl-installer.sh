#!/bin/bash

#================================================================================#
#            УСТАНОВЩИК GITEA С DOCKER, POSTGRES, NGINX И SSL                  #
#                                                                              #
#================================================================================#

# --- Цвета для вывода ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

info() { echo -e "${BLUE}[INFO]${NC} $1"; }
warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

exec > >(tee -a /var/log/gitea-installer.log) 2>&1

# Добавляем параметры командной строки
AUTO_INSTALL=false
GITEA_DOMAIN=""
LETSENCRYPT_EMAIL=""
GITEA_ADMIN_USER=""

# Парсинг аргументов
while [[ $# -gt 0 ]]; do
    case $1 in
        --auto)
            AUTO_INSTALL=true
            shift
            ;;
        --domain)
            GITEA_DOMAIN="$2"
            shift 2
            ;;
        --email)
            LETSENCRYPT_EMAIL="$2"
            shift 2
            ;;
        --admin-user)
            GITEA_ADMIN_USER="$2"
            shift 2
            ;;
        --help)
            echo "Использование: $0 [--auto] [--domain DOMAIN] [--email EMAIL] [--admin-user USER]"
            echo ""
            echo "Опции:"
            echo "  --auto           Автоматическая установка без интерактивного ввода"
            echo "  --domain         Доменное имя для Gitea"
            echo "  --email          Email для Let's Encrypt"
            echo "  --admin-user     Имя администратора Gitea"
            echo "  --help           Показать эту справку"
            echo ""
            echo "Примеры:"
            echo "  $0                                    # Интерактивная установка"
            echo "  $0 --auto --domain git.example.com --email admin@example.com --admin-user admin"
            exit 0
            ;;
        *)
            error "Неизвестный параметр: $1"
            echo "Используйте --help для справки"
            exit 1
            ;;
    esac
done

prepare_system() {
    info "Подготовка системы..."
    if [ "$EUID" -ne 0 ]; then
        error "Скрипт должен запускаться от root или через sudo."
        exit 1
    fi

    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y \
        curl wget gnupg2 ca-certificates lsb-release apt-transport-https \
        software-properties-common ufw sudo net-tools dnsutils

    if ! command -v docker &> /dev/null; then
        info "Установка Docker..."
        install -m 0755 -d /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        chmod a+r /etc/apt/keyrings/docker.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
        https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
        | tee /etc/apt/sources.list.d/docker.list > /dev/null
        apt-get update
        apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
        systemctl enable docker
        success "Docker установлен."
    else
        success "Docker уже установлен."
    fi

    for pkg in nginx certbot python3-certbot-nginx fail2ban; do
        if ! dpkg -s $pkg &>/dev/null; then
            apt-get install -y $pkg
        fi
    done
    success "Nginx, Certbot и fail2ban проверены."
}

setup_firewall() {
    info "Настройка UFW..."
    ufw allow 22/tcp
    ufw allow 80/tcp
    ufw allow 443/tcp
    ufw allow 2222/tcp
    ufw --force enable
    success "Фаервол настроен."
}

setup_fail2ban() {
    info "Настройка fail2ban для SSH..."
    cat > /etc/fail2ban/jail.local <<EOF
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 7200
EOF
    systemctl enable fail2ban
    systemctl restart fail2ban
    success "fail2ban настроен."
}

validate_domain() {
    local domain=$1
    if [[ ! "$domain" =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]{0,61}[a-zA-Z0-9]?\.[a-zA-Z]{2,}$ ]]; then
        return 1
    fi
    return 0
}

validate_email() {
    local email=$1
    if [[ ! "$email" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
        return 1
    fi
    return 0
}

validate_username() {
    local username=$1
    if [[ ! "$username" =~ ^[a-zA-Z][a-zA-Z0-9_-]{2,30}$ ]]; then
        return 1
    fi
    return 0
}

get_user_data_interactive() {
    echo
    echo "==============================================="
    echo "  НАСТРОЙКА GITEA - ВВОД ПАРАМЕТРОВ"
    echo "==============================================="
    echo

    # Ввод домена
    while true; do
        echo -n "Введите доменное имя для Gitea (например: git.example.com): "
        read GITEA_DOMAIN
        if validate_domain "$GITEA_DOMAIN"; then
            break
        else
            error "Некорректный формат домена. Попробуйте снова."
        fi
    done

    # Ввод email
    while true; do
        echo -n "Введите email для Let's Encrypt: "
        read LETSENCRYPT_EMAIL
        if validate_email "$LETSENCRYPT_EMAIL"; then
            break
        else
            error "Некорректный формат email. Попробуйте снова."
        fi
    done

    # Ввод имени администратора
    while true; do
        echo -n "Введите имя администратора Gitea (3-30 символов, начинается с буквы): "
        read GITEA_ADMIN_USER
        if validate_username "$GITEA_ADMIN_USER"; then
            break
        else
            error "Некорректное имя пользователя. Должно начинаться с буквы и содержать 3-30 символов."
        fi
    done

    # Ввод пароля для системного пользователя
    while true; do
        echo -n "Введите пароль для системного пользователя gitea (минимум 8 символов): "
        read -s GITEA_USER_PASSWORD
        echo
        if [ ${#GITEA_USER_PASSWORD} -ge 8 ]; then
            echo -n "Повторите пароль: "
            read -s GITEA_USER_PASSWORD_CONFIRM
            echo
            if [ "$GITEA_USER_PASSWORD" = "$GITEA_USER_PASSWORD_CONFIRM" ]; then
                break
            else
                error "Пароли не совпадают. Попробуйте снова."
            fi
        else
            error "Пароль должен содержать минимум 8 символов."
        fi
    done
}

get_user_data_auto() {
    # Автоматический режим - генерация случайного пароля
    GITEA_USER_PASSWORD=$(openssl rand -base64 16)
    info "Автоматически сгенерирован пароль для пользователя gitea"
}

get_user_data() {
    if [ "$AUTO_INSTALL" = true ]; then
        # Проверяем, что все необходимые параметры указаны
        if [ -z "$GITEA_DOMAIN" ] || [ -z "$LETSENCRYPT_EMAIL" ] || [ -z "$GITEA_ADMIN_USER" ]; then
            error "Для автоматической установки требуются параметры: --domain, --email, --admin-user"
            echo "Пример: $0 --auto --domain git.example.com --email admin@example.com --admin-user admin"
            exit 1
        fi
        
        # Валидация параметров
        if ! validate_domain "$GITEA_DOMAIN"; then
            error "Некорректный формат домена: $GITEA_DOMAIN"
            exit 1
        fi
        
        if ! validate_email "$LETSENCRYPT_EMAIL"; then
            error "Некорректный формат email: $LETSENCRYPT_EMAIL"
            exit 1
        fi
        
        if ! validate_username "$GITEA_ADMIN_USER"; then
            error "Некорректное имя пользователя: $GITEA_ADMIN_USER"
            exit 1
        fi
        
        get_user_data_auto
    else
        get_user_data_interactive
    fi

    # Проверка DNS
    if ! nslookup "$GITEA_DOMAIN" > /dev/null 2>&1; then
        warning "Домен $GITEA_DOMAIN не резолвится. Убедитесь, что DNS настроен правильно."
        if [ "$AUTO_INSTALL" = false ]; then
            echo -n "Продолжить установку? (y/N): "
            read CONTINUE
            if [[ ! "$CONTINUE" =~ ^[Yy]$ ]]; then
                info "Установка отменена пользователем."
                exit 1
            fi
        else
            warning "Продолжаем установку в автоматическом режиме..."
        fi
    fi

    # Генерация паролей и ключей
    GITEA_ADMIN_PASSWORD=$(openssl rand -base64 12)
    DB_PASSWORD=$(openssl rand -base64 16)
    GITEA_SECRET_KEY=$(openssl rand -hex 32)
    GITEA_INTERNAL_TOKEN=$(openssl rand -hex 32)
    GITEA_JWT_SECRET=$(openssl rand -hex 32)

    mkdir -p /opt/gitea
    cat > /opt/gitea/.env <<EOF
GITEA_ADMIN_PASSWORD=${GITEA_ADMIN_PASSWORD}
DB_PASSWORD=${DB_PASSWORD}
GITEA_SECRET_KEY=${GITEA_SECRET_KEY}
GITEA_INTERNAL_TOKEN=${GITEA_INTERNAL_TOKEN}
GITEA_JWT_SECRET=${GITEA_JWT_SECRET}
EOF
    chmod 600 /opt/gitea/.env
    
    success "Конфигурация сохранена в /opt/gitea/.env"
}

create_gitea_user() {
    info "Создание пользователя gitea..."
    if ! id gitea &>/dev/null; then
        adduser --system --group --shell /bin/bash --home /opt/gitea gitea
    fi
    
    # Безопасная установка пароля
    echo "gitea:${GITEA_USER_PASSWORD}" | chpasswd
    
    # Сохраняем пароль в файл для администратора
    echo "SYSTEM_USER_PASSWORD=${GITEA_USER_PASSWORD}" >> /opt/gitea/.env
    unset GITEA_USER_PASSWORD GITEA_USER_PASSWORD_CONFIRM
    
    usermod -aG docker gitea
    success "Пользователь gitea готов."
}

create_docker_compose() {
    info "Создание конфигурации Docker Compose..."
    GITEA_UID=$(id -u gitea)
    GITEA_GID=$(id -g gitea)
    cat > /opt/gitea/docker-compose.yml <<EOF
version: "3.8"
services:
  gitea:
    image: gitea/gitea:latest
    container_name: gitea
    restart: always
    environment:
      - USER_UID=${GITEA_UID}
      - USER_GID=${GITEA_GID}
      - GITEA__database__DB_TYPE=postgres
      - GITEA__database__HOST=postgres:5432
      - GITEA__database__NAME=gitea
      - GITEA__database__USER=gitea
      - GITEA__database__PASSWD=\${DB_PASSWORD}
      - GITEA__server__DOMAIN=${GITEA_DOMAIN}
      - GITEA__server__ROOT_URL=https://${GITEA_DOMAIN}
      - GITEA__server__SSH_PORT=2222
      - GITEA__security__INSTALL_LOCK=true
      - GITEA__security__SECRET_KEY=\${GITEA_SECRET_KEY}
      - GITEA__security__INTERNAL_TOKEN=\${GITEA_INTERNAL_TOKEN}
      - GITEA__security__JWT_SECRET=\${GITEA_JWT_SECRET}
      - GITEA__service__DISABLE_REGISTRATION=true
    ports:
      - "127.0.0.1:3000:3000"
      - "2222:2222"
    volumes:
      - ./gitea-data:/data
    depends_on:
      - postgres
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3000"]
      interval: 30s
      timeout: 10s
      retries: 3

  postgres:
    image: postgres:14
    container_name: gitea-db
    restart: always
    environment:
      - POSTGRES_USER=gitea
      - POSTGRES_PASSWORD=\${DB_PASSWORD}
      - POSTGRES_DB=gitea
    volumes:
      - ./postgres:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U gitea"]
      interval: 30s
      timeout: 5s
      retries: 3
EOF
    
    # Настройка логирования Docker
    mkdir -p /etc/docker
    cat > /etc/docker/daemon.json <<EOF
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF
    systemctl restart docker
    
    chown -R gitea:gitea /opt/gitea
    success "docker-compose.yml создан."
}

setup_nginx_and_ssl() {
    info "Настройка Nginx и SSL..."
    
    # Временная конфигурация для получения сертификата
    cat > /etc/nginx/sites-available/${GITEA_DOMAIN}.conf <<EOF
server {
    listen 80;
    server_name ${GITEA_DOMAIN};
    location /.well-known/acme-challenge/ { 
        root /var/www/html; 
    }
    location / { 
        return 301 https://\$host\$request_uri; 
    }
}
EOF

    ln -sf /etc/nginx/sites-available/${GITEA_DOMAIN}.conf /etc/nginx/sites-enabled/
    rm -f /etc/nginx/sites-enabled/default
    
    if ! nginx -t; then
        error "Ошибка конфигурации Nginx"
        exit 1
    fi
    
    systemctl restart nginx

    # Получение SSL сертификата
    info "Получение SSL сертификата для домена ${GITEA_DOMAIN}..."
    if ! certbot --nginx -d ${GITEA_DOMAIN} --non-interactive --agree-tos -m ${LETSENCRYPT_EMAIL}; then
        error "Не удалось получить сертификат SSL"
        exit 1
    fi

    # Полная конфигурация с проксированием
    cat > /etc/nginx/sites-available/${GITEA_DOMAIN}.conf <<EOF
server {
    listen 80;
    server_name ${GITEA_DOMAIN};
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name ${GITEA_DOMAIN};

    ssl_certificate /etc/letsencrypt/live/${GITEA_DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${GITEA_DOMAIN}/privkey.pem;
    
    # Современные SSL настройки
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-CHACHA20-POLY1305:ECDHE-RSA-AES128-SHA256;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;
    ssl_stapling on;
    ssl_stapling_verify on;

    # Security headers
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Content-Type-Options nosniff;
    add_header X-Frame-Options DENY;
    add_header X-XSS-Protection "1; mode=block";

    client_max_body_size 512M;
    client_body_timeout 60s;
    client_header_timeout 60s;

    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_buffering off;
        proxy_request_buffering off;
        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;
    }
}
EOF

    if ! nginx -t; then
        error "Ошибка финальной конфигурации Nginx"
        exit 1
    fi
    
    systemctl reload nginx
    success "Nginx и SSL настроены."
}

start_gitea() {
    info "Запуск контейнеров Gitea и PostgreSQL..."
    
    cd /opt/gitea
    if ! sudo -u gitea -H bash -c "docker compose --env-file .env up -d"; then
        error "Не удалось запустить контейнеры"
        exit 1
    fi
    
    # Проверка статуса контейнеров
    sleep 10
    if ! docker ps | grep -q "gitea.*Up"; then
        error "Контейнер Gitea не запустился"
        docker logs gitea
        exit 1
    fi
    
    if ! docker ps | grep -q "gitea-db.*Up"; then
        error "Контейнер PostgreSQL не запустился"
        docker logs gitea-db
        exit 1
    fi
    
    wait_for_gitea
    create_admin_user
}

wait_for_gitea() {
    info "Проверка доступности Gitea на порту 3000..."
    for i in {1..60}; do
        if curl -s http://localhost:3000 > /dev/null 2>&1; then
            success "Gitea доступна на порту 3000."
            return
        fi
        echo -n "."
        sleep 2
    done
    echo
    error "Gitea не отвечает на порту 3000. Проверьте 'docker logs gitea'."
    exit 1
}

create_admin_user() {
    info "Создание администратора Gitea..."
    sleep 5
    
    # Создание администратора через Gitea CLI
    docker exec -u git gitea gitea admin user create \
        --username "${GITEA_ADMIN_USER}" \
        --password "${GITEA_ADMIN_PASSWORD}" \
        --email "${LETSENCRYPT_EMAIL}" \
        --admin \
        --must-change-password=false 2>/dev/null || {
        warning "Администратор уже существует или будет создан при первом входе"
    }
}

final_instructions() {
    echo
    echo "=================================================="
    success "Установка Gitea завершена!"
    echo "=================================================="
    echo
    echo "🌐 Адрес: https://${GITEA_DOMAIN}"
    echo "👤 Логин администратора: ${GITEA_ADMIN_USER}"
    echo "🔐 Пароль администратора: ${GITEA_ADMIN_PASSWORD}"
    echo "📧 Email: ${LETSENCRYPT_EMAIL}"
    echo "🔌 SSH порт: 2222"
    echo
    echo "⚠️  ВАЖНО: Сохраните пароль администратора!"
    echo "⚠️  ВАЖНО: Все пароли сохранены в /opt/gitea/.env"
    echo
    echo "Полезные команды:"
    echo "• Просмотр логов: docker logs gitea"
    echo "• Перезапуск: cd /opt/gitea && docker compose restart"
    echo "• Обновление: cd /opt/gitea && docker compose pull && docker compose up -d"
    echo "• Статус: docker ps | grep gitea"
    echo
}

show_menu() {
    echo
    echo "==============================================="
    echo "         УСТАНОВЩИК GITEA"
    echo "==============================================="
    echo
    echo "Выберите действие:"
    echo "1) Установить Gitea"
    echo "2) Удалить Gitea"
    echo "3) Показать статус"
    echo "4) Выйти"
    echo
    echo -n "Ваш выбор (1-4): "
    read CHOICE

    case $CHOICE in
        1) main_install ;;
        2) uninstall_gitea ;;
        3) show_status ;;
        4) 
            echo "Выход..."
            exit 0 
            ;;
        *) 
            error "Неверный выбор. Попробуйте снова."
            show_menu
            ;;
    esac
}

show_status() {
    echo
    info "Статус сервисов Gitea:"
    echo
    
    if [ -d "/opt/gitea" ]; then
        cd /opt/gitea
        echo "Docker контейнеры:"
        docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "(gitea|postgres)" || echo "Контейнеры не запущены"
        echo
        
        if [ -f ".env" ]; then
            echo "✅ Конфигурация найдена"
            if docker ps | grep -q "gitea.*Up"; then
                echo "✅ Gitea запущена"
                DOMAIN=$(docker exec gitea env 2>/dev/null | grep GITEA__server__DOMAIN | cut -d= -f2 || echo "unknown")
                echo "🌐 URL: https://${DOMAIN}"
            else
                echo "❌ Gitea не запущена"
            fi
        else
            echo "❌ Конфигурация не найдена"
        fi
    else
        echo "❌ Gitea не установлена"
    fi
    
    echo
    if [ "$AUTO_INSTALL" = false ]; then
        echo -n "Нажмите Enter для продолжения..."
        read
        show_menu
    fi
}

uninstall_gitea() {
    echo
    warning "Удаление Gitea и всех связанных данных..."
    
    if [ "$AUTO_INSTALL" = false ]; then
        echo -n "Вы уверены, что хотите удалить Gitea и все его данные? (y/N): "
        read CONFIRM
        if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
            info "Удаление отменено."
            show_menu
            return
        fi
    fi
    
    # Остановка и удаление контейнеров
    info "Остановка контейнеров..."
    docker stop gitea gitea-db 2>/dev/null || true
    docker rm gitea gitea-db 2>/dev/null || true
    
    # Удаление данных и конфигурации
    info "Удаление данных..."
    rm -rf /opt/gitea
    
    # Получаем домен из конфигурации nginx
    DOMAIN_CONF=$(ls /etc/nginx/sites-enabled/*.conf 2>/dev/null | head -1)
    if [ -n "$DOMAIN_CONF" ]; then
        DOMAIN=$(basename "$DOMAIN_CONF" .conf)
        
        # Удаление конфигурации Nginx
        rm -f /etc/nginx/sites-enabled/${DOMAIN}.conf /etc/nginx/sites-available/${DOMAIN}.conf
        systemctl reload nginx 2>/dev/null || true
        
        # Удаление SSL сертификатов
        certbot delete --cert-name ${DOMAIN} --non-interactive 2>/dev/null || true
    fi
    
    # Удаление пользователя
    userdel -r gitea 2>/dev/null || true
    
    success "Gitea полностью удалена."
    
    if [ "$AUTO_INSTALL" = false ]; then
        echo -n "Нажмите Enter для продолжения..."
        read
        show_menu
    fi
}

main_install() {
    echo
    info "Начинаем установку Gitea..."
    prepare_system
    setup_firewall
    setup_fail2ban
    get_user_data
    create_gitea_user
    create_docker_compose
    setup_nginx_and_ssl
    start_gitea
    final_instructions
}

# Главная логика
if [ "$AUTO_INSTALL" = true ]; then
    info "Запуск автоматической установки..."
    main_install
else
    show_menu
fi
