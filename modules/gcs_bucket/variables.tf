variable "name" {
  type = string
}

variable "project" {
  type = string
}

variable "location" {
  type = string
}

variable "versioning" {
  type    = bool
  default = false
}

variable "keep_versions" {
  type    = number
  default = 10
}
