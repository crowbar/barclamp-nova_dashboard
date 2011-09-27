# FIXME(ja): this is because dashboard has some odd pathings
import sys
sys.path.append('/var/lib/dash/')

import logging
import os
import django.core.handlers.wsgi
from django.conf import settings

os.environ['DJANGO_SETTINGS_MODULE'] = 'dashboard.settings'
sys.stdout = sys.stderr

DEBUG = False

application = django.core.handlers.wsgi.WSGIHandler()

