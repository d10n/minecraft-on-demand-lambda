#!/usr/bin/env python
# -*- coding: utf-8 -*-

import os
import sys
import stat
import subprocess
import boto3
import json
import errno


DISCORD_CLIENT_TOKEN = os.environ.get('DISCORD_CLIENT_TOKEN')
DISCORD_CHANNEL = os.environ.get('DISCORD_CHANNEL')

S3_TERRAFORM_PLAN_BUCKET = os.environ.get('S3_TERRAFORM_PLAN_BUCKET')

MODULE_DIR = '/tmp/python_modules'

# Version of Terraform that we're using
TERRAFORM_VERSION = '0.10.5'
# TERRAFORM_VERSION = '0.9.6'

# Download URL for Terraform
TERRAFORM_DOWNLOAD_URL = (
    'https://releases.hashicorp.com/terraform/%s/terraform_%s_linux_amd64.zip'
    % (TERRAFORM_VERSION, TERRAFORM_VERSION))

# Paths where Terraform should be installed
TERRAFORM_DIR = os.path.join('/tmp', 'terraform_%s' % TERRAFORM_VERSION)
TERRAFORM_PATH = os.path.join(TERRAFORM_DIR, 'terraform')


def mkdir_p(path):
    try:
        os.makedirs(path, exist_ok=True)
    except TypeError as exc:
        os.makedirs(path)
    except OSError as exc:  # Python >2.5
        if exc.errno == errno.EEXIST and os.path.isdir(path):
            pass
        else:
            raise


def import_unbundled_packages():
    mkdir_p(MODULE_DIR)
    sys.path.append(MODULE_DIR)
    install_and_import('requests')
    install_and_import('discord.py', import_as='discord')

    # install_and_import('awscli')
    # install_and_import('requests_oauthlib')
    # from requests_oauthlib import OAuth2Session
    # from oauthlib.oauth2 import BackendApplicationClient


def check_call(args, cwd='/tmp', env=None, always_print=False):
    """Wrapper for subprocess that checks if a process runs correctly,
    and if not, prints stdout and stderr.
    """
    proc = subprocess.Popen(args,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        cwd=cwd,
        env=env)
    stdout, stderr = proc.communicate()
    if proc.returncode != 0 or always_print:
        print(stdout)
        print(stderr)
        send_discord_message('Error Building Server')
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

    #urllib.urlretrieve(TERRAFORM_DOWNLOAD_URL, '/tmp/terraform.zip')
    terraform_zip = requests.get(TERRAFORM_DOWNLOAD_URL)
    with open('/tmp/terraform.zip', 'wb') as f:
        f.write(terraform_zip.content)

    # Flags:
    #   '-o' = overwrite existing files without prompting
    #   '-d' = output directory
    check_call(['unzip', '-o', '/tmp/terraform.zip', '-d', TERRAFORM_DIR])


def send_discord_message(message):
    client = discord.Client()
    async def async_part():
        await client.login(DISCORD_CLIENT_TOKEN)
        await client.send_message(discord.Object(id=DISCORD_CHANNEL), message)
        await client.close()
    client.loop.run_until_complete(async_part())



def install_and_import(package, import_as=None):
    import importlib
    if import_as is None:
        import_as = package
    try:
        importlib.import_module(import_as)
    except ImportError:
        import pip
        print(pip.__version__)
        pip.main(['install', '--target', MODULE_DIR, package])
    finally:
        globals()[import_as] = importlib.import_module(import_as)


def apply_terraform_plan(s3_bucket):
    """Download a Terraform plan from S3 and run a 'terraform apply'.

    :param s3_bucket: Name of the S3 bucket where the plan is stored.
    :param path: Path to the Terraform planfile in the S3 bucket.

    """
    # Although the /tmp directory may persist between invocations, we always
    # download a new copy of the planfile, as it may have changed externally.
    mkdir_p('/tmp/terraform_plan/')
    # check_call(['python', '/tmp/python_modules/awscli', 's3', 'sync', 's3://' + s3_bucket, '/tmp/terraform_plan'], env=dict(os.environ, PYTHONPATH=MODULE_DIR))
    s3 = boto3.resource('s3')
    files = [
        'instance.tf',
        'variables.tf',
        'terraform.tfvars',
        'provision_minecraft.sh',
    ]
    for filename in files:
        file = s3.Object(s3_bucket, filename)
        file.download_file('/tmp/terraform_plan/' + filename)
    check_call([TERRAFORM_PATH, 'init'], cwd='/tmp/terraform_plan')
    check_call([TERRAFORM_PATH, 'apply'], cwd='/tmp/terraform_plan')


def destroy_terraform_plan(s3_bucket):
    """Download a Terraform plan from S3 and run a 'terraform apply'.

    :param s3_bucket: Name of the S3 bucket where the plan is stored.
    :param path: Path to the Terraform planfile in the S3 bucket.

    """
    # Although the /tmp directory may persist between invocations, we always
    # download a new copy of the planfile, as it may have changed externally.
    mkdir_p('/tmp/terraform_plan/')
    # check_call(['python', '/tmp/python_modules/awscli', 's3', 'sync', 's3://' + s3_bucket, '/tmp/terraform_plan'], env=dict(os.environ, PYTHONPATH=MODULE_DIR))
    s3 = boto3.resource('s3')
    files = [
        'instance.tf',
        'variables.tf',
        'terraform.tfvars',
        'provision_minecraft.sh',
    ]
    for filename in files:
        file = s3.Object(s3_bucket, filename)
        file.download_file('/tmp/terraform_plan/' + filename)
    check_call([TERRAFORM_PATH, 'init'], cwd='/tmp/terraform_plan')
    check_call([TERRAFORM_PATH, 'destroy','-force'], cwd='/tmp/terraform_plan')


def is_request_id_duplicate(context):
    try:
        with open('/tmp/last_request_id') as file:
            last_request_id = json.load(file)
            if context.aws_request_id == last_request_id:
                return True
    except (FileNotFoundError, json.JSONDecodeError) as exc:
        with open('/tmp/last_request_id', 'w') as file:
            json.dump(context.aws_request_id, file)
    return False


def lambda_handler_destroy(event, context):
    if is_request_id_duplicate(context):
        print('duplicate request id')
        return

    import_unbundled_packages()
    send_discord_message('Stopping Server')
    install_terraform()
    destroy_terraform_plan(s3_bucket=S3_TERRAFORM_PLAN_BUCKET)
    return {
        'statusCode': 200,
        'headers': {'Content-Type': 'application/json'},
        'body': """{"message":"success"}"""
    }


def read_tfvars():
    try:
        with open('/tmp/terraform_plan/terraform.tfvars') as file:
            tfvars = json.load(file)
            return tfvars
    except:
        return {'ip': {'value': 'minecraft.example.com'}}


def lambda_handler_deploy(event, context):
    if is_request_id_duplicate(context):
        print('duplicate request id')
        return

    import_unbundled_packages()
    send_discord_message('Starting Server')
    install_terraform()
    apply_terraform_plan(s3_bucket=S3_TERRAFORM_PLAN_BUCKET)
    ip = read_tfvars()['ip']['value']
    send_discord_message('Server started at {} with Minecraft v1.12.2. Please allow a few minutes for login to become available'.format(ip))
    return {
        'statusCode': 200,
        'headers': {'Content-Type': 'application/json'},
        'body': """{"message":"success"}"""
    }
