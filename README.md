# terraform-ddc-create-nodes
Terraform to create DDC nodes

This repo contains Terraform templates to create new nodes on AWS split across availability zones ready to deploy on using Ansible (or similar automation like salt-ssh etc).

I've used an AMI for Centos 7 based in AWS London, and added a second disk for each node for devicemapper thinpool storage using LVM as the backend storage for the Docker engine.

An S3 bucket is created for the DTR stared storage.  The DTR cluster instances are created with an IAM instance profile associated with an IAM role and associated policy to give the storage access required.
