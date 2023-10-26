#!/bin/bash

printhelp()
{
	echo "Usage: $0 [options] USERNAME

Options:
  -h, --help                    display this help message and exit
  -c, --clear                   Clear all key for user.
  -k, --keynames KEYNAMES       Remove Keys for user.
  -f, --bindfile				set url,binddn,bindpasswd with file
  -H, --url URL					LDAP Uniform Resource Identifier(s)
  -D, --binddn DN				bind DN
  -w, --bindpasswd PASSWORD		bind password" 1>&2
	exit 1
}

setattr()
{
    cmd=$1
    attrname=$2
    attrdata=$3
    echo "dn: cn=$keyname,cn=$username,ou=people,$basedn
changetype: modify
$cmd: $attrname
$attrname: $attrdata" | ldapmodify -x $ldapurl -D "$binddn" -w "$bindpasswd"
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
fi

clearmode=false
keynames=""
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
                -c|--clear)
                        clearmode=true
                        ;;
                -k|--keynames)
                        shift
						keynames=$1
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
                        if [ "$username" == "" ]
                        then
                            username=$1
                        else
                            echo "Bad args ..." 1>&2
                            printhelp
                        fi
                        ;;
        esac
        shift
done

if [ "$username" = "" ] || [ "$binddn" = "" ]
then
	echo "Please add your keynames, username and ldapbinddn." 1>&2
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

if ! hash wg &>/dev/null
then
    echo "Please install wireguard!" 1>&2
    exit 1
fi


if [ "$keynames" != "" ]
then
    IFS=,
    for a in $keynames
    do
        checkname="$(getattr "" cn "cn=$a,ou=wireguard,cn=$username,ou=people" 2>/dev/null)"
        if [ "$checkname" != "" ]
        then
            ldapdelete -x $ldapurl -D "$binddn" -w "$bindpasswd" "cn=$a,ou=wireguard,cn=$username,ou=people,$basedn"
        fi
    done
    unset IFS
fi

if $clearmode
then
    ldapdelete -r -x $ldapurl -D "$binddn" -w "$bindpasswd" "ou=wireguard,cn=$username,ou=people,$basedn"
fi
