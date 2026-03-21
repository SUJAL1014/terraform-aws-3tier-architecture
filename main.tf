module "networking" {
  source = "./modules/networking"

  project = var.project
  environment = var.environment
  aws_region = var.aws_region
  vpc_cidr = var.vpc_cidr
}

module "security" {
    source = "./modules/security"

    project = var.project
    environment = var.environment
    vpc_id = module.networking.vpc_id
    app_port = var.app_port
    db_port = var.db_port  
}