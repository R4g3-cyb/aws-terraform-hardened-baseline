terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# ==============================================================================
# RED Y VPC
# ==============================================================================

resource "aws_vpc" "vpc_principal" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "VPC-Principal-Hardened"
  }
}


resource "aws_subnet" "subred_publica" {
  vpc_id                  = aws_vpc.vpc_principal.id
  cidr_block              = var.subnet_cidr
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = false

  tags = {
    Name = "Subred-Publica-Hardened"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc_principal.id

  tags = {
    Name = "IGW-Principal"
  }
}

resource "aws_route_table" "tabla_ruteo_publica" {
  vpc_id = aws_vpc.vpc_principal.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "Tabla-Ruteo-Publica"
  }
}

resource "aws_route_table_association" "asociacion_publica" {
  subnet_id      = aws_subnet.subred_publica.id
  route_table_id = aws_route_table.tabla_ruteo_publica.id
}

# ==============================================================================
# CLOUDWATCH
# ==============================================================================

resource "aws_cloudwatch_log_group" "logs" {
  name = "logs"
  kms_key_id        = aws_kms_key.example.arn   
  retention_in_days = 365                    
}

resource "aws_iam_role" "flowlog" {
  name = "flowlog"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "vpc-flow-logs.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_role_policy" "test_policy" {
  name = "test_policy"
  role = aws_iam_role.flowlog.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams",
        
        ]
        Effect   = "Allow"
        Resource = "${aws_cloudwatch_log_group.logs.arn}:*"
      },
    ]
  })
}

resource "aws_flow_log" "example" {
  iam_role_arn    = aws_iam_role.flowlog.arn
  log_destination = aws_cloudwatch_log_group.logs.arn
  traffic_type    = "ALL"
  vpc_id          = aws_vpc.vpc_principal.id
}

# ==============================================================================
# SEGURIDAD Y FIREWALLING (SECURITY GROUPS)
# ==============================================================================

resource "aws_default_security_group" "default" {
  vpc_id = aws_vpc.vpc_principal.id 
}

module "mi_sg" {
  source     = "./modules/security_group"
  vpc_id     = aws_vpc.vpc_principal.id
  allowed_ip = var.my_ip
  sg_name    = "app-sg-"
}

data "aws_caller_identity" "current" {}

resource "aws_kms_key" "example" {
  description             = "An example symmetric encryption KMS key"
  enable_key_rotation     = true
  deletion_window_in_days = 20
}

resource "aws_kms_key_policy" "example" {
  key_id = aws_kms_key.example.id
  policy = jsonencode({
    Version = "2012-10-17"
    Id      = "key-default-1"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        },
        Action   = "kms:*"
        Resource = "*"
      }
    ]
  })
}



# ==============================================================================
# ALMACENAMIENTO (S3 BUCKET HARDENED)
# ==============================================================================

resource "aws_s3_bucket" "bucket_privado" {
#checkov:skip=CKV2_AWS_62: Practica de producción, no aplica a seguridad
#checkov:skip=CKV2_AWS_61: Practica de producción, no aplica a seguridad
#checkov:skip=CKV_AWS_144: Practica de producción, no aplica a seguridad
  bucket_prefix = "lab-privado-hardened-"
  force_destroy = true

  tags = {
    Name        = "Bucket-Privado-Hardened"
    Environment = "DevSecOps"
  }
}

resource "aws_s3_bucket" "logging" {
#checkov:skip=CKV2_AWS_62: Practica de producción, no aplica a seguridad
#checkov:skip=CKV2_AWS_61: Practica de producción, no aplica a seguridad
#checkov:skip=CKV_AWS_144: Practica de producción, no aplica a seguridad
  bucket_prefix = "access-logs-"
  force_destroy = true
}

data "aws_iam_policy_document" "logging_bucket_policy" {
  statement {
    principals {
      identifiers = ["logging.s3.amazonaws.com"]  
      type        = "Service"
    }
    actions   = ["s3:PutObject"]                   
    resources = ["${aws_s3_bucket.logging.arn}/*"] 
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]  
    }
  }
}

resource "aws_s3_bucket_policy" "logging" {
  bucket = aws_s3_bucket.logging.id
  policy = data.aws_iam_policy_document.logging_bucket_policy.json
}

resource "aws_s3_bucket_logging" "bucket_privado_logging" {
  bucket        = aws_s3_bucket.bucket_privado.id   
  target_bucket = aws_s3_bucket.logging.id          
  target_prefix = "log/"                            
}

resource "aws_s3_bucket_public_access_block" "bloqueo_publico_s3" {
  bucket = aws_s3_bucket.bucket_privado.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "bloqueo_publico_s3_2" {
  bucket = aws_s3_bucket.logging.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cifrado_s3" {
  bucket = aws_s3_bucket.bucket_privado.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
      kms_master_key_id = aws_kms_key.example.arn
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cifrado_s3_2" {
  bucket = aws_s3_bucket.logging.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
      kms_master_key_id = aws_kms_key.example.arn
    }
  }
}

resource "aws_s3_bucket_versioning" "versionado_s3" {
  bucket = aws_s3_bucket.bucket_privado.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_versioning" "versionado_s3_2" {
  bucket = aws_s3_bucket.logging.id

  versioning_configuration {
    status = "Enabled"
  }
}

# ==============================================================================
# COMPUTO (EC2 HARDENED + IMDSv2)
# ==============================================================================

data "aws_ami" "ubuntu_latest" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_instance" "servidor_prueba" {
#checkov:skip=CKV2_AWS_41: Una ec2 es mas segura sin un rol iam porque no tiene credenciales que puedan ser comprometidas
#checkov:skip=CKV_AWS_135: Un EBS optimizado no es importante para la seguridad
  ami                         = data.aws_ami.ubuntu_latest.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.subred_publica.id
  vpc_security_group_ids = [module.mi_sg.sg_id]
  associate_public_ip_address = false
  monitoring                  = true

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    encrypted = true
  }

  tags = {
    Name = "Servidor-Prueba-Hardened"
  }
}