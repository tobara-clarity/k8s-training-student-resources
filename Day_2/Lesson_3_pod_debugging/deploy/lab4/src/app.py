import os
import sys
import time


required_var = os.environ.get("REQUIRED_ENV4")

with open("/var/log/log.txt", "r+") as f:

    if (not required_var or require_var != "true"):
        f.write("Missing or incorrect value for required variable REQUIRED_ENV. Set it to True.")
        exit(1)

    while True:
        time.sleep(600)

