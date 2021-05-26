provider "aws" {
  region = var.region
}

resource "aws_vpc" "this" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  instance_tenancy     = "default"
  tags                 = var.tags
}

data "aws_availability_zones" "this" {
  state = "available"
}

resource "aws_subnet" "this" {
  availability_zone = data.aws_availability_zones.this.names[0]
  vpc_id            = aws_vpc.this.id
  cidr_block        = "10.0.1.0/24"
  tags              = var.tags
}

resource "aws_subnet" "this_b" {
  availability_zone = data.aws_availability_zones.this.names[1]
  vpc_id            = aws_vpc.this.id
  cidr_block        = "10.0.2.0/24"
  tags              = var.tags
}


resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = var.tags
}

resource "aws_route_table" "this" {
  vpc_id = aws_vpc.this.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }
  tags = var.tags
}

resource "aws_route_table_association" "this" {
  subnet_id      = aws_subnet.this.id
  route_table_id = aws_route_table.this.id
}

resource "aws_route_table_association" "this_b" {
  subnet_id      = aws_subnet.this_b.id
  route_table_id = aws_route_table.this.id
}

resource "aws_security_group" "this" {
  name        = "sg_${var.organization}_${var.project}"
  description = "Allow TLS inbound traffic"
  vpc_id      = aws_vpc.this.id

  ingress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = var.tags
}


resource "aws_cloudwatch_log_group" "this" {
  name              = "logs_${var.organization}_${var.project}"
  retention_in_days = 3
  tags              = var.tags
}

resource "aws_ecs_cluster" "this" {
  name = "cluster_${var.organization}_${var.project}"
  tags = var.tags
  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

data "aws_iam_role" "this" {
  name = var.aws_iam_role
}

resource "aws_ecs_task_definition" "this" {
  family                   = "family-ecs-${var.organization}-${var.project}"
  memory                   = 2048
  cpu                      = 1024
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  task_role_arn            = data.aws_iam_role.this.arn
  execution_role_arn       = data.aws_iam_role.this.arn
  container_definitions    = <<EOF
  [
    {
      "name": "${var.project}",
      "image": "owncloud/server",
      "cpu": 0,
      "essential": true,
      "logConfiguration": {
        "logDriver": "awslogs",
        "secretOptions": [],
        "options": {
          "awslogs-group": "${aws_cloudwatch_log_group.this.id}",
          "awslogs-region": "${var.region}",
          "awslogs-stream-prefix": "${var.project}"
        }
      },
      "portMappings": [
        {
          "hostPort": 8080,
          "protocol": "tcp",
          "containerPort": 8080
        }
      ],
      "mountPoints": [
        {
          "containerPath": "/mnt/data/",
          "sourceVolume": "persistencia"
        }
      ],
      "environment": [
        {
          "name": "OWNCLOUD_ADMIN_USERNAME",
          "value": "admin"
        },
        {
          "name": "OWNCLOUD_ADMIN_PASSWORD",
          "value": "admin"
        },
        {
          "name": "OWNCLOUD_MYSQL_UTF8MB",
          "value": "true"
        },
        {
          "name": "OWNCLOUD_DB_HOST",
          "value": "${aws_db_instance.this.address}"
        },     
        {
          "name": "OWNCLOUD_DB_TYPE",
          "value": "${aws_db_instance.this.engine}"
        },  
        {
          "name": "OWNCLOUD_DB_NAME",
          "value": "${aws_db_instance.this.name}"
        },  
        {
          "name": "OWNCLOUD_DB_USERNAME",
          "value": "${aws_db_instance.this.username}"
        },
        {
          "name": "OWNCLOUD_DB_PASSWORD",
          "value": "${aws_db_instance.this.password}"
        },
        {
          "name": "OWNCLOUD_REDIS_ENABLED",
          "value": "true"
        },
        {
          "name": "OWNCLOUD_REDIS_HOST",
          "value": "${aws_elasticache_replication_group.this.primary_endpoint_address}"
        },
        {
          "name": "OWNCLOUD_DOMAIN",
          "value": "localhost"
        }
      ]
    }
  ]
  EOF
  tags                     = var.tags
  volume {
    name = "persistencia"

    efs_volume_configuration {
      file_system_id     = module.efs_owncloud.id
      transit_encryption = "ENABLED"
    }
  }
}

resource "aws_ecs_service" "this" {
  name                               = "service_${var.organization}_${var.project}"
  cluster                            = aws_ecs_cluster.this.name
  task_definition                    = aws_ecs_task_definition.this.arn
  desired_count                      = 1
  deployment_maximum_percent         = 200
  deployment_minimum_healthy_percent = 100
  launch_type                        = "FARGATE"
  scheduling_strategy                = "REPLICA"
  tags                               = var.tags
  network_configuration {
    security_groups  = [aws_security_group.this.id]
    subnets          = [aws_subnet.this.id, aws_subnet.this_b.id]
    assign_public_ip = true
  }
}

resource "aws_db_subnet_group" "this" {
  name       = "db_subnet_${var.organization}_${var.project}"
  subnet_ids = [aws_subnet.this.id, aws_subnet.this_b.id]
  tags       = var.tags
}

resource "aws_security_group" "this_b" {
  name   = "rds_sg_${var.organization}_${var.project}"
  vpc_id = aws_vpc.this.id

  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = [aws_subnet.this.cidr_block, aws_subnet.this_b.cidr_block]

  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = var.tags
}

resource "aws_db_instance" "this" {
  identifier             = "db-${var.organization}-${var.project}-1"
  allocated_storage      = 10
  engine                 = "mysql"
  engine_version         = "5.7"
  instance_class         = "db.t2.micro"
  name                   = "db_${var.organization}_${var.project}"
  username               = var.db_username
  password               = var.db_password
  db_subnet_group_name   = aws_db_subnet_group.this.id
  vpc_security_group_ids = [aws_security_group.this_b.id]
  skip_final_snapshot    = true
  tags                   = var.tags
}

resource "aws_elasticache_subnet_group" "this" {
  name       = "cache-subnet${var.organization}-${var.project}"
  subnet_ids = [aws_subnet.this.id, aws_subnet.this_b.id]
  tags       = var.tags
}

resource "aws_elasticache_parameter_group" "this" {
  name   = "cache-sg-${var.organization}-${var.project}"
  family = "redis6.x"
}

resource "aws_elasticache_replication_group" "this" {
  replication_group_id          = "id-1-cache-${var.organization}-${var.project}"
  replication_group_description = "Terraform-managed ElastiCache replication group for ${var.organization}-${var.project}"
  number_cache_clusters         = 2
  node_type                     = "cache.t2.micro"
  automatic_failover_enabled    = true
  availability_zones            = [data.aws_availability_zones.this.names[0], data.aws_availability_zones.this.names[1]]
  engine                        = "redis"
  port                          = 6379
  parameter_group_name          = "default.redis6.x"
  subnet_group_name             = aws_elasticache_subnet_group.this.id
  security_group_ids            = [aws_security_group.this.id]
  tags                          = var.tags
}

module "efs_owncloud" {
  source          = "git::https://gitlab.wiedii.co/puma/terraform-efs.git?ref=1.0.3"
  name            = "efs_${var.organization}_${var.project}"
  subnet_ids      = [aws_subnet.this.id, aws_subnet.this_b.id]
  security_groups = [aws_security_group.this.id]
  access_points   = ["/owncloud"]
  tags            = var.tags
}