#!/usr/bin python3

# Author: Aravind Prabhakar
# Version: 1.0
# Date: 2022-11-11
# Description: Render template for day0 configs for vSRX on Kubevirt environments as an alternative to cloudinit
# Usage: python3 render_template.py -fxp 192.167.1.1/24 -reg ARD92/vsrx:config -cname vsrxconfig 

import argparse
import os
import docker
from jinja2 import Template

parser = argparse.ArgumentParser()
parser.add_argument("-cname", action='store', dest='CNAME', help='optional param. save the image as .tar file which can be used to copy to other nodes')
parser.add_argument("-reg", action='store', dest='REG', help='registry name. container would be built with tag in format <user>/<regname>:<tag>')
parser.add_argument("-fxp", action='store', dest='FXP', help='fxp address in format w.x.y.z/subnet which needs to be part of day0 config')
args = parser.parse_args()

def renderTemplate():
    """
    render template based on fxp argument passed. This will 
    define the ip address that need to be used for the day0 
    config on vSRX spun on kubevirt
    """
    with open("templates/juniper.conf","r") as fread:
        template = Template(fread.read())
    processip = args.FXP.split("/")
    address = processip[0]
    subnet = processip[1]
    rtemplate = template.render(address=address, subnet=subnet)
    with open("iso_dir/juniper.conf", "w") as fwrite:
        fwrite.write(rtemplate)
    os.system("mkisofs -l -o config.iso iso_dir")

def pushToRegistry():
    """
    build and push container to registry. This image must 
    be used in kubevirt manifest file and mounted as a 
    containerDisk. container name is used to save the image as .tar file
    so that it could be loaded to other machines 
    """
    os.system("docker build -t {} .".format(args.REG))
    #os.system("docker tag {} {}".format(args.CNAME, args.REG))
    if args.CNAME:
        os.system("docker save --output {}.tar {}".format(args.CNAME, args.REG))

def main():
    pathexist = os.path.exists("iso_dir")
    if not pathexist:
        os.mkdir("iso_dir")
    renderTemplate()
    pushToRegistry()
    
if __name__ == '__main__':
    main()



