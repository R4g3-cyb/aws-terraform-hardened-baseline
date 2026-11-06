resource "aws_security_group" "this" {
  description = "Permite ingress SSH restringido a IP del host y egress de salida"
  name_prefix = var.sg_name
  vpc_id      = var.vpc_id


ingress {
  description = "SSH"
  from_port   = 22
  to_port     = 22
  protocol    = "tcp"
  cidr_blocks = ["${var.allowed_ip}/32"]
}

egress {
  description = "Permite trafico port 443"
  from_port   = 443
  to_port     = 443
  protocol    = "tcp"
  cidr_blocks = ["0.0.0.0/0"]
 }
}