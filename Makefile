init:
	git submodule update --init --recursive

up:
	docker compose up --build -d

up-all:
	docker compose up --build -d --scale background-processing=3

delete:
	docker compose down -v

down:
	docker compose down

logs:
	docker compose logs -f

client:
	docker compose exec client cat /app/logs/client.log

background-processing:
	docker compose exec background-processing cat /app/data/background-data.txt
