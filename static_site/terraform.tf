terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
      # 👇 告诉 Terraform：本模块会用到名为 aws.us_east_1 的 provider 配置
      configuration_aliases = [ aws.us_east_1 ]
    }
  }
}