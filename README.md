### Installation
Requirements:
- Go
- [Lego](https://github.com/go-acme/lego)

### Usage
#### Configuration
Copy the file `.env.example` to `.env` and modify it according to your needs.
The only required variables are the DNS challenge type (see `lego dnshelp`), and
an API KEY whose name depends on the DNS challenge.

#### Querying Let's Encrypt
If it's the first time you ask for a certificate for your domain, you can use:
```shell script
./renew_certs.sh run <your_domain> [ <another_domain> ... ]
```

If your .lego directory is already populated:
```shell script
./renew_certs.sh renew <your_domain> [ <another_domain> ... ]
```

> WARNING:
> Renewing an SSL certificate IS NOT THE SAME as using the command action `renew`.
> If this script handles a new domain, you **MUST** use the `run` action.

#### Using certificates
Once the script has finished, the certificates can be found in the `.lego` directory.
The script also works as a hook that is executed every time a certificate is generated.
Take a look at `services.example.dat`, copy it to `services.dat`, modify it as needed, and the actions will be
executed on `run`/`renew` actions.

#### Remote configuration
***TODO***