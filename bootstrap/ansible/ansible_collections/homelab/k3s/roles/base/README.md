Role Name
=========

A brief description of the role goes here.

Requirements
------------

Any pre-requisites that may not be covered by Ansible itself or the role should be mentioned here. For instance, if the role uses the EC2 module, it may be a good idea to mention in this section that the boto package is required.

Role Variables
--------------

- `k3s_install_version`: The version of k3s to install. Defaults to `""` (empty string), which triggers the installation of the current stable version from https://get.k3s.io. If a version is specified, the role will ensure that version is installed.
- `disable_flannel`: Boolean to disable flannel CNI.
- `disable_traefik`: Boolean to disable traefik ingress.
- `disable_servicelb`: Boolean to disable servicelb.
- `disable_embedded_registry`: Boolean to disable embedded registry.

Dependencies
------------

None.

Example Playbook
----------------

Including an example of how to use your role (for instance, with variables passed in as parameters) is always nice for users too:

    - hosts: servers
      roles:
         - role: homelab.k3s.base
           vars:
             k3s_install_version: "v1.31.0+k3s1"

License
-------

BSD

Author Information
------------------

An optional section for the role authors to include contact information, or a website (HTML is not allowed).
