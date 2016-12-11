#!/bin/bash
# Script to build a base image, that is then turned into a custom AMI,
# and for use with ELB and other services where you need a quick spin.
# Wil Birkmaier

#Check if they SSH dir for keys exists, if not make it
if [ ! -d ~/.ssh ]; 
then
	mkdir ~/.ssh
	chmod 700 ~/.ssh
fi

#Create a aws keypair and place the pem file in the .ssh directory
echo -e "\033[0;32mCreating a new keypair called finalProject and placing it in your ~./ssh directory. \033[0m"
aws ec2 create-key-pair --key-name finalProject --query 'KeyMaterial' --output text > ~/.ssh/finalProject.pem
chmod 600 ~/.ssh/finalProject.pem

echo -e "\033[0;32mCreating AWS Security Group called WebService. \033[0m"
groupId=$(aws ec2 create-security-group --group-name WebService --description "Linux SSH and HTTP" --query 'GroupId' --output text)

echo -e ""
echo -e "\033[0;32mThe WebService GroupID is: \033[0m"
echo -e $groupId
echo -e ""

echo -e "\033[0;32mAdding ports 22 and 80 to the WebService Security Group... \033[0m"
aws ec2 authorize-security-group-ingress --group-name WebService --protocol tcp --port 22 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-name WebService --protocol tcp --port 80 --cidr 0.0.0.0/0
echo -e ""

echo -e "\033[0;32mDescribing the WebService Security Group... \033[0m"
aws ec2 describe-security-groups --group-id $groupId --query 'SecurityGroups[*].IpPermissions[*]'
echo -e ""

echo -e "\033[0;32mCreating New Base Image EC2 Instance, this can take several minutes... \033[0m"
echo -e ""
instanceId=$(aws ec2 run-instances --image-id ami-2051294a --security-group-ids $groupId --count 1 --instance-type t2.micro --key-name finalProject --query 'Instances[*].InstanceId' --output text)

#Grab the public IP
publicIpAddress=$(aws ec2 describe-instances --instance-id $instanceId --query 'Reservations[*].Instances[*].PublicIpAddress' --output text)

#This is here to wait for the AWS to catch up with the status on the backend as it may be null
while [  "$instanceStatus" == "" ]; do
	echo -e "Waiting for the AWS instance to register in the AWS datastore..."
	instanceStatus=$(aws ec2 describe-instance-status --instance-id $instanceId --query 'InstanceStatuses[*].SystemStatus.Status' --output text)
	sleep 10
done


#While loop to wait for instance to be change from "initializing" to "ok"
instanceStatus="initializing"

while [  "$instanceStatus" == "initializing" ]; do
	echo The instance is still $instanceStatus please be patient...

	instanceStatus=$(aws ec2 describe-instance-status --instance-id $instanceId --query 'InstanceStatuses[*].SystemStatus.Status' --output text)
	
	sleep 15
done

echo The instance is now $instanceStatus !
echo -e ""

echo -e "\033[0;32mInstalling httpd and php packages on remote instance. \033[0m"
ssh -tt -i ~/.ssh/finalProject.pem -l ec2-user -o StrictHostKeyChecking=no $publicIpAddress 'sudo yum -y install httpd php'
echo -e ""

echo -e "\033[0;32mStarting httpd service on remote instance. \033[0m"
ssh -tt -i ~/.ssh/finalProject.pem -l ec2-user -o StrictHostKeyChecking=no $publicIpAddress 'sudo systemctl start httpd.service'
ssh -tt -i ~/.ssh/finalProject.pem -l ec2-user -o StrictHostKeyChecking=no $publicIpAddress 'sudo systemctl status httpd'
echo -e ""

echo -e "\033[0;32mEnabling httpd to be persistant start on remote instance. \033[0m"
ssh -tt -i ~/.ssh/finalProject.pem -l ec2-user -o StrictHostKeyChecking=no $publicIpAddress 'sudo systemctl enable httpd'
echo -e ""

echo -e "\033[0;32mChanging ownership of the /var/www/html to the ec2-user on remote instance. \033[0m"
ssh -tt -i ~/.ssh/finalProject.pem -l ec2-user -o StrictHostKeyChecking=no $publicIpAddress 'sudo chown ec2-user /var/www/html'
echo -e ""

#Cloning my code repository from git for a password generating website
echo -e "\033[0;32mCloning website code from git. \033[0m"
git clone git@github.com:wbirkmaier/p2.git
echo -e ""

echo -e "\033[0;32mCopying the local project code to the /var/www/html on remote instance. \033[0m"
scp -r -i ~/.ssh/finalProject.pem -o StrictHostKeyChecking=no p2/* ec2-user@$publicIpAddress:/var/www/html/.
echo -e ""

#Create the new custom AMI
echo -e "\033[0;32mCreating a new gold AMI, this will take several minutes to complete. \033[0m"
imageId=$(aws ec2 create-image --instance-id $instanceId --name "MasterWebServer" --description "Master Web Server Image" --query 'ImageId' --output text)

#We again do this to wait for the image to get in a known state in the backend
while [  "$imageState" == "" ]; do
	echo "The image is still in an unkown state, please wait..."
	imageState=$(aws ec2 describe-images --image-id $imageId --query 'Images[*].State' --output text)
	sleep 5
done

#Now we will wait for the image to be successfull
imageState="pending"

while [  "$imageState" == "pending" ]; do
	        echo The image is still $imageState ...

		imageState=$(aws ec2 describe-images --image-id $imageId --query 'Images[*].State' --output text)
	        sleep 15
done

echo  The image is now $imageState !
echo  The gold custom image AMI id is $imageId for use with CloudFormation.
echo -e ""

#Terminate the original image
echo -e "\033[0;32mDeleting the original image. \033[0m"
aws ec2 terminate-instances --instance-ids $instanceId --output table
echo ""

echo "Remember the following information:"
echo Your Security Group ID is $groupId
echo Your Gold AMI Image ID is $imageId
echo Your PEM file for the finalProject key is in ~./ssh
