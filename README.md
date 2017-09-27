# minecraft-on-demand-lambda

Turnkey solution for on-demand pushbutton minecraft servers

## Features:
 * Creates a URL that deploys the server
 * Auto shutoff after 30 minutes
 * Backup every 5 minutes

## Instructions:

Requirements:

 * terraform
 * jdk 1.8 (if you want spigot)
 * A terraform ssh key pair:

       ssh-keygen -t rsa -b 2048 -f ~/.ssh/id_minecraft

 * Ensure you have awscli credentials configured: http://docs.aws.amazon.com/cli/latest/userguide/cli-chap-getting-started.html
 * Copy core/terraform.tfvars.example to core/terraform.tfvars
    * Fill in the values of the terraform.tfvars file. The s3 buckets and dynamodb tables will be created with the supplied names.
 * Edit the backend variables at the top of instance/instance.tf

Initial setup:

    make

Spigot setup (optional):

    make spigot # if you prefer spigot to vanilla minecraft

To update after making changes:

    make

Spigot is used if a spigot jar file is detected in the minecraft world backup s3 bucket.
