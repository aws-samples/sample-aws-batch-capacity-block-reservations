terraform {
  required_providers {
    awscc = {
      source = "hashicorp/awscc"
      version = "1.28.0"
    }
    random = {
      source = "hashicorp/random"
      version = "~> 3"
    }
  }
}

provider "awscc" {
  # Configuration options
  region = var.aws_region
  profile = var.aws_profile
}

resource "random_string" "suff" {
  length = 5
  special = false
  upper = true
  numeric = true
}

locals {
  id_suffix = random_string.suff

  tags = [
    {
      key = "ManagedBy",
      value = "Terraform"
    },
    {
      key = "Project",
      value = "BatchCapacityBlockExample"
    }
  ] 
  batch_tags = {
    ManagedBy = "Terraform"
    Project = "BatchCapacityBlockExample"
  }
}

## Existing VPC and subnet for the Capacity Block for ML Reservation
data "awscc_ec2_vpc" "selected" {
  id = var.vpc_id
}
data "awscc_ec2_subnet" "selected" {
  id = var.subnet_id
}

## The capacity reservation. This will fail if the CBR does not exist.
data "awscc_ec2_capacity_reservation" "cbr_reservation" {
  id = var.capacity_reservation_id
}

# AWS Batch IAM security group for internode communication. Security group ingress rule to allow all traffic from the same security group.
resource "awscc_ec2_security_group" "sg" {
  group_description = "EFA security group"
  vpc_id = data.awscc_ec2_vpc.selected.id
  tags = local.tags
}
resource "awscc_ec2_security_group_ingress" "sg_ingress" {
  ip_protocol = "-1"
  group_id = resource.awscc_ec2_security_group.sg.id
  source_security_group_id = resource.awscc_ec2_security_group.sg.id
}

resource "awscc_ec2_launch_template" "cbr_p4d_lt" {
  launch_template_name = "cbr_p4d_launch_template_${local.id_suffix.result}"
  launch_template_data = {
    instance_market_options = {
      market_type = "capacity-block"
    }
    capacity_reservation_specification = {
      capacity_reservation_target = {
        capacity_reservation_id = var.capacity_reservation_id
      }
    }
    network_interfaces = concat(
      [
        {
          description = "EFA interface 0"
          interface_type = "efa" 
          network_card_index = 0
          device_index = 0
          delete_on_termination = true
          groups = [resource.awscc_ec2_security_group.sg.id]
        }
      ],
      [ for i in range(1,4):
        {
          description = "EFA interface ${i}"
          interface_type = "efa-only"
          network_card_index = i
          device_index = 1
          delete_on_termination = true
          groups = [resource.awscc_ec2_security_group.sg.id]
        }
      ]
    )
  }
}

resource "awscc_ec2_launch_template" "cbr_p5_lt" {
  launch_template_name = "cbr_p5_launch_template_${local.id_suffix.result}"
  launch_template_data = {
    instance_market_options = {
      market_type = "capacity-block"
    }
    capacity_reservation_specification = {
      capacity_reservation_target = {
        capacity_reservation_id = var.capacity_reservation_id
      }
    }
    network_interfaces = concat(
      [
        {
          description = "EFA interface 0"
          interface_type = "efa" 
          network_card_index = 0
          device_index = 0
          delete_on_termination = true
          groups = [resource.awscc_ec2_security_group.sg.id]
        }
      ],
      [ for i in range(1,32):
        {
          description = "EFA interface ${i}"
          interface_type = i % 4 == 0 ? "efa" : "efa-only"
          network_card_index = i
          device_index = 1
          delete_on_termination = true
          groups = [resource.awscc_ec2_security_group.sg.id]
        }
      ]
    )
  }
}

# AWS Batch EC2 instance role and instance profile for AWS Batch nodes. These permissions are used to enable the EC2 instance to register with and join the underlying ECS cluster.
resource "awscc_iam_role" "batch_instance_role" {
  role_name = "batch_instance_role_${local.id_suffix.result}"
  assume_role_policy_document = jsonencode({
    "Version" = "2012-10-17",
    "Statement" = [
      {
        "Effect" = "Allow",
        "Principal" = {
          "Service" = "ec2.amazonaws.com"
        },
        "Action" = "sts:AssumeRole"
      }
    ]
  })
  managed_policy_arns = [
    "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
  ]
  tags = local.tags
}
resource "awscc_iam_instance_profile" "batch_instance_profile" {
  instance_profile_name = "batch_instance_profile_${local.id_suffix.result}"
  roles = [
    resource.awscc_iam_role.batch_instance_role.role_name
  ]
}

# AWS Batch ECS task execution role. This role is used by the ECS agent to pull and start the container.
resource "awscc_iam_role" "ecs_execution_role" {
  role_name = "ecs_execution_role_${local.id_suffix.result}"
  assume_role_policy_document = jsonencode({
    "Version" = "2012-10-17",
    "Statement" = [
      {
        "Effect" = "Allow",
        "Principal" = {
          "Service" = "ecs-tasks.amazonaws.com"
        },
        "Action" = "sts:AssumeRole"
      }
    ]
  })
  managed_policy_arns = [
    "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
  ]
  tags = local.tags
}

# AWS Batch job role, defining the permissions that the running container has across AWS resources. If you need additional permissions for your job at runtime, this is where you give those permissions.
resource "awscc_iam_role" "batch_job_role" {
  role_name = "batch_job_role_${local.id_suffix.result}"
  assume_role_policy_document = jsonencode({
    "Version" = "2012-10-17",
    "Statement" = [
      {
        "Effect" = "Allow",
        "Principal" = {
          "Service" = "ecs-tasks.amazonaws.com"
        },
        "Action" = "sts:AssumeRole"
      }
    ]
  })
  managed_policy_arns = [
    "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
  ]
  tags = local.tags
}

## AWS Batch compute enviornment for the Capacity Blocks for ML reservation.
resource "awscc_batch_compute_environment" "cbrP5CE" {
  type = "MANAGED"
  compute_environment_name = "cbrP5CE-${local.id_suffix.result}"
  replace_compute_environment = false
  compute_resources = {
    type = "EC2"
    ec_2_configuration = [{
      image_type = "ECS_AL2_NVIDIA"
    }]
    minv_cpus = 192
    maxv_cpus = 384
    instance_role = resource.awscc_iam_instance_profile.batch_instance_profile.arn
    ecs_execution_role =  resource.awscc_iam_role.ecs_execution_role.arn
    launch_template = {
      launch_template_id = awscc_ec2_launch_template.cbr_p5_lt.id
    }
    instance_types = ["p5.48xlarge"]
    subnets = [ data.awscc_ec2_subnet.selected.id ]
    tags = {
      "Project" =  "BatchCapacityBlockExample"
    }
  }
  tags = local.batch_tags
}

# AWS Batch job queue for jobs that target the CB for ML reservation.
resource "awscc_batch_job_queue" "cbrP5JQ" {
  job_queue_name = "cbrJQ-${local.id_suffix.result}"
  compute_environment_order = [
    {
      compute_environment = resource.awscc_batch_compute_environment.cbrP5CE.id
      order = 1
    }
  ]
  priority = 1
  state = "ENABLED"
  tags = local.batch_tags
}

# AWS Batch job definition for a single instance NCCL test. 
resource "awscc_batch_job_definition" "cbr-p5-nccl-test" {
  job_definition_name = "cbr-p5-nccl-test-${local.id_suffix.result}"
  type = "container"
  propagate_tags = true
  retry_strategy = {
    attempts = 1
  }
  ecs_properties = {
    task_properties = [
      {
        execution_role_arn = resource.awscc_iam_role.ecs_execution_role.arn 
        task_role_arn = resource.awscc_iam_role.batch_job_role.arn
        containers = [
          {
            name = "application"
            image = "public.ecr.aws/hpc-cloud/nccl-tests:latest"

            command = [
              "/opt/amazon/openmpi/bin/mpirun",
              "--allow-run-as-root",
              "--tag-output",
              "-np",
              "2",
              "-N",
              "2",
              "--bind-to",
              "none",
              "-x",
              "PATH",
              "-x",
              "LD_LIBRARY_PATH",
              "-x",
              "NCCL_DEBUG=INFO",
              "-x",
              "NCCL_BUFFSIZE=8388608",
              "-x",
              "NCCL_P2P_NET_CHUNKSIZE=524288",
              "-x",
              "NCCL_TUNER_PLUGIN=/opt/aws-ofi-nccl/install/lib/libnccl-ofi-tuner.so",
              "--mca",
              "pml",
              "^cm,ucx",
              "--mca",
              "btl",
              "tcp,self",
              "--mca",
              "btl_tcp_if_exclude",
              "lo,docker0,veth_def_agent",
              "/opt/nccl-tests/build/all_reduce_perf",
              "-b",
              "8",
              "-e",
              "16G",
              "-f",
              "2",
              "-g",
              "1",
              "-c",
              "1",
              "-n",
              "100"
            ]
            environment = [
              {
                "name": "LD_LIBRARY_PATH",
                "value": "/opt/amazon/openmpi/lib:/opt/nccl/build/lib:/opt/amazon/efa/lib:/opt/aws-ofi-nccl/install/lib:/usr/local/nvidia/lib:$LD_LIBRARY_PATH"
              },
              {
                "name": "PATH",
                "value": "$PATH:/opt/amazon/efa/bin:/usr/bin"
              }
            ]
            resource_requirements = [
              {
                type = "VCPU",
                value = "192"
              },
              {
                type = "MEMORY",
                value = "1049000"
              },
              {
                type = "GPU",
                value = "8"
              }
            ]
            ulimits = [
              {
                "name": "memlock",
                "hard_limit": -1,
                "soft_limit": -1
              },
              {
                "name": "stack",
                "hard_limit": 67108864,
                "soft_limit": 67108864
              },
              {
                "name": "nofile",
                "hard_limit": 1024000,
                "soft_limit": 1024000
              }                
            ]
            linux_parameters = {
              shared_memory_size = 49152,
              devices = [
                for i in range(32): 
                {
                  host_path = "/dev/infiniband/uverbs${i}",
                  container_path = "/dev/infiniband/uverbs${i}",
                  permissions = ["READ","WRITE","MKNOD"]
                }
              ]
            }
          }
        ]
      }
    ]
  }
}

# Output the AWS CLI command used to run the example job.
output "run-job-cmd" {
  description = "The AWS CLI command that you can use to run the example job definition."
  value = "JOB_ID=$(aws --profile ${var.aws_profile} --region ${var.aws_region} batch submit-job --job-queue ${resource.awscc_batch_job_queue.cbrP5JQ.id} --job-definition ${resource.awscc_batch_job_definition.cbr-p5-nccl-test.id} --job-name runNcclTest --query jobId --output text)\necho $JOB_ID"
}
