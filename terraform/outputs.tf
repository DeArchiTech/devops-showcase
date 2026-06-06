output "server_ip" {
  description = "Public IP of the VPS — add to GitHub Secrets as SERVER_IP"
  value       = vultr_instance.server.main_ip
}

output "grafana_url" {
  description = "Grafana dashboard URL"
  value       = "http://${vultr_instance.server.main_ip}:3000"
}

output "app_url" {
  description = "Application URL"
  value       = "http://${vultr_instance.server.main_ip}/health"
}
