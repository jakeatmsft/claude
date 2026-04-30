terraform {
  required_version = ">= 1.6"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.55"
    }
    azapi = {
      source  = "azure/azapi"
      version = ">= 2.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.6"
    }
  }
  # Local state lives under .azure/<env-name>/infra/ when run via `azd up`.
  backend "local" {}
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

provider "azapi" {
  subscription_id = var.subscription_id
}
