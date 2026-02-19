variable "aws_region" {
  type    = string
  default = "eu-west-2" # London; change if you want
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "key_name" {
  type        = string
  default     = null
  description = "Optional EC2 key pair name for SSH access."
}

variable "allowed_cidr" {
  type        = string
  default     = "0.0.0.0/0"
  description = "Who can reach WordPress (HTTP). For safer access, set to your IP /32."
}

variable "db_name" {
  type    = string
  default = "wordpress"
}

variable "db_username" {
  type    = string
  default = "wpadmin"
}

variable "db_password" {
  type        = string
  sensitive   = true
  description = "RDS master password (8-41 chars)."
}

variable "db_instance_class" {
  type    = string
  default = "db.t3.micro"
}

variable "db_allocated_storage" {
  type    = number
  default = 20
}

variable "wp_title" {
  type    = string
  default = "My WordPress"
}

variable "wp_admin_user" {
  type    = string
  default = "admin"
}

variable "wp_admin_password" {
  type        = string
  sensitive   = true
  description = "Used for initial WordPress admin user creation."
}

variable "wp_admin_email" {
  type    = string
  default = "admin@example.com"
}
