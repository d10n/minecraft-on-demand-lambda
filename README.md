# minecraft-on-demand-lambda

Turnkey solution for on-demand pushbutton minecraft servers

## Features

 * Creates a URL that deploys the server
 * Auto shutoff after 30 minutes
 * Backup every 5 minutes
 * Costs about $4/mo with light usage and with a static Elastic IP, or about $0.30/mo without a static Elastic IP (see notes at bottom)


## Instructions

Requirements:

 * Terraform
 * JDK 1.8 (if you want spigot)
 * An ssh key pair to SSH into the running Minecraft server:

       ssh-keygen -t rsa -b 2048 -f ~/.ssh/id_minecraft

 * Ensure you have awscli credentials configured: <http://docs.aws.amazon.com/cli/latest/userguide/cli-chap-getting-started.html>
 * Copy core/terraform.tfvars.example to core/terraform.tfvars and fill in the values.
    * See the variables section below for instructions to get the values.
    * The s3 buckets and dynamodb tables will be created with the supplied names; you don't need to create them manually
 * Edit the backend variables at the top of instance/instance.tf

Initial setup:

    make

Spigot setup (optional):

    make spigot # if you prefer spigot to vanilla minecraft

To update after making changes:

    make

Spigot is used if a spigot jar file is detected in the minecraft world backup s3 bucket.


## Variables

To get the discord client token:
 * Click "New Application" on the Applications page: <https://discordapp.com/developers/applications/me>
 * Enter a name and click "Create Application"
 * Click "Create Bot User" and click the confirmation button
 * Click the token reveal link

To add the discord bot to your channel (and get the channel ID):
 * Get the Client ID from the top of your bot's page
 * Visit <https://discordapp.com/oauth2/authorize?client_id=INSERT_CLIENT_ID_HERE&scope=bot&permissions=2048>
 * Follow the instructions to add the bot to your channel
 * On Discord, open User Settings -> Appearance -> Enable Developer Mode
 * Right click on the channel that you added the bot to and click "Copy ID" to get the channel ID

To get the AWS access key and secret key:
 * Visit the IAM console and click Add User
 * Set a user name, check Programmatic Access, and click Next
 * Click the Create group button, enter a group name, check AdministratorAccess, and click Create Group
 * Click Next and then click Create user
 * Write down the Access key ID and Secret access key from the success page, because this is the last time you can get the secret access key!

To get the region:
 * Pick one from the Region column in the tables at <https://docs.aws.amazon.com/general/latest/gr/rande.html>. Make sure it supports Amazon API Gateway and AWS Lambda.
 * I suggest us-east-1

The SSH terraform public key should point to the public key you want to use to SSH into the Minecraft server.

For dynamodb and s3 names, any value is fine as long as it hasn't been used by another AWS user.


## Repository layout

 * `core` configures the AWS infrastructure that can create the Minecraft server on demand
 * `core/core.tf` configures all of the permanent AWS resources, like the S3 buckets, Lambda functions, and API Gateway methods
 * `core/terraform.tfvars` holds your individual settings
 * `core/variables.tf` tells terraform what variables to expect
 * `core/auto_shutoff.py` is downloaded by the instance and periodically run to shut the server off if there were no players for the last 30 minutes
 * `core/lambda_destroy_deploy/lambda_destroy_deploy.py` is the code for the Lambda destroy and deploy functions
 * `core/lambda_status/lambda_status.py` is the code for the Lambda status function
 * `core/lambda_status/requirements.txt` lists the dependencies to be installed for `lambda_status.py`

 * `web/index_src.html` is the template for `web/index.html`. The core deployment plugs in the deploy and status URLs.
 * `web/index.html` is a basic web page with a button to deploy the Minecraft server

 * `instance` is the configuration that the core uses to deploy and destroy the Minecraft server
 * `instance/provision_minecraft.sh` is ec2 user data, which runs when the machine starts
 * `instance/variables.tf` tells terraform how to read `instance/terraform.tfvars`
 * `instance/terraform.tfvars` is generated from the output variables of the core terraform deployment
 * `instance/instance.tf` configures all of the on-demand AWS resources, including the Minecraft EC2 server and its VPC

 * `terraform/terraform-bundle.hcl` configures terraform-bundle to include provider dependencies used by this repository (not currently used)

 * `Makefile` has recipes to run all the required setup commands in the right order
    * `make` deploys or updates the core
    * `make plan` runs `terraform plan` after building the lambda function zip file
    * `make info` shows the variable output from the core deployment
    * `make spigot` compiles spigot and uploads it to your s3 world bucket
    * `make terraform-bundle` compiles a terraform bundle with all provider dependencies included (not currently used)


## Notes

 * If you need more RAM, set a bigger instance size than t2.micro in instance.tf and increase Xmx and Xms in `provision_minecraft.sh` to be a little below the instance size's total allocated RAM
 * The Lambda functions can have bundled dependencies or they can install dependencies when they run. I don't know which I prefer yet and I have both approaches: the destroy and deploy functions install dependencies at runtime, while the status function bundles its dependencies.
 * Terraform 0.10 splits providers out of the main terraform core, but it's possible to build a self-contained bundle with required providers to bundle it with a Lambda function
 * Elastic IP is a static IP that works across redeploys of the server. Using Elastic IP is convenient to avoid DNS TTL caching, but costs can be lowered by using alternative options:
    * Route 53 (configure it yourself)
    * Give the user the IP on the status page for every deploy (comment out all blocks containing "eip" references in `core/core.tf` and `instance/instance.tf`)
