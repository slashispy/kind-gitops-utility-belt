# =============================================================================
# kind-gitops-utility-belt — Makefile
# -----------------------------------------------------------------------------
# Orquesta el bootstrap del circuito GitOps en KIND. Cada target delega en un
# script de scripts/ (que contiene la lógica real y es ejecutable a mano).
#
# Flujo típico de cero a funcionando:
#     make bootstrap      # up + argocd + image + keys + apps
# o paso a paso:
#     make up argocd image keys apps status
# =============================================================================

SHELL := /usr/bin/env bash
SCRIPTS := ./scripts

.DEFAULT_GOAL := help

.PHONY: help up argocd image keys apps bootstrap status down

help: ## Muestra esta ayuda
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
	  | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

up: ## Crea el cluster KIND
	$(SCRIPTS)/00-create-cluster.sh

argocd: ## Instala Argo CD y espera readiness
	$(SCRIPTS)/01-install-argocd.sh

image: ## Construye quicktask:dev y quicktask-auth:dev y las carga en KIND
	$(SCRIPTS)/02-build-and-load-image.sh

keys: ## Crea los Secrets JWT (par RSA + cliente demo); no se versionan
	$(SCRIPTS)/04-generate-jwt-keys.sh

apps: ## Aplica la App of Apps (arranca el circuito GitOps)
	$(SCRIPTS)/03-bootstrap-apps.sh

bootstrap: up argocd image keys apps ## Circuito completo de cero (up+argocd+image+keys+apps)
	@echo "Bootstrap completo. Usa 'make status' para ver el estado."

status: ## Muestra Applications, pods y servicios
	$(SCRIPTS)/status.sh

down: ## Elimina el cluster KIND (destruye todo el estado)
	$(SCRIPTS)/99-teardown.sh
