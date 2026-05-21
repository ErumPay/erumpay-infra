# Jenkins에서 이미지 push할 때 URL 참조용
output "repository_urls" {
  value = {
    for name, repo in aws_ecr_repository.main :
    name => repo.repository_url
  }
}