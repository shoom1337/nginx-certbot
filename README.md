[![CI](https://github.com/shoom1337/nginx-certbot/actions/workflows/ci.yml/badge.svg?branch=master)](https://github.com/shoom1337/nginx-certbot/actions/workflows/ci.yml)

# nginx + Let's Encrypt SSL

Быстрое развёртывание HTTPS-сервера с автоматическими SSL-сертификатами от Let's Encrypt.

## Требования

- [Docker](https://docs.docker.com/get-docker/)
- [Docker Compose](https://docs.docker.com/compose/install/) (плагин, не legacy `docker-compose`)
- `curl`
- Домен, DNS которого резолвится на IP вашего сервера
- Порты **80** и **443** доступны снаружи (не закрыты файерволом)

## Быстрый старт

```bash
git clone https://github.com/shoom1337/nginx-certbot.git
cd nginx-certbot
bash setup.sh
```

Скрипт сам запросит у вас домен, email и все нужные параметры, сгенерирует конфиг и стартует сервер с SSL.

## Структура проекта

```
nginx-certbot/
├── setup.sh                          # Главный скрипт — точка входа
├── init-letsencrypt.sh               # Логика получения сертификата
├── docker-compose.yml                # nginx + certbot контейнеры
├── .env-example                      # Шаблон переменных окружения
├── .env                              # Конфиг (создаётся setup.sh, не в git)
├── data/
│   ├── nginx/conf.d/
│   │   └── app.conf-template         # Nginx конфиг (подстановка домена через envsubst)
│   └── certbot/                      # Сертификаты и TLS-параметры (создаётся в runtime)
└── sites/
    └── index.html                    # Контент сайта — кладите свои файлы сюда
```

## Как это работает

1. `setup.sh` собирает ввод и генерирует `.env`
2. `init-letsencrypt.sh` создаёт временный сертификат, стартует nginx, затем запрашивает реальный сертификат у Let's Encrypt через ACME webroot-валидацию
3. nginx перезагружается с реальным сертификатом
4. Контейнер `certbot` автоматически обновляет сертификат каждые 12 часов (проверка), nginx перезагружается каждые 6 часов чтобы подхватить обновлённый сертификат

## Параметры .env

| Переменная        | Описание                                                                 |
|-------------------|--------------------------------------------------------------------------|
| `DOMAIN_NAME`     | Ваш домен (например `example.com`)                                       |
| `CERTBOT_EMAIL`   | Email для уведомлений от Let's Encrypt (оставить пустым — без email)      |
| `CERTBOT_STAGING` | `1` для тестирования (staging-сертификат, не входит в rate-limit)         |

## Частые команды

```bash
# Посмотреть логи
docker compose logs -f

# Остановить сервер
docker compose down

# Перезапустить сервер
docker compose up -d

# Заново получить сертификат (например при смене домена)
docker compose down
rm -rf data/certbot
bash setup.sh
```

## Частые проблемы

| Проблема | Решение |
|----------|---------|
| `Connection refused` при валидации | Порт 80 закрыт файерволом или занят другим процессом |
| `too many requests` от Let's Encrypt | Превышен rate-limit. Пересапустите setup.sh и выберите staging-режим для тестирования |
| Сертификат не обновляется | Проверьте `docker compose logs certbot` |
| Nginx не стартует | Проверьте `docker compose logs nginx` — скорее всего проблема с конфигом или сертификатом |
