# 🚀 Gitea Auto Installer

Автоматический установщик Gitea с Docker, PostgreSQL, Nginx и SSL сертификатами.

![Gitea](https://img.shields.io/badge/Gitea-34495E?style=for-the-badge&logo=gitea&logoColor=5D9425)
![Docker](https://img.shields.io/badge/Docker-2CA5E0?style=for-the-badge&logo=docker&logoColor=white)
![PostgreSQL](https://img.shields.io/badge/PostgreSQL-316192?style=for-the-badge&logo=postgresql&logoColor=white)
![Nginx](https://img.shields.io/badge/Nginx-009639?style=for-the-badge&logo=nginx&logoColor=white)

## ✨ Особенности

- 🐳 **Docker Compose** - изолированная среда выполнения
- 🗄️ **PostgreSQL** - надежная база данных
- 🌐 **Nginx** - реверс-прокси с SSL
- 🔒 **Let's Encrypt** - автоматические SSL сертификаты
- 🛡️ **Безопасность** - fail2ban, firewall, современные SSL настройки
- 📱 **Интерактивный интерфейс** - простая настройка через меню
- ⚡ **Одна команда** - полная автоматизация установки

## 🚀 Быстрая установка

**Запустите одной командой:**

```bash
curl -fsSL https://raw.githubusercontent.com/DeadFlamingo/AutoGiteaInstaller/refs/heads/main/gitea-nginx-postgres-docker-ssl-installer.sh | sudo bash
```

## 📋 Требования

### Система
- Ubuntu 20.04+ или Debian 11+
- Root доступ или sudo права
- Минимум 2GB RAM
- Минимум 20GB свободного места

### Сеть
- Статический IP адрес
- Домен, направленный на ваш сервер
- Открытые порты: 80, 443, 2222 (SSH для Git)

## 🔧 Что устанавливается

| Компонент | Версия | Порт | Описание |
|-----------|--------|------|----------|
| **Gitea** | latest | 3000→443 | Git сервер |
| **PostgreSQL** | 14 | 5432 | База данных |
| **Nginx** | latest | 80,443 | Веб-сервер + SSL |
| **Docker** | latest | - | Контейнеризация |
| **fail2ban** | latest | - | Защита от брутфорса |

## 🛠️ Процесс установки

1. **Подготовка системы** - установка Docker, Nginx, сертификатов
2. **Настройка безопасности** - файрвол, fail2ban
3. **Сбор данных** - домен, email, учетные записи
4. **Создание конфигурации** - Docker Compose, Nginx
5. **Получение SSL** - автоматически через Let's Encrypt
6. **Запуск сервисов** - Gitea + PostgreSQL
7. **Финальная настройка** - создание администратора

## 📝 Пример использования

### Перед установкой
1. Настройте DNS запись для вашего домена:
   ```
   git.example.com → ВАШ_IP_АДРЕС
   ```

2. Убедитесь, что порты доступны:
   ```bash
   # Проверка портов
   sudo netstat -tlnp | grep -E ':80|:443|:2222'
   ```

### Запуск установки
```bash
# Обновите систему
sudo apt update && sudo apt upgrade -y

# Запустите установщик
curl -fsSL https://raw.githubusercontent.com/DeadFlamingo/AutoGiteaInstaller/refs/heads/main/gitea-nginx-postgres-docker-ssl-installer.sh | sudo bash
```

### После установки
Скрипт покажет:
```
🌐 Адрес: https://git.example.com
👤 Логин: admin
🔐 Пароль: сгенерированный_пароль
📧 Email: ваш@email.com
🔌 SSH порт: 2222
```

## 🎯 Управление

### Основные команды
```bash
# Переход в директорию Gitea
cd /opt/gitea

# Просмотр статуса контейнеров
docker compose ps

# Просмотр логов
docker logs gitea
docker logs gitea-db

# Перезапуск сервисов
docker compose restart

# Остановка сервисов
docker compose stop

# Обновление Gitea
docker compose pull
docker compose up -d
```

### Повторный запуск меню
```bash
# Если нужно управлять установкой
sudo bash /opt/gitea/gitea_installer_enhanced.sh
```

## 🔒 Безопасность

### Автоматически настраивается:
- ✅ UFW файрвол (порты 22, 80, 443, 2222)
- ✅ fail2ban для защиты SSH
- ✅ SSL сертификаты Let's Encrypt
- ✅ Современные SSL/TLS настройки
- ✅ Security headers в Nginx
- ✅ Отключена регистрация новых пользователей

### Рекомендации:
- 🔑 Смените пароль администратора после первого входа
- 🔄 Настройте автоматические обновления
- 💾 Регулярно создавайте резервные копии
- 🔍 Мониторьте логи безопасности

## 🐛 Устранение проблем

### Gitea не запускается
```bash
# Проверьте логи
docker logs gitea

# Проверьте порты
sudo netstat -tlnp | grep 3000

# Перезапустите контейнеры
cd /opt/gitea && docker compose restart
```

### Проблемы с SSL
```bash
# Проверьте сертификат
sudo certbot certificates

# Обновите сертификат
sudo certbot renew

# Проверьте конфигурацию Nginx
sudo nginx -t
```

### Проблемы с доступом
```bash
# Проверьте DNS
nslookup ваш_домен.com

# Проверьте файрвол
sudo ufw status

# Проверьте Nginx
sudo systemctl status nginx
```

## 📁 Структура файлов

```
/opt/gitea/
├── docker-compose.yml    # Конфигурация Docker
├── .env                  # Переменные окружения (пароли)
├── gitea-data/          # Данные Gitea
└── postgres/            # База данных PostgreSQL

/etc/nginx/sites-available/
└── ваш_домен.conf       # Конфигурация Nginx

/var/log/
└── gitea-installer.log  # Логи установки
```

## 🗑️ Удаление

Для полного удаления Gitea запустите скрипт и выберите пункт "Удалить Gitea":

```bash
curl -fsSL https://raw.githubusercontent.com/DeadFlamingo/AutoGiteaInstaller/refs/heads/main/gitea-nginx-postgres-docker-ssl-installer.sh | sudo bash
```

Или вручную:
```bash
# Остановка и удаление контейнеров
docker stop gitea gitea-db
docker rm gitea gitea-db

# Удаление данных
sudo rm -rf /opt/gitea

# Удаление конфигурации Nginx
sudo rm /etc/nginx/sites-*/ваш_домен.conf
sudo systemctl reload nginx

# Удаление SSL сертификата
sudo certbot delete --cert-name ваш_домен.com
```

## 📞 Поддержка

- 📖 [Официальная документация Gitea](https://docs.gitea.io/)
- 🐛 [Сообщить о проблеме](https://github.com/ВАШЕ_ИМЯ/gitea-installer/issues)
- 💡 [Предложить улучшение](https://github.com/ВАШЕ_ИМЯ/gitea-installer/discussions)

## 📄 Лицензия

MIT License - используйте свободно!

---

⭐ **Если скрипт был полезен, поставьте звездочку!**

**Сделано с ❤️ для разработчиков**
