terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.27"
    }
  }

  required_version = ">= 0.14.9"
}

data "external" "whoami" {
 program = [ "python",  "-c",  "import getpass; import json; j = { 'user' :getpass.getuser()}; print(json.dumps(j))" ]
}

provider "aws" {
  profile = "default"
  region  = "us-west-2"
  default_tags {
    tags = {
      owner_email = "svelasco+gts@confluent.io"
      created_by = "terraform" #   Static tags only due to but https://github.com/hashicorp/terraform-provider-aws/issues/19583
    }
  }
}


resource "aws_security_group" "main" {
  egress = [
    {
      cidr_blocks      = [ "0.0.0.0/0", ]
      description      = ""
      from_port        = 0
      ipv6_cidr_blocks = []
      prefix_list_ids  = []
      protocol         = "-1"
      security_groups  = []
      self             = false
      to_port          = 0
    }
  ]
 ingress                = [
   {
     cidr_blocks      = [ "0.0.0.0/0", ]
     description      = ""
     from_port        = 22
     ipv6_cidr_blocks = []
     prefix_list_ids  = []
     protocol         = "tcp"
     security_groups  = []
     self             = false
     to_port          = 22
  }
  ]
}

resource "aws_security_group" "internal" {
  egress = [
    {
      cidr_blocks      = [ "0.0.0.0/0", ]
      description      = ""
      from_port        = 0
      ipv6_cidr_blocks = []
      prefix_list_ids  = []
      protocol         = "-1"
      security_groups  = []
      self             = true
      to_port          = 0
    }
  ]
 ingress                = [
   {
     cidr_blocks      = [ "0.0.0.0/0", ]
     description      = ""
     from_port        = 0
     ipv6_cidr_blocks = []
     prefix_list_ids  = []
     protocol         = "-1"
     security_groups  = []
     self             = true
     to_port          = 0
  }
  ]
}


resource "tls_private_key" "pk" {
  algorithm = "RSA"
}


resource "aws_key_pair" "key" {
  public_key = tls_private_key.pk.public_key_openssh
}


resource "local_sensitive_file" "pem_file" {
  filename = "id_rsa"
  file_permission = "600"
  content = tls_private_key.pk.private_key_pem
}

resource "aws_instance" "c3" {
  count = 1
  ami           = "ami-056c679fab9e48d8a" #CentOS 8
# instance_type = "r5d.large" #	$0.144	2	16 GiB	1 x 75 NVMe SSD	Up to 10 Gigabit
  instance_type = "t3.xlarge" # 4cpu / 16GiB / EBS - $0.1664
  key_name=aws_key_pair.key.key_name
  vpc_security_group_ids = [aws_security_group.internal.id,aws_security_group.main.id]

connection {
   type    = "ssh"
   user    = "centos"
   host    = self.public_ip
   private_key   = tls_private_key.pk.private_key_pem
 }

  provisioner "remote-exec" {
   inline = [
   "sudo cp /home/centos/.ssh/authorized_keys /root/.ssh/authorized_keys"
    ]
   }

tags = {
    Name = "C3-${count.index} ${data.external.whoami.result.user}"
    Owner = "${data.external.whoami.result.user}"
  } 
}


resource "aws_instance" "brokers_rack2" {
  count = 4
  ami           = "ami-056c679fab9e48d8a" #CentOS 8
  instance_type = "t3.large" # 2cpu / 8GB / EBS - $ 0.832
  # instance_type = "c5d.large" # 2cpu / 4GiB / 50 NVMe SSD - $0.096
  # instance_type = "c5d.xlarge" # 4cpu / 8GiB / 100 NVMe SSD - $0.192
  key_name=aws_key_pair.key.key_name
  vpc_security_group_ids = [aws_security_group.internal.id,aws_security_group.main.id]

 connection {
   type    = "ssh"
   user    = "centos"
   host    = self.public_ip
   private_key   = tls_private_key.pk.private_key_pem
 }

  provisioner "remote-exec" {
   inline = [
   "sudo cp /home/centos/.ssh/authorized_keys /root/.ssh/authorized_keys"
    ]
   }

  tags = {
    Name = "Broker-${count.index} ${data.external.whoami.result.user}"
    Owner = "${data.external.whoami.result.user}"
  }
}



resource "aws_instance" "brokers_rack1" {
  count = 4
  ami           = "ami-056c679fab9e48d8a" #CentOS 8
  instance_type = "t3.large" # 2cpu / 8GB / EBS - $ 0.832
  # instance_type = "c5d.large" # 2cpu / 4GiB / 50 NVMe SSD - $0.096
  # instance_type = "c5d.xlarge" # 4cpu / 8GiB / 100 NVMe SSD - $0.192
  key_name=aws_key_pair.key.key_name
  vpc_security_group_ids = [aws_security_group.internal.id,aws_security_group.main.id]

 connection {
   type    = "ssh"
   user    = "centos"
   host    = self.public_ip
   private_key   = tls_private_key.pk.private_key_pem
 }

  provisioner "remote-exec" {
   inline = [
   "sudo cp /home/centos/.ssh/authorized_keys /root/.ssh/authorized_keys"
    ]
   }

  tags = {
    Name = "Broker-${count.index} ${data.external.whoami.result.user}"
    Owner = "${data.external.whoami.result.user}"
  }
}



resource "local_file" "ansible_inventory" {
  content = templatefile("inventory.tmpl",
    {
        brokers_rack1 = aws_instance.brokers_rack1.*.private_dns,
        brokers_rack2 = aws_instance.brokers_rack2.*.private_dns,
        zookeepers = aws_instance.c3.*.private_dns,
        control_centers = aws_instance.c3.*.private_dns
    })
    filename = "hosts_inventory"
}

resource "aws_instance" "ansible" {
  ami           = "ami-056c679fab9e48d8a" #CentOS 8
  instance_type = "t3.micro" # t3.micro	$0.0104	2	1 GiB	EBS Only	Up to 5 Gigabit
  # instance_type = "t3.small" # $0.0208	2	2 GiB	EBS Only	Up to 5 Gigabit
  key_name=aws_key_pair.key.key_name
  vpc_security_group_ids = [aws_security_group.internal.id,aws_security_group.main.id]

depends_on = [ 
    local_file.ansible_inventory,
    aws_instance.brokers_rack1,
    aws_instance.brokers_rack2,
    aws_instance.c3
]

connection {
   type    = "ssh"
   user    = "centos"
   host    = self.public_ip
   private_key   = tls_private_key.pk.private_key_pem
 }

  provisioner "file" {
    source = "config"
    destination = "/home/centos/.ssh/config"
  } 

  provisioner "file" {
    source = "hosts_inventory"
    destination = "/home/centos/hosts.yml"
  }

  provisioner "file" {
    content = "${data.template_file.ansible_setup.rendered}"
    destination = "/home/centos/ansible_setup.sh"
  }

  provisioner "file" {
    source = "id_rsa"
    destination = "/home/centos/.ssh/id_rsa"
  }

  provisioner "remote-exec" {
   inline = [
   "bash -x /home/centos/ansible_setup.sh"
  ]
   on_failure = continue
  }


  tags = {
    Name = "Ansible ${data.external.whoami.result.user}"
    Owner = "${data.external.whoami.result.user}"
  }
}


output "brokers_rack1" {
 value = aws_instance.brokers_rack1.*.private_dns
}

output "brokers_rack2" {
 value = aws_instance.brokers_rack2.*.private_dns
}

output "c3" {
 value = aws_instance.c3.*.private_dns
}

output "ansible" {
  value = aws_instance.ansible.*.public_dns
}



data "template_file" "result" {
template = <<EOT
#!/bin/bash
ssh $${ansible} -D9000 -i id_rsa -q
EOT

vars = {
    ansible = tostring(aws_instance.ansible.*.public_dns[0])
}
} 

resource "local_file" "connect_script" {
    content = "${data.template_file.result.rendered}"
    filename= "connect.sh"
}

data "template_file" "ansible_setup" {
template = <<EOT
#!/bin/bash
date > /tmp/provision.log
chmod 600 ~/.ssh/id_rsa >> /tmp/provision.log
sudo yum install epel-release -y >> /tmp/provision.log
sudo yum install ansible -y >> /tmp/provision.log
sudo yum install git vim -y >> /tmp/provision.log
mkdir -p ~/cp-ansible/ansible_collections/confluent >> /tmp/provision.log
git clone https://github.com/confluentinc/cp-ansible ~/cp-ansible/ansible_collections/confluent/platform >> /tmp/provision.log
sed -i 's%collections_paths=%collections_paths=./cp-ansible/:%' ~/cp-ansible/ansible_collections/confluent/platform/ansible.cfg >> /tmp/provision.log
cp ~/cp-ansible/ansible_collections/confluent/platform/ansible.cfg .
ansible all -m command -a "hostname" -i hosts.yml
ansible-playbook -i hosts.yml cp-ansible/ansible_collections/confluent/platform/playbooks/all.yml -vvv | tee -a /tmp/provision.log
EOT
}

