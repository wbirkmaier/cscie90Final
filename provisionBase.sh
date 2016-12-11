#!/bin/bash

#Check if they SSH dir for keys exists, if not make it
if [ ! -d "~/.ssh" ]; 
	then
		mkdir ~/.ssh
		chmod 700 ~/.ssh
fi

#Create a aws keypair and place the pem file in the .ssh directory
aws ec2 create-key-pair --key-name finalProject --query 'KeyMaterial' --output text > ~/.ssh/finalProject.pem
chmod 600 ~/.ssh/finalProject.pem

echo "Creating AWS Security Group called WebService"
groupId=$(aws ec2 create-security-group --group-name WebService --description "Linux SSH and HTTP" --query 'GroupId' --output text)

echo ""
echo "The WebService GroupID is:"
echo $groupId
echo ""

echo "Adding ports 22 and 80 to the WebService Security Group"
aws ec2 authorize-security-group-ingress --group-name WebService --protocol tcp --port 22 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-name WebService --protocol tcp --port 80 --cidr 0.0.0.0/0

echo "Describing the WebService Security Group"
aws ec2 describe-security-groups --group-id $groupId --output table

echo "Creating New Base Image EC2 Instance"
instanceId=$(aws ec2 run-instances --image-id ami-2051294a --security-group-ids $groupId --count 1 --instance-type t2.micro --key-name finalProject --query 'Instances[*].InstanceId' --output text)

#Grab the public IP
publicIpAddress=$(aws ec2 describe-instances --instance-id $instanceId --query 'Reservations[*].Instances[*].PublicIpAddress' --output text)

#While loop to wait for instance to be change from "initializing" to "ok"

instanceStatus="initializing"

while [  "$instanceStatus" == "initializing" ]; do
	echo The instance is still $instanceStatus ...

	instanceStatus=$(aws ec2 describe-instance-status --instance-id $instanceId --query 'InstanceStatuses[*].SystemStatus.Status' --output text)
	
	sleep 15
done

echo The instance is now $instanceStatus !

echo "Installing httpd and php packages on remote instance."
ssh -tt -i ~/.ssh/finalProject.pem -l ec2-user -o StrictHostKeyChecking=no $publicIpAddress 'sudo yum -y install httpd php'

echo "Starting httpd service on remote instance."
ssh -tt -i ~/.ssh/finalProject.pem -l ec2-user -o StrictHostKeyChecking=no $publicIpAddress 'sudo systemctl start httpd.service'
ssh -tt -i ~/.ssh/finalProject.pem -l ec2-user -o StrictHostKeyChecking=no $publicIpAddress 'sudo systemctl status httpd'

echo "Enabling httpd to be persistant start on remote instance"
ssh -tt -i ~/.ssh/finalProject.pem -l ec2-user -o StrictHostKeyChecking=no $publicIpAddress 'sudo systemctl enable httpd'

echo "Changing ownership of the /var/www/html to the ec2-user on remote instance."
ssh -tt -i ~/.ssh/finalProject.pem -l ec2-user -o StrictHostKeyChecking=no $publicIpAddress 'sudo chown ec2-user /var/www/html'

#Cloning my code repository from git for a password generating website
echo "Cloning website code from git."
git clone git@github.com:wbirkmaier/p2.git

echo "Copying the local project code to the /var/www/html on remote instance."
scp -r -i ~/.ssh/finalProject.pem -o StrictHostKeyChecking=no p2/* ec2-user@$publicIpAddress:/var/www/html/.

#Create the new custom AMI
echo "Creating a new gold ami"
#amiID=$(create the image and return the ID)
echo The gold custom image AMI id is $amiID

#Loop to check for when it is done
echo "The image creation is now done!"
