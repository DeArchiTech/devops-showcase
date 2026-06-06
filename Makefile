.PHONY: provision deploy monitor destroy

provision: ## Spin up VPS on Vultr and install k3s via Terraform
	cd terraform && terraform init && terraform apply -auto-approve
	@echo "\nNext: base64-encode terraform/kubeconfig.yaml and add to GitHub Secrets as KUBECONFIG"
	@echo "Run: cat terraform/kubeconfig.yaml | base64 | pbcopy"

deploy: ## Apply k8s manifests to the cluster
	kubectl apply -f k8s/apps/
	kubectl apply -f k8s/monitoring/
	kubectl rollout status deployment/signal-api

monitor: ## Open Grafana dashboard in browser (password: showcase)
	@IP=$$(cd terraform && terraform output -raw server_ip); \
	echo "Opening http://$$IP:3000"; \
	xdg-open "http://$$IP:3000"

destroy: ## Tear down all infrastructure
	cd terraform && terraform destroy -auto-approve

logs: ## Tail logs from the running app pod
	kubectl logs -l app=signal-api -f

status: ## Show pod and service status
	kubectl get pods,svc -A
