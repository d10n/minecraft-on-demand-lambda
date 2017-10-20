#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
Shut off the server
"""

#sudo pip install mcstatus requests
from mcstatus import MinecraftServer
import requests
import time
import json
import os.path
import socket
# import urllib2

server = MinecraftServer.lookup('localhost:25565')

started = True
try:
    status = server.status()
except socket.error as exc:
    started = False

if os.path.exists('/tmp/last_activity'):
    f = open('/tmp/last_activity', 'r+')

    if started and status.players.online:
        f.seek(0)
        f.write(str(time.time()))
        f.truncate()
    else:
        old_time = float(f.read())
        time_passed = time.time() - old_time
        if time_passed > (30 * 60):
            with open('/tmp/auto_shutoff_attempted', 'w') as out:
                out.write('auto shutoff attempted')
            # req = urllib2.urlopen('<SERVER DESTROY LAMBDA FUNCTION>')
            req = requests.delete('${lambda_destroy_url}')
else:
    if started:
        f = open('/tmp/last_activity', 'w')
        f.write(str(time.time()))
