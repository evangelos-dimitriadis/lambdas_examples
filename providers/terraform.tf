terraform {
  required_version = "~>1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~>5.26.0"
    }
    http = {
      source  = "hashicorp/http"
      version = "~>3.4.0"
    }
  }
}
