#!/usr/bin/python3

import json
import os
import waitress
import yaml

from flask import Flask, jsonify, request
from paste.translogger import TransLogger


def find_dhcp_assignment(ip):
    # Iterate over all machines, using the dict key as the name
    for name, machine in machines.items():
        for net in machine.get('networks', []):
            if net.get('ip') == ip:
                # Return a dict with name, mac, ip, and any other needed fields
                return {
                    'name': name,
                    'mac': net.get('mac'),
                    'ip': net.get('ip'),
                    'machine': machine
                }
    return None


def find_machine(name):
    return machines.get(name, None)


def find_machine_by_ip(ip):
    a = find_dhcp_assignment(ip)
    if a is None:
        return None

    m = find_machine(a.get('name', None))
    if m is None:
        return None

    # If fqdn is missing, try to construct it from network data
    if not m.get('fqdn'):
        # Try to get domain from the first network
        domain = None
        for net in m.get('networks', []):
            if net.get('domain'):
                domain = net['domain']
                break
        if domain:
            m['fqdn'] = f"{m.get('name', 'unknown')}.{domain}"
        else:
            m['fqdn'] = m.get('name', 'unknown')

    return m


def init():
    bgp_networks = read_yaml('/var/lib/libvirt/nocloud-metadata/bgp_networks.yaml')
    machines = read_yaml('/var/lib/libvirt/nocloud-metadata/machines.yaml')
    networks = read_yaml('/var/lib/libvirt/nocloud-metadata/networks.yaml')
    ssh_keys = read_yaml('/var/lib/libvirt/nocloud-metadata/ssh_keys.yaml')
    root_password_hash = '!'
    with open('/var/lib/libvirt/nocloud-metadata/root_password_hash.txt', 'r') as f:
        root_password_hash = f.read().strip()

    return bgp_networks, machines, networks, ssh_keys, root_password_hash


def read_yaml(fname):
    try:
        with open(fname, 'r') as f:
            return yaml.load(f, Loader=yaml.FullLoader)
    except Exception:
        return {}


app = Flask(__name__)
bgp_networks, machines, networks, ssh_keys, root_password_hash = init()


@app.route('/')
def index():
    return ''

@app.route('/2021-01-03/dynamic/instance-identity/document')
def iid():
    result = {
        "availabilityZone": "vmmd-local",
        "instanceId": "i-{}".format(request.remote_addr),
        "region": "vmmd-local",
    }
    return jsonify(result), 200


@app.route('/2021-01-03/meta-data/public-keys')
def meta_data_public_keys():
    result = ""
    for idx, val in enumerate(ssh_keys):
        result += "{}={}\n".format(idx, idx)
    return app.response_class(content=result), 200


@app.route('/2021-01-03/meta-data/public-keys/<int:idx>')
def meta_data_public_keys_idx(idx):
    if not ssh_keys.get(idx, None):
        return app.response_class(mimetype='text/plain'), 404
    return app.response_class(content='openssh-key'), 200


@app.route('/2021-01-03/meta-data/public-keys/<int:idx>/openssh-key')
def meta_data_public_keys_idx_openssh_key(idx):
    if not ssh_keys.get(idx, None):
        return app.response_class(mimetype='text/plain'), 404
    return app.response_class(content=ssh_keys[idx]), 200


@app.route('/latest/api/token', methods=['PUT'])
def latest_api_token():
    return app.response_class(mimetype='text/plain'), 200


@app.route('/meta-data')
def meta_data():
    m = find_machine_by_ip(request.remote_addr)
    if m is None:
        return app.response_class(mimetype='text/plain'), 404

    content = '''---
instance-id: {}-0000001
local-hostname: {}
'''.format(m.get('name', 'unknown'), m.get('fqdn', 'unknown'))

    return app.response_class(response=content), 200


@app.route('/user-data')
def user_data():
    m = find_machine_by_ip(request.remote_addr)
    if m is None:
        return app.response_class(mimetype='text/plain'), 404


    content = '''#cloud-config
hostname: {}
fqdn: {}

ssh_authorized_keys: {}

runcmd:
    - [ /usr/bin/systemctl, mask, cloud-config.service ]
    - [ /usr/bin/systemctl, mask, cloud-final.service ]
    - [ /usr/bin/systemctl, mask, cloud-init.service ]
    - [ /usr/bin/systemctl, mask, cloud-init-local.service ]
    - [ /usr/bin/systemctl, mask, cloud-config.target ]
'''.format(m.get('name', 'unknown'), m.get('fqdn', 'unknown'), json.dumps(ssh_keys), m.get('root_password_hash', root_password_hash))

    return app.response_class(response=content), 200


@app.route('/vendor-data')
def vendor_data():
    return app.response_class(response=''), 200


@app.route('/machines')
def route_machines():
    return jsonify(machines)


@app.route('/networks')
def route_networks():
    return jsonify(networks)


@app.route('/ssh-keys')
def route_ssh_keys():
    return jsonify(ssh_keys)


if __name__ == '__main__':
    # Get port from environment variable, default to 8041
    port = int(os.environ.get('NOCLOUD_METADATA_PORT', 8041))
    waitress.serve(TransLogger(app, setup_console_handler=False), host='0.0.0.0', port=port, url_scheme='http')