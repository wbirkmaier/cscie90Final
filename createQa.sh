#!/bin/bash
#This will provision a stack with cloudFormation named qaStack and the qaDeploy.json with the finalProject keypair.
#Wil Birkmaier

echo -e "\033[0;32mCreating your stack: \033[0m"
aws cloudformation create-stack --stack-name qaStack --template-body file://./qaDeploy.json --parameters  ParameterKey=KeyName,ParameterValue=finalProject
echo ""

echo -e "\033[0;32mThis is your stack description: \033[0m"
aws cloudformation describe-stacks
echo ""

while [  "$elbDns" == "" ]; do
	echo "Querying the stack for the ELB URL, please wait..."
	elbDns=$(aws cloudformation describe-stacks --stack-name qaStack --query 'Stacks[*].Outputs[*].OutputValue' --output text)
	sleep 5
done
echo ""


echo This is the ELB for the stack $elb

