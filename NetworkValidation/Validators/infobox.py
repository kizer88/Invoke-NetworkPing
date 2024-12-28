import requests
import json
import urllib3
import base64
import socket
import sys
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry

# Disable SSL warnings
urllib3.disable_warnings()


def get_ipam_info(ip_address, username, password):
    base_url = "https://ipam.hpicorp.net/wapi/v2.7"

    # Validate IP address format
    try:
        socket.inet_aton(ip_address)
    except socket.error:
        print(f"Error: Invalid IP address format: {ip_address}")
        return None

    # Authentication
    auth = (username, password)

    # Headers
    headers = {"Content-Type": "application/json", "Accept": "application/json"}

    # Debug auth header
    auth_string = f"{username}:{password}"
    auth_bytes = auth_string.encode("ascii")
    base64_auth = base64.b64encode(auth_bytes).decode("ascii")

    # Setup session with retries and connection pooling
    session = requests.Session()
    retries = Retry(total=3, backoff_factor=0.1, status_forcelist=[500, 502, 503, 504])

    session.mount(
        "https://",
        HTTPAdapter(max_retries=retries, pool_connections=10, pool_maxsize=10),
    )

    try:
        # First test basic connectivity
        socket_test = socket.create_connection(("ipam.hpicorp.net", 443), timeout=5)
        socket_test.close()

        # Get network info
        network_url = f"{base_url}/network?contains_address={ip_address}"

        response = session.get(
            network_url,
            auth=auth,
            headers=headers,
            verify=False,
            timeout=(5, 15),  # Reduced timeouts
        )

        if response.status_code == 200:
            network_data = response.json()
            network_info = (
                network_data[0]
                if network_data and len(network_data) > 0
                else {"network": None, "comment": None}
            )

            # Get IP specific info
            ip_url = f"{base_url}/ipv4address?ip_address={ip_address}"
            ip_response = requests.get(
                ip_url, auth=auth, headers=headers, verify=False, timeout=(10, 30)
            )

            if ip_response.status_code == 200:
                ip_data = ip_response.json()
                ip_info = (
                    ip_data[0]
                    if ip_data and len(ip_data) > 0
                    else {
                        "names": [None, None],
                        "mac_address": None,
                        "status": "NOT_FOUND",
                        "lease_state": None,
                        "usage": [],
                        "types": [],
                    }
                )

                result = {
                    "ip_address": ip_address,
                    "network": network_info.get("network"),
                    "network_comment": network_info.get("comment"),
                    "hostname": (
                        ip_info.get("names", [None])[0]
                        if ip_info.get("names")
                        else None
                    ),
                    "fqdn": (
                        ip_info.get("names", [None])[0]
                        if len(ip_info.get("names", [])) == 1
                        else (
                            ip_info.get("names", [None, None])[1]
                            if len(ip_info.get("names", [])) > 1
                            else None
                        )
                    ),
                    "mac_address": ip_info.get("mac_address"),
                    "status": ip_info.get("status"),
                    "lease_state": ip_info.get("lease_state"),
                    "usage": ip_info.get("usage", []),
                    "types": ip_info.get("types", []),
                }

                # Output only the JSON
                print(json.dumps(result))
                return result

        return None

    except Exception as e:
        sys.stderr.write(f"Error querying IPAM: {str(e)}\n")
        return None


# Test the function
if __name__ == "__main__":
    if len(sys.argv) != 4:
        sys.stderr.write(
            "Usage: python infobox.py <ip_address> <username> <password>\n"
        )
        sys.exit(1)

    ip_address = sys.argv[1]
    username = sys.argv[2]
    password = sys.argv[3]

    result = get_ipam_info(ip_address, username, password)
