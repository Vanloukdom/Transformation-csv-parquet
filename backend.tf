terraform {
  backend "s3" {
    bucket  = "my-terraform-project-terraform-state-127214177486"
    encrypt = true
    key     = "my-terraform-project-terraform-locks"
    region  = "eu-west-3"
  }
}