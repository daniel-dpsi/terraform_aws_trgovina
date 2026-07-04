terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "eu-central-1"
}

data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"]
}

resource "aws_vpc" "glavni_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "trgovina-vpc"
  }
}

resource "aws_subnet" "javno_subnet" {
  vpc_id                  = aws_vpc.glavni_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "eu-central-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "trgovina-javno-subnet"
  }
}

resource "aws_subnet" "zasebno_subnet_1" {
  vpc_id            = aws_vpc.glavni_vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "eu-central-1a"

  tags = {
    Name = "trgovina-zasebno-subnet-1"
  }
}

resource "aws_subnet" "zasebno_subnet_2" {
  vpc_id            = aws_vpc.glavni_vpc.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "eu-central-1b"

  tags = {
    Name = "trgovina-zasebno-subnet-2"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.glavni_vpc.id

  tags = {
    Name = "trgovina-igw"
  }
}

resource "aws_route_table" "javno_rt" {
  vpc_id = aws_vpc.glavni_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "trgovina-javno-rt"
  }
}

resource "aws_route_table_association" "javno_assoc" {
  subnet_id      = aws_subnet.javno_subnet.id
  route_table_id = aws_route_table.javno_rt.id
}

resource "aws_db_subnet_group" "rds_subnet_group" {
  name       = "trgovina-rds-subnet-group"
  subnet_ids = [aws_subnet.zasebno_subnet_1.id, aws_subnet.zasebno_subnet_2.id]

  tags = {
    Name = "Trgovina RDS Subnet Group"
  }
}

resource "aws_security_group" "ec2_sg" {
  name        = "trgovina-ec2-sg"
  description = "Dovoli HTTP in SSH promet"
  vpc_id      = aws_vpc.glavni_vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "trgovina-ec2-sg"
  }
}

resource "aws_security_group" "rds_sg" {
  name        = "trgovina-rds-sg"
  description = "Dovoli MySQL promet SAMO iz EC2 streznika"
  vpc_id      = aws_vpc.glavni_vpc.id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "trgovina-rds-sg"
  }
}

resource "aws_db_instance" "baza" {
  allocated_storage      = 20
  max_allocated_storage  = 100
  db_name                = "trgovina_db"
  engine                 = "mysql"
  engine_version         = "8.0"
  instance_class         = "db.t4g.micro"
  username               = "rootuser"
  password               = "MojeVarnoGeslo123!"
  parameter_group_name   = "default.mysql8.0"
  db_subnet_group_name   = aws_db_subnet_group.rds_subnet_group.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  skip_final_snapshot    = true

  tags = {
    Name = "trgovina-rds-baza"
  }
}

resource "aws_instance" "spletni_streznik" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.javno_subnet.id
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]

  user_data = <<-EOF
              #!/bin/bash
              apt-get update -y
              apt-get install -y apache2 php libapache2-mod-php php-mysqli git
              
              systemctl start apache2
              systemctl enable apache2
              
              rm /var/www/html/index.html
              
              echo "<?php phpinfo(); ?>" > /var/www/html/index.php
              
              chown -R www-data:www-data /var/www/html/
              chmod -R 755 /var/www/html/
              EOF

  tags = {
    Name = "trgovina-spletni-streznik"
  }
}

output "javni_ip_streznik" {
  value       = aws_instance.spletni_streznik.public_ip
  description = "Javni IP naslov tvoje spletne trgovine"
}

output "rds_endpoint" {
  value       = aws_db_instance.baza.endpoint
  description = "Povezovalni niz za MySQL bazo podatkov"
}