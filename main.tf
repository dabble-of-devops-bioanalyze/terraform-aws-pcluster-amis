locals {
  ami_name = var.ami_name != "" ? var.ami_name : title(join(" ", split("-", module.this.id, )))
}

output "ami_name" {
  value = local.ami_name
}

data "aws_ami" "pcluster" {
  most_recent = true
  owners      = ["247102896272"]

  filter {
    name   = "name"
    values = ["aws-parallelcluster-${var.pcluster_version}-amzn2-hvm-x86_64*"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

output "aws_ami_pcluster" {
  value = data.aws_ami.pcluster
}

data "aws_ami" "deeplearning" {
  count       = length(var.deep_learning_amis)
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "owner-alias"
    values = ["amazon"]
  }

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
# EC2 Image Builder Components
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

data "local_file" "scientific_stack" {
  filename = "${path.module}/files/image-builder/scipy-bootstrap.yml"
}

locals {
  scientific_stack = yamldecode(data.local_file.scientific_stack.content)
}

resource "aws_imagebuilder_component" "scientific_stack" {
  name     = "${module.this.id}-scientific-stack-component"
  platform = "Linux"
  version  = "1.0.0"
  data     = data.local_file.scientific_stack.content
  tags     = module.this.tags
}

output "scientific_stack" {
  value = aws_imagebuilder_component.scientific_stack
}

#resource "aws_imagebuilder_component" "gromacs" {
#  name     = "${module.this.id}-gromacs-component"
#  platform = "Linux"
#  version  = "1.0.0"
#  data     = data.local_file.gromacs.content
#  tags     = module.this.tags
#}
#
#output "gromacs_component" {
#  value = aws_imagebuilder_component.gromacs
#}


locals {
  components = flatten([
    data.aws_imagebuilder_component.aws_imagebuilder_components[*].arn,
    aws_imagebuilder_component.scientific_stack.arn,
  ])
}

locals {
  pcluster_build_config_dir = "files/pcluster-v${var.pcluster_version}"
}

locals {
  ami_ids          = flatten(data.aws_ami.deeplearning[*].image_id)
  ami_names        = flatten(data.aws_ami.deeplearning[*].name)
  pcluster_ami_ids = flatten([
  for i in range(length(local.ami_ids)) : trimspace("${module.this.id}-pcluster-${replace(var.pcluster_version, ".", "-")}--${lower(replace(replace(replace(local.ami_names[i], "(Amazon Linux 2)", "alinux2"), " ", "-") ,".", "-") )}")
  ])
  pcluster_ami_names = flatten([
  for i in range(length(local.ami_ids)) : replace(trimspace("${local.ami_name} PCluster ${var.pcluster_version} ${local.ami_names[i]}"), "(Amazon Linux 2)", "Amazon Linux 2")
  ])
  pcluster_ami_build_config_files = flatten([
  for i in range(length(local.ami_ids)) : "files/pcluster-v${var.pcluster_version}/pcluster_build-${local.pcluster_ami_ids[i]}.yaml"
  ])
  pcluster_ami_build_cloudformation_template_files = flatten([
  for i in range(length(local.ami_ids)) : "files/pcluster-v${var.pcluster_version}/cloudformation-${local.pcluster_ami_ids[i]}.json"
  ])
  pcluster_ami_build_cloudformation_status_files = flatten([
  ])

}

locals {
  dt = formatdate("YYYYMMDD", timestamp())
}

locals {
  # TODO Sanity check
  # Tags must not have '(' or ')' in their values
  pcluster_image_build_template = [
  for i in range(length(local.ami_ids)) :
  {
    Region : var.region,
    Image : {
      Name : local.pcluster_ami_names[i]
      Tags : [
        {
          Key : "Name",
          Value : replace(local.pcluster_ami_names[i], "(Amazon Linux 2)", "Amazon Linux 2" )
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
          Value : replace(local.ami_names[i], "(Amazon Linux 2)", "Amazon Linux 2")
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
        [for key in keys(module.this.tags) : { Key : key, Value : module.this.tags[key] }], [
          { Key : "ParentAmiId", Value : local.ami_ids[i] },
          { Key : "ParentAmiName", Value : replace(local.ami_names[i], "(Amazon Linux 2)", "Amazon Linux 2") }
        ]
      ])
    },
  }
  ]
}

resource "null_resource" "make_dirs" {
  count      = length(local.pcluster_image_build_template)
  depends_on = [
  ]
  provisioner "local-exec" {
    command = <<EOF
mkdir -p files/pcluster-v${var.pcluster_version}
touch ${local.pcluster_ami_build_config_files[count.index]}
touch ${local.pcluster_ami_build_cloudformation_template_files[count.index]}
EOF
  }
}

resource "local_file" "pcluster_build_configurations" {
  depends_on = [null_resource.make_dirs]
  count      = length(local.pcluster_image_build_template)
  filename   = local.pcluster_ami_build_config_files[count.index]
  content    = yamlencode(local.pcluster_image_build_template[count.index])
}

# trick to wait on resources
# https://stackoverflow.com/questions/63744524/sequential-resource-creation-in-terraform-with-count-or-for-each-possible
resource "null_resource" "set_initial_state" {
  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = "echo \"0\" > current_state.txt"
  }
}

resource "null_resource" "pcluster_build_images" {
  count      = length(local.pcluster_image_build_template)
  depends_on = [
    null_resource.make_dirs,
    aws_imagebuilder_component.scientific_stack,
    local_file.pcluster_build_configurations,
    null_resource.set_initial_state,
  ]

  #  provisioner "local-exec" {
  #    interpreter = ["bash", "-c"]
  #    command     = "while [[ $(cat current_state.txt) != \"${count.index}\" ]]; do echo \"${count.index} is waiting...\";sleep 5;done"
  #  }

  provisioner "local-exec" {
    command = <<EOF
pcluster build-image \
  --image-id ${local.pcluster_ami_ids[count.index]} \
  -r ${var.region} \
  -c ${local.pcluster_ami_build_config_files[count.index]}
EOF
  }

  #  provisioner "local-exec" {
  #    interpreter = ["bash", "-c"]
  #    command     = "echo \"${count.index+1}\" > current_state.txt"
  #  }
}

output "pcluster_create_command" {
  count = length(local.pcluster_image_build_template)
  value = <<EOF
pcluster build-image \
  --image-id ${local.pcluster_ami_ids[count.index]} \
  -r ${var.region} \
  -c ${local.pcluster_ami_build_config_files[count.index]}
EOF
}

resource "null_resource" "pcluster_get_cloudformation_templates" {
  count      = length(local.pcluster_image_build_template)
  depends_on = [
    null_resource.make_dirs,
    null_resource.pcluster_build_images,
    local_file.pcluster_build_configurations,
  ]
  provisioner "local-exec" {
    command = <<EOF
  sleep 60
  echo "Fetching cloudformation templates"
  aws cloudformation get-template \
      --stack-name \
    ${local.pcluster_ami_ids[count.index]} > ${local.pcluster_ami_build_cloudformation_template_files[count.index]}
EOF
  }
}

data "local_file" "pcluster_stacks" {
  depends_on = [
    null_resource.pcluster_get_cloudformation_templates
  ]
  count    = length(local.pcluster_image_build_template)
  filename = local.pcluster_ami_build_cloudformation_template_files[count.index]
}

resource "null_resource" "pcluster_wait" {
  count      = length(local.pcluster_image_build_template)
  depends_on = [
    null_resource.make_dirs,
    null_resource.pcluster_build_images,
    local_file.pcluster_build_configurations,
  ]
  provisioner "local-exec" {
    command = <<EOF
# pcluster deletes the stack
# so once this operation is done it will fail with a message about expecting output
for i in {1..5}; do aws cloudformation wait stack-create-complete --stack-name ${local.pcluster_ami_ids[count.index]} && break || sleep 5m; done
EOF
  }
}

output "pcluster_cloudformation_status_files" {
  value = local.pcluster_ami_build_cloudformation_status_files
}

# TODO Write a python script to run sanity checks for images and stacks
resource "null_resource" "pcluster_get_cloudformation_statuses" {
  count      = length(local.pcluster_image_build_template)
  depends_on = [
    null_resource.make_dirs,
    null_resource.pcluster_build_images,
    local_file.pcluster_build_configurations,
    null_resource.pcluster_wait,
  ]
  provisioner "local-exec" {
    command = <<EOF
# pcluster deletes the stack
# so once this operation is done it will fail with a message about expecting output
aws cloudformation describe-stacks \
      --stack-name ${local.pcluster_ami_ids[count.index]} >  ${local.pcluster_ami_build_cloudformation_status_files[count.index]}  || echo "Unable to get cloudformation stack data"
EOF
  }
}

resource "null_resource" "pcluster_image_creation_sanity_check" {
  count      = length(local.pcluster_image_build_template)
  depends_on = [
    null_resource.make_dirs,
    local_file.pcluster_build_configurations,
    null_resource.pcluster_build_images,
    null_resource.pcluster_wait,
  ]
  provisioner "local-exec" {
    command = <<EOF
pcluster describe-image \
  --image-id ${local.pcluster_ami_ids[count.index]} \
  --query 'ec2AmiInfo.amiId'
EOF
  }
}

data "aws_ami" "pcluster_build_image_amis" {
  count      = length(local.pcluster_image_build_template)
  depends_on = [
    null_resource.pcluster_wait,
    null_resource.pcluster_build_images,
    null_resource.pcluster_get_cloudformation_statuses
  ]
  most_recent = true
  owners      = ["self"]

  filter {
    name   = "name"
    values = [
      "${local.pcluster_ami_names[count.index]}*",
    ]
  }
}

output "pcluster_ami_ids" {
  value = local.pcluster_ami_ids
}

output "pcluster_ami_names" {
  value = local.pcluster_ami_names
}

output "pcluster_build_image_amis" {
  value = data.aws_ami.pcluster_build_image_amis
}
