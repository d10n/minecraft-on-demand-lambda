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
# import urllib2

server = MinecraftServer.lookup('localhost:25565')
status = server.status()

if os.path.exists('/last_activity'):
    f = open('/last_activity', 'r+')

    if status.players.online:
        f.seek(0)
        f.write(str(time.time()))
        f.truncate()
    else:
        old_time = float(f.read())
        time_past = time.time() - old_time
        if time_past > (30 * 60):
            with open('/auto_shutoff_attempted', 'w') as out:
                out.write('auto shutoff attempted')
            # req = urllib2.urlopen('<SERVER DESTROY LAMBDA FUNCTION>')
            req = requests.delete('${lambda_destroy_url}')
else:
    f = open('/last_activity', 'w')
    f.write(str(time.time()))
