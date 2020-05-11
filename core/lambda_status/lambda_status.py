#!/usr/bin/env python
# -*- coding: utf-8 -*-

from mcstatus import MinecraftServer
import json
import boto3
import os
import subprocess
import socket
from botocore.exceptions import ClientError

S3_TERRAFORM_PLAN_BUCKET = os.environ.get('S3_TERRAFORM_PLAN_BUCKET')
S3_TERRAFORM_STATE_BUCKET = os.environ.get('S3_TERRAFORM_STATE_BUCKET')


def lambda_handler_status(event, context):
    s3 = boto3.resource('s3')

    # Elastic IP
    try:
        files = [
            'terraform.tfvars.json',
        ]
        for filename in files:
            file = s3.Object(S3_TERRAFORM_PLAN_BUCKET, filename)
            file.download_file('/tmp/' + filename)
    except ClientError as exc:
        pass

    # Non-Elastic IP
    try:
        files = [
            'terraform.tfstate',
        ]
        for filename in files:
            file = s3.Object(S3_TERRAFORM_STATE_BUCKET, filename)
            file.download_file('/tmp/' + filename)
    except ClientError as exc:
        pass

    ip = None
    tfstate_ok = None
    tfvars_ok = None
    try:
        with open('/tmp/terraform.tfvars.json') as file:
            tfvars = json.load(file)
            tfvars_ok = True
            ip = tfvars['ip']['value']
    except Exception as exc:
        try:
            with open('/tmp/terraform.tfstate') as file:
                tfstate = json.load(file)
                tfstate_ok = True
                for resource in tfstate['resources']:
                    if resource['type'] == 'aws_instance' and resource['name'] == 'minecraft':
                        ip = resource['instances'][0]['attributes']['public_ip']
        except Exception as exc:
            if not (tfvars_ok and tfstate_ok):
                return {
                    'statusCode': 500,
                    'headers': {'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*'},
                    'body': """{"status": "Internal Server Error (bad tfvars)"}"""
                }

    status = {'status': 'offline'}
    if not ip:
        return {
            'statusCode': 200,
            'headers': {'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*'},
            'body': json.dumps(status)
        }

    try:
        socket.create_connection((ip, 22), timeout=1)
        status['status'] = 'pending'
        status['host'] = ip
    except (socket.error, socket.timeout, Exception) as exc:
        return {
            'statusCode': 200,
            'headers': {'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*'},
            'body': json.dumps(status)
        }

    try:
        server = MinecraftServer.lookup(ip + ':25565')
        status = server.status().raw
        status['status'] = 'online'
        status['host'] = ip
    except AttributeError as exc:
        # silence mcstatus bug:
        # Exception ignored in: <bound method TCPSocketConnection.__del__ of <mcstatus.protocol.connection.TCPSocketConnection object at 0x7fef589619b0>>
        # Traceback (most recent call last):
        # File "/var/task/mcstatus/protocol/connection.py", line 153, in __del__
        #     self.socket.close()
        # AttributeError: 'TCPSocketConnection' object has no attribute 'socket'
        pass
    except Exception as exc:
        pass

    return {
        'statusCode': 200,
        'headers': {'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*'},
        'body': json.dumps(status)
    }
