resource "vultr_ssh_key" "deployer" {
  name    = "devops-showcase-deployer"
  ssh_key = var.ssh_public_key
}

resource "vultr_firewall_group" "main" {
  description = "devops-showcase firewall"
}

resource "vultr_firewall_rule" "ssh" {
  firewall_group_id = vultr_firewall_group.main.id
  protocol          = "tcp"
  ip_type           = "v4"
  subnet            = "0.0.0.0"
  subnet_size       = 0
  port              = "22"
  notes             = "SSH access"
}

resource "vultr_firewall_rule" "http" {
  firewall_group_id = vultr_firewall_group.main.id
  protocol          = "tcp"
  ip_type           = "v4"
  subnet            = "0.0.0.0"
  subnet_size       = 0
  port              = "80"
  notes             = "HTTP — app ingress"
}

resource "vultr_firewall_rule" "grafana" {
  firewall_group_id = vultr_firewall_group.main.id
  protocol          = "tcp"
  ip_type           = "v4"
  subnet            = "0.0.0.0"
  subnet_size       = 0
  port              = "3000"
  notes             = "Grafana dashboard"
}

resource "vultr_firewall_rule" "k3s_api" {
  firewall_group_id = vultr_firewall_group.main.id
  protocol          = "tcp"
  ip_type           = "v4"
  subnet            = "0.0.0.0"
  subnet_size       = 0
  port              = "6443"
  notes             = "k3s API server — GitHub Actions kubectl access"
}

resource "vultr_instance" "server" {
  plan              = var.plan
  region            = var.region
  os_id             = 2284 # Ubuntu 22.04 LTS
  label             = "devops-showcase"
  hostname          = "devops-showcase"
  firewall_group_id = vultr_firewall_group.main.id
  ssh_key_ids       = [vultr_ssh_key.deployer.id]

  # Bootstrap k3s on first boot — no manual SSH required
  user_data = <<-EOT
    #!/bin/bash
    curl -sfL https://get.k3s.io | sh -
    # Allow non-root kubectl access
    mkdir -p /home/ubuntu/.kube
    cp /etc/rancher/k3s/k3s.yaml /home/ubuntu/.kube/config
    chown ubuntu:ubuntu /home/ubuntu/.kube/config
  EOT
}

# Pull kubeconfig after VPS is up — replaces loopback IP with public IP
# so GitHub Actions can reach the k3s API from outside
resource "null_resource" "fetch_kubeconfig" {
  depends_on = [vultr_instance.server]

  provisioner "local-exec" {
    command = <<-EOT
      sleep 60  # wait for k3s to finish installing via user_data
      ssh -o StrictHostKeyChecking=no root@${vultr_instance.server.main_ip} \
        'cat /etc/rancher/k3s/k3s.yaml' | \
        sed 's/127.0.0.1/${vultr_instance.server.main_ip}/' \
        > kubeconfig.yaml
      echo "Kubeconfig saved to terraform/kubeconfig.yaml"
      echo "Next: base64 encode and add to GitHub Secrets as KUBECONFIG"
    EOT
  }
}
