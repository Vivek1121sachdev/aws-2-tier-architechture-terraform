terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16"
    }
  }
}

#configure the AWS provider
provider "aws" {
  region = "us-east-1"
}

#create a VPC
resource "aws_vpc" "vpc" {
  cidr_block       = "10.0.0.0/16"
  instance_tenancy = "default"

  tags = {
    Name = "terraform-aws-vpc"
  }
}

#create internet gateway
resource "aws_internet_gateway" "my-igw" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name = "terraform-aws-igw"
  }
}

#create 2 public subnets
resource "aws_subnet" "public-1" {
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "terraform-aws-public-1"
  }
}

resource "aws_subnet" "public-2" {
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = true

  tags = {
    Name = "terraform-aws-public-2"
  }
}

#create 2 private subnets
resource "aws_subnet" "private-1" {
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = "10.0.3.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = false

  tags = {
    Name = "terraform-aws-private-1"
  }
}

resource "aws_subnet" "private-2" {
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = "10.0.4.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = false

  tags = {
    Name = "terraform-aws-private-2"
  }
}

#create route table for internet gateway
resource "aws_route_table" "my-rt" {
  vpc_id = aws_vpc.vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.my-igw.id
  }

  tags = {
    Name = "terraform-aws-rt"
  }
}

#associate public subnets with route table
resource "aws_route_table_association" "public-route-1" {
  subnet_id      = aws_subnet.public-1.id
  route_table_id = aws_route_table.my-rt.id
}

resource "aws_route_table_association" "public-route-2" {
  subnet_id      = aws_subnet.public-2.id
  route_table_id = aws_route_table.my-rt.id
}

#create security group
resource "aws_security_group" "public-sg" {
  name        = "aws-public-sg"
  description = "Allow web and ssh traffic"
  vpc_id      = aws_vpc.vpc.id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "SSH"
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
}

resource "aws_security_group" "private-sg" {
  name        = "aws-private-sg"
  description = "Allow web tier and ssh traffic"
  vpc_id      = aws_vpc.vpc.id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    cidr_blocks     = ["10.0.0.0/16"]
    security_groups = [aws_security_group.public-sg.id]
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
}

#create sg for alb
resource "aws_security_group" "alb-sg" {
  name        = "aws-alb-sg"
  description = "sg for alb"
  vpc_id      = aws_vpc.vpc.id

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Create ALB
resource "aws_lb" "aws-alb" {
  name               = "alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb-sg.id]
  subnets            = [aws_subnet.public-1.id, aws_subnet.public-2.id]
}

#create alb target group
resource "aws_lb_target_group" "alb-target" {
  name     = "aws-alb-target"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.vpc.id

  depends_on = [aws_vpc.vpc]
}

#create target attachments
resource "aws_lb_target_group_attachment" "tg-attachment-1" {
  target_group_arn = aws_lb_target_group.alb-target.arn
  target_id        = aws_instance.web-1.id
  port             = 80

  depends_on = [aws_instance.web-1]
}

resource "aws_lb_target_group_attachment" "tg-attachment-2" {
  target_group_arn = aws_lb_target_group.alb-target.arn
  target_id        = aws_instance.web-2.id
  port             = 80

  depends_on = [aws_instance.web-2]
}

#create listener
resource "aws_lb_listener" "listener-lb" {
  load_balancer_arn = aws_lb.aws-alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    target_group_arn = aws_lb_target_group.alb-target.arn
    type             = "forward"
  }
}

#create ec2 instace
resource "aws_instance" "web-1" {
  ami                         = "ami-0cff7528ff583bf9a"
  instance_type               = "t2.micro"
  key_name                    = "MyKey"
  availability_zone           = "us-east-1a"
  vpc_security_group_ids      = [aws_security_group.public-sg.id]
  subnet_id                   = aws_subnet.public-1.id
  associate_public_ip_address = true

  user_data = <<-EOF
        #!/bin/bash
        yum update -y
        yum install httpd -y
        systemctl start httpd
        systemctl enable httpd
        echo "<html><body><h1>Hi there</h1></body></html>" > /var/www/html/index.html
        EOF

  tags = {
    Name = "web1_instance"
  }
}

resource "aws_instance" "web-2" {
  ami                         = "ami-0cff7528ff583bf9a"
  instance_type               = "t2.micro"
  key_name                    = "MyKey"
  availability_zone           = "us-east-1b"
  vpc_security_group_ids      = [aws_security_group.public-sg.id]
  subnet_id                   = aws_subnet.public-2.id
  associate_public_ip_address = true

  user_data = <<-EOF
        #!/bin/bash
        yum update -y
        yum install httpd -y
        systemctl start httpd
        systemctl enable httpd
        echo "<html><body><h1>Hi there again</h1></body></html>" > /var/www/html/index.html
        EOF

  tags = {
    Name = "web2_instance"
  }
}

#database subnet group
resource "aws_db_subnet_group" "db-subnet" {
  name       = "aws-db-subnet"
  subnet_ids = [aws_subnet.private-1.id, aws_subnet.private-2.id]
}

#create db instance
resource "aws_db_instance" "project-db" {
  allocated_storage      = 5
  engine                 = "mysql"
  engine_version         = "5.7"
  instance_class         = "db.t2.micro"
  identifier             = "db-instance"
  db_name                = "project_db"
  username               = "admin"
  password               = "password"
  db_subnet_group_name   = aws_db_subnet_group.db-subnet.id
  vpc_security_group_ids = [aws_security_group.private-sg.id]
  publicly_accessible    = false
  skip_final_snapshot    = true
}