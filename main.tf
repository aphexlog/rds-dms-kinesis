provider "aws" {
  region = "us-east-1"
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
          "ec2:DescribeNetworkInterfaces"
        ],
        Resource = "*"
      }
    ]
  })
}

resource "aws_security_group" "rds_dms_kinesis_security_group" {
  name        = "rds-dms-kinesis-security-group"
  description = "Allow inbound traffic"
  vpc_id      = "vpc-5f9fb825"

  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_db_instance" "rds_dms_kinesis_rds_instance" {
  allocated_storage      = 20
  engine                 = "mysql"
  engine_version         = "8.0"
  instance_class         = "db.r5d.large"
  username               = "admin"
  password               = "password"
  parameter_group_name   = "default.mysql8.0"
  skip_final_snapshot    = true
  vpc_security_group_ids = [aws_security_group.rds_dms_kinesis_security_group.id]

  depends_on = [
    aws_kinesis_stream.rds_dms_kinesis_stream,
  ]
}

resource "aws_kinesis_stream" "rds_dms_kinesis_stream" {
  name             = "rds_dms_kinesis_stream"
  shard_count      = 1
  retention_period = 24
}

resource "aws_dms_replication_instance" "rds_dms_kinesis_dms_instance" {
  replication_instance_class = "dms.t3.micro"
  allocated_storage          = 100
  engine_version             = "3.5.1"
  replication_instance_id    = "rds-dms-kinesis-dms-instance"
  vpc_security_group_ids = [aws_security_group.rds_dms_kinesis_security_group.id]
  replication_subnet_group_id = aws_dms_replication_subnet_group.rds_dms_kinesis_subnet_group.replication_subnet_group_id
  depends_on = [
    aws_kinesis_stream.rds_dms_kinesis_stream,
  ]
}

resource "aws_dms_endpoint" "rds_dms_kinesis_source_endpoint" {
  endpoint_id   = "rds-dms-kinesis-source-endpoint"
  endpoint_type = "source"
  engine_name   = "mysql"
  username      = aws_db_instance.rds_dms_kinesis_rds_instance.username
  password      = aws_db_instance.rds_dms_kinesis_rds_instance.password
  server_name   = aws_db_instance.rds_dms_kinesis_rds_instance.address
  port          = 3306
  database_name = "source_database"
}

resource "aws_dms_replication_subnet_group" "rds_dms_kinesis_subnet_group" {
  replication_subnet_group_id = "rds-dms-kinesis-subnet-group"
  subnet_ids = ["subnet-744c4613", "subnet-54b7e96a"]
  replication_subnet_group_description = "Replication subnet group for RDS DMS Kinesis"

  tags = {
    Name = "rds-dms-kinesis-subnet-group"
  }
}

resource "aws_dms_endpoint" "rds_dms_kinesis_target_endpoint" {
  endpoint_id   = "rds-dms-kinesis-target-endpoint"
  endpoint_type = "target"
  engine_name   = "kinesis"
  kinesis_settings {
    message_format = "json"
    stream_arn     = aws_kinesis_stream.rds_dms_kinesis_stream.arn
    service_access_role_arn = aws_iam_role.dms_vpc_role.arn
  }

  depends_on = [ aws_kinesis_stream.rds_dms_kinesis_stream ]
}

resource "aws_dms_replication_task" "rds_dms_kinesis_replication_task" {
  replication_task_id = "rds-dms-kinesis-task"
  source_endpoint_arn = aws_dms_endpoint.rds_dms_kinesis_source_endpoint.endpoint_arn
  target_endpoint_arn = aws_dms_endpoint.rds_dms_kinesis_target_endpoint.endpoint_arn
  migration_type      = "cdc"
  table_mappings      = file("table-mappings.json")
  # replication_task_settings = file("task-settings.json")
  replication_instance_arn = aws_dms_replication_instance.rds_dms_kinesis_dms_instance.replication_instance_arn

  depends_on = [
    aws_dms_endpoint.rds_dms_kinesis_source_endpoint,
    aws_dms_endpoint.rds_dms_kinesis_target_endpoint
  ]
}
