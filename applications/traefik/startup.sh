#!/bin/sh

set -e
set -u

myself=${0##*/}

info()
{
	echo "$myself: $*"
}

# general variables
docker_dir='/path/to/applications'
secret_dir="$docker_dir/secrets"
bridge_name="bridge1"
podman_ipv4_net='10.1'
pod_ipv6_subnet='fdff:z:y:x'

# define pod variables and create pod
pod_name='proxy'
pod_number="$(cat $docker_dir/pod.conf | grep $pod_name | awk '{print $2}')"
pod_ipv4_subnet="${podman_ipv4_net}.${pod_number}"
pod_ipv4_addr="${pod_ipv4_subnet}.100"
pod_ipv6_addr="$pod_ipv6_subnet::$pod_number:100"

#' create bridge interface
create_bridge_interface()
{
	info 'Creating bridge interface ...'
	#. Prepare bridge network
	cat <<-EOF | sudo tee /etc/systemd/network/$bridge_name.netdev
	[NetDev]
	Name=$bridge_name
	Kind=bridge
	EOF
	
	cat <<-EOF | sudo tee /etc/systemd/network/$bridge_name.network
	[Match]
	Name=$bridge_name
	
	[Network]
	Address=${podman_ipv4_net}.0.1/16
	Address=$pod_ipv6_subnet::1/96
	EOF
	
	#. restart systemd-networkd to activate bridge interface
	sudo systemctl restart systemd-networkd
}
#.

#' create pod and link bridge interface
create_pod()
{
	info "Creating pod $pod_name and link $bridge_name into it ..."
	# create pod
	podman pod create --name $pod_name --net=none

	# start a random container within pod to activate pod
	podman run --pod $pod_name --rm alpine

	# connect bridge to pod after first pod container has started
	## InfraContainerID
	ctr_id=$(podman pod inspect $pod_name | grep -i 'InfraContainerID' \
			| awk '{print $2}' | sed -e 's|"||g;s|,||')
	net_ns_name="cont-${ctr_id}"
	ctr_pc_id=$(podman inspect -f '{{.State.Pid}}' "${ctr_id}")
	[[ ! -d /var/run/netns ]] && sudo mkdir -v /var/run/netns
	sudo ln -sfTv "/proc/${ctr_pc_id}/ns/net" "/var/run/netns/${net_ns_name}"
	ip netns list
	## link container to bridge interface (only needed for the first container)
	veth_name="veth${pod_number}00"
	peer_name='eth0'
	sudo ip link add ${veth_name} type veth peer name ${veth_name}p
	sudo ip link set dev ${veth_name} master $bridge_name
	sudo ip link set ${veth_name}p netns "${net_ns_name}"
	## optional: rename peer in namespace
	sudo ip -netns "${net_ns_name}" link set ${veth_name}p name ${peer_name}
	sudo ip link set dev ${veth_name} up
	sudo ip -netns "${net_ns_name}" link set dev ${peer_name} up
	sudo ip -netns "${net_ns_name}" address add ${pod_ipv4_addr}/16 dev ${peer_name}
	sudo ip -netns "${net_ns_name}" route add default via ${podman_ipv4_net}.0.1
	sudo ip -6 -netns "${net_ns_name}" address add ${pod_ipv6_addr}/96 dev ${peer_name}
	sudo ip -6 -netns "${net_ns_name}" route add default via $pod_ipv6_subnet::1
}
#.

#' add port forwarding rules to nftables
add_fwdPorts_nftables()
{
	local interface="$1"
	local protocol="$2"
	local forward_port="$3"
	local target_port="$4"

	info 'Create nftables rules ...'
	sudo nft add rule inet nat prerouting iifname "$interface" \
		$protocol dport { $forward_port } counter \
		dnat ip to "${pod_ipv4_addr}:$target_port"
	sudo nft add rule inet nat prerouting iifname "$interface" \
		$protocol dport { $forward_port } counter \
		dnat ip6 to "[${pod_ipv6_addr}]:$target_port"
}
#.

#' cleanup netns
cleanup_netns()
{
	info 'Cleanup netns ...'
	netns_pids="$(ls /var/run/netns/ -l | awk '{print $NF}' | sed -e 's|/proc/||' -e 's|/.*||')"

	# remove "never-existed" part 1
	[ "$(ls /var/run/netns/ -hula | grep 'cont- ' | awk '{print $(NF-2)}')" = 'cont-' ] && sudo unlink /var/run/netns/cont- 

	for pid in $netns_pids
	do
		# remove "never-existed" part 2
		if [ "$pid" = "0" ]
		then
			netns_names=$(ls /var/run/netns/ -hula | grep '/0/' | awk '{print $(NF-2)}')
			for netns_name in $netns_names
			do
				sudo unlink /var/run/netns/$netns_name
			done
		fi
		# remove zombie container netns
		if [ ! "$(ps aux | awk '{print $2}' | grep $pid)" = "$pid" ]
		then
			netns_name=$(ls /var/run/netns/ -hula | grep "$pid" | awk '{print $(NF-2)}')
			sudo unlink /var/run/netns/$netns_name
			echo "deleted link for $netns_name"
		fi
	done
}
#.

# check if bridge device exists
info 'Check for bridge interface existence ...'
! [ "$(ip a | grep "$bridge_name:" | sed -e 's|:||g' | awk '{{print $2}}')" ] \
	&& create_bridge_interface

# check if pod exists
info 'Check for pod existence ...'
# check if pod exists
! [ "$(podman pod ls | grep "$pod_name" | awk '{{print $2}}')" ] \
	&& create_pod

# create container
## general variables
app_name='traefik'
ctr_name="$pod_name-$app_name"
ctr_image='docker.io/traefik:latest'
restart_policy='unless-stopped'
## container specific variables
ctr_uid='1000'
app_data="$docker_dir/traefik/appdata"
secrets='cf_email cf_api_key htpasswd'

for secret in $secrets
do
	info "(Delete old and re-)Create podman secret $secret  ..."
	[ "$(podman secret ls | grep $secret)" ]\
		&& podman secret rm "$secret"
	podman secret create "$secret" "$secret_dir/$app_name/$secret"
done

info 'Create relevant files cert/log files ...'
if ! [ -f "$app_data/acme/acme.json" ]
then 
	! [ -d "$app_data/acme" ] && \
		install -dm700 -o $ctr_uid -g $ctr_uid "$app_data/acme"
	touch "$app_data/acme/acme.json"
	chmod 600 "$app_data/acme/acme.json"
fi
if ! [ -f "$app_data/logs/traefik.log" ]
then 
	! [ -d "$app_data/logs" ] && \
		install -dm700 -o $ctr_uid -g $ctr_uid "$app_data/logs"
	touch "$app_data/logs/traefik.log"
	chmod 600 "$app_data/logs/traefik.log"
fi
if ! [ -f "$app_data/logs/access.log" ]
then 
	! [ -d "$app_data/logs" ] && \
		install -dm700 -o $ctr_uid -g $ctr_uid "$app_data/logs"
	touch "$app_data/logs/access.log"
	chmod 600 "$app_data/logs/access.log"
fi

info 'Adjust host directory/file permissions ...'
podman unshare chown -R $ctr_uid:$ctr_uid $app_data

info "Start container $ctr_name ..."
podman run -d --pod="$pod_name" \
	-v $docker_dir/resolv.conf:/etc/resolv.conf:ro \
	--restart="$restart_policy" \
	--name "$ctr_name" \
	--user ${ctr_uid}:${ctr_uid} \
	--read-only \
	--cap-drop=ALL \
	--cap-add=NET_BIND_SERVICE \
	--security-opt no-new-privileges \
	-v $app_data/acme:/acme \
	-v $app_data/config/traefik.yml:/etc/traefik.yml \
	-v $app_data/logs:/logs \
	-v $app_data/rules:/rules \
	-e CF_API_EMAIL_FILE=/run/secrets/cf_email \
	-e CF_API_KEY_FILE=/run/secrets/cf_api_key \
	-e HTPASSWD_FILE=/run/secrets/htpasswd \
	--secret cf_email \
	--secret cf_api_key \
	--secret htpasswd \
	"$ctr_image" --configFile=/etc/traefik.yml

#podman generate systemd --new --name "$pod_name" --no-header

cleanup_netns
