# AWS Hardened Web Infrastructure with Terraform & DevSecOps Auditing

[![Terraform](https://img.shields.io/badge/IaC-Terraform-623CE4?logo=terraform&logoColor=white)](https://www.terraform.io/)
[![AWS](https://img.shields.io/badge/Cloud-AWS-232F3E?logo=amazon-aws&logoColor=white)](https://aws.amazon.com/)
[![Security](https://img.shields.io/badge/Audited_by-Trivy-1976D2?logo=aqua&logoColor=white)](https://trivy.dev/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

Este repositorio contiene la definición en código (Infrastructure as Code) de una arquitectura web desacoplada y endurecida en Amazon Web Services (AWS), aplicando principios de **Least Privilege**, defensas contra vectores de ataque comunes en la nube (como SSRF hacia metadatos) y auditoría estática de seguridad automatizada con **Trivy**.

---

## 🏛️ Diagrama de Arquitectura

```text
                                     VPC (10.0.0.0/16)
 ┌─────────────────────────────────────────────────────────────────────────────────────────┐
 │                                                                                         │
 │   Internet Gateway                                                                      │
 │          │                                                                              │
 │          ▼                                                                              │
 │   Public Subnet (10.0.1.0/24)                                                           │
 │   ┌─────────────────────────────────────────────────────────────────────────────────┐   │
 │   │                                                                                 │   │
 │   │   Security Group (Ingress: TCP 80/443/22 | Egress: TCP 80/443 only)             │   │
 │   │   ┌─────────────────────────────────────────────────────────────────────────┐   │   │
 │   │   │                                                                         │   │   │
 │   │   │   EC2 Instance (Ubuntu 22.04 LTS / Nginx)                               │   │   │
 │   │   │   ├── IMDSv2 Enforced (Session tokens required, hop-limit=1)            │   │   │
 │   │   │   ├── Root EBS Volume (Encrypted via KMS/AES-256)                       │   │   │
 │   │   │   └── IAM Instance Profile (Least Privilege S3 Access)                  │   │   │
 │   │   │                               │                                         │   │   │
 │   │   └───────────────────────────────┼─────────────────────────────────────────┘   │   │
 │   │                                   │ (ReadOnly API Calls)                        │   │
 │   └───────────────────────────────────┼─────────────────────────────────────────────┘   │
 │                                       │                                                 │
 └───────────────────────────────────────┼─────────────────────────────────────────────────┘
                                         ▼
                 ┌─────────────────────────────────────────────────┐
                 │  Private S3 Bucket (SSE-S3 AES-256 Encrypted)   │
                 │  └── Public Access Block (All 4 flags enabled)  │
                 └─────────────────────────────────────────────────┘


[![Terraform](https://img.shields.io/badge/IaC-Terraform-623CE4?logo=terraform&logoColor=white)](https://www.terraform.io/)
[![AWS](https://img.shields.io/badge/Cloud-AWS-232F3E?logo=amazon-aws&logoColor=white)](https://aws.amazon.com/)
[![Security](https://img.shields.io/badge/Audited_by-Trivy-1976D2?logo=aqua&logoColor=white)](https://trivy.dev/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

This repository contains the Infrastructure as Code (IaC) implementation for a decoupled, production-hardened web architecture on Amazon Web Services (AWS). It emphasizes **Least Privilege Access**, proactive mitigation against common cloud attack vectors (such as SSRF-based metadata exfiltration), and automated static security analysis using **Trivy**.

---

## 🏛️ Architecture Diagram

```text
                                     VPC (10.0.0.0/16)
 ┌─────────────────────────────────────────────────────────────────────────────────────────┐
 │                                                                                         │
 │   Internet Gateway                                                                      │
 │          │                                                                              │
 │          ▼                                                                              │
 │   Public Subnet (10.0.1.0/24)                                                           │
 │   ┌─────────────────────────────────────────────────────────────────────────────────┐   │
 │   │                                                                                 │   │
 │   │   Security Group (Ingress: TCP 80/443/22 | Egress: TCP 80/443 only)             │   │
 │   │   ┌─────────────────────────────────────────────────────────────────────────┐   │   │
 │   │   │                                                                         │   │   │
 │   │   │   EC2 Instance (Ubuntu 22.04 LTS / Nginx)                               │   │   │
 │   │   │   ├── IMDSv2 Enforced (Session tokens required, hop-limit=1)            │   │   │
 │   │   │   ├── Root EBS Volume (Encrypted via KMS/AES-256)                       │   │   │
 │   │   │   └── IAM Instance Profile (Least Privilege S3 Access)                  │   │   │
 │   │   │                               │                                         │   │   │
 │   │   └───────────────────────────────┼─────────────────────────────────────────┘   │   │
 │   │                                   │ (ReadOnly API Calls)                        │   │
 │   └───────────────────────────────────┼─────────────────────────────────────────────┘   │
 │                                       │                                                 │
 └───────────────────────────────────────┼─────────────────────────────────────────────────┘
                                         ▼
                 ┌─────────────────────────────────────────────────┐
                 │  Private S3 Bucket (SSE-S3 AES-256 Encrypted)   │
                 │  └── Public Access Block (All 4 flags enabled)  │
                 └─────────────────────────────────────────────────┘

## 🛡️ Security Hardening & Mitigations

### 1. Enforcing IMDSv2 on EC2 (SSRF Mitigation)
By default, AWS allows fallback to IMDSv1 (Instance Metadata Service v1), which responds to simple unauthenticated HTTP GET requests directed at `169.254.169.254`. If an application running on the instance suffers from a Server-Side Request Forgery (SSRF) flaw, an attacker could steal temporary IAM instance credentials.
* **Mitigation:** Configured the `metadata_options` block with `http_tokens = "required"` and `http_put_response_hop_limit = 1`. This requires a PUT request to acquire a session token prior to querying metadata and prevents traversal through misconfigured reverse proxies/WAFs.

### 2. Strict Egress Filtering
Rather than relying on the standard permissive `0.0.0.0/0` outbound rule across all ports and protocols:
* **Mitigation:** Removed the wildcard `protocol = "-1"` egress rule and defined explicit egress paths restricted strictly to TCP ports **80 (HTTP)** and **443 (HTTPS)**. This prevents compromised compute instances from opening arbitrary reverse shells or exfiltrating data over unmonitored ports and protocols.

### 3. Encryption at Rest
* **Root EBS Volume:** Configured `encrypted = true` on the `root_block_device` block, ensuring temporary swap files, application files, and local logs are encrypted at rest.
* **S3 Bucket:** Server-side encryption enabled by default via `aws_s3_bucket_server_side_encryption_configuration` using the standard `AES256` (SSE-S3) algorithm.

### 4. S3 Public Access Prevention
* Applied the `aws_s3_bucket_public_access_block` resource with all restrictive flags enforced:
  * `block_public_acls = true`
  * `ignore_public_acls = true`
  * `block_public_policy = true`
  * `restrict_public_buckets = true`

### 5. IAM Principle of Least Privilege
* Attached an IAM instance profile providing read-only permissions (`s3:GetObject`, `s3:ListBucket`) scoped exclusively to the project's designated S3 bucket ARN, avoiding wildcard (`*`) access and eliminating hardcoded access keys on disk.

---

## 🔍 DevSecOps Audit Report (Trivy)

Static configuration analysis was performed against the Terraform manifests using **Trivy**:

```bash
trivy config .
