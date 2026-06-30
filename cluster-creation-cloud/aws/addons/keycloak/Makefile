# tf-rosa-keycloak
# Keycloak on ROSA (Kubernetes/OpenShift manifests and scripts; no Terraform).

.PHONY: help deploy setup-database restore backup

help:
	@echo "Keycloak on ROSA"
	@echo "  make deploy          - Deploy Keycloak (see deploy.sh)"
	@echo "  make setup-database   - Run database setup (see setup-database.sh)"
	@echo "  make backup           - Backup database (see backup-database.sh)"
	@echo "  make restore          - Restore database (see restore-database.sh)"
	@echo "  See README.md and QUICKSTART.md for full instructions."

deploy:
	./deploy.sh

setup-database:
	./setup-database.sh

backup:
	./backup-database.sh

restore:
	./restore-database.sh
