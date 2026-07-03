# M-Video Test

Проект реализует систему из трех сервисов:

- `m-video-test-web-api` - асинхронный Web API сервис на FastAPI.
- `m-video-test-client` - клиентский сервис, который генерирует лог-строки и отправляет их в Web API.
- `m-video-test-background-processing` - сервис фоновой обработки, который периодически выгружает данные из Web API в файл.

Все сервисы запускаются через Docker Compose.

## Архитектура

Система состоит из следующих контейнеров:

- `db` - PostgreSQL 16, хранит распарсенные записи логов.
- `app` - FastAPI приложение. При старте запускает Alembic migrations, затем поднимает HTTP API.
- `client` - многопоточный генератор логов. Отправляет POST-запросы в `app` и пишет отправленные строки в файл.
- `background-processing` - периодический воркер. Выполняет GET-запросы к `app` и сохраняет результат в общий файл Docker Volume.

Поток данных:

1. `client` генерирует строку вида `192.168.1.1 GET /api/users 200`.
2. `app` принимает строку через `POST /api/data`, валидирует, парсит и сохраняет в PostgreSQL.
3. `background-processing` по таймеру запрашивает `GET /api/data` и дописывает результат в файл.

## Запуск

Если репозиторий клонируется с submodules:

```bash
git clone --recurse-submodules <repository-url>
cd m-video-test
```

Если репозиторий уже склонирован без submodules:

```bash
git submodule update --init --recursive
```

Запуск всей системы:

```bash
docker compose up --build -d
```

API будет доступен на:

```text
http://localhost:8080
```

Остановка:

```bash
docker compose down
```

Остановка с удалением volumes:

```bash
docker compose down -v
```

Также доступны команды из `Makefile`:

```bash
make up
make up-all
make logs
make down
make delete
```

`make up-all` запускает несколько экземпляров фонового обработчика.

## Технологии

- Python 3.12
- FastAPI
- Pydantic v2
- SQLAlchemy 2 async
- asyncpg
- PostgreSQL 16
- Alembic
- Docker
- Docker Compose
- requests
- threading

## Переменные окружения

Для запуска через Docker Compose рабочие значения уже заданы в `docker-compose.yml`.
Файлы `.env.example` в сервисах можно использовать как шаблон для локального запуска сервисов без Compose.

### Web API

Значения в `docker-compose.yml` для сервиса `app`.

| Переменная | Значение по умолчанию | Описание |
| --- | --- | --- |
| `DATABASE_URL` | `postgresql+asyncpg://postgres:postgres@db:5432/postgres` | DSN для подключения к PostgreSQL. |
| `LOG_LEVEL` | `INFO` | Уровень логирования приложения. |

### Client

Значения в `docker-compose.yml` для сервиса `client`.

| Переменная | Значение по умолчанию | Описание |
| --- | --- | --- |
| `URL` | `http://app:8000/api/data` | URL Web API для отправки логов. |
| `FILE_PATH` | `/app/logs/client.log` | Файл для записи отправленных сообщений. |
| `N` | `5` | Количество потоков отправки. |
| `M` | `1000` | Максимальная случайная задержка между запросами в миллисекундах. |
| `LOG_LEVEL` | `INFO` | Уровень логирования. |

### Background Processing

Значения в `docker-compose.yml` для сервиса `background-processing`.

| Переменная | Значение по умолчанию | Описание |
| --- | --- | --- |
| `URL` | `http://app:8000/api/data` | URL Web API для чтения данных. |
| `FILE_PATH` | `/app/data/background-data.txt` | Общий файл для сохранения результатов. |
| `TIMER` | `10` | Интервал между запросами в секундах. |
| `LOG_LEVEL` | `INFO` | Уровень логирования. |

### PostgreSQL

Значения заданы в `docker-compose.yml`:

| Переменная | Значение |
| --- | --- |
| `POSTGRES_USER` | `postgres` |
| `POSTGRES_PASSWORD` | `postgres` |
| `POSTGRES_DB` | `postgres` |

## Архитектурные решения и допущения

- Web API реализован асинхронно: FastAPI, SQLAlchemy async и asyncpg.
- Строка лога должна состоять ровно из четырех частей: IP, HTTP method, URI и HTTP status code.
- URI считается валидным, если это относительный путь, который начинается с `/`, не содержит пробелов, scheme, netloc и fragment.
- HTTP status code ограничен диапазоном `100..599`.
- Для `GET /api/data` используется пагинация через `page` и `page_size`.
- Для сортировки записей по времени создания добавлен индекс `idx_data_created_at`.
- Для статистики используются агрегирующие SQL-запросы по `method` и `status_code`.
- Фоновый сервис пишет результат в JSON Lines формат: одна JSON-запись на строку.
- Для совместной записи несколькими экземплярами фонового сервиса используется файловая блокировка `fcntl.flock`.
- Фоновые и клиентские файлы сохраняются в Docker Volumes: `background_data` и `client_logs`.
- При старте Web API автоматически применяет Alembic migrations.

## API

### Healthcheck

```bash
curl http://localhost:8080/_info
```

### Создать запись

```bash
curl -X POST http://localhost:8080/api/data \
  -H "Content-Type: application/json" \
  -d '{"log":"192.168.1.1 GET /api/users 200"}'
```

Успешный ответ:

```text
HTTP/1.1 201 Created
```

### Получить записи

```bash
curl "http://localhost:8080/api/data?page=1&page_size=20"
```

Пример ответа:

```json
[
  {
    "id": "b7c6f1e5-0b5f-4f3d-a3f4-8d9d4c62e11a",
    "created": "2026-07-03T12:00:00Z",
    "log": {
      "ip": "192.168.1.1",
      "method": "GET",
      "uri": "/api/users",
      "status_code": 200
    }
  }
]
```

Параметры:

| Параметр | Описание |
| --- | --- |
| `page` | Номер страницы, начиная с `1`. |
| `page_size` | Размер страницы, от `1` до `100`. |

### Получить статистику

```bash
curl http://localhost:8080/api/stats
```

Пример ответа:

```json
{
  "methods": {
    "GET": 5,
    "POST": 1,
  },
  "status_codes": {
    "200": 5,
    "201": 1
  }
}
```
