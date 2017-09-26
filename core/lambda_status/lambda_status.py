#!/usr/bin/env python
# -*- coding: utf-8 -*-

from mcstatus import MinecraftServer
import json
import boto3
import os
import subprocess
import socket

S3_TERRAFORM_PLAN_BUCKET = os.environ.get('S3_TERRAFORM_PLAN_BUCKET')


def lambda_handler_status(event, context):
    s3 = boto3.resource('s3')
    files = [
        'terraform.tfvars',
    ]
    for filename in files:
        file = s3.Object(S3_TERRAFORM_PLAN_BUCKET, filename)
        file.download_file('/tmp/' + filename)

    try:
        with open('/tmp/terraform.tfvars') as file:
            tfvars = json.load(file)
            ip = tfvars['ip']['value']
    except Exception as exc:
        return {
            'statusCode': 500,
            'headers': {'Content-Type': 'application/json'},
            'body': """{"status": "Internal Server Error (bad tfvars)"}"""
        }

    try:
        server = MinecraftServer.lookup(ip + ':25565')
        status = server.status().raw
        status['status'] = 'online'
    except AttributeError as exc:
        # silence mcstatus bug:
        # Exception ignored in: <bound method TCPSocketConnection.__del__ of <mcstatus.protocol.connection.TCPSocketConnection object at 0x7fef589619b0>>
        # Traceback (most recent call last):
        # File "/var/task/mcstatus/protocol/connection.py", line 153, in __del__
        #     self.socket.close()
        # AttributeError: 'TCPSocketConnection' object has no attribute 'socket'
        status = {'status': 'offline'}
    except Exception as exc:
        status = {'status': 'offline'}

    if status['status'] == 'offline':
        # s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        try:
            socket.create_connection((ip, 22), timeout=1)
            status['status'] = 'pending'
        except socket.error as exc:
            pass

    return {
        'statusCode': 200,
        'headers': {'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*'},
        'body': json.dumps(status)
    }
