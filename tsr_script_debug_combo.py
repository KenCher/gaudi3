#!/usr/bin/python3
#
# SupportAssistCollectionLocalREDFISH. Python script using Redfish API with OEM extension to perform Support Assist operations.
#
# _author_ = Texas Roemer <Texas_Roemer@Dell.com>
# _version_ = 17.0
#
# Copyright (c) 2020, Dell, Inc.
# GNU GPLv2 License

import argparse
import getpass
import json
import logging
import requests
import sys
import time
import warnings

from datetime import datetime
from pprint import pprint

warnings.filterwarnings("ignore")

parser = argparse.ArgumentParser(description="Python script using Redfish API with OEM extension to perform Support Assist(SA) operations. These include export SA report locally, accept End User License Agreement(EULA) or register SA for iDRAC.")
parser.add_argument('-ip',help='iDRAC IP address', required=False)
parser.add_argument('-u', help='iDRAC username', required=False)
parser.add_argument('-p', help='iDRAC password. If you do not pass in argument -p, script will prompt to enter user password which will not be echoed to the screen.', required=False)
parser.add_argument('-x', help='Pass in X-Auth session token for executing Redfish calls.', required=False)
parser.add_argument('--ssl', help='SSL cert verification for all Redfish calls, pass in value \"true\" or \"false\".', required=False)
parser.add_argument('--script-examples', help='Get executing script examples', action="store_true", required=False)
parser.add_argument('--export', help='Export support assist collection locally. You must also use argument --data for export SA collection.', action="store_true", required=False)
parser.add_argument('--accept', help='Accept support assist end user license agreement (EULA)', action="store_true", required=False)
parser.add_argument('--get', help='Get support assist end user license agreement (EULA)', action="store_true", required=False)
parser.add_argument('--register', help='Register SupportAssist for iDRAC. NOTE: You must also pass in registration fields.', action="store_true", required=False)
parser.add_argument('--city', required=False)
parser.add_argument('--companyname', required=False)
parser.add_argument('--country', required=False)
parser.add_argument('--first-email', dest="first_email", required=False)
parser.add_argument('--firstname', required=False)
parser.add_argument('--lastname', required=False)
parser.add_argument('--phonenumber', required=False)
parser.add_argument('--second-firstname', dest="second_firstname", required=False)
parser.add_argument('--second-lastname', dest="second_lastname", required=False)
parser.add_argument('--second-phonenumber', dest="second_phonenumber", required=False)
parser.add_argument('--second-email', dest="second_email", required=False)
parser.add_argument('--street', required=False)
parser.add_argument('--state', required=False)
parser.add_argument('--zip', required=False)
parser.add_argument('--data', help='Pass in value for type of data for Support Assist collection.', required=False)
parser.add_argument('--filter', help='Filter PII: 0 for \"No\", 1 for \"Yes\".', required=False)
parser.add_argument('--filename', help='Custom filename for SupportAssist zip.', required=False, default='sacollect.zip')

args = vars(parser.parse_args())
logging.basicConfig(format='%(message)s', stream=sys.stdout, level=logging.INFO)

def script_examples():
    print("""\n- SupportAssistCollectionLocalREDFISH.py -ip 192.168.0.120 -u root -p calvin --get
    \n- SupportAssistCollectionLocalREDFISH.py -ip 192.168.0.120 -u root --accept
    \n- SupportAssistCollectionLocalREDFISH.py -ip 192.168.0.120 -x bd480... --export --data 0,3
    \n- SupportAssistCollectionLocalREDFISH.py -ip 192.168.0.120 -u root -p calvin --register --city Austin --state Texas --zip 78665 --companyname Dell --country US --firstname test --lastname tester --phonenumber \"512-123-4567\" --first-email \"tester1@yahoo.com\" --second-email \"tester2@gmail.com\" --street \"1234 One Dell Way\"
    \n- SupportAssistCollectionLocalREDFISH.py -ip 192.168.0.120 -u root -p calvin --export --data 1
    \n- SupportAssistCollectionLocalREDFISH.py -ip 192.168.0.120 -u root -p calvin --accept --export --data 1 --filename R640_SA_collection.zip""")
    sys.exit(0)

def check_supported_idrac_version():
    global idrac_ip, idrac_username, idrac_password, verify_cert
    supported = "no"
    if args["x"]:
        response = requests.get('https://%s/redfish/v1/Managers/iDRAC.Embedded.1/Oem/Dell/DellLCService' % idrac_ip, verify=verify_cert, headers={'X-Auth-Token': args["x"]})
    else:
        response = requests.get('https://%s/redfish/v1/Managers/iDRAC.Embedded.1/Oem/Dell/DellLCService' % idrac_ip, verify=verify_cert,auth=(idrac_username, idrac_password))
    if response.__dict__['reason'] == "Unauthorized":
        logging.error("\n- FAIL, unauthorized to execute Redfish command.")
        sys.exit(0)
    for i in response.json()['Actions'].keys():
        if "SupportAssistCollection" in i:
            supported = "yes"
    if supported == "no":
        logging.warning("\n- WARNING, iDRAC version not supported.")
        sys.exit(0)

def get_server_generation():
    global idrac_model
    if args["x"]:
        response = requests.get('https://%s/redfish/v1/Managers/iDRAC.Embedded.1?$select=Model' % idrac_ip, verify=verify_cert, headers={'X-Auth-Token': args["x"]})
    else:
        response = requests.get('https://%s/redfish/v1/Managers/iDRAC.Embedded.1?$select=Model' % idrac_ip, verify=False,auth=(idrac_username,idrac_password))
    data = response.json()
    if response.status_code == 401:
        logging.error("\n- ERROR, status code 401 detected.")
        sys.exit(0)
    elif response.status_code != 200:
        logging.warning("\n- WARNING, unable to get current server model generation")
        sys.exit(0)
    if "14" in data["Model"] or "15" in data["Model"] or "16" in data["Model"]:
        idrac_model = 9
    else:
        idrac_model = 10

def support_assist_collection():
    global job_id_uri, start_time
    start_time = datetime.now()
    url = 'https://%s/redfish/v1/Managers/iDRAC.Embedded.1/Oem/Dell/DellLCService/Actions/DellLCService.SupportAssistCollection' % (idrac_ip)
    payload = {"ShareType":"Local"}
    if args["filter"]:
        payload["Filter"] = "Yes" if args["filter"] == "1" else "No"
    if args["data"]:
        data_selector_values=[]
        for v in args["data"].split(","):
            v = v.strip()
            if v == "0": data_selector_values.append("DebugLogs")
            if v == "1": data_selector_values.append("HWData")
            if v == "2": data_selector_values.append("OSAppData")
            if v == "3": data_selector_values.append("TTYLogs")
            if v == "4": data_selector_values.append("TelemetryReports")
            if v == "5": data_selector_values.append("GPULogs")
        payload["DataSelectorArrayIn"] = data_selector_values
    headers = {'content-type': 'application/json'}
    if args["x"]:
        headers['X-Auth-Token'] = args["x"]
    response = requests.post(url, data=json.dumps(payload), headers=headers, verify=verify_cert, auth=None if args["x"] else (idrac_username,idrac_password))
    if response.status_code != 202:
        logging.error("\n- FAIL, status code %s returned: %s" % (response.status_code, response.json()))
        sys.exit(0)
    try:
        job_id_uri = response.headers.get('Location')
    except Exception:
        logging.error("- FAIL, unable to find job ID in headers POST response.")
        sys.exit(0)
    job_id = job_id_uri.split("/")[-1] if job_id_uri else "unknown"
    logging.info("\n- PASS, job ID %s successfully created for SupportAssistCollection method\n" % job_id)

def support_assist_accept_EULA():
    url = 'https://%s/redfish/v1/Managers/iDRAC.Embedded.1/Oem/Dell/DellLCService/Actions/DellLCService.SupportAssistAcceptEULA' % (idrac_ip)
    headers = {'content-type': 'application/json'}
    if args["x"]: headers['X-Auth-Token'] = args["x"]
    response = requests.post(url, data=json.dumps({}), headers=headers, verify=verify_cert, auth=None if args["x"] else (idrac_username,idrac_password))
    if response.status_code in (200, 202):
        logging.info("\n- PASS, EULA accepted.")
    else:
        logging.error("\n- FAIL, status code %s returned: %s" % (response.status_code, response.json()))
        sys.exit(0)

def support_assist_get_EULA_status():
    global accept_interface
    url = 'https://%s/redfish/v1/Managers/iDRAC.Embedded.1/Oem/Dell/DellLCService/Actions/DellLCService.SupportAssistGetEULAStatus' % (idrac_ip)
    headers = {'content-type': 'application/json'}
    if args["x"]: headers['X-Auth-Token'] = args["x"]
    response = requests.post(url, data=json.dumps({}), headers=headers, verify=verify_cert, auth=None if args["x"] else (idrac_username,idrac_password))
    data = response.json()
    if args["accept"]:
        accept_interface = data.get("Interface")
    else:
        logging.info("\n- Current Support Assist EULA Info -\n")
        for k, v in data.items():
            if "ExtendedInfo" not in k:
                print("%s: %s" % (k,v))

def support_assist_register():
    url = 'https://%s/redfish/v1/Managers/iDRAC.Embedded.1/Oem/Dell/DellAttributes/iDRAC.Embedded.1' % idrac_ip
    payload = {"Attributes":{"OS-BMC.1.AdminState":"Enabled"}}
    headers = {'content-type': 'application/json'}
    if args["x"]: headers['X-Auth-Token'] = args["x"]
    response = requests.patch(url, data=json.dumps(payload), headers=headers, verify=verify_cert, auth=None if args["x"] else (idrac_username,idrac_password))
    if response.status_code != 200:
        logging.error("\n- FAIL, Command failed for action, status code is: %s\n" % response.status_code)
        logging.error("Extended Info Message: {0}".format(response.json()))
        sys.exit(0)
    url = 'https://%s/redfish/v1/Managers/iDRAC.Embedded.1/Oem/Dell/DellLCService/Actions/DellLCService.SupportAssistRegister' % (idrac_ip)
    payload = {
        "City": args["city"], "CompanyName": args["companyname"], "Country":args["country"],
        "PrimaryFirstName":args["firstname"],"PrimaryLastName":args["lastname"], "PrimaryPhoneNumber":args["phonenumber"],
        "State":args["state"], "Street1": args["street"],"Zip":args["zip"]
    }
    if args["first_email"]: payload["PrimaryEmail"] = args["first_email"]
    if args["second_email"]: payload["SecondaryEmail"] = args["second_email"]
    if args["second_firstname"]: payload["SecondaryFirstName"] = args["second_firstname"]
    if args["second_lastname"]: payload["SecondaryLastName"] = args["second_lastname"]
    if args["second_phonenumber"]: payload["SecondaryPhoneNumber"] = args["second_phonenumber"]
    response = requests.post(url, data=json.dumps(payload), headers=headers, verify=verify_cert, auth=None if args["x"] else (idrac_username,idrac_password))
    if response.status_code in (200, 202):
        logging.info("\n- PASS, SupportAssistRegister action passed, status code %s returned" % response.status_code)
    else:
        logging.error("\n- FAIL, SupportAssistRegister action failed, status code %s: %s" % (response.status_code, response.text))
        sys.exit(0)

def loop_job_status_iDRAC9():
    loop_count = 0
    job_id = job_id_uri.split("/")[-1] if job_id_uri else "unknown"
    while True:
        if loop_count == 30:
            logging.info("- INFO, retry count of 30 for GET request has been elapsed, script will exit.")
            sys.exit(0)
        try:
            url = 'https://%s%s' % (idrac_ip, job_id_uri)
            headers = {'X-Auth-Token': args["x"]} if args.get("x") else {}
            response = requests.get(url, verify=verify_cert, headers=headers if args.get("x") else None, auth=None if args.get("x") else (idrac_username, idrac_password))
        except Exception as e:
            logging.error(f"- ERROR: {e}")
            time.sleep(5)
            loop_count += 1
            continue
        current_time = (datetime.now()-start_time)
        if response.status_code not in (200, 202):
            logging.error("- FAIL, status code %s returned, GET command will retry" % response.status_code)
            time.sleep(10)
            loop_count += 1
            continue
        try:
            data = response.json()
        except Exception:
            logging.info("- INFO, unable to parse JSON response, retry")
            time.sleep(5)
            loop_count += 1
            continue
        location = response.headers.get('Location')
        if location and "sacollect.zip" in location.lower():
            logging.info("- PASS, job ID %s successfully marked completed" % job_id)
            file_url = 'https://%s%s' % (idrac_ip, location)
            headers = {'X-Auth-Token': args["x"]} if args.get("x") else {}
            file_resp = requests.get(file_url, verify=verify_cert, headers=headers if args.get("x") else None, auth=None if args.get("x") else (idrac_username, idrac_password))
            fname = args.get("filename") or "sacollect.zip"
            with open(fname, "wb") as output:
                output.write(file_resp.content)
            logging.info("\n- INFO, check your local directory for \"%s\"" % fname)
            sys.exit(0)
        if str(current_time)[0:7] >= "0:30:00":
            logging.error("\n- FAIL: Timeout of 30 minutes has been hit, script stopped\n")
            sys.exit(0)
        elif data.get("JobState") == "CompletedWithErrors":
            logging.info("\n- INFO, SA collection completed with errors.")
            sys.exit(0)
        elif any([("Fail" in data.get("Message", "")), ("fail" in data.get("Message", "")), (data.get("JobState") == "Failed"), ("error" in data.get("Message", "")), ("Error" in data.get("Message", ""))]):
            logging.error("- FAIL: job ID %s failed, failed message is: %s" % (job_id, data.get("Message", "N/A")))
            sys.exit(0)
        elif data.get("JobState") == "Completed" or ("complete" in data.get("Message", "").lower()):
            if "local path" in data.get('Message', ''):
                logging.info("\n--- PASS, Final Detailed Job Status Results ---\n")
                for i in data.items():
                    pprint(i)
            else:
                loc = response.headers.get('Location', 'unknown')
                logging.warning("- WARNING, unable to detect final job status. Browse URI \"%s\" to see if SA zip is available." % loc)
            break
        else:
            logging.info("- INFO, Job status not marked completed; polling again, execution time: %s" % str(current_time)[0:7])
            time.sleep(5)

if __name__ == "__main__":
    if args["script_examples"]:
        script_examples()
    if args.get("ip") and (args.get("ssl") or args.get("u") or args.get("p") or args.get("x")):
        idrac_ip = args["ip"]
        idrac_username = args.get("u")
        if args.get("p"):
            idrac_password = args.get("p")
        if not args.get("p") and not args.get("x") and args.get("u"):
            idrac_password = getpass.getpass("\n- INFO, argument -p not detected, enter iDRAC user %s password: " % args["u"])
        ssl_value = args.get("ssl")
        if ssl_value is not None and ssl_value.lower() == "true":
            verify_cert = True
        else:
            verify_cert = False
        check_supported_idrac_version()
    else:
        logging.error("\n- FAIL, invalid argument values. See help or --script-examples.")
        sys.exit(0)
    if args.get("accept"):
        support_assist_get_EULA_status()
        if not globals().get("accept_interface", None):
            support_assist_accept_EULA()
        else:
            logging.info("\n- WARNING, SupportAssist EULA has already been accepted")
        if not args.get("export"):
            sys.exit(0)
    if args.get("export"):
        support_assist_collection()
        get_server_generation()
        if globals().get("idrac_model", 9) == 9:
            loop_job_status_iDRAC9()
        else:
            logging.warning("- WARNING, manual job status check may be needed (non-9th gen server)")
        sys.exit(0)
    if args.get("get"):
        support_assist_get_EULA_status()
        sys.exit(0)
    if args.get("register") and args.get("city") and args.get("companyname") and args.get("country") and args.get("firstname") and args.get("lastname") and args.get("phonenumber") and args.get("state") and args.get("street") and args.get("zip"):
        support_assist_register()
        sys.exit(0)
    else:
        logging.error("\n- FAIL, invalid argument values or not all required parameters passed in. See help or --script-examples.")
