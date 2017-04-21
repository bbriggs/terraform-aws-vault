# terraform-aws-vault
Deploy Hasicorp Vault into an existing VPC on AWS. Designed for use with complimentary [consul module](https://github.com/bbriggs/terraform-aws-consul)

## Usage

Example: 

Note that we are using output from the Consul module as input for Vault. Vault actually looks for servers with the metadata tags that are produced in the Consul module, so using these together is not necessary, but is highly recommended.

```terraform
module "consul" {
  source = "github.com/bbriggs/terraform-aws-consul"

  ami                = "${var.your_consul_ami}"
  availability_zones = ["us-east-1c","us-east-1d","us-east-1e"]
  instance_type      = "m3.medium"
  key_name           = "my_key_or_something"
  num_instances      = "5"
  prefix             = "consul-"
  private_subnets    = ["${data.aws_subnet.private_c.id}","${data.aws_subnet.private_d.id}","${data.aws_subnet.private_e.id}"]
  region             = "${var.REGION}"
  security_groups    = ["${data.aws_security_group.bastion.id}"]
  vpc                = "${var.your_vpc}"
}

module "vault" {
  source = "github.com/bbriggs/terraform-aws-vault"

  ami                = "${var.your_vault_ami}"
  availability-zones = ["us-east-1c", "us-east-1d", "us-east-1e"]
  instance_type      = "m3.medium"
  key-name           = "my_key_or_something"
  nodes              = "2"
  region             = "us-east-1"
  security_groups    = ["${module.consul.security_group}","${data.aws_security_group.some_other_security_group_why_not_zoidberg.id}"]
  subnets            = ["${data.aws_subnet.private_1.id}", "${data.aws_subnet.private_2.id}", "${data.aws_subnet.private_3.id}"]
  vpc-id             = "${var.your_vpc}"
}
```

### Gotcha: Using awscli and jq to discover consul

While Vault can use several different storage backends, this module specifically points to a consul cluster for its storage backend. If you're not looking to use a consul backend, fork this module and change the Vault config to point to your perferred backend or just look elsewhere.

In order to discover where the consul cluster is, the consul agent on the Vault machine must be given a reachable IP address of another consul server. This is accomplished using awscli to query for servers with a key/value in tags like `Name:consul`. This is set in the Consul module and will be configurable soon. The node then attempts a `consul join` for every Consul node it finds until it is successful.

### Contributing

Pull requests are of course welcome, as are issues. Feel free to reach out to me on Gitter, particularly in the Vault, Consul, and Terraform rooms if you have any questions.
