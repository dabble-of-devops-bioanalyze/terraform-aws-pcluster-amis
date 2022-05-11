variable "subnet_id" {
  type = string
}

variable "region" {
  type    = string
  default = "us-east-1"
}

variable "ami_name" {
  description = "Name to prepend to the created ami."
  default     = ""
}
