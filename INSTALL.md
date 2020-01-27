### Installation
Requirements:
- Go
- Lego
- a functioning id_ed25519 key pair
- editing services.dat for remote push

##### Remote configuration
- a service accounts with ssh / scp capabilities
- an rw- directory to push certs to
- a root or nginx cron that will detect and move files
- a reload when new certs are pushed
