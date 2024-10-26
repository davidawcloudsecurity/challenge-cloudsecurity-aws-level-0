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

# Create VPC
resource "aws_vpc" "main" {
  cidr_block = "172.16.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "main-vpc"
  }
}

# Create Subnet
resource "aws_subnet" "public_subnet" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "172.16.10.0/24"
  availability_zone = "${var.region}a"
  map_public_ip_on_launch = true

  tags = {
    Name = "public-subnet"
  }
}

# Create Internet Gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "main-igw"
  }
}

# Create Route Table
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "public-route-table"
  }
}

# Associate Route Table with Subnet
resource "aws_route_table_association" "public_subnet_association" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_route_table.id
}

# Create Security Group
resource "aws_security_group" "public_security_group" {
  name        = "allow_80_443"
  description = "Allow SSH inbound traffic"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

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

  ingress {
    from_port   = 3389
    to_port     = 3389
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 3306
    to_port     = 3306
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

# Create IAM Role for EC2 Instance
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

# Attach IAM Policy for Session Manager
resource "aws_iam_role_policy_attachment" "session_manager_policy" {
  role       = aws_iam_role.ec2_session_manager_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Create Instance Profile for the Role
resource "aws_iam_instance_profile" "ec2_session_manager_profile" {
  name = "ec2_session_manager_profile"
  role = aws_iam_role.ec2_session_manager_role.name
}

# Launch EC2 Instance with Session Manager
resource "aws_instance" "ubuntu_instance" {
  ami                    = var.ami
  instance_type         = "t2.micro"
  subnet_id             = aws_subnet.public_subnet.id
  vpc_security_group_ids = [aws_security_group.public_security_group.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_session_manager_profile.name
  user_data = filebase64("${var.setup_filename}")

  tags = {
    Name = "my-first-web-app"
  }
}

# Launch EC2 Instance with Session Manager
resource "aws_instance" "threat_actor" {
  ami                    = var.ami
  instance_type         = "t2.micro"
  subnet_id             = aws_subnet.public_subnet.id
  vpc_security_group_ids = [aws_security_group.public_security_group.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_session_manager_profile.name
  user_data = <<-EOF
#!/bin/bash
docker pull hackersploit/bugbountytoolkit
docker run -it hackersploit/bugbountytoolkit
EOF

  tags = {
    Name = "threat-actor"
  }
}

# Enable GuardDuty / Enable Security Hub
# Create S3 Bucket for GuardDuty threat list
resource "aws_s3_bucket" "guardduty_threat_list" {
  bucket = "my-guardduty-threat-list-bucket-${random_id.bucket_suffix.hex}"
  
  tags = {
    Name = "GuardDutyThreatListBucket"
  }
}

# Generate a random ID to make sure the bucket name is unique
resource "random_id" "bucket_suffix" {
  byte_length = 8
}

# Null resource to create and append EC2 instance public IP to threat-list.txt
resource "null_resource" "create_threat_list" {
  provisioner "local-exec" {
    command = <<EOT
      # Create the threat-list.txt file if it doesn't exist
      touch threat-list.txt

      # Append the public IP of the EC2 instance to the threat list
      echo "${aws_instance.ubuntu_instance.public_ip}" >> threat-list.txt

      # Display the contents of the file (optional)
      cat threat-list.txt
    EOT
  }

  # Ensure the EC2 instance is created before we run this
  depends_on = [aws_instance.ubuntu_instance]
}

# Update S3 object resource (fix deprecation warning)
resource "aws_s3_object" "guardduty_threat_list_file" {
  bucket = aws_s3_bucket.guardduty_threat_list.bucket
  key    = "threat-list.txt"
  source = "threat-list.txt"

  tags = {
    Name = "GuardDutyThreatListFile"
  }

  depends_on = [null_resource.create_threat_list]
}

# Enable GuardDuty
resource "aws_guardduty_detector" "main" {
  enable = true
}

# Update GuardDuty ThreatIntelSet with required name
resource "aws_guardduty_threatintelset" "guardduty_threatintelset" {
  detector_id = aws_guardduty_detector.main.id
  name        = "custom-threat-list"  # Add required name argument
  activate    = true
  format      = "TXT"
  location    = "s3://${aws_s3_bucket.guardduty_threat_list.bucket}/threat-list.txt"  # Simplified location reference

  depends_on = [aws_s3_object.guardduty_threat_list_file]

  tags = {
    Name = "GuardDutyThreatIntelSet"
  }
}

# Fix output reference
output "guardduty_detector_id" {
  value = aws_guardduty_detector.main.id  # Update reference to match resource name
}

resource "aws_securityhub_account" "this" {}

# Adding SNS for GuardDuty Findings
# Create an SNS Topic for GuardDuty Findings
resource "aws_sns_topic" "guardduty_findings" {
  name = "guardduty-findings"
}

# Create a CloudWatch Event Rule for GuardDuty Findings
resource "aws_cloudwatch_event_rule" "guardduty_findings_rule" {
  name        = "guardduty-findings-rule"
  description = "Triggers on GuardDuty findings"
  event_pattern = jsonencode({
    source = ["aws.guardduty"]
    detail-type = ["GuardDuty Finding"]
  })
}

# Create a CloudWatch Event Target to send notifications to the SNS Topic
resource "aws_cloudwatch_event_target" "guardduty_findings_target" {
  rule      = aws_cloudwatch_event_rule.guardduty_findings_rule.name
  target_id = "GuardDutyFindingsSNS"
  arn       = aws_sns_topic.guardduty_findings.arn
}

# Grant permissions for CloudWatch Events to publish to the SNS Topic
resource "aws_sns_topic_subscription" "guardduty_subscription" {
  topic_arn = aws_sns_topic.guardduty_findings.arn
  protocol  = "email"
  endpoint  = "foabdavid@gmail.com"  # Replace with your email
}

# You may also want to set up IAM roles or policies for further integration

/* 
# Security Hub Integration with AWS Config
# Enabling AWS Config and Creating a Rule
resource "aws_config_configuration_recorder" "this" {
  name     = "config_recorder"
  role_arn = aws_iam_role.config_role.arn

  recording_group {
    all_supported = true
    include_global_resource_types = true
  }
}

resource "aws_config_delivery_channel" "this" {
  name           = "config_channel"
  s3_bucket_name = "your-s3-bucket-name"  # Replace with your bucket name
}

resource "aws_config_rule" "s3_bucket_public_read_prohibited" {
  name = "s3-bucket-public-read-prohibited"

  source {
    owner             = "AWS"
    source_identifier = "S3_BUCKET_PUBLIC_READ_PROHIBITED"
  }

  input_parameters = jsonencode({})

  maximum_execution_frequency = "Six_Hours"
}
*/

/* Remove to learn better first

# AWS Lambda for Security Hub Findings Processing
# Create a directory for the Lambda function
resource "null_resource" "create_lambda_files" {
  # Add triggers to ensure this runs when needed
  triggers = {
    # This will trigger a rebuild whenever these files change
    index_js_hash = md5(<<-EOT
      const AWS = require('aws-sdk');
      const sns = new AWS.SNS();
      exports.handler = async (event) => {
          console.log('Event: ', JSON.stringify(event, null, 2));
          for (const record of event.Records) {
              const finding = JSON.parse(record.Sns.Message);
              console.log(\`Processing finding: \$\{finding.Id\}\`);
              const params = {
                  Message: \`New GuardDuty finding: \$\{finding.Id\}\`,
                  TopicArn: process.env.SNS_TOPIC_ARN
              };
              await sns.publish(params).promise();
          }
          return {
              statusCode: 200,
              body: JSON.stringify('Processing complete.'),
          };
      };
    EOT
    )
  }

  provisioner "local-exec" {
    command = <<EOT
      mkdir -p ${path.module}/lambda_function
      
      # Create index.js
      cat > ${path.module}/lambda_function/index.js <<'EOF'
      const AWS = require('aws-sdk');
      const sns = new AWS.SNS();
      exports.handler = async (event) => {
          console.log('Event: ', JSON.stringify(event, null, 2));
          for (const record of event.Records) {
              const finding = JSON.parse(record.Sns.Message);
              console.log(\`Processing finding: \$\{finding.Id\}\`);
              const params = {
                  Message: \`New GuardDuty finding: \$\{finding.Id\}\`,
                  TopicArn: process.env.SNS_TOPIC_ARN
              };
              await sns.publish(params).promise();
          }
          return {
              statusCode: 200,
              body: JSON.stringify('Processing complete.'),
          };
      };
EOF

      # Create package.json
      cat > ${path.module}/lambda_function/package.json <<'EOF'
      {
          "name": "findings-processor",
          "version": "1.0.0",
          "description": "A Lambda function to process GuardDuty findings",
          "main": "index.js",
          "dependencies": {
              "aws-sdk": "^2.1000.0"
          }
      }
EOF

      cd ${path.module}/lambda_function && \
      npm install && \
      zip -r ../findings_processor.zip .
    EOT
  }
}

data "archive_file" "lambda_zip" {
  depends_on = [null_resource.create_lambda_files]
  type        = "zip"
  source_dir  = "${path.module}/lambda_function"
  output_path = "${path.module}/findings_processor.zip"
}

# Create Lambda function
resource "aws_lambda_function" "findings_processor" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "findingsProcessor"
  role             = aws_iam_role.lambda_exec.arn
  handler          = "index.handler"
  runtime          = "nodejs18.x"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      SNS_TOPIC_ARN = aws_sns_topic.guardduty_findings.arn
    }
  }

  depends_on = [
    null_resource.create_lambda_files,
    data.archive_file.lambda_zip
  ]
}

# Create an IAM Role for Lambda Execution
resource "aws_iam_role" "lambda_exec" {
  name = "lambda_exec_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

# Attach policy for publishing to SNS
resource "aws_iam_role_policy_attachment" "lambda_sns_policy" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Grant permission for Lambda to publish to the SNS Topic
resource "aws_sns_topic_subscription" "lambda_subscription" {
  topic_arn = aws_sns_topic.guardduty_findings.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.findings_processor.arn
}
*/

# Adding Outputs
output "vpc_id" {
  value = aws_vpc.main.id
}

output "public_subnet_id" {
  value = aws_subnet.public_subnet.id
}

output "ec2_instance_id" {
  value = aws_instance.ubuntu_instance.id
}

/*
output "aws_guardduty_detector_id" {
  value = aws_guardduty_detector.id
}
*/

output "securityhub_status" {
  value = aws_securityhub_account.this.id
}
