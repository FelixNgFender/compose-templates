#######################################################################
#                            Main targets                             #
#######################################################################

## Simple example tasks for NextCloud

help:     ## Show this help.
	@egrep -h '(\s##\s|^##\s)' $(MAKEFILE_LIST) | egrep -v '^--' | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[32m  %-35s\033[0m %s\n", $$1, $$2}'

build:   ## Build containers.
	@echo "${green}Create app${no_color}"
	docker compose build

up:   ## Start containers.
	@echo "${green}Start container${no_color}"
	docker compose up --detach

down:   ## Stop containers and discard them.
	@echo "${green}Stop container${no_color}"
	docker compose down

status: ## Show current status.
	@docker compose ps --all | \
		sed "s/\b\(exited\)\b/${orange}\U\1\E${no_color}/gi" | \
		sed "s/\b\(up\)\b/${green}\U\1\E${no_color}/gi" | \
		sed "s/\b\(healthy\)\b/${green}\U\1\E${no_color}/gi" | \
		sed "s/\b\(unhealthy\)\b/${orange}\U\1\E${no_color}/gi" | tee /tmp/status
	@(grep -qi "UP" /tmp/status && echo "${green}UP!${no_color}") || echo "${red}DOWN!${no_color}"

shell: ## Start shell as unprivileged user.
	@echo "${green}Start shell interactive console${no_color}"
	docker compose run -it --entrypoint=/bin/bash --user www-data --rm nextcloud

root: ## Start shell as root.
	@echo "${orange}Start shell interactive console${no_color}"
	docker compose run -it --entrypoint=/bin/bash --rm nextcloud

# Just an example with occ script
# https://docs.nextcloud.com/server/latest/admin_manual/configuration_server/occ_command.html
files_scan: ## Update nextcloud files DB
	@echo "${green}Scan files${no_color}"
	docker compose run --user www-data --rm nextcloud php occ files:scan --all

# make occ
# make occ OCC_PARAMS="config:list"
# make occ OCC_PARAMS="status --output=json_pretty"
occ: ## Run occ command, with OCC_PARAMS as params
	@echo "${green}Run occ with ${OCC_PARAMS}${no_color}"
	docker compose run --user www-data --rm nextcloud php occ ${OCC_PARAMS}

sql: up ## Starts Postgres console.
	@echo "${green}Start Postgres console${no_color}"
	docker compose exec db psql -U $(DB_USERNAME) $(DB_NAME)

update: down ## Update images
	@echo "${orange}Update images${no_color}"
	docker compose pull

sql_dump: down ## Dump whole DB as SQL.
	@echo "${green}Dump whole DB to SQL${no_color}"
	@{\
		set -e;\
		SQL_FILE=$$(date +"$(DB_VOLUME_NAME)_%Y%m%d_%H%M.sql") ;\
		docker compose up db --wait --detach ;\
		docker compose exec db pg_dumpall -U $(DB_USERNAME) --clean --if-exists --file /tmp/db.sql ;\
		docker compose cp db:/tmp/db.sql ./$${SQL_FILE} ;\
		gzip -f $${SQL_FILE} ;\
		docker compose down ;\
		echo "${green}  Done!${no_color}" ;\
		ls -lh $${SQL_FILE}.gz ;\
	}

sql_restore: down ## ⚠️ Restore whole DB from SQL.
	@echo "${green}Restore whole DB from SQL${no_color}"
	@{\
		set -e;\
		LAST_DUMP=$$(ls -Art $(DB_VOLUME_NAME)_20*.sql.gz | tail -n1) ;\
		ls -lh "$${LAST_DUMP}" ;\
		docker compose up db --wait --detach ;\
		docker compose cp "$${LAST_DUMP}" db:/tmp/db.sql.gz ;\
		docker compose exec db gunzip -f /tmp/db.sql.gz ;\
		echo "${green}Import SQL${no_color}" ;\
		docker compose exec db bash -c "psql -U $(DB_USERNAME) -d postgres -q < /tmp/db.sql" ;\
		echo "${green}Check DB${no_color}" ;\
		docker compose exec db psql -U $(DB_USERNAME) $(DB_NAME) -c '\dt' ;\
		docker compose down ;\
	}

logs: ## Show logs
	@echo "${green}Show logs${no_color}"
	docker compose logs --follow

#NOTE: This is a private target. It won't be listed in make help. It can still be called with make -- --check-var
--check-var: ## Check that BACKUP_VOLUMES is defined in env file
	@test -n "$(BACKUP_VOLUMES)" || (echo 'Please define BACKUP_VOLUMES environment variable' && false)

list: --check-var ## List content of DB volume.
	@{\
		set -e;\
		for VOLUME_NAME in $(BACKUP_VOLUMES); do\
			echo "  ${green}List content of '$${VOLUME_NAME}'${no_color}";\
			docker run --rm -i -v=$${VOLUME_NAME}:/tmp/myvolume busybox sh -c "cd /tmp/myvolume && tree ." ;\
		done;\
	}

volume_backup: --check-var ## Backup content of DB volume.
	@echo "${green}Backup volumes${no_color}"
	@{\
		set -e;\
		for VOLUME_NAME in $(BACKUP_VOLUMES); do\
			echo "  ${green}Backup '$${VOLUME_NAME}'${no_color}";\
			docker volume inspect $${VOLUME_NAME} && \
				docker run --rm -v=$${VOLUME_NAME}:/source:ro busybox tar -czC /source . > $${VOLUME_NAME}-volume.tar.gz && \
				echo "${green}  Done!${no_color}" && \
				ls -lh $${VOLUME_NAME}-volume.tar.gz;\
		done;\
	}

volume_restore: --check-var ## ⚠️ Restore content of DB volume.
	@echo "${green}Restore volumes${no_color}"
	@{\
		set -e;\
		for VOLUME_NAME in $(BACKUP_VOLUMES); do\
			echo "  ${green}Restore '$${VOLUME_NAME}'${no_color}";\
			tar -tzf $${VOLUME_NAME}-volume.tar.gz && \
				echo "${orange}Discard volume (if existing)${no_color}" && \
				docker compose down && \
				docker volume rm -f $${VOLUME_NAME} && \
				echo "${green}Create empty volume${no_color}" && \
				docker compose create && \
				echo "${green}Restore volume${no_color}" && \
				docker run --rm -i -v=$${VOLUME_NAME}:/target busybox tar -xzC /target < $${VOLUME_NAME}-volume.tar.gz ;\
		done;\
	}

backup: sql_dump volume_backup ## Backup DB, config and files (No docker image or container)

images_backup: ## Save images to tar.gz.
	@echo "${green}Backup images${no_color}"
	@{\
		set -e;\
		for img in $$(docker compose config --images); do\
			images="$${images} $${img}";\
		done;\
		for service in $$(docker compose config --services); do\
			services="$${services}-$${service}";\
		done;\
		echo "  ${green}Found images: ${no_color}$${images}";\
		echo "  ${green}Backup..${no_color}";\
		docker save $${images} | gzip > images$${services}.tar.gz;\
		ls -lh images$${services}.tar.gz;\
		echo "  ${green}Done!${no_color}";\
	}

images_restore: ## Restore images from tar.gz.
	@echo "${green}Restore images${no_color}"
	@{\
		set -e;\
		for service in $$(docker compose config --services); do\
			services="$${services}-$${service}";\
		done;\
		ls -lh images$${services}.tar.gz;\
		docker image load -i images$${services}.tar.gz;\
		echo "  ${green}Done!${no_color}";\
	}

# Maintenance tasks

portainer: ## Start Portainer container.
	@echo "${green}Start Portainer container${no_color}"
	@docker run -d -p 9443:9443 --name portainer -v /var/run/docker.sock:/var/run/docker.sock portainer/portainer-ce:latest || \
		echo "${orange}Already started!${no_color}" && \
		echo "${green}https://localhost:9443${no_color}"

portainer_down: ## Stop portainer container.
	@echo "${green}Stop Portainer container${no_color}"
	@(docker container inspect portainer > /dev/null 2>&1) && \
	(docker stop portainer > /dev/null 2>&1) && \
	(docker rm portainer > /dev/null 2>&1) && \
	echo "${green}  Stopped!${no_color}" || echo "${orange}  Not found!${no_color}"

glances: ## Start Glances, for monitoring
	@echo "${green}Show Glances info${no_color}"
	docker run --rm -e TZ="${TZ}" -v /var/run/docker.sock:/var/run/docker.sock:ro -v /run/user/1000/podman/podman.sock:/run/user/1000/podman/podman.sock:ro --pid host --network host -it nicolargo/glances:latest-full

list_all_volumes: ## List all containers and related volumes
	@docker ps -a --format '{{ .ID }}' | xargs -I {} docker inspect -f '{{ .Name }}{{ printf "\n" }}{{ range .Mounts }}{{ printf "\n\t" }}{{ .Type }} {{ if eq .Type "bind" }}{{ .Source }}{{ end }}{{ .Name }} => {{ .Destination }}{{ end }}{{ printf "\n" }}' {}


.PHONY: help backup shell root sql logs list build update occ

green=`tput setaf 2`
orange=`tput setaf 9`
red=`tput setaf 1`
no_color=`tput sgr0`
include .env
