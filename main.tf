provider "aws" {
  region = var.region
}

resource "aws_iam_role" "dms_vpc_role" {
  name = "dms-vpc-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "dms.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "dms_vpc_role_policy" {
  name = "dms-vpc-role-policy"
  role = aws_iam_role.dms_vpc_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "kinesis:DescribeStream",
          "kinesis:GetRecords",
          "kinesis:GetShardIterator",
          "kinesis:ListStreams",
          "kinesis:PutRecord",
          "kinesis:PutRecords",
          "ec2:Describe*",
          "ec2:CreateNetworkInterface",
          "ec2:DeleteNetworkInterface",
          "ec2:DescribeNetworkInterfaces",
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ],
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "dms_vpc_role_policy_attachment" {
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
  role       = aws_iam_role.dms_vpc_role.name
}

resource "aws_security_group" "dms_security_group" {
  name        = "dms-security-group"
  description = "Allow inbound and outbound traffic for DMS"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "DMS-Migration-SG"
  }
}

resource "aws_db_instance" "postgresql_rds_instance" {
  allocated_storage      = 20
  engine                 = "postgres"
  engine_version         = "16.3"
  instance_class         = "db.r5d.large"
  username               = var.db_username
  password               = var.db_password
  parameter_group_name   = "default.postgres16"
  skip_final_snapshot    = true
  publicly_accessible    = true
  vpc_security_group_ids = [aws_security_group.dms_security_group.id]
  db_name                = var.db_name

}

resource "aws_kinesis_stream" "dms_kinesis_stream" {
  name             = "dms_kinesis_stream"
  retention_period = 24

  stream_mode_details {
    stream_mode = "ON_DEMAND"
  }
}

resource "aws_dms_replication_subnet_group" "dms_replication_subnet_group" {
  replication_subnet_group_id          = "dms-replication-subnet-group"
  subnet_ids                           = [var.subnet_ids[0], var.subnet_ids[1]]
  replication_subnet_group_description = "Replication subnet group for DMS"

  tags = {
    Name = "dms-replication-subnet-group"
  }
}

resource "aws_dms_replication_instance" "dms_replication_instance" {
  replication_instance_class  = "dms.t3.micro"
  apply_immediately           = true
  allocated_storage           = 100
  engine_version              = "3.5.1"
  replication_instance_id     = "dms-replication-instance"
  vpc_security_group_ids      = [aws_security_group.dms_security_group.id]
  replication_subnet_group_id = aws_dms_replication_subnet_group.dms_replication_subnet_group.replication_subnet_group_id
  publicly_accessible         = true

  depends_on = [aws_dms_replication_subnet_group.dms_replication_subnet_group,
  aws_security_group.dms_security_group]
}

resource "aws_dms_endpoint" "postgresql_source_endpoint" {
  endpoint_id   = "postgresql-source-endpoint"
  endpoint_type = "source"
  engine_name   = "postgres"
  username      = aws_db_instance.postgresql_rds_instance.username
  password      = aws_db_instance.postgresql_rds_instance.password
  server_name   = aws_db_instance.postgresql_rds_instance.address
  port          = 3306
  database_name = var.db_name

  depends_on = [aws_db_instance.postgresql_rds_instance]
}

resource "aws_dms_endpoint" "kinesis_target_endpoint" {
  endpoint_id   = "kinesis-target-endpoint"
  endpoint_type = "target"
  engine_name   = "kinesis"

  kinesis_settings {
    message_format          = "json"
    stream_arn              = aws_kinesis_stream.dms_kinesis_stream.arn
    service_access_role_arn = aws_iam_role.dms_vpc_role.arn
  }

  depends_on = [aws_kinesis_stream.dms_kinesis_stream]
}

resource "aws_dms_replication_task" "dms_replication_task" {
  replication_task_id       = "dms-replication-task"
  source_endpoint_arn       = aws_dms_endpoint.postgresql_source_endpoint.endpoint_arn
  target_endpoint_arn       = aws_dms_endpoint.kinesis_target_endpoint.endpoint_arn
  migration_type            = "full-load-and-cdc"
  table_mappings            = file("table-mappings.json")
  replication_task_settings = file("task-settings.json")
  replication_instance_arn  = aws_dms_replication_instance.dms_replication_instance.replication_instance_arn

  depends_on = [
    aws_dms_replication_instance.dms_replication_instance,
    aws_dms_endpoint.postgresql_source_endpoint,
    aws_dms_endpoint.kinesis_target_endpoint
  ]
}

output "aws_db_instance" {
  value = aws_db_instance.postgresql_rds_instance.address
}
