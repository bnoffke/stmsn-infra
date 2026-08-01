variable "project_id" {
  type    = string
  default = "madison-municipal-data"
}

variable "region" {
  type    = string
  default = "us-central1"
}

# Read-only lakehouse guests. Key is the SA slug (must keep
# "guest-<key>-sa" within the account_id pattern [a-z][a-z0-9-]{4,28}[a-z0-9]);
# value is the person's email, recorded for ownership only — guests never log
# into GCP, they get an HMAC pair.
#
# The roster lives here rather than in a tfvars file on purpose: *.tfvars is
# gitignored, and the bucket viewer bindings are authoritative, so an
# uncommitted roster would make a bare `terraform apply` revoke every guest.
variable "guest_readers" {
  type = map(string)
  default = {
    jo = "jo.olson03@gmail.com",
    jk = "james.kreft@gmail.com",
    bw = "blakewasung@gmail.com"
  }
}
