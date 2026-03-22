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



module "compute" {
  source      = "./modules/compute"
  project     = var.project
  environment = var.environment
  aws_region  = var.aws_region

  # From networking module
  vpc_id                 = module.networking.vpc_id
  public_subnet_ids      = module.networking.public_subnet_ids
  private_app_subnet_ids = module.networking.private_app_subnet_ids

  # From security module
  sg_alb_id = module.security.sg_alb_id
  sg_app_id = module.security.sg_app_id

  # From database module
  db_host       = module.database.db_host
  db_name       = var.db_name
  db_username   = var.db_username
  db_secret_arn = module.database.db_secret_arn

  # From root variables
  app_port                = var.app_port
  instance_type           = var.instance_type
  asg_min                 = var.asg_min
  asg_max                 = var.asg_max
  asg_desired             = var.asg_desired
  cpu_scale_out_threshold = var.cpu_scale_out_threshold
  cpu_scale_in_threshold  = var.cpu_scale_in_threshold
}

# ── Module 5: Frontend ────────────────────────────────────────
module "frontend" {
  source      = "./modules/frontend"
  project     = var.project
  environment = var.environment
  price_class = var.price_class
  default_ttl = var.default_ttl
  alb_dns_name = module.compute.alb_dns_name
}