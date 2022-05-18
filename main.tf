terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.27"
    }
  }

  required_version = ">= 0.14.9"
}

provider "aws" {
  profile = "default"
  region  = "us-west-2"
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

resource "aws_key_pair" "deployer" {
  key_name   = "svelascos_key"
  public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCcV2vsy/iih44WZfUqRXOwQFdbx98Vk8C3CLWZDq+Ai8h4ovXEqRS7FGNa0qI8yEOi+jKnqRnoyLOcPA9qaKqxlVh08NSUFOCiC0HFYnOkJlHh5ZmJVQOb9Ih2bSp4N7qcVLIa6ooYY3lPEc+ELHjx4o0LdqFC3jAxcVcv1MG8UloAa2rK2f2zqjDHatk/1KF2Nh8RdUeRuvLoePV1nmNDdvBpzJWItLq9TC+tGMFJNbnyWgHzmRfuQQYHPX30+KIPtXJ2I31YfgGJgoZbHiWMM8bsT0pP39cT/1erO9Xj5rjHvxoDNOqeyT5TqOM15KMGIZCgHREBGbFF6zWQfjffcgymBIdSpdJT9mvaeFBgVexkHwhi2JBetd6VVNP1lfzpiUKqFj5Ox7QdOPaPZrYr1/Z9qMODjMfMGOFJhIwt6fklETsItSmDry4Yv2t72reSWub8J+fOdzvMIbvVBEvF0DBLnTkES/19UbjOnCdLZSMZAqTOd2XFwjRKxLbdSi8= svelasco@MacBook-Pro.local"
}

resource "aws_instance" "c3" {
  count = 1
  ami           = "ami-056c679fab9e48d8a" #CentOS 8
  instance_type = "t2.xlarge"
  key_name= "svelascos_key"
  vpc_security_group_ids = [aws_security_group.internal.id,aws_security_group.main.id]

connection {
   type    = "ssh"
   user    = "centos"
   host    = self.public_ip
   private_key   = "${file("/Users/svelasco/terraform/id_rsa")}"
 }

  provisioner "remote-exec" {
   inline = [
   "sudo cp /home/centos/.ssh/authorized_keys /root/.ssh/authorized_keys"
    ]
   }

tags = {
    Name = "C3-${count.index} svelasco"
    Owner = "svelasco+cops@confluent.io"
  }
}


resource "aws_instance" "broker" {
  count = 3
  ami           = "ami-056c679fab9e48d8a" #CentOS 8
  instance_type = "t2.xlarge"
  key_name= "svelascos_key"
  vpc_security_group_ids = [aws_security_group.internal.id,aws_security_group.main.id]

 connection {
   type    = "ssh"
   user    = "centos"
   host    = self.public_ip
   private_key   = "${file("/Users/svelasco/terraform/id_rsa")}"
 }

  provisioner "remote-exec" {
   inline = [
   "sudo cp /home/centos/.ssh/authorized_keys /root/.ssh/authorized_keys"
    ]
   }

  tags = {
    Name = "Broker-${count.index} svelasco"
    Owner = "svelasco+cops@confluent.io"
  }
}



resource "local_file" "ansible_inventory" {
  content = templatefile("inventory.tmpl",
    {
        brokers = aws_instance.broker.*.private_dns,
        zookeepers = aws_instance.broker.*.private_dns,
        schema_registries = aws_instance.c3.*.private_dns,
        kafka_rests = aws_instance.c3.*.private_dns,
        ksqls = aws_instance.c3.*.private_dns,
        kafka_connects = aws_instance.broker.*.private_dns,
        control_centers = aws_instance.c3.*.private_dns
    })
    filename = "hosts_inventory"
}

resource "aws_instance" "ansible" {
  ami           = "ami-056c679fab9e48d8a" #CentOS 8
  instance_type = "t2.small"
  key_name= "svelascos_key"
  vpc_security_group_ids = [aws_security_group.internal.id,aws_security_group.main.id]

depends_on = [ 
    local_file.ansible_inventory
]

connection {
   type    = "ssh"
   user    = "centos"
   host    = self.public_ip
   private_key   = "${file("/Users/svelasco/terraform/id_rsa")}"
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
    source = "id_rsa"
    destination = "/home/centos/.ssh/id_rsa"
  }

  provisioner "remote-exec" {
   inline = [
   "date > /tmp/provision.log",
   "chmod 600 ~/.ssh/id_rsa >> /tmp/provision.log",
   "sudo yum install epel-release -y >> /tmp/provision.log",
   "sudo yum install ansible -y >> /tmp/provision.log",
   "sudo yum install git vim -y >> /tmp/provision.log",
   "mkdir -p ~/cp-ansible/ansible_collections/confluent >> /tmp/provision.log",
   "git clone https://github.com/confluentinc/cp-ansible ~/cp-ansible/ansible_collections/confluent/platform >> /tmp/provision.log",
   "sed -i 's%collections_paths=%collections_paths=/home/centos/cp-ansible/:%' ~/cp-ansible/ansible_collections/confluent/platform/ansible.cfg >> /tmp/provision.log",
   "cp ~/cp-ansible/ansible_collections/confluent/platform/ansible.cfg .",
   "ansible-playbook -i hosts.yml cp-ansible/ansible_collections/confluent/platform/playbooks/all.yml -vvv  >> /tmp/provision.log"
  ]
  }


  tags = {
    Name = "Ansible svelasco"
    Owner = "svelasco+cops@confluent.io"
  }
}

data "template_file" "result" {
template = "ssh $${ansible} -D9000\nhttp://$${c3}:9021"
vars = {
    ansible = tostring(aws_instance.ansible.*.public_dns[0])
    c3 = tostring(aws_instance.c3.*.private_dns[0])
}
} 

output "final" {
 value = "${data.template_file.result.rendered}"
}

output "brokers" {
 value = aws_instance.broker.*.private_dns
}

output "c3" {
 value = aws_instance.c3.*.private_dns
}

output "ansible" {
  value = aws_instance.ansible.*.public_dns
}
