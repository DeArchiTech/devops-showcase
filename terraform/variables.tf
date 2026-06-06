variable "ssh_public_key" {
  description = "SSH public key for VPS access"
  type        = string
}

variable "region" {
  description = "Vultr region slug"
  type        = string
  default     = "lax" # Los Angeles — closest available to Vancouver
}

variable "plan" {
  description = "Vultr plan slug — 1 vCPU, 2GB RAM, enough for k3s + monitoring"
  type        = string
  default     = "vc2-1c-2gb"
}
