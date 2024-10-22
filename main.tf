# Configure the AWS Provider
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}

# Define Variables
variable "region" {
  default = "us-east-1"
}

variable "setup_filename" {
  default = "setup_wordpress_nginx_ready_state.sh"
}

variable "ami" {
  default = "ami-0866a3c8686eaeeba" # Ubuntu Server 20.04 LTS (HVM), SSD Volume Type, us-east-1
}

# Check if VPC exists
data "aws_vpc" "existing_vpc" {
  filter {
    name   = "cidr"
    values = ["172.16.0.0/16"]
  }
}

# Create VPC if it doesn't exist
resource "aws_vpc" "main" {
  count             = length(data.aws_vpc.existing_vpc.id) == 0 ? 1 : 0
  cidr_block        = "172.16.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "main-vpc"
  }
}

# Check if Subnet exists
data "aws_subnet" "existing_subnet" {
  filter {
    name   = "cidr-block"
    values = ["172.16.10.0/24"]
  }
  filter {
    name   = "vpc-id"
    values = [aws_vpc.main.id]
  }
}

# Create Subnet if it doesn't exist
resource "aws_subnet" "public_subnet" {
  count             = length(data.aws_subnet.existing_subnet.id) == 0 ? 1 : 0
  vpc_id            = aws_vpc.main.id
  cidr_block        = "172.16.10.0/24"
  availability_zone = "${var.region}a"
  map_public_ip_on_launch = true

  tags = {
    Name = "public-subnet"
  }
}

# Check if Internet Gateway exists
data "aws_internet_gateway" "existing_igw" {
  filter {
    name   = "attachment.vpc-id"
    values = [aws_vpc.main.id]
  }
}

# Create Internet Gateway if it doesn't exist
resource "aws_internet_gateway" "igw" {
  count  = length(data.aws_internet_gateway.existing_igw.id) == 0 ? 1 : 0
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "main-igw"
  }
}

# Check if Route Table exists
data "aws_route_table" "existing_route_table" {
  filter {
    name   = "vpc-id"
    values = [aws_vpc.main.id]
  }
}

# Create Route Table if it doesn't exist
resource "aws_route_table" "public_route_table" {
  count  = length(data.aws_route_table.existing_route_table.id) == 0 ? 1 : 0
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "public-route-table"
  }
}

# Associate Route Table with Subnet if not associated
data "aws_route_table_association" "existing_rta" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table_association" "public_subnet_association" {
  count = length(data.aws_route_table_association.existing_rta.id) == 0 ? 1 : 0
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_route_table.id
}

# Check if Security Group exists
data "aws_security_group" "existing_sg" {
  filter {
    name   = "group-name"
    values = ["allow_80_443"]
  }
  filter {
    name   = "vpc-id"
    values = [aws_vpc.main.id]
  }
}

# Create Security Group if it doesn't exist
resource "aws_security_group" "public_security_group" {
  count       = length(data.aws_security_group.existing_sg.id) == 0 ? 1 : 0
  name        = "allow_80_443"
  description = "Allow SSH inbound traffic"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
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
    Name = "allow_80_443"
  }
}

# IAM Role for EC2 Instance (No data lookup needed for IAM resources)
resource "aws_iam_role" "ec2_session_manager_role" {
  name = "ec2_session_manager_role"

  assume_role_policy = jsonencode({
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Principal": {
          "Service": "ec2.amazonaws.com"
        },
        "Action": "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "session_manager_policy" {
  role       = aws_iam_role.ec2_session_manager_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2_session_manager_profile" {
  name = "ec2_session_manager_profile"
  role = aws_iam_role.ec2_session_manager_role.name
}

# Launch EC2 Instance with Session Manager
resource "aws_instance" "ubuntu_instance" {
  ami                    = var.ami
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.public_subnet.id
  vpc_security_group_ids = [aws_security_group.public_security_group.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_session_manager_profile.name
  user_data = filebase64("${var.setup_filename}")

  tags = {
    Name = "my-first-web-app"
  }
}
