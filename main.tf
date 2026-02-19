data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default_vpc_subnets" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# Pick the latest Amazon Linux 2023 AMI
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

# Security group for WordPress EC2
resource "aws_security_group" "wp_ec2_sg" {
  name        = "wp-ec2-sg"
  description = "Allow HTTP and optional SSH"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.allowed_cidr]
  }

  ingress {
    description = "SSH (only if you set allowed_cidr to your IP and key_name)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_cidr]
  }

  egress {
    description = "All egress"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Security group for RDS: only allow MySQL from the EC2 SG
resource "aws_security_group" "rds_sg" {
  name        = "wp-rds-sg"
  description = "Allow MySQL from WordPress EC2 only"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description     = "MySQL from EC2"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.wp_ec2_sg.id]
  }

  egress {
    description = "All egress"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# RDS subnet group using the default subnets in the default VPC
resource "aws_db_subnet_group" "default_vpc_db_subnets" {
  name       = "wp-default-vpc-db-subnets"
  subnet_ids = data.aws_subnets.default_vpc_subnets.ids

  tags = {
    Name = "wp-default-vpc-db-subnets"
  }
}

resource "aws_db_instance" "wp_db" {
  identifier             = "wp-mysql"
  engine                 = "mysql"
  engine_version         = "8.0"
  instance_class         = var.db_instance_class
  allocated_storage      = var.db_allocated_storage
  db_name                = var.db_name
  username               = var.db_username
  password               = var.db_password
  db_subnet_group_name   = aws_db_subnet_group.default_vpc_db_subnets.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]

  publicly_accessible = false
  multi_az            = false

  # For quick demos. For production, set this to false and manage snapshots.
  skip_final_snapshot = true

  deletion_protection = false

  tags = {
    Name = "wp-mysql"
  }
}

resource "aws_instance" "wp" {
  ami           = data.aws_ami.al2023.id
  instance_type = var.instance_type
  subnet_id     = data.aws_subnets.default_vpc_subnets.ids[0]

  vpc_security_group_ids = [aws_security_group.wp_ec2_sg.id]
  key_name               = var.key_name

  user_data = <<-EOF
    #!/bin/bash
    set -euxo pipefail

    dnf update -y
    dnf install -y httpd php php-mysqlnd php-fpm php-gd php-xml php-mbstring unzip curl

    systemctl enable --now httpd

    # Download WordPress
    cd /tmp
    curl -LO https://wordpress.org/latest.zip
    unzip -o latest.zip

    # Deploy to web root
    rm -rf /var/www/html/*
    cp -R wordpress/* /var/www/html/
    chown -R apache:apache /var/www/html

    # Create wp-config.php
    cd /var/www/html
    cp wp-config-sample.php wp-config.php

    sed -i "s/database_name_here/${var.db_name}/" wp-config.php
    sed -i "s/username_here/${var.db_username}/" wp-config.php
    sed -i "s/password_here/${var.db_password}/" wp-config.php
    sed -i "s/localhost/${aws_db_instance.wp_db.address}/" wp-config.php

    # Security salts
    SALTS=$(curl -s https://api.wordpress.org/secret-key/1.1/salt/)
    perl -0777 -i -pe 's/define\\(\\x27AUTH_KEY\\x27,.*?\\);\\n.*?define\\(\\x27NONCE_SALT\\x27,.*?\\);\\n/$ENV{SALTS}/ms' wp-config.php SALTS="$SALTS"

    # Make Apache happy
    cat >/etc/httpd/conf.d/wordpress.conf <<'CONF'
    <Directory "/var/www/html">
        AllowOverride All
        Require all granted
    </Directory>
    CONF

    systemctl restart httpd

    # Optional: install WP CLI and create admin user/site (best-effort)
    curl -sS -o /usr/local/bin/wp https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
    chmod +x /usr/local/bin/wp

    # Wait briefly for DB to accept connections
    for i in {1..30}; do
      /usr/local/bin/wp db check --path=/var/www/html --allow-root && break || true
      sleep 10
    done

    /usr/local/bin/wp core install \
      --path=/var/www/html \
      --url="http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)/" \
      --title="${var.wp_title}" \
      --admin_user="${var.wp_admin_user}" \
      --admin_password="${var.wp_admin_password}" \
      --admin_email="${var.wp_admin_email}" \
      --skip-email \
      --allow-root || true
  EOF

  tags = {
    Name = "wp-ec2"
  }

  depends_on = [aws_db_instance.wp_db]
}
