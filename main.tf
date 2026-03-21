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

module "database" {
  source                = "./modules/database"
  project               = var.project
  environment           = var.environment
  private_db_subnet_ids = module.networking.private_db_subnet_ids
  sg_db_id              = module.security.sg_db_id
  db_name               = var.db_name
  db_username           = var.db_username
  db_password           = var.db_password
  db_port               = var.db_port
  db_instance_class     = var.db_instance_class
  multi_az              = var.multi_az
  deletion_protection   = var.deletion_protection
}