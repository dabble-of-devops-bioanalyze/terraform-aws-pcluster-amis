module "pcluster_amis" {
  source = "../.."
  region = var.region

  instance_type = "t3a.medium"
  subnet_id     = var.subnet_id
  ami_name      = var.ami_name
  context       = module.this.context
}

output "id" {
  description = "ID of the created example"
  value       = module.this.id
}

output "pcluster_amis" {
  value = module.pcluster_amis
}
