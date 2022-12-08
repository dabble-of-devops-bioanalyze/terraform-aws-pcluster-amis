##################################################
# Variables
# This file has various groupings of variables
##################################################

##################################################
# AWS
##################################################

variable "region" {
  type        = string
  default     = "us-east-1"
  description = "AWS Region"
}

variable "subnet_id" {
  type = string
}

variable "security_group_ids" {
  type    = list(string)
  default = []
}

variable "ami_id" {
  type    = string
  default = ""
}

variable "instance_type" {
  type    = string
  default = "t3a.medium"
}

#TODO change this to map of name/value
variable "deep_learning_amis" {
  description = "List of DeepLearning AMIs to build additional pcluster images."
  default     = [
    "Deep Learning AMI (Amazon Linux 2) Version 61*",
    "Deep Learning AMI GPU PyTorch 1* (Amazon Linux 2) 2022*",
  ]
}

variable "image_recipe_version" {
  type    = string
  default = "1.0.0"
}

variable "ami_name" {
  description = "Name to prepend to the created ami. Default is to use the context id."
  default     = ""
}

##################################################
# Software Version Variables
##################################################

variable "pcluster_version" {
  default = "3.3.1"
}

variable "additional_component_arns" {
  default = []
}
