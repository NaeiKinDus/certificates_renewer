## Introduction
This tool is composed two shell scripts used as a wrapper around [Go-Acme's Lego](https://github.com/go-acme/lego) and an automatic
certificate updater. You can easily configure where and how your **LE** certificates are pushed, easing the administration
of your HTTPS services.
Both scripts are configured either using command-line flags (call `<script.sh> --help` to have more information), or an
environment file (`.env`) which has an example of located at `.env.example`.

### Certificate generation
The `renew_certs.sh` shell script is the wrapper around **Lego** and will take care of creating or renewing your HTTPS
certificates and then performing copy actions (using cp or scp for example) to where your certificates are needed.
This script supports working on multiple domains at once and will use the domain name as a selector to know where
to send the certificates.
To configure this script's behavior you will use the `services.cfg` file and perform the action of your choice to copy
the generated files.
This script is intended to be used along with a cron entry to ensure that all certificates are renewed within their
90-days validity period.

Here is an example of a working `services.cfg`:
```
# Available variables:
## $CERT_PATH: path to domain certificate
## $PRIV_KEY_PATH: path to domain private key
## $ISSUER_PATH: path to issuer certificate
## $CERT_DIR_PATH: path to all data generated for this domain
## $CURRENT_DIR: directory where the script is located
#
# Example
mydomain.xyz,scp,-i $CURRENT_DIR/ssh_identity/id_ed25519 $CERT_PATH $PRIV_KEY_PATH certificates_manager@server1.mydomain.xyz:/opt/cert_manager/new_certificates
another.io,scp,-i $CURRENT_DIR/ssh_identity/id_ed25519 $CERT_PATH $PRIV_KEY_PATH certificates_manager@web.another.io:/opt/cert_manager/new_certificates
```

### Certificate installation
The `install_certificates.sh` shell script is used to install and restart services that need the updated certificate file
sent by the `renew_certs.sh` script. Using the file `actions.cfg` and pre-made "actions", located in the `available-actions`
directory, this script will know what actions should be executed to perform its duty.

#### Actions
Actions are a way for you to tell the installation script what you want it to do. It comes in two flavor: pre-made actions,
essentially a small script that performs multiple tasks, and core actions, which are basic one-task functions.

##### Pre-made actions
They are available in the `available-actions` directory, such as `nginx.sh`, and are used for well-known services to
avoid you the hassle of doing it by yourself. To use them you first have to enable the selected one using a symlink from
the `available-actions` directory to the `enabled-actions` one. Then you have to reference it, with the assorted arguments
required if applicable, in the `actions.cfg` file.

Here's an example of what it would look like in said file:
```bash
# Actions are below this line
update_nginx
pct_push,114,${CERT_FILE},/tmp${CERT_FILE}
pct_exec,114,ls -lah /root
```

Here's a non-exhaustive list of existing pre-made actions:
- nginx.sh: used to update certificates for NginX,
- pct_exec.sh: used to exec commands for Proxmox containers,
- pct_push.sh: used to push files to Proxmox containers,
- traefik.sh: used to update certificates for Traefik,
- cleanup.sh: called after all other actions, used to remove the certificates once they are successfully installed
everywhere else.

##### Core actions
Core actions are single-task actions performing a basic task like copying a file, changing the permissions of a file
or executing a shell action. They are useful if your setup does not match the one expected by a pre-made action or if
there is no pre-made action available for your specific need. They also are the functions called by pre-made actions !
If you want to see a list of what you can call, just take a look at the functions in `common.sh`.

Here's a non-exhaustive list of these actions and what they do:
- quiet_print: print a message if `-q` flag is **NOT** specified,
- verbose_print: print a message if `-v` flag **IS** specified,
- assert_defined: asserts a variable is not empty,
- assert_executable: asserts a file name is an executable,
- copy_files: copies a file to a specific destination,
- do_chown: performs a chown on a file,
- do_chmod: performs a chmod on a file.

To use a core action you only have to declare its call in `actions.cfg`, no need to enable anything in `enabled-actions`.

##### Actions configuration
The file `actions.cfg` is used to execute a series of actions to update all services. To this end, you have access to
several pre-made actions, but you can also create yours. Either create your own shell script in `actions-available` and
then enable it, or use available core actions to create your own scenario. To this end, you have access to several variables:
- DRY_RUN (0 or 1): set to 1 if no actions should be performed,
- EMAIL_CONTACT (string): email to send reports to; also used by Let's Encrypt,
- NO_OUTPUT (0 or 1): set to 1 if no output is expected,
- VERBOSE (0 or 1): set to 1 if extra information should be printed,
- ENV_FILE (string): path to the loaded `.env` file,
- CERT_FILE (string): full path to the certificate file,
- KEY_FILE (string): full path to the key file,
- DEST_CERT_FILENAME (string): filename of the cert file,
- DEST_KEY_FILENAME (string): filename of the key file.

Additionally, all variables exported in your `.env` file will be available.

### Assumptions
The expected setup is one server used to query Let's Encrypt using the DNS challenge (only this challenge is supported)
and several "clients" to which the generated certificates will be pushed. In order to use scp, a dedicated account is
created on every client machine with an SSH authorization mechanism based on an identity key. A root account could be used
as well but offers less security, so sudo will have to be installed too. Currently, all actions have a sudoers
configuration example. Finally, a cron should be installed on the generating machine to be run every few weeks to
renew certificates automatically, and another cron should be installed on client machines to check if new certificates
are available for installation.

## Installation
### Generator
Requirements:
- [Lego](https://github.com/go-acme/lego),
- bash 4+,
- git,

Optional, but recommended:
- sudo, if the machine generating the certificates needs an update too, and the root account is not used.


To install this project on your machine that will query Let's Encrypt you just have to clone this repository.

### Services
- bash 4+,
- git

Optional, but recommended:
- sudo, if the root account is not used,


To install this project on your clients you just have to clone the repository. It is advised to use a dedicated user for
this process with a sudoers file correctly configured to allow said account to perform the certificates' installation steps.

## Configuration
### Generator
Copy the file `.env.example` to `.env` and modify it according to your needs.
The only required variables are the DNS challenge type (see `lego dnshelp`), and
an API KEY whose name depends on the DNS challenge.
Copy the file `services.example.cfg` to `services.cfg` and modify it so that the generated certificate files will be
automatically copied to the servers needing them.

### Services
Copy the file `.env.example` to `.env` and modify it according to your needs.
The only required variable in this file is **USE_SUDO=1** if you use sudo.
Clone this repository on each server needing the certificates and copy `actions.example.cfg` to `actions.cfg`.
Modify `actions.cfg` to perform all the steps required to update your services with the newly retrieved certificates.
You will have to enable each actions you use in your `actions.cfg` with:
```
ln /path/to/available-actions/action.sh /path/to/enabled-actions`
```

## Usage
### Generator
> WARNING:
> Renewing an SSL certificate IS NOT THE SAME as using the command action `renew`.
> If this script handles a domain it has never handled before, you **MUST** use the `run` action.


If it's the first time you ask for a certificate for your domain **WITH THIS SCRIPT**, you can use:
```bash
./renew_certs.sh run <your_domain> [ <another_domain> ... ]
```

If your .lego directory is already populated:
```bash
./renew_certs.sh renew <your_domain> [ <another_domain> ... ]
```

If you want to create a wildcard certificate, this script uses the V2 Let's Encrypt server, so you can do it this way:
```bash
## will be equivalent to asking certificates for domain.com AND \*.domain.com
./renew_certs.sh run \*.domain.com
```

Once the generator script has finished, the certificates can be found in the `.lego` directory.
The script also works as a hook that is executed every time a certificate is generated.
Take a look at `services.example.cfg`, copy it to `services.cfg`, modify it as needed, and the actions will be
executed on `run`/`renew` actions.

### Services
The new certificates are expected to be present in a directory called "new_certificates". If only one domain is handled,
you can simply do:
```bash
# directory "new_certificates" contains new certificates to install.
./install_certiificates.sh ./new_certificates
```

If you handle multiple domains, you can use a discriminator:
```bash
./install_certiificates.sh -s your_domain.com ./new_certificates
```
