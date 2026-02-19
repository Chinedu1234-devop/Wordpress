output "wordpress_url" {
  value       = "http://${aws_instance.wp.public_ip}/"
  description = "Open this in your browser"
}

output "ec2_public_ip" {
  value       = aws_instance.wp.public_ip
  description = "Public IP of the WordPress EC2 instance"
}

output "rds_endpoint" {
  value       = aws_db_instance.wp_db.address
  description = "RDS endpoint hostname"
}
