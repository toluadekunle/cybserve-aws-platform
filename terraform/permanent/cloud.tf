terraform {
  required_version = ">= 1.6.0"

  cloud {
    organization = "Cybserve"

    workspaces {
      name = "ha-3tier-permanent-prod"
    }
  }
}
