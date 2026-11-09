# AWS Hardened Infrastructure with Terraform & Checkov (DevSecOps)

[![Terraform](https://img.shields.io/badge/IaC-Terraform-623CE4?logo=terraform&logoColor=white)](https://www.terraform.io/)
[![AWS](https://img.shields.io/badge/Cloud-AWS-232F3E?logo=amazon-aws&logoColor=white)](https://aws.amazon.com/)
[![Scanned by Checkov](https://img.shields.io/badge/Scanned_by-Checkov-6C47FF?logo=bridgecrew&logoColor=white)](https://www.checkov.io/)
[![Checkov CI](https://github.com/R4g3-cyb/aws-terraform-hardened-baseline/actions/workflows/checkov.yml/badge.svg)](https://github.com/R4g3-cyb/aws-terraform-hardened-baseline/actions/workflows/checkov.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

**ES** — Este repositorio define, como Infraestructura como Código (Terraform), una **base de infraestructura endurecida en AWS**: una VPC con subred pública, una instancia EC2 bastionada y almacenamiento S3 cifrado, todo **auditado automáticamente con Checkov en cada push** mediante GitHub Actions (modo *hard-fail*). El objetivo no es solo que funcione, sino que cada recurso aplique controles de seguridad explícitos y defendibles: **mínimo privilegio, mínima exposición, cifrado en reposo y trazabilidad**.

**EN** — This repository defines, as Infrastructure as Code (Terraform), a **hardened AWS baseline**: a VPC with a public subnet, a bastioned EC2 instance, and encrypted S3 storage — all **automatically audited by Checkov on every push** via GitHub Actions (hard-fail mode). The goal isn't just working infrastructure, but infrastructure where every resource applies explicit, defensible security controls: **least privilege, minimal exposure, encryption at rest, and auditability**.

---

## 🏛️ Architecture

```text
                                VPC  (10.0.0.0/16)
 ┌──────────────────────────────────────────────────────────────────────────┐
 │                                                                            │
 │   Internet Gateway                                                         │
 │          │                                                                 │
 │          ▼                                                                 │
 │   Public Subnet (10.0.1.0/24)                                              │
 │   ┌────────────────────────────────────────────────────────────────────┐ │
 │   │  Security Group                                                      │ │
 │   │    Ingress:  TCP 22 (SSH)   <-  solo IP del administrador (/32)      │ │
 │   │    Egress :  TCP 443 (HTTPS)   unicamente                           │ │
 │   │   ┌──────────────────────────────────────────────────────────────┐ │ │
 │   │   │  EC2 Instance (Ubuntu)                                        │ │ │
 │   │   │   ├── IMDSv2 obligatorio (http_tokens=required, hop-limit=1)  │ │ │
 │   │   │   ├── Root EBS cifrado (AES-256, clave gestionada por AWS)    │ │ │
 │   │   │   ├── Sin IP publica (associate_public_ip_address = false)    │ │ │
 │   │   │   ├── Monitoreo detallado habilitado                          │ │ │
 │   │   │   └── SIN rol IAM  (decision deliberada -- ver seccion 2)     │ │ │
 │   │   └──────────────────────────────────────────────────────────────┘ │ │
 │   └────────────────────────────────────────────────────────────────────┘ │
 │                                                                            │
 │   Default Security Group  ->  sin reglas ingress/egress (bloqueado)        │
 │   VPC Flow Logs           ->  CloudWatch Log Group (cifrado KMS, retencion)│
 └──────────────────────────────────────────────────────────────────────────┘

        KMS CMK (rotacion habilitada)
              │ cifra
              ▼
 ┌─────────────────────────────────────────────┐        ┌───────────────────────────┐
 │  S3 Bucket privado                          │  logs  │  S3 Bucket de logs          │
 │   ├── SSE-KMS (CMK del cliente)             │ ─────▶ │   ├── SSE-KMS               │
 │   ├── Public Access Block (4 flags)         │        │   ├── Public Access Block   │
 │   ├── Versioning                            │        │   └── Versioning            │
 │   └── Server access logging habilitado      │        └───────────────────────────┘
 └─────────────────────────────────────────────┘
```

> Nota: la instancia **no** realiza llamadas a la API de AWS (no tiene rol), por eso no hay flecha de la EC2 hacia S3. El bucket es almacenamiento endurecido independiente, no un recurso consumido por el servidor.

---

## 🛡️ Security hardening & mitigations

### 1. IMDSv2 enforced (SSRF mitigation)
By default AWS allows fallback to IMDSv1 (Instance Metadata Service v1), which answers simple unauthenticated HTTP GET requests to `169.254.169.254`. If an app on the instance has a Server-Side Request Forgery (SSRF) flaw, an attacker could read instance metadata.
* **Mitigation:** `metadata_options` configured with `http_tokens = "required"` and `http_put_response_hop_limit = 1`. A session token (PUT) is required before any metadata query, and the single hop limit blocks traversal through misconfigured proxies/containers.

### 2. No IAM role on the instance (deliberate attack-surface reduction)
The instance is configured **without an IAM instance profile**, and this is an intentional decision, not an omission.
* **Rationale:** this instance has no need to call AWS APIs. Attaching a role would only place temporary credentials in the metadata service — exactly the asset an attacker targets via SSRF or RCE. With no role, there are **no instance credentials to steal**. Combined with IMDSv2 enforcement (§1), this closes the EC2 credential-theft path demonstrated by scenarios like CloudGoat's `ec2_ssrf`.
* **Trade-off (honest):** if this instance ever needs to access an AWS service (e.g. read the S3 bucket), the correct pattern is a **least-privilege IAM role** scoped to specific actions and resource ARNs — never hardcoded access keys on disk.
* Documented in code via a justified Checkov skip (`CKV2_AWS_41`) rather than silently ignored.

### 3. Minimal network exposure
* **Ingress:** only TCP **22 (SSH)**, restricted to the administrator's IP (`/32`) — never `0.0.0.0/0`.
* **Egress:** restricted strictly to TCP **443 (HTTPS)**. The permissive wildcard `protocol = "-1"` outbound rule is removed, preventing a compromised instance from opening reverse shells or exfiltrating data over arbitrary ports.
* **No public IP** assigned to the instance (`associate_public_ip_address = false`).
* **Default security group hardened:** `aws_default_security_group` defined with no ingress/egress rules, removing the implicit allow-all default VPC behavior.

### 4. Encryption at rest
* **Root EBS volume:** `encrypted = true` on `root_block_device` (AES-256, AWS-managed EBS key).
* **S3 buckets (private + logging):** server-side encryption with **SSE-KMS**, using a **customer-managed CMK with automatic key rotation enabled** and a key policy scoping access — stronger than the default SSE-S3 (AES-256) because key usage is controlled and auditable.

### 5. S3 protection & auditability
* **Public Access Block** with all four flags enforced on both buckets:
  * `block_public_acls = true`
  * `ignore_public_acls = true`
  * `block_public_policy = true`
  * `restrict_public_buckets = true`
* **Versioning** enabled (protection against accidental or malicious overwrite/deletion).
* **Server access logging** from the private bucket to a dedicated logging bucket.

### 6. Logging & monitoring
* **VPC Flow Logs** delivered to a **CloudWatch Log Group** (KMS-encrypted, with a retention period), through a dedicated IAM role with a least-privilege policy.
* **Detailed monitoring** enabled on the EC2 instance.

---

## 🔍 DevSecOps pipeline

Security is enforced at two layers (defense in depth):

| Layer | Tool | When it runs |
|---|---|---|
| **Server (CI)** | **Checkov** (GitHub Actions) | On every `push` to `main`. Scans all Terraform. |
| **Local (pre-commit)** | **Trivy** (IaC + image) + **Gitleaks** (secrets) | Before commits leave the machine. |

* The Checkov action runs in **hard-fail mode** (not `soft_fail`): a misconfiguration **blocks the pipeline** instead of being silently reported — so the repo cannot drift back into an insecure state unnoticed.
* Exceptions are **explicit and justified inline** (e.g. the deliberate no-IAM-role decision in §2), never globally disabled. Each skip carries a reason a reviewer can read and challenge.

```bash
# Run Checkov locally against the Terraform
checkov -d . --framework terraform
```

---

## 🚀 Usage

```bash
terraform init
terraform fmt -check
terraform validate
terraform plan
# terraform apply   # creates real AWS resources (costs may apply)
# terraform destroy # tear everything down
```

Set the required variables in a local `terraform.tfvars` (for example `allowed_ip`, `instance_type`) — see `variables.tf`.

> **Never committed:** `*.tfvars`, `*.tfstate`, `.terraform/` are in `.gitignore`. They hold environment-specific values and state (including your real IP and potential secrets) and must stay out of version control.

---

## 📄 License

MIT — see [LICENSE](LICENSE).
