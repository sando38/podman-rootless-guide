#!/bin/sh

# general variables
docker_dir='/path/to/applications'
secret_dir="$docker_dir/secrets"
tmp_dir='/tmp/acme.sh'
cert_application="ejabberd"
cert_dir="$docker_dir/$cert_application/appdata/$cert_application/tls"
dhparam_path="$docker_dir/$cert_application/appdata/$cert_application/dhparam"
dhparam_file="$dhparam_path/dh.pem"
email='iamgroot@example.com'
acme_sh="$HOME/.acme.sh/acme.sh"

# install acme.sh and create account
wget -O -  https://get.acme.sh | sh
$acme_sh --register-account -m $email

# create cert directory
! [ -d "$cert_dir" ] && mkdir -p "$cert_dir"
podman unshare rm -rf "$cert_dir/*"

# create tmp folder
! [ -d "$tmp_dir" ] && mkdir -p "$tmp_dir"

# create certs
domains='example.net'
#'
for domain in $domains
do
	echo "create/ renew certificates for domain $domain"
	export CF_Token="213434134341351351355"
	$acme_sh --issue --dns dns_cf \
		--keylength ec-384 \
		--always-force-new-domain-key \
		-d $domain \
		-d comments.$domain \
		-d conference.$domain \
		-d news.$domain \
		-d upload.$domain \
		-d proxy.$domain \
		-d vjud.$domain \
		--server zerossl \
		--key-file "$tmp_dir/$domain-key.pem" \
		--ca-file "$tmp_dir/$domain-ca.pem" \
		--cert-file "$tmp_dir/$domain-crt.pem" \
		--fullchain-file "$tmp_dir/$domain-fullchain.pem" \
		--force
done

podman unshare cp "$tmp_dir/*.pem" "$cert_dir"

# create dhparam
echo "create/ renew dh-parameters"
if [ ! -f $dhparam_file ]
then 
	mkdir -p $dhparam_path
	openssl dhparam -out '/tmp/dh.pem' '4096'
else
	echo "use existing dh-parameters"
fi

podman unshare cp '/tmp/dh.pem' "$dhparam_path"
