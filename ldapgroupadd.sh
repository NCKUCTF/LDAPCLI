#!/bin/bash

printhelp()
{
	echo "Usage: $0 [options] GROUP

Options:
  -g, --gid GID                 use GID for the new group
  -h, --help                    display this help message and exit
  -m, --members USERS			list of users of the new group
  -A, --pveACLs                 Set user pve acl. format: <path>:<rule>,/pool/PVEuser:PVEVMAdmin,...
  -f, --bindfile				set url,binddn,bindpasswd with file
  -H, --url URL					LDAP Uniform Resource Identifier(s)
  -D, --binddn DN				bind DN
  -w, --bindpasswd PASSWORD		bind password"
	exit 0
}

argnum=$#
if [ $argnum -eq 0 ]
then
	printhelp
	exit 0
fi

groupname=""
gid=""
users=""
url=""
binddn=""
bindpasswd=""
pveACLs='[]'

for a in $(seq 1 1 $argnum)
do
        nowarg=$1
        case "$nowarg" in
				-h|--help)
                        printhelp
                        ;;
                -g|--gid)
                        shift
                        gid=$1
                        ;;
                -m|--members)
                        shift
                        users=$(echo $1 | sed "s/,/ /g")
                        ;;
                -A|--pveACLs)
                        shift
                        pveACLs="$(echo "\"$1\"" | jq -c 'split(",") | map({"path": split(":")[0], "rule": split(":")[1]})')"
                        ;;
				-f|--bindfile)
						shift
						url=$(yq e '.url' $1)
						if [ "$url" == "null" ]
						then
							url=""
						fi
						binddn=$(yq e '.binddn' $1)
						if [ "$binddn" == "null" ]
						then
							binddn=""
						fi
						bindpasswd=$(yq e '.bindpasswd' $1)
						if [ "$bindpasswd" == "null" ]
						then
							bindpasswd=""
						fi
						;;
                -H|--url)
                        shift
                        url=$1
                        ;;
                -D|--binddn)
                        shift
                        binddn=$1
                        ;;
                -w|--bindpasswd)
                        shift
                        bindpasswd=$1
                        ;;
                *)
                        if [ "$nowarg" = "" ]
                        then
                                break
                        fi
						groupname=$1
                        ;;
        esac
        shift
done

if [ "$groupname" = "" ] || [ "$binddn" = "" ]
then
	echo "Please add your groupname and ldapbinddn."
	printhelp
fi

if [ "$bindpasswd" = "" ]
then
	read -p "Enter LDAP Password: " -s bindpasswd
fi

if [ "$url" != "" ]
then
	ldapurl="-H $url"
fi

basedn=$(echo $(for a in $(echo "$binddn" | sed "s/,/ /g"); do  printf "%s," $(echo $a | grep dc=); done) | sed "s/^,//g" | sed "s/,$//g")

gid=$(echo $gid | sed "s/[^0-9]//g")

if [ "$gid" = "" ]
then
	gid=$(($(ldapsearch -x $ldapurl -D "$binddn" -w "$bindpasswd" -b "$basedn" "(objectClass=posixGroup)" -LLL | grep gidNumber: | awk '{print $2}' | sort -n | tail -n 1 | sed "s/[^0-9]//g") + 1))
fi

if [ "$gid" = "1" ]
then
	gid=10000
fi

echo "dn: cn=$groupname,ou=groups,$basedn
objectClass: posixGroup
objectClass: memberGroup
cn: $groupname
gidNumber: $gid" | ldapadd -x $ldapurl -D "$binddn" -w "$bindpasswd"

if [ $(echo "$pveACLs" | jq '. | length') -gt 0 ]
then
	echo "dn: cn=$groupname,ou=groups,$basedn
changetype: modify
add: objectClass
objectClass: pveobject" | ldapmodify -x $ldapurl -D "$binddn" -w "$bindpasswd"
fi

for a in $(seq 0 1 $(echo "$pveACLs" | jq '. | length - 1'))
do
	echo "dn: cn=$groupname,ou=groups,$basedn
changetype: modify
add: pveacl
pveacl: $(echo "$pveACLs" | jq -c ".[$a]")" | ldapmodify -x $ldapurl -D "$binddn" -w "$bindpasswd"
done

for a in $users
do
	
	if [ "$(ldapsearch -x $ldapurl -D "$binddn" -w "$bindpasswd" -b "$basedn" "(&(objectClass=person)(uid=$a))" -LLL)" != "" ]
	then
		echo "dn: cn=$groupname,ou=groups,$basedn
changetype: modify
add: memberUid
memberUid: $a
-
add: member
member: cn=$a,ou=people,$basedn" | ldapmodify -x $ldapurl -D "$binddn" -w "$bindpasswd"
	fi
done


