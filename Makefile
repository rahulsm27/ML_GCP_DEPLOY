# Make all targets .PHONY
.PHONY: $(shell sed -n -e '/^$$/ { n ; /^[^ .\#][^ ]*:/ { s/:.*$$// ; p ; } ; }' $(MAKEFILE_LIST))

#include .envs/.gcp
#include .envs/.tracking-server

include .env
export 

SHELL := /usr/bin/env bash
HOSTNAME := $(shell hostname)

ifeq (, $(shell which docker-compose))
	DOCKER_COMPOSE_COMMAND = sudo docker compose
else
	DOCKER_COMPOSE_COMMAND = sudo docker-compose
endif

include .envs/.gcp
include .envs/.tracking-server
export

lock-dependencies: BUILD_POETRY_LOCK = /root/poetry.lock.build 

# Returns true if the stem is a non-empty environment variable, or else raises an error.
guard-%:
	@#$(or ${$*}, $(error $* is not set))

## Deploy MLFlow using GCP Cloud Run
deploy: push
	./scripts/create-server.sh

## Run ssh tunnel for MLFlow
mlflow-tunnel:
	gcloud compute ssh "$${VM_NAME}" --zone "$${ZONE}" --tunnel-through-iap -- -N -L "$${MLFLOW_PORT}:localhost:$${MLFLOW_PORT}"

## Build docker containers with docker-compose
build:
	$(DOCKER_COMPOSE_COMMAND) build 
	
## Build docker containers with docker-compose
_build-for-dependencies:
	rm -f *lock
	$(DOCKER_COMPOSE_COMMAND) build

## Push docker image to GCP Container Registery. Requires IMAGE_TAG to be specified.
# push: guard-IMAGE_TAG build
# 	@gcloud auth configure-docker eu.gcr.io --quiet
# 	@docker tag  "${DOCKER_IMAGE_NAME}:latest" "$${GCP_DOCKER_REGISTERY_URL}:$${IMAGE_TAG}"
# 	@docker push "$${GCP_DOCKER_REGISTERY_URL}:$${IMAGE_TAG}"

push: guard-IMAGE_TAG build
	@gcloud auth configure-docker eu.gcr.io --quiet
	@docker tag  "${DOCKER_IMAGE_NAME}:latest" "$${GCP_DOCKER_REGISTERY_URL}:$${IMAGE_TAG}"
	@docker push "$${GCP_DOCKER_REGISTERY_URL}:$${IMAGE_TAG}"


## docker-compose up
up:
	$(DOCKER_COMPOSE_COMMAND) up

## docker-compose up -d
upd:
	$(DOCKER_COMPOSE_COMMAND) up -d

## docker-compose down
down:
	$(DOCKER_COMPOSE_COMMAND) down

## docker exec -it mlflow-tracking-server bash
exec-in: upd
	docker exec -it mlflow-tracking-server bash

## Lock dependencies with pipenv
lock-dependencies: _build-for-dependencies
	$(DOCKER_COMPOSE_COMMAND) run --entrypoint "" --rm app bash -c "if [ -e $(BUILD_POETRY_LOCK) ]; then cp $(BUILD_POETRY_LOCK) ./poetry.lock; else poetry lock; fi"

## Delete all compiled Python files
clean:
	find . -type f -name "*.py[co]" -delete
	find . -type d -name "__pycache__" -delete


.DEFAULT_GOAL := help

# Inspired by <http://marmelab.com/blog/2016/02/29/auto-documented-makefile.html>
# sed script explained:
# /^##/:
# 	* save line in hold space
# 	* purge line
# 	* Loop:
# 		* append newline + line to hold space
# 		* go to next line
# 		* if line starts with doc comment, strip comment character off and loop
# 	* remove target prerequisites
# 	* append hold space (+ newline) to line
# 	* replace newline plus comments by `---`
# 	* print line
# Separate expressions are necessary because labels cannot be delimited by
# semicolon; see <http://stackoverflow.com/a/11799865/1968>
.PHONY: help
help:
	@echo "$$(tput bold)Available rules:$$(tput sgr0)"
	@echo
	@sed -n -e "/^## / { \
		h; \
		s/.*//; \
		:doc" \
		-e "H; \
		n; \
		s/^## //; \
		t doc" \
		-e "s/:.*//; \
		G; \
		s/\\n## /---/; \
		s/\\n/ /g; \
		p; \
	}" ${MAKEFILE_LIST} \
	| LC_ALL='C' sort --ignore-case \
	| awk -F '---' \
		-v ncol=$$(tput cols) \
		-v indent=23 \
		-v col_on="$$(tput setaf 6)" \
		-v col_off="$$(tput sgr0)" \
	'{ \
		printf "%s%*s%s ", col_on, -indent, $$1, col_off; \
		n = split($$2, words, " "); \
		line_length = ncol - indent; \
		for (i = 1; i <= n; i++) { \
			line_length -= length(words[i]) + 1; \
			if (line_length <= 0) { \
				line_length = ncol - indent - length(words[i]) - 1; \
				printf "\n%*s ", -indent, " "; \
			} \
			printf "%s ", words[i]; \
		} \
		printf "\n"; \
	}' \
	| more $(shell test $(shell uname) = Darwin && echo '--no-init --raw-control-chars')
