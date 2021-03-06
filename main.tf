terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "3.1.0"
    }
  }
}

resource "random_pet" "cluster" {
  keepers = {
    cluster = var.cluster_name
  }
}

resource "aws_autoscaling_group" "ecs" {
  name                 = "ecs-${var.cluster_name}-asg-${random_pet.cluster.id}"
  min_size             = var.cluster_min_size
  max_size             = var.cluster_max_size
  vpc_zone_identifier  = var.subnets
  launch_configuration = aws_launch_configuration.ecs_instance.name

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_iam_instance_profile" "ecs_instance" {
  name = "ecs_instance_profile-${random_pet.cluster.id}"
  role = aws_iam_role.ecs_instance_role.name
}

resource "aws_iam_role" "ecs_instance_role" {
  name = "ecs_instance_role-${random_pet.cluster.id}"

  assume_role_policy = <<EOF
{
  "Version": "2008-10-17",
  "Statement": [
    {
      "Sid": "",
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": [
        "sts:AssumeRole"
      ]
    }
  ]
}
EOF
}

resource "aws_iam_policy" "instance_policy" {
  name        = "ecs-instance-policy-${random_pet.cluster.id}"
  description = "ECS Instance Policy"

  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ec2:DescribeTags",
                "ecs:CreateCluster",
                "ecs:DeregisterContainerInstance",
                "ecs:DiscoverPollEndpoint",
                "ecs:Poll",
                "ecs:RegisterContainerInstance",
                "ecs:StartTelemetrySession",
                "ecs:UpdateContainerInstancesState",
                "ecs:Submit*",
                "ecr:GetAuthorizationToken",
                "ecr:BatchCheckLayerAvailability",
                "ecr:GetDownloadUrlForLayer",
                "ecr:BatchGetImage",
                "logs:CreateLogStream",
		${var.extra_instance_policy_actions}
                "logs:PutLogEvents"
            ],
            "Resource": "*"
        }
    ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "instance_policy_attach" {
  role       = aws_iam_role.ecs_instance_role.name
  policy_arn = aws_iam_policy.instance_policy.arn
}

resource "aws_launch_configuration" "ecs_instance" {
  name                 = "ecs-instance-${var.cluster_name}-${random_pet.cluster.id}"
  image_id             = var.ecs_ami
  instance_type        = var.ecs_instance_type
  key_name             = var.ecs_instance_key
  iam_instance_profile = aws_iam_instance_profile.ecs_instance.name

  user_data = <<EOF
#!/bin/bash
echo ECS_CLUSTER=${var.cluster_name} >> /etc/ecs/ecs.config
${var.extra_user_data}  
EOF

  security_groups = [aws_security_group.cluster_instance.id]

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_ecs_cluster" "cluster" {
  name = var.cluster_name
}

resource "aws_security_group" "cluster_instance" {
  name   = "ecs-cluster-${var.cluster_name}-${random_pet.cluster.id}"
  vpc_id = var.vpc_id

  ingress {
    from_port = "0"
    to_port   = "0"
    protocol  = "-1"
    self      = true
  }

  ingress {
    from_port       = "0"
    to_port         = "0"
    protocol        = "-1"
    security_groups = var.allowed_sgs
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
