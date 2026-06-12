.PHONY: dev migrate test test-e2e seed simulate lint fmt worker evals docker-build onboard

dev:
	uvicorn src.main:app --reload --host 0.0.0.0 --port 8000

worker:
	python -m src.core.worker

migrate:
	alembic upgrade head

migrate-create:
	alembic revision --autogenerate -m "$(msg)"

test:
	pytest tests/ -v --tb=short

test-cov:
	pytest tests/ -v --tb=short --cov=src --cov-report=term-missing

test-e2e:
	pytest tests/test_e2e.py -v --tb=short

seed:
	python scripts/seed_client.py

simulate:
	python scripts/simulate_conversation.py

lint:
	ruff check src/ tests/

fmt:
	ruff format src/ tests/

docker-up:
	docker-compose up -d

docker-down:
	docker-compose down

docker-logs:
	docker-compose logs -f

onboard:
	python scripts/onboard_client.py

evals:
	python -m src.evals.runner --dataset src/evals/datasets/qualification_v1.json

docker-build:
	docker build -t leadengine .

reset-db:
	docker-compose down -v
	docker-compose up -d postgres redis
	sleep 3
	alembic upgrade head
