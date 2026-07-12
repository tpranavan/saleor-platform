.PHONY: help tunnel tunnel-stop tunnel-status setup-shared-env up-shared up-local up-neon migrate-neon down

COMPOSE_BOTO := -f docker-compose.yml -f docker-compose.boto-local.yml
COMPOSE_SHARED := docker compose $(COMPOSE_BOTO) -f docker-compose.shared-qa.yml
COMPOSE_LOCAL := docker compose $(COMPOSE_BOTO) -f docker-compose.local-db.yml --profile local-db
COMPOSE_NEON := docker compose $(COMPOSE_BOTO) -f docker-compose.neon-upstash.yml

help:
	@echo "saleor-platform (BOTO)"
	@echo "  Preferred QA data plane: Neon Postgres + Upstash Redis (dedicated, no shared VM)"
	@echo "  up-neon           Run Saleor against Neon + Upstash (preferred for BOTO)"
	@echo "  migrate-neon      Run Django migrate against Neon (via api container)"
	@echo "  up-local          Run Saleor with local Postgres + Valkey"
	@echo ""
	@echo "  Legacy / Feed Me shared VM (not for BOTO Cloud Run):"
	@echo "  setup-shared-env  Generate backend.env.shared-qa from credentials"
	@echo "  tunnel            Start SSH tunnel to shared QA Postgres + Redis"
	@echo "  tunnel-stop       Stop SSH tunnel"
	@echo "  tunnel-status     Check tunnel"
	@echo "  up-shared         Local API against shared VM db/redis (legacy)"
	@echo "  down              Stop all services"

setup-shared-env:
	@chmod +x scripts/setup-shared-qa-env.sh
	@./scripts/setup-shared-qa-env.sh

tunnel:
	@chmod +x scripts/shared-qa-tunnel.sh
	@./scripts/shared-qa-tunnel.sh start

tunnel-stop:
	@chmod +x scripts/shared-qa-tunnel.sh
	@./scripts/shared-qa-tunnel.sh stop

tunnel-status:
	@chmod +x scripts/shared-qa-tunnel.sh
	@./scripts/shared-qa-tunnel.sh status

up-shared: setup-shared-env
	@echo "WARNING: up-shared uses fortronx-qa-shared (Feed Me). Prefer 'make up-neon' for BOTO."
	@chmod +x scripts/shared-qa-tunnel.sh
	@./scripts/shared-qa-tunnel.sh start
	$(COMPOSE_SHARED) up -d api worker dashboard mailpit jaeger

up-local:
	$(COMPOSE_LOCAL) up -d

up-neon:
	@test -f backend.env.neon-upstash || { \
	  echo "Missing backend.env.neon-upstash — copy backend.env.neon-upstash.example and fill secrets"; \
	  exit 1; \
	}
	$(COMPOSE_NEON) up -d api worker dashboard mailpit jaeger

migrate-neon:
	@test -f backend.env.neon-upstash || { \
	  echo "Missing backend.env.neon-upstash — copy backend.env.neon-upstash.example and fill secrets"; \
	  exit 1; \
	}
	$(COMPOSE_NEON) run --rm --no-deps api python3 manage.py migrate

down:
	$(COMPOSE_NEON) down --remove-orphans 2>/dev/null || true
	$(COMPOSE_SHARED) down --remove-orphans 2>/dev/null || true
	$(COMPOSE_LOCAL) down --remove-orphans 2>/dev/null || true
