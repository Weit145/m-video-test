up:
	docker compose up --build -d

delete:
	docker compose down -v

down:
	docker compose down

logs:
	docker compose logs -f