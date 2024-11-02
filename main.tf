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

variable email {
  default = "admin@example.com"
}

variable "setup_filename" {
  default = "setup_wordpress_mrRobot_nginx_ready_state.sh"
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

resource "random_id" "suffix" {
  byte_length = 4
}

# Create IAM Role for EC2 Instance
resource "aws_iam_role" "ec2_session_manager_role" {
  name = "ec2_session_manager_role_${random_id.suffix.hex}"
#  name = "ec2_session_manager_role"

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
#  name = "ec2_session_manager_profile"
  name = "ec2_session_manager_profile_${random_id.suffix.hex}"

  role = aws_iam_role.ec2_session_manager_role.name
}

resource "null_resource" "import_ova" {
  provisioner "local-exec" {
    command = <<-EOF
#!/bin/bash

# Set the bucket name from a variable
your_bucket_name="${aws_s3_bucket.guardduty_threat_list.bucket}"

# Download the OVA file
wget https://download.vulnhub.com/mrrobot/mrRobot.ova -O /tmp/mrRobot.ova

# Upload the OVA file to S3
aws s3 cp /tmp/mrRobot.ova s3://$your_bucket_name

# Create the containers.json file for importing the image
echo '[
  {
    "Description": "mrRobot ova image",
    "Format": "ova",
    "UserBucket": {
      "S3Bucket": "'$your_bucket_name'",
      "S3Key": "mrRobot.ova"
    }
  }
]' > /tmp/containers.json

# Import the OVA to EC2
IMPORTTASKID=$(aws ec2 import-image --description "mrRobot VM" --disk-containers "file:///tmp/containers.json" --query ImportTaskId --output text)
while [[ "$(aws ec2 describe-import-image-tasks --import-task-ids $${IMPORTTASKID} --query 'ImportImageTasks[*].StatusMessage' --output text)" != "preparing ami" ]]; do
    echo $(aws ec2 describe-import-image-tasks --import-task-ids $${IMPORTTASKID} --query 'ImportImageTasks[*].StatusMessage' --output text)
    sleep 10
done
echo "Import completed!"

# Wait for AMI ID
while [[ -z "$(aws ec2 describe-import-image-tasks --import-task-ids $${IMPORTTASKID} --query 'ImportImageTasks[*].ImageId' --output text)" ]]; do
    echo "Waiting for AMI ID..."
    sleep 10
done
AMI_ID=$(aws ec2 describe-import-image-tasks --import-task-ids $${IMPORTTASKID} --query 'ImportImageTasks[*].ImageId' --output text)
echo "AMI ID: $${AMI_ID}"

# Get the region and copy the image
REGION=$(aws ec2 describe-availability-zones --output text --query 'AvailabilityZones[0].[RegionName]')
COPIED_AMI_ID=$(aws ec2 copy-image --source-image-id $${AMI_ID} --source-region $${REGION} --region $${REGION} --name "mrRobot-$${AMI_ID#ami-}" --description "Based on the show, Mr. Robot." --query ImageId --output text)
echo "Copied AMI ID: $${COPIED_AMI_ID}"

# Tag the new AMI and deregister the original
aws ec2 create-tags --resources "$${COPIED_AMI_ID}" --tags Key=Name,Value="mrRobot"
aws ec2 deregister-image --image-id "$${AMI_ID}"
EOF
  }

  # Use a trigger to force the resource to run each time
  triggers = {
    always_run = "${timestamp()}"
  }
}

# Launch EC2 Instance with Session Manager
resource "aws_instance" "ubuntu_instance" {
  ami                   = $${COPIED_AMI_ID}
  instance_type         = "t2.micro"
  subnet_id             = aws_subnet.public_subnet.id
  vpc_security_group_ids = [aws_security_group.public_security_group.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_session_manager_profile.name

  tags = {
    Name = "my-first-web-app"
  }
  depends_on = [null_resource.import_ova]
}

# Launch EC2 Instance with Session Manager
resource "aws_instance" "threat_actor" {
  ami                    = var.ami
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.public_subnet.id
  vpc_security_group_ids = [aws_security_group.public_security_group.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_session_manager_profile.name
  root_block_device {
    volume_size = 15
  }
  user_data = <<-EOF
#!/bin/bash
apt update -y
apt install apt-transport-https ca-certificates curl software-properties-common -y
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu focal stable"
apt-cache policy docker-ce
apt install docker-ce -y
systemctl status docker
systemctl start docker
usermod -aG docker ssm-user
docker pull hackersploit/bugbountytoolkit
docker run -it hackersploit/bugbountytoolkit
EOF

  tags = {
    Name = "threat-actor"
  }
}

# Enable GuardDuty / Enable Security Hub

# Generate a random ID to make sure the bucket name is unique
resource "random_id" "bucket_suffix" {
  byte_length = 8
}

# Create S3 Bucket for GuardDuty threat list
resource "aws_s3_bucket" "guardduty_threat_list" {
  bucket = "my-guardduty-threat-list-bucket-${random_id.bucket_suffix.hex}"
  
  tags = {
    Name = "GuardDutyThreatListBucket"
  }
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

# Enable GuardDuty
resource "aws_guardduty_detector" "main" {
  enable = true
}

resource "aws_securityhub_account" "this" {}

/* Disable first to learn better
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
*/

/*
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
  endpoint  = "${var.email}"  # Replace with your email
}
*/

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

# Define an external data source to read the AMI ID from the JSON file
data "external" "ami_id" {
  program = ["cat", "/tmp/ami_output.json"]
}

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

output "guardduty_detector_id" {
  value = aws_guardduty_detector.main.id  # Update reference to match resource name
}

output "securityhub_status" {
  value = aws_securityhub_account.this.id
}
