//-------------------------------------------------------------------
// Vault settings
//-------------------------------------------------------------------

variable "extra-install" {
  type        = "string"
  default     = ""
  description = "Extra commands to run in the install script"
}

//-------------------------------------------------------------------
// AWS settings
//-------------------------------------------------------------------

variable "ami" {
  type = "string"
  default     = ""
  description = "AMI for Vault instances"
}

variable "availability-zones" {
  type        = "list"
  description = "Availability zones for launching the Vault instances"
}

variable "elb-health-check" {
  type        = "string"
  default     = "HTTP:8200/v1/sys/health"
  description = "Health check for Vault servers"
}

variable "instance_type" {
  type        = "string"
  default     = "m3.medium"
  description = "Instance type for Vault instances"
}

variable "key-name" {
  type        = "string"
  default     = "default"
  description = "SSH key name for Vault instances"
}

variable "nodes" {
  type        = "string"
  default     = "2"
  description = "Number of Vault instances"
}

variable "region" {
  type       = "string"
  description = "Region in which the nodes will reside"
}

variable "security_groups" {
  type = "list"
  description = "Additional security groups for Vault servers"
}

variable "subnets" {
  type        = "list"
  description = "Comma separated list of subnets to launch Vault within"
}

variable "vpc-id" {
  type        = "string"
  description = "VPC ID"
}

// We launch Vault into an ASG so that it can properly bring them up for us.
resource "aws_autoscaling_group" "vault" {
  name                      = "vault - ${aws_launch_configuration.vault.name}"
  launch_configuration      = "${aws_launch_configuration.vault.name}"
  availability_zones        = "${var.availability-zones}"
  min_size                  = "${var.nodes}"
  max_size                  = "${var.nodes}"
  desired_capacity          = "${var.nodes}"
  health_check_grace_period = 15
  health_check_type         = "EC2"
  vpc_zone_identifier       = ["${var.subnets}"]
  load_balancers            = ["${aws_elb.vault.id}"]

  tag {
    key                 = "Name"
    value               = "vault"
    propagate_at_launch = true
  }
}

data "template_file" "vault-userdata" {
  template = "${file("${path.module}/templates/bootstrap.sh.tmpl")}"

  vars {
    region = "${var.region}"
  }
}

resource "aws_launch_configuration" "vault" {
  name_prefix     = "vault-"
  image_id        = "${var.ami}"
  instance_type   = "${var.instance_type}"
  key_name        = "${var.key-name}"
  security_groups = ["${var.security_groups}", "${aws_security_group.vault.id}"]
  iam_instance_profile = "${aws_iam_instance_profile.vault.id}"
  user_data       = "${data.template_file.vault-userdata.rendered}"

  lifecycle {
	  create_before_destroy = true
  }
}

resource "aws_iam_role" "vault" {
	name = "vault"
	assume_role_policy = "${file("${path.module}/policies/role-ec2.json")}"
}

resource "aws_iam_role_policy_attachment" "ec2-read-only" {
	role = "${aws_iam_role.vault.name}"
	policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ReadOnlyAccess"
}

resource "aws_iam_instance_profile" "vault" {
	name = "vault"
	role = "${aws_iam_role.vault.name}"
	depends_on = ["aws_iam_role.vault"]
}


// Security group for Vault allows SSH and HTTP access (via "tcp" in
// case TLS is used)
resource "aws_security_group" "vault" {
  name        = "vault"
  description = "Vault servers"
  vpc_id      = "${var.vpc-id}"
}

resource "aws_security_group_rule" "vault-ssh" {
  security_group_id = "${aws_security_group.vault.id}"
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  self              = "true"
}

// This rule allows Vault HTTP API access to individual nodes, since each will
// need to be addressed individually for unsealing.
resource "aws_security_group_rule" "vault-http-api" {
  security_group_id = "${aws_security_group.vault.id}"
  type              = "ingress"
  from_port         = 8200
  to_port           = 8200
  protocol          = "tcp"
  self              = "true"
}

resource "aws_security_group_rule" "vault-egress" {
  security_group_id = "${aws_security_group.vault.id}"
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
}

// Launch the ELB that is serving Vault. This has proper health checks
// to only serve healthy, unsealed Vaults.
resource "aws_elb" "vault" {
  name                        = "vault"
  connection_draining         = true
  connection_draining_timeout = 400
  internal                    = true
  subnets                     = ["${var.subnets}"]
  security_groups             = ["${aws_security_group.elb.id}"]

  listener {
    instance_port     = 8200
    instance_protocol = "tcp"
    lb_port           = 80
    lb_protocol       = "tcp"
  }

  listener {
    instance_port     = 8200
    instance_protocol = "tcp"
    lb_port           = 443
    lb_protocol       = "tcp"
  }

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    target              = "${var.elb-health-check}"
    interval            = 15
  }
}

resource "aws_security_group" "elb" {
  name        = "vault-elb"
  description = "Vault ELB"
  vpc_id      = "${var.vpc-id}"
}

resource "aws_security_group_rule" "vault-elb-http" {
  security_group_id = "${aws_security_group.elb.id}"
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "vault-elb-https" {
  security_group_id = "${aws_security_group.elb.id}"
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "vault-elb-egress" {
  security_group_id = "${aws_security_group.elb.id}"
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
}
