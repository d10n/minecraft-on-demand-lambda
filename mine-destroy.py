# -*- coding: utf-8 -*-

import os
import subprocess
import urllib
import boto3
import urllib2
import json


# Version of Terraform that we're using
TERRAFORM_VERSION = '0.9.6'

# Download URL for Terraform
TERRAFORM_DOWNLOAD_URL = (
    'https://releases.hashicorp.com/terraform/%s/terraform_%s_linux_amd64.zip'
    % (TERRAFORM_VERSION, TERRAFORM_VERSION))

# Paths where Terraform should be installed
TERRAFORM_DIR = os.path.join('/tmp', 'terraform_%s' % TERRAFORM_VERSION)
TERRAFORM_PATH = os.path.join(TERRAFORM_DIR, 'terraform')

def send_discord_message(message):
    url = "" # discord url
    data = json.dumps({'content': message})

    req = urllib2.Request(url)
    req.add_header('Content-Type', 'application/json')
    req.add_header('User-Agent', 'Magic Browser')
    response = urllib2.urlopen(req, data)

def check_call(args):
    """Wrapper for subprocess that checks if a process runs correctly,
    and if not, prints stdout and stderr.
    """
    proc = subprocess.Popen(args,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        cwd='/tmp')
    stdout, stderr = proc.communicate()
    if proc.returncode != 0:
        print(stdout)
        print(stderr)
        send_discord_message("Error Destroying Server")
        raise subprocess.CalledProcessError(
            returncode=proc.returncode,
            cmd=args)


def install_terraform():
    """Install Terraform on the Lambda instance."""
    # Most of a Lambda's disk is read-only, but some transient storage is
    # provided in /tmp, so we install Terraform here.  This storage may
    # persist between invocations, so we skip downloading a new version if
    # it already exists.
    # http://docs.aws.amazon.com/lambda/latest/dg/lambda-introduction.html
    if os.path.exists(TERRAFORM_PATH):
        return

    urllib.urlretrieve(TERRAFORM_DOWNLOAD_URL, '/tmp/terraform.zip')

    # Flags:
    #   '-o' = overwrite existing files without prompting
    #   '-d' = output directory
    check_call(['unzip', '-o', '/tmp/terraform.zip', '-d', TERRAFORM_DIR])

    check_call([TERRAFORM_PATH, '--version'])


def destroy_terraform_plan(s3_bucket, path):
    """Download a Terraform plan from S3 and run a 'terraform apply'.

    :param s3_bucket: Name of the S3 bucket where the plan is stored.
    :param path: Path to the Terraform planfile in the S3 bucket.

    """
    # Although the /tmp directory may persist between invocations, we always
    # download a new copy of the planfile, as it may have changed externally.
    s3 = boto3.resource('s3')
    planfile = s3.Object(s3_bucket, path)
    planfile.download_file('/tmp/terraform.tfstate')
    check_call([TERRAFORM_PATH, 'destroy','-force','-state=/tmp/terraform.tfstate'])
    s3.meta.client.upload_file('/tmp/terraform.tfstate', 'terraform-minecraft-plan', 'terraform.tfstate')


def lambda_handler(event, context):
    send_discord_message("Server is now turning off")
    install_terraform()
    destroy_terraform_plan(s3_bucket="terraform-minecraft-plan", path="terraform.tfstate")
