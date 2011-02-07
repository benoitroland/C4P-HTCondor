#!/usr/bin/env python
# -*- coding: utf-8 -*-

# Need ENABLE_RUNTIME_CONFIG = True
# and appopriate config params as 
# shown for this test

from qmf.console import Session
from sys import exit, argv

url = len(argv) > 1 and argv[1] or "amqp://localhost:5672"
session = Session();
try:
	broker = session.addBroker(url)
except:
	print 'Unable to connect to broker'
	exit(1)

quota = 0.01

negotiators = session.getObjects(_class="negotiator", _package='com.redhat.grid')
print "Current Negotiator:"
for negotiator in negotiators:
	print negotiator.Name
	print '\t',negotiator.GetLimits()
	print '\t',negotiator.GetRawConfig('GROUP_NAMES')
	old_quota = negotiator.GetRawConfig('GROUP_QUOTA_DYNAMIC_MGMT.CUMIN')
	print '\t',old_quota.Value
	new_quota = float(old_quota.Value)+quota
	print '\tSetting GROUP_QUOTA_DYNAMIC_MGMT.CUMIN to', new_quota
	ret = negotiator.SetRawConfig('GROUP_QUOTA_DYNAMIC_MGMT.CUMIN',str(new_quota))
	if (ret.status != 0):
		print 'Call failed: ', ret
		exit(1)
	negotiator.Reconfig()
	got_quota = negotiator.GetRawConfig('GROUP_QUOTA_DYNAMIC_MGMT.CUMIN')
	if (str(new_quota) != got_quota.Value):
		print 'SetRawConfig failed!'
		exit(1)

session.delBroker(broker)


