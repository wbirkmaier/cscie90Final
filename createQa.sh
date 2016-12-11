#!/bin/bash
#This will provision a stack with cloudFormation named qaStack and the qaDeploy.json with the finalProject keypair.
#Wil Birkmaier

echo -e "\033[0;32mCreating your stack: \033[0m"
aws cloudformation create-stack --stack-name qaStack --template-body file://./qaDeploy.json --parameters  ParameterKey=KeyName,ParameterValue=finalProject
echo ""

echo -e "\033[0;32mThis is your stack description: \033[0m"
aws cloudformation describe-stacks
echo ""


echo -e "\033[0;32mNow checking for the ELB creations status: \033[0m"
while [  "$elbDns" == "" ]; do
	echo "Querying the stack for the ELB URL, please wait..."
	elbDns=$(aws cloudformation describe-stacks --stack-name qaStack --query 'Stacks[*].Outputs[*].OutputValue' --output text)
	sleep 10
done
echo ""

echo -e "\033[0;32mThis is your stack's resources: \033[0m"
aws cloudformation describe-stack-resources --stack-name qaStack
echo ""

#We will discover the ELBs name in the stack
elbString=$(aws cloudformation describe-stack-resources --stack-name qaStack  | grep qaStack-ElasticLoa- | cut -d ":" -f 2)

#Remove the cruft around the ELBs name
elbName=$(echo $elbString | sed -e "s/^.//" -e "s/..$//")

#Get the service state of the instances in the ELB
elbArray=$(aws elb describe-instance-health --load-balancer-name $elbName --query 'InstanceStates[].State' --output text)

#Pull the status of the first instance
elbService=$(echo $elbArray | cut -d " " -f 1)

#Now we will check the ELB in the stack and see if the first instance is in service
while [  "$elbService" == "OutOfService" ]; do
        echo "The ELB is coming into service, please wait..."
        elbArray=$(aws elb describe-instance-health --load-balancer-name $elbName --query 'InstanceStates[].State' --output text)
		elbService=$(echo $elbArray | cut -d " " -f 1)
        sleep 10
done

echo "Your ELB has now at least 1 instance in service!"
echo ""

echo -e "\033[0;32mYou can now connect to the following URL for the app: \033[0m"
echo $elbDns

