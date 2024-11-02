#!/bin/bash

# Extract the OVA file
your-bucket-name=$1
wget https://download.vulnhub.com/mrrobot/mrRobot.ova -O /tmp/mrRobot.ova

# Upload the VMDK or RAW file to S3 (assuming an S3 bucket is created)
aws s3 cp /tmp/mrRobot.ova s3://${your-bucket-name}

# Create the containers.json file for importing the image
echo '[
  {
    "Description": "mrRobot ova image",
    "Format": "ova",
    "UserBucket": {
      "S3Bucket": "${your-bucket-name}",
      "S3Key": "mrRobot.ova"
    }
  }
]' > /tmp/containers.json

# Import the VMDK to EC2
IMPORTTASKID=$(aws ec2 import-image --description "mrRobot VM" --disk-containers "file:///tmp/containers.json" --query ImportTaskId --output text)
while [[ "$(aws ec2 describe-import-image-tasks --import-task-ids $IMPORTTASKID --query 'ImportImageTasks[*].StatusMessage' --output text)" != "preparing ami" ]]; do echo $(aws ec2 describe-import-image-tasks --import-task-ids $IMPORTTASKID --query 'ImportImageTasks[*].StatusMessage' --output text); sleep 10; done; echo "Import completed!";
AMI_ID=$(aws ec2 describe-import-image-tasks --import-task-ids $IMPORTTASKID --query 'ImportImageTasks[*].ImageId' --output text)
REGION=$(aws ec2 describe-availability-zones --output text --query 'AvailabilityZones[0].[RegionName]')
COPIED_AMI_ID=$(aws ec2 copy-image --source-image-id $AMI_ID --source-region us-east-1 --region $REGION --name mrRobot${AMI_ID#ami-} --description "Based on the show, Mr. Robot." --query ImageId --output text)
aws ec2 create-tags --resources $COPIED_AMI_ID --tags Key=Name,Value="mrRobot"
aws ec2 deregister-image --image-id $AMI_ID
