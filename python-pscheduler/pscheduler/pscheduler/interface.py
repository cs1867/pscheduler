"""
Functions for figuring out common interface operations
"""

import datetime
import netaddr
import netifaces
import os
import re
import socket

from .ipaddr import *
from .psdns import *


def source_affinity(address, ip_version=None):
    """Easy to use function that returns the CPU affinity
    given an address. Uses source_interface and interface_affinity
    functions call to accomplish, so it's really just a shorthand
    """
    (_, interface) = source_interface(address, ip_version=ip_version)

    if interface is None:
        return None

    return interface_affinity(interface)


def source_interface(address, port=80, ip_version=None):
    """Figure out what local interface is being used to
    reach an address.

    Returns a tuple of (address, interface_name)
    """

    family = ip_addr_version(address, resolve=False, family=True)[0]
    if family is None:
        return (None, None)

    sock = socket.socket(family, socket.SOCK_DGRAM)
    try:
        sock.connect((address, port))
    except socket.error:
        return (None, None)

    interface_address = sock.getsockname()[0]

    sock.close()

    interface_name = address_interface(interface_address, ip_version=ip_version)

    if interface_name:
        return (interface_address, interface_name)

    return (None, None)



def address_interface(address, ip_version=None):
    """Given an address, returns what interface
    has this interface, or None
    """

    # See if the address looks like an address and not a hostname.
    # Make sure we resolve any address to a specific IP address before
    # looking up interfaces

    if not is_ip(address):
        resolved = dns_resolve(address, ip_version=ip_version)
        if resolved is None:
            return None
        address = resolved

    all_interfaces = netifaces.interfaces()
    for interface in all_interfaces:
        addresses = netifaces.ifaddresses(interface)

        for family in addresses:
            for addr_info in addresses[family]:
                if addr_info['addr'] == address:
                    return interface

    return None



def interface_affinity(interface):
    """Given an interface name, returns the CPU affinity
    for that interface if available, otherwise
    returns None.

    PORT: This only works on linux. A good todo might be
    to figure out if it could work on other platforms, but
    given the nature of high speed networking it seems
    like it might not be a big deal.
    """

    # if it's a sub interface, we have to look up the 'main'
    # interface for affinity detection
    match = re.search(r'(.+)\.\d+$', interface)
    if match:
        interface = match.groups()[0]

    filename = "/sys/class/net/%s/device/numa_node" % interface

    if not os.path.exists(filename):
        return None

    with open(filename, 'r') as numa_file:
        affinity = numa_file.read().rstrip()

        # This is the same as no affinity, so make calling
        # functions not care
        if affinity == "-1":
            return None

        return affinity

    return None


class LocalIPList(object):
    """
    Self-refrshing list of local IP addresses
    """

    def __init__(
            self,
            refresh=30  # Maximum age in seconds before refresh
    ):
        self.refresh = refresh
        self.addresses = None
        # Force immediate expiration.
        self.expires = datetime.datetime(year=datetime.MINYEAR, month=1, day=1)


    def __refresh(self):
        """
        Update the list of local interfaces if needed
        """
        if self.addresses is None \
           or datetime.datetime.now() > self.expires:

            self.addresses = {}

            if_regex = r'%.*$'

            # Netifaces returns a very deep structure.
            for ifhash in [netifaces.ifaddresses(iface)
                           for iface in netifaces.interfaces()]:
                for afamily in ifhash:
                    for iface in ifhash[afamily]:
                        address = re.sub(if_regex, '', iface["addr"])
                        try:
                            addr_object = netaddr.IPAddress(address)
                            self.addresses[addr_object] = 1
                        except netaddr.core.AddrFormatError:
                            # Don't care about things that don't look like IPS.
                            pass

            self.expires = datetime.datetime.now() \
                + datetime.timedelta(seconds=self.refresh)


    def __len__(self):
        """Return the number of addresses on the system"""
        self.__refresh()
        return len(self.addresses)


    def __iter__(self):
        """Return an iterator for instances of this class"""
        self.__refresh()
        return iter(self.addresses)


    def __next__(self):
        """Return the next address"""
        if not self.addresses:
            raise StopIteration
        return next(self.addresses)


    def __contains__(self, item):
        """
        Determine if item is in the address list
        """
        self.__refresh()
        item_ip = netaddr.IPAddress(item)
        return item_ip in self.addresses


    def loopback(self, ip_version=None):
        """
        Find the first loopback for IP version 'ip_version', preferring
        IPv6 if None.  If there is no loopback interface, raise an
        IndexError.
        """
        assert ip_version in [ None, 4, 6 ], f'Invalid ip_version {ip_version}'
        self.__refresh()
        loopbacks = filter(lambda v: v.is_loopback(), self.addresses)
        if ip_version is not None:
            try:
                return list(filter(lambda v: v.version == ip_version, loopbacks))[0]
            except IndexError:
                raise IndexError(f'No IPv{ip_version} loopbacks on this system')

        # With no ip_version, sort the list to prefer IPv6 and return whatever is first.
        loopbacks = sorted(loopbacks,
                           key=lambda v: [ v.version, v.sort_key() ],
                           reverse=True  # Prefer IPv6
                           )
        try:
            return list(loopbacks)[0]
        except IndexError:
            raise IndexError('No loopbacks on this system')


if __name__ == "__main__":

    for dest in ["www.perfsonar.net",
                 "10.0.2.4",
                 "obvouslynotavalidhost.perfsonar.net"]:
        (addr, intf) = source_interface(dest)
        print("For dest %s, addr = %s, intf = %s" % (dest, addr, intf))

    for intf in ["eth0", "eth1", "lo", "eth1.412", "eth0.120"]:
        aff = interface_affinity(intf)
        print("interface affinity = %s for %s" % (aff, intf))

    localips = LocalIPList(refresh=5)

    for addr in ["1.2.3.4", "5.6.7.8", "10.0.0.1", "127.0.0.1"]:
        print(addr, addr in localips)
