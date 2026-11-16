variable "subscription_id" {
  description = "ID da assinatura Azure (az account show --query id -o tsv)."
  type        = string
}

variable "location" {
  description = "Região de todos os recursos."
  type        = string
  default     = "brazilsouth"
}

variable "resource_group_name" {
  description = "Grupo de recursos criado pelo Terraform."
  type        = string
  default     = "rg-aprovia"
}

variable "storage_replication" {
  description = "Redundância da Storage Account: LRS, ZRS, GRS ou GZRS."
  type        = string
  default     = "ZRS"
}

variable "alert_email" {
  description = "E-mail que recebe os alertas do Azure Monitor."
  type        = string
}

variable "mongo_connection_string" {
  description = "Connection string do MongoDB Atlas usada pela Function App."
  type        = string
  sensitive   = true
}

variable "mongo_db_name" {
  description = "Banco do MongoDB usado pela API e pela Function App."
  type        = string
  default     = "aprovia_db"
}

variable "expo_access_token" {
  description = "Token do Expo Push Service (opcional)."
  type        = string
  sensitive   = true
  default     = ""
}

variable "tags" {
  type = map(string)
  default = {
    projeto  = "aprovia"
    ambiente = "producao"
    origem   = "terraform"
  }
}

variable "postgres_high_availability" {
  description = "true = General Purpose com réplica em outra zona (HA real, custo ~US$ 250/mês). false = Burstable B1ms (gratuito na conta de estudante)."
  type        = bool
  default     = false
}

variable "postgres_geo_backup" {
  description = "Copia os backups do PostgreSQL para a região par. Só pode ser definido na criação do servidor."
  type        = bool
  default     = true
}

variable "postgres_allowed_ips" {
  description = "IPs liberados no firewall do PostgreSQL além dos serviços da Azure (ex.: sua máquina, para usar o psql)."
  type        = list(string)
  default     = []
}

variable "budget_amount" {
  description = "Orçamento mensal da assinatura em USD. 0 desliga o orçamento."
  type        = number
  default     = 20
}

variable "budget_start_date" {
  description = "Início do orçamento: primeiro dia de um mês, não anterior ao mês atual."
  type        = string
  default     = "2026-11-01T00:00:00Z"
}

variable "vm_size" {
  description = "Tamanho da VM da API Python + Ollama (mínimo 8 GB para os modelos). A série B é bloqueada na assinatura de estudante; D2s_v4 = 2 vCPU / 8 GB."
  type        = string
  default     = "Standard_D2s_v4"
}

variable "vm_zone" {
  description = "Zona de disponibilidade da VM e do IP público."
  type        = string
  default     = "1"
}

variable "vm_auto_shutdown" {
  description = "Desliga a VM todo dia às 23:30 para economizar crédito."
  type        = bool
  default     = true
}

variable "vm_auto_start" {
  description = "Liga a VM às 08:00 de segunda a sexta (Logic App com identidade gerenciada)."
  type        = bool
  default     = true
}

variable "ssh_public_key" {
  description = "Chave pública SSH do usuário azureuser (conteúdo de ~/.ssh/id_ed25519.pub)."
  type        = string
}

variable "admin_ip_cidr" {
  description = "IP liberado para SSH na VM, ex.: 203.0.113.10/32. Vazio fecha a porta 22."
  type        = string
  default     = ""
}

variable "api_repo_url" {
  description = "Repositório da API Python clonado pela VM."
  type        = string
  default     = "https://github.com/medeirosfbia/python_ProjetoIA_BackEnd.git"
}

variable "api_repo_branch" {
  description = "Branch da API Python implantada na VM."
  type        = string
  default     = "main"
}

variable "admin_users" {
  description = "Usernames com permissão de admin na API Python, separados por vírgula."
  type        = string
  default     = "admin"
}

variable "cors_origins" {
  description = "Origens aceitas pela API Python (front na Vercel, app), separadas por vírgula."
  type        = string
}

variable "java_image" {
  description = "Imagem da API Java publicada pelo GitHub Actions do manager_back."
  type        = string
  default     = "ghcr.io/medeirosfbia/manager_back:latest"
}

variable "java_min_replicas" {
  description = "Réplicas sempre ligadas da API Java. 1 elimina o cold start; 2 mantém o serviço durante a troca de uma réplica."
  type        = number
  default     = 1
}

variable "java_admin_password" {
  description = "Senha do admin padrão criado pelo AdminSeeder da API Java."
  type        = string
  sensitive   = true
}

variable "postgres_location" {
  description = "Região do PostgreSQL, quando diferente de location (a assinatura de estudante bloqueia o Flexible Server em eastus). Vazio = location."
  type        = string
  default     = ""
}
