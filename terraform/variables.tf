variable "aws_profile" {
  description = "The AWS profile to use."
  type        = string
  default = "default"
}

variable "aws_region" {
  description = "The AWS Region to deploy resources to."
  type        = string
}

variable "vpc_id" {
  description = "The VPC ID to deploy resources to."
  type        = string
}

variable "subnet_id" {
  description = "The subnet ID to deploy resources to. If using capacity block reservation, make sure the subnet is in the corresponding Availabiity Zone as the reservation."
  type        = string
}

# the capacity block reservation id as input variable
variable "capacity_reservation_id" {
  description = "The ID of the Capacity Block Reservation."
  type = string
}
