variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "eu-north-1"
}

variable "aws_access_key" {
  description = "AWS access key (Student user)"
  type        = string
  sensitive   = true
}

variable "aws_secret_key" {
  description = "AWS secret key (Student user)"
  type        = string
  sensitive   = true
}

variable "app_image" {
  description = "Container image pushed to ECR"
  type        = string
  default     = "989346119941.dkr.ecr.eu-north-1.amazonaws.com/todoai:Vbarabash"
}

variable "domain_name" {
  description = "Public DNS name served through Route53 alias to ALB"
  type        = string
  default     = "hwbarabash1.pp.ua"
}

variable "container_port" {
  description = "Application port inside the container"
  type        = number
  default     = 80
}

variable "cpu" {
  description = "Fargate task CPU units"
  type        = number
  default     = 256
}

variable "memory" {
  description = "Fargate task memory (MiB)"
  type        = number
  default     = 512
}

variable "min_capacity" {
  description = "Minimum number of tasks (autoscaling)"
  type        = number
  default     = 1
}

variable "max_capacity" {
  description = "Maximum number of tasks (autoscaling)"
  type        = number
  default     = 4
}

variable "scale_out_threshold" {
  description = "Scale OUT when CPU or request rate is above this percent"
  type        = number
  default     = 70
}

variable "scale_in_threshold" {
  description = "Scale IN metric stays below this percent for cooldown"
  type        = number
  default     = 50
}

variable "scale_in_cooldown_seconds" {
  description = "Scale IN only after metric is low for this long (15 min per exam condition)"
  type        = number
  default     = 900
}
