provider "aws" {
  region = "ap-south-1"
}

# vpc creation 
resource "aws_vpc" "prod" {
  cidr_block = var.VPC_cidr_block
  tags = {
    Name = "prod-vpc"
  }
}

#IGW creation 
resource "aws_internet_gateway" "prodigw" {
  vpc_id = aws_vpc.prod.id
  tags = {
    Name = "prod-IGW"
  }
}

#public subnet-1
resource "aws_subnet" "public_subnet1" {
  vpc_id     = aws_vpc.prod.id
  cidr_block = var.subnet_cidr
  availability_zone = "ap-south-1a"
  tags = {
    Name = "prod-public_subnet_1"
  }
}


#public route -1
resource "aws_route_table" "publicrt1" {
  vpc_id = aws_vpc.prod.id

  route {
    gateway_id = aws_internet_gateway.prodigw.id
    cidr_block = "0.0.0.0/0"
  }

  tags = {
    Name = "prod-Public_Route_1"
  }
}


#subnet-1 and route-1 association 
resource "aws_route_table_association" "name" {
  subnet_id      = aws_subnet.public_subnet1.id
  route_table_id = aws_route_table.publicrt1.id
}


#public subnet 2
resource "aws_subnet" "subnet2" {
  vpc_id     = aws_vpc.prod.id
  cidr_block = "10.0.2.0/24"
  availability_zone = "ap-south-1b"


  tags = {
    Name = "prod-Public_subnet_2"
  }
}

# subnet routable asscoition 
resource "aws_route_table_association" "RT" {
  subnet_id      = aws_subnet.subnet2.id
  route_table_id = aws_route_table.publicrt1.id
}


resource "aws_instance" "web1" {
  ami               = "ami-02d26659fd82cf299"
  instance_type     = "t3.micro"
  subnet_id         = aws_subnet.public_subnet1.id
  associate_public_ip_address = true
  availability_zone = "ap-south-1a" 
  user_data = <<-EOF
              #!/bin/bash
              sudo apt update -y
              sudo apt install nginx -y
              sudo systemctl start nginx
              sudo systemctl enable nginx
              EOF
  tags = {
    web = "prod server 1"
  }
}


resource "aws_instance" "web2" {
  ami               = "ami-02d26659fd82cf299"
  instance_type     = "t3.micro"
  subnet_id         = aws_subnet.subnet2.id
  availability_zone = "ap-south-1b"
  associate_public_ip_address = true
  user_data = <<-EOF
              #!/bin/bash
              sudo apt update -y
              sudo apt install nginx -y
              sudo systemctl start nginx
              sudo systemctl enable nginx
              EOF
  tags = {
    web = "prod server 2"
  }
}

resource "aws_security_group" "websecurity1" {
  vpc_id = aws_vpc.prod.id
  tags = {
    Name = "web security1"
  }
}




resource "aws_security_group_rule" "allow_ssh" {
  security_group_id = aws_security_group.websecurity1.id
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  type              = "ingress"
  cidr_blocks       = ["0.0.0.0/0"]

}

resource "aws_security_group_rule" "allow_http" {
  security_group_id = aws_security_group.websecurity1.id
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  type              = "ingress"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "allow_https" {
  security_group_id = aws_security_group.websecurity1.id
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  type              = "ingress"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "port_out" {
  security_group_id = aws_security_group.websecurity1.id
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = -1
  cidr_blocks       = ["0.0.0.0/0"]

}

resource "aws_security_group" "alb_sg" {
  vpc_id = aws_vpc.prod.id
}

resource "aws_security_group_rule" "allow_http_alb" {
  security_group_id = aws_security_group.alb_sg.id
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  type              = "ingress"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "allow_all_outbound_alb" {
  security_group_id = aws_security_group.alb_sg.id
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  type              = "egress"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_lb_target_group" "tg" {
  name     = "test-load"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.prod.id
  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = {
    Name = "web-tg"
  }
}


resource "aws_lb_target_group_attachment" "web1" {
  target_group_arn = aws_lb_target_group.tg.arn
  target_id        = aws_instance.web1.id
  port             = 80
}


resource "aws_lb_target_group_attachment" "web2" {
  target_group_arn = aws_lb_target_group.tg.arn
  target_id        = aws_instance.web2.id
  port             = 80
}

resource "aws_lb" "alb" {
  name               = "prod-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets = [
    aws_subnet.public_subnet1.id,
    aws_subnet.subnet2.id
  ]

  tags = {
    Name = "prod-alb"
  }
}
resource "aws_lb_listener" "http_listener" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg.arn
  }
}


output "lb" {
  value = aws_lb.alb.dns_name
}