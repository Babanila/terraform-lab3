output "instance_public_ip" {
  description = "Public IP of the web server"
  value       = aws_instance.web.public_ip
}

output "instance_public_dns" {
  description = "Public DNS name"
  value       = aws_instance.web.public_dns
}

output "web_url" {
  description = "URL to open in your browser"
  value       = "http://${aws_instance.web.public_dns}"
}
