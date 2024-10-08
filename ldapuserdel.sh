#!/bin/bash

printhelp()
{
	echo "Usage: $0 [options] LOGIN

Options:
  -h, --help                    display this help message and exit
  -f, --bindfile				set url,binddn,bindpasswd with file
  -H, --url URL					LDAP Uniform Resource Identifier(s)
  -D, --binddn DN				bind DN
  -w, --bindpasswd PASSWORD		bind password"
	exit 0
}

getattr()
{
    filter=$1
    attrname=$2
    subbasedn=$3
    if [ "$subbasedn" != "" ]
    then
        subbasedn="${subbasedn},"
    fi
    ldapsearch -x $ldapurl -D "$binddn" -w "$bindpasswd" -b "$subbasedn$basedn" "$filter" "$attrname" -LLL | grep -P "^$attrname:" | cut -d ' ' -f 2-
}

argnum=$#
if [ $argnum -eq 0 ]
then
	printhelp
	exit 0
fi

username=""
url=""
binddn=""
bindpasswd=""

for a in $(seq 1 1 $argnum)
do
        nowarg=$1
        case "$nowarg" in
				-h|--help)
                        printhelp
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
						username=$1
                        ;;
        esac
        shift
done

if [ "$username" = "" ] || [ "$binddn" = "" ]
then
	echo "Please add your username and ldapbinddn."
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

groupsdn=$(getattr "(&(objectClass=person)(uid=$username))" memberOf)

gid=$(getattr "(&(objectClass=person)(uid=$username))" gidNumber)

if [ "$gid" == "" ]
then
    echo "username no exist!" 1>&2
    exit 1
fi

gidgroupdn=$(getattr "(&(objectClass=posixGroup)(gidNumber=$gid))" dn)

IFS="
"
for a in $groupsdn
do
	echo "dn: $a
changetype: modify
delete: memberUid
memberUid: $username
-
delete: member
member: cn=$username,ou=people,$basedn" | ldapmodify -x $ldapurl -D "$binddn" -w "$bindpasswd"
done
unset IFS

if [ "$(getattr "(&(objectClass=posixGroup)(gidNumber=$gid))" memberUid)" = "" ]
then
	ldapdelete -x $ldapurl -D "$binddn" -w "$bindpasswd" $gidgroupdn
else
	echo "$0: group $(getattr "(&(objectClass=posixGroup)(gidNumber=$gid))" cn) not removed because it has other members."
fi

ldapdelete -r -x $ldapurl -D "$binddn" -w "$bindpasswd" "cn=$username,ou=people,$basedn"
