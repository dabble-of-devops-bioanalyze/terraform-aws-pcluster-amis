resource "time_static" "this" {}

locals {
  dt         = formatdate("YYYYMMDD", time_static.this.rfc3339)
  dt_day     = formatdate("YYYYMMDD", time_static.this.rfc3339)
  dt_time    = formatdate("YYYYMMDD-hh-mm-ss", time_static.this.rfc3339)
  dt_version = formatdate("YYYY.MM.DD", time_static.this.rfc3339)
}

locals {
  ami_name     = var.ami_name != "" ? var.ami_name : title(join(" ", split("-", module.this.id, )))
  #  owner    = var.os == "alinux2" ? "amazon" : "ubuntu"
  replace_orig = "(Ubuntu 20.04)"
  replace_with = "ubuntu2004"
}

output "ami_name" {
  value = local.ami_name
}

data "aws_ami" "deeplearning" {
  count       = length(var.deep_learning_amis)
  most_recent = true
  owners      = [var.ami_owner]

  #  filter {
  #    name   = "owner-alias"
  #    values = [var.ami_owner]
  #  }

  filter {
    name   = "name"
    values = [var.deep_learning_amis[count.index]]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

output "deeplearning_ami" {
  value = data.aws_ami.deeplearning
}

################################################
# AWS - EC2 Image Builder Components
################################################

locals {
  aws_imagebuilder_components = [
    { name : "python-3-linux", version : "1.0.1" },
    { name : "amazon-cloudwatch-agent-linux", version : "1.0.1" },
    { name : "aws-cli-version-2-linux", version : "1.0.3" }
  ]
}

data "aws_imagebuilder_component" "aws_imagebuilder_components" {
  count = length(local.aws_imagebuilder_components)
  arn   = "arn:aws:imagebuilder:${var.region}:aws:component/${local.aws_imagebuilder_components[count.index].name}/${local.aws_imagebuilder_components[count.index].version}"
}

################################################
# Custom - EC2 Image Builder Components
################################################

locals {
  custom_aws_imagebuilder_components = [
    {
      name : "base-packages",
      version : local.dt_version,
      filename : "${path.module}/files/image-builder/${var.os}/base-packages-component.yaml",
    },
    {
      name : "singularity",
      version : local.dt_version,
      filename : "${path.module}/files/image-builder/${var.os}/singularity-component.yaml",
    },
    {
      name : "desktop",
      version : local.dt_version,
      filename : "${path.module}/files/image-builder/${var.os}/desktop-component.yaml",
    },
    {
      name : "rstudio",
      version : local.dt_version,
      filename : "${path.module}/files/image-builder/${var.os}/rstudio-component.yaml",
    },
    {
      name : "docker",
      version : local.dt_version,
      filename : "${path.module}/files/image-builder/${var.os}/docker-component.yaml",
    },
    # I think it should install nvidia if we have a compatible gpu instance
    {
      name : "nvidia",
      version : local.dt_version,
      filename : "${path.module}/files/image-builder/${var.os}/nvidia-component.yaml",
    },
    {
      name : "vscode",
      version : local.dt_version,
      filename : "${path.module}/files/image-builder/${var.os}/vscode-component.yaml",
    },
    {
      name : "open-demand-hpc",
      version : local.dt_version,
      filename : "${path.module}/files/image-builder/${var.os}/open-demand-hpc-component.yaml",
    },
  ]
}

data "local_file" "custom_components" {
  count    = length(local.custom_aws_imagebuilder_components)
  filename = local.custom_aws_imagebuilder_components[count.index].filename
}

output "custom_components_data" {
  value = data.local_file.custom_components[*].content
}

resource "aws_imagebuilder_component" "custom_stacks" {
  depends_on = [
    data.local_file.custom_components
  ]
  count    = length(data.local_file.custom_components)
  name     = "${module.this.id}-${local.custom_aws_imagebuilder_components[count.index].name}-${local.dt}"
  platform = "Linux"
  // Version must be in format: major.minor.patch
  #  version  = "1.0.0"
  #  version  = formatdate("YYYY.MM.DD", timestamp())
  version  = local.dt_version
  data     = data.local_file.custom_components[count.index].content
  tags     = module.this.tags
}

output "scientific_stack" {
  value = aws_imagebuilder_component.custom_stacks
}

locals {
  components = flatten([
    data.aws_imagebuilder_component.aws_imagebuilder_components[*].arn,
    aws_imagebuilder_component.custom_stacks[*].arn,
    var.additional_component_arns,
  ])
}

locals {
  pcluster_build_config_dir = "files/pcluster-v${var.pcluster_version}"
}

resource "random_string" "amis" {
  count   = length(data.aws_ami.deeplearning)
  length  = 6
  special = false
  upper   = false
  lower   = true
}

locals {
  ami_ids               = flatten(data.aws_ami.deeplearning[*].image_id)
  ami_names             = flatten(data.aws_ami.deeplearning[*].name)
  pcluster_ami_long_ids = flatten([
    # the ami id already gets the date time attached
    # The value supplied for parameter 'name' is not valid. name must match pattern ^[-_A-Za-z-0-9][-_A-Za-z0-9 ]{1,126}[-_A-Za-z-0-9]$
    for i in range(length(local.ami_ids)) :
    trimspace("${module.this.id}-${local.dt_day}-pcluster-${replace(var.pcluster_version, ".", "-")}--${lower(replace(replace(replace(local.ami_names[i], local.replace_orig, local.replace_with), " ", "-") ,".", "-") )}")
  ])
  # keep running into issues where this is too long
  pcluster_ami_ids = flatten([
    # the ami id already gets the date time attached
    # The value supplied for parameter 'name' is not valid. name must match pattern ^[-_A-Za-z-0-9][-_A-Za-z0-9 ]{1,126}[-_A-Za-z-0-9]$
    # make sure we are using a name pattern that is allowed
    # The 'Name' tag has the full name
    for i in range(length(local.ami_ids)) :
    trimspace("pcluster-${replace(var.pcluster_version, ".", "-")}-${random_string.amis[i].id}-${local.dt_day}")
  ])
  pcluster_ami_names = flatten([
    #  for i in range(length(local.ami_ids)) : replace(trimspace("${local.ami_name} PCluster ${var.pcluster_version} ${local.ami_names[i]}"), "(Amazon Linux 2)", "Amazon Linux 2")
    for i in range(length(local.ami_ids)) :
    replace(trimspace("${local.ami_name} PCluster ${var.pcluster_version} ${local.ami_names[i]}"), local.replace_orig, local.replace_with)
  ])
  pcluster_ami_build_config_files = flatten([
    for i in range(length(local.ami_ids)) :
    "files/pcluster-v${var.pcluster_version}/pcluster_build-${local.pcluster_ami_ids[i]}.yaml"
  ])
  pcluster_ami_build_cloudformation_template_files = flatten([
    for i in range(length(local.ami_ids)) :
    "files/pcluster-v${var.pcluster_version}/cloudformation-${local.pcluster_ami_ids[i]}.json"
  ])
  pcluster_ami_build_cloudformation_status_files = flatten([
    for i in range(length(local.ami_ids)) :
    "files/pcluster-v${var.pcluster_version}/cloudformation-${local.pcluster_ami_ids[i]}.json"
  ])
  pcluster_ami_build_pcluster_describe_files = flatten([
    for i in range(length(local.ami_ids)) :
    "files/pcluster-v${var.pcluster_version}/pcluster-ami-${local.pcluster_ami_ids[i]}.json"
  ])

}


locals {
  # TODO Sanity check
  # Tags must not have '(' or ')' in their values
  pcluster_image_build_template = [
    for i in range(length(local.ami_ids)) :
    {
      Region : var.region,
      Image : {
        Name : local.pcluster_ami_ids[i]
        Tags : [
          {
            Key : "Name",
            Value : replace(local.pcluster_ami_names[i], local.replace_orig, local.replace_with )
          },
          {
            Key : "Version",
            Value : var.image_recipe_version,
          },
          {
            Key : "Date",
            Value : local.dt
          },
          {
            Key : "ParentAmiID",
            Value : local.ami_ids[i]
          },
          {
            Key : "ParentAmiName",
            Value : replace(local.ami_names[i], local.replace_orig, local.replace_with)
          },
        ]
      },
      Build : {
        ParentImage : local.ami_ids[i],
        InstanceType : var.instance_type,
        SubnetId : var.subnet_id,
        SecurityGroupIds : var.security_group_ids,
        Components : [for component in local.components : { Type : "arn", Value : component }],
        Tags : flatten([
          [
            {
              Key : "Version",
              Value : var.image_recipe_version,
            },
            {
              Key : "Date",
              Value : local.dt
            },
            { Key : "ParentAmiId", Value : local.ami_ids[i] },
            { Key : "ParentAmiName", Value : replace(local.ami_names[i], local.replace_orig, local.replace_with) }
          ]
        ])
      },
    }
  ]
}

locals {
  make_dirs_command = flatten([
    for i in range(length(local.pcluster_image_build_template)) :
    <<EOF
mkdir -p files/pcluster-v${var.pcluster_version}
touch ${local.pcluster_ami_build_config_files[i]}
touch ${local.pcluster_ami_build_cloudformation_template_files[i]}
touch ${local.pcluster_ami_build_pcluster_describe_files[i]}
EOF
  ])
  pcluster_build_command = flatten([
    for i in range(length(local.pcluster_image_build_template)) :
    <<EOF
echo "${local.pcluster_ami_names[i]}"

pcluster delete-image \
  --image-id ${local.pcluster_ami_ids[i]} \
  -r ${var.region} || echo "Image does not exist"

EOF
  ])
}

locals {
  triggers = {
  }
}

output "pcluster_build_command" {
  value = local.pcluster_build_command
}

resource "null_resource" "make_dirs" {
  count      = length(local.pcluster_image_build_template)
  depends_on = [
  ]
  triggers = local.triggers
  provisioner "local-exec" {
    command = local.make_dirs_command[count.index]
  }
}

resource "local_file" "pcluster_build_configurations" {
  depends_on = [null_resource.make_dirs]
  count      = length(local.pcluster_image_build_template)
  filename   = local.pcluster_ami_build_config_files[count.index]
  content    = yamlencode(local.pcluster_image_build_template[count.index])
}

resource "null_resource" "pcluster_build_images" {
  count      = length(local.pcluster_image_build_template)
  triggers   = local.triggers
  depends_on = [
    data.aws_ami.deeplearning,
    null_resource.make_dirs,
    aws_imagebuilder_component.custom_stacks,
    local_file.pcluster_build_configurations,
  ]

  provisioner "local-exec" {
    command = local.pcluster_build_command[count.index]
  }
}

resource "null_resource" "pcluster_wait" {
  count      = length(local.pcluster_image_build_template)
  triggers   = local.triggers
  depends_on = [
    null_resource.make_dirs,
    null_resource.pcluster_build_images,
    local_file.pcluster_build_configurations,
  ]
  provisioner "local-exec" {
    command = <<EOF
# this operation always takes ~1.5 hours

pcluster-bootstrap-helper \
  build-and-watch-ami \
  --region ${var.region} \
  --config-file ${local.pcluster_ami_build_config_files[count.index]} \
  --image-id ${local.pcluster_ami_ids[count.index]} \
  --output ${local.pcluster_ami_build_pcluster_describe_files[count.index]}

EOF
  }
}


data "local_file" "pcluster_amis" {
  depends_on = [
    null_resource.make_dirs,
    null_resource.pcluster_build_images,
    local_file.pcluster_build_configurations,
    null_resource.pcluster_wait,
  ]
  count    = length(local.pcluster_image_build_template)
  filename = local.pcluster_ami_build_pcluster_describe_files[count.index]
}

locals {
  pcluster_amis = [for pcluster_ami in data.local_file.pcluster_amis : jsondecode(pcluster_ami.content)]
}

output "pcluster_build_image_amis" {
  value = local.pcluster_amis
}

resource "null_resource" "pcluster_image_creation_sanity_check" {
  count      = length(local.pcluster_image_build_template)
  triggers   = local.triggers
  depends_on = [
    null_resource.make_dirs,
    local_file.pcluster_build_configurations,
    null_resource.pcluster_build_images,
    null_resource.pcluster_wait,
  ]
  provisioner "local-exec" {
    command = <<EOF
echo "Describing image: ${local.pcluster_ami_ids[count.index]}"

pcluster describe-image \
  -r ${var.region} \
  --image-id ${local.pcluster_ami_ids[count.index]}

echo "Ami ID image: ${local.pcluster_ami_ids[count.index]}"
pcluster describe-image \
  -r ${var.region} \
  --image-id ${local.pcluster_ami_ids[count.index]} \
  --query 'ec2AmiInfo.amiId'
EOF
  }
}

output "pcluster_ami_ids" {
  value = local.pcluster_ami_ids
}

output "pcluster_ami_names" {
  value = local.pcluster_ami_names
}
