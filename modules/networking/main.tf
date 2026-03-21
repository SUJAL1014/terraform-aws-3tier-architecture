data "aws_availability_zones" "available" { state = "available" }

resource "aws_vpc" "vpc" {
  cidr_block =  var.vpc_cidr

  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "Main"
  }
}


resource "aws_subnet" "public" {
  count = 2

  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index + 1)
  map_public_ip_on_launch = true
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = { 
    Name = "${var.project}-${var.environment}-public-${count.index + 1}",
    Tier = "public" 
    }
}


resource "aws_subnet" "private_app" {
  count             = 2
  vpc_id            = aws_vpc.vpc.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 10)
  availability_zone = data.aws_availability_zones.available.names[count.index]


  tags = { 
    Name = "${var.project}-${var.environment}-app-${count.index + 1}" ,
    Tier = "app" 
    }
}


resource "aws_subnet" "private_db" {
  count             = 2
  vpc_id            = aws_vpc.vpc.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 20)
  availability_zone = data.aws_availability_zones.available.names[count.index]


  tags = { 
    Name = "${var.project}-${var.environment}-db-${count.index + 1}", 
    Tier = "db"
    }
}


resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.vpc.id

  tags   = { 
    Name = "${var.project}-${var.environment}-igw" 
    }
}


resource "aws_eip" "nat" {
  domain     = "vpc"
  depends_on = [aws_internet_gateway.main]
  tags       = { Name = "${var.project}-${var.environment}-nat-eip" }
}


resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id
  depends_on    = [aws_internet_gateway.main]
  tags          = { Name = "${var.project}-${var.environment}-nat" }
}


resource "aws_route_table" "public" {
  vpc_id = aws_vpc.vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = { 
    Name = "${var.project}-${var.environment}-public-rt" 
    }
}


resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}


resource "aws_route_table" "private" {
  vpc_id = aws_vpc.vpc.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }
  tags = { Name = "${var.project}-${var.environment}-private-rt" }
}


resource "aws_route_table_association" "private_app" {
  count          = 2
  subnet_id      = aws_subnet.private_app[count.index].id
  route_table_id = aws_route_table.private.id
}


resource "aws_route_table_association" "private_db" {
  count          = 2
  subnet_id      = aws_subnet.private_db[count.index].id
  route_table_id = aws_route_table.private.id
}