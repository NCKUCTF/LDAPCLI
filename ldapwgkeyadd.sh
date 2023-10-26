#!/bin/bash

printhelp()
{
	echo "Usage: $0 [options] KEYNAME USERNAME

Options:
  -h, --help                    display this help message and exit
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

getindex()
{
    allindex="$(getattr "" ipindex "ou=people" | sort -n)"

    tmpindex=1
    for a in $allindex
    do
        if [ $a -eq $tmpindex ]
        then
            tmpindex=$(($tmpindex+1))
        else
            break
        fi
    done
    echo "$tmpindex"
}

argnum=$#
if [ $argnum -eq 0 ]
then
	printhelp
fi

keyname=""
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
                        if [ "$keyname" == "" ]
                        then
						    keyname=$1
                        elif [ "$username" == "" ]
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

if [ "$keyname" = "" ] || [ "$username" = "" ] || [ "$binddn" = "" ]
then
	echo "Please add your keyname, username and ldapbinddn." 1>&2
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

checkname="$(getattr "" cn "cn=$keyname,ou=wireguard,cn=$username,ou=people" 2>/dev/null)"

if ! hash wg &>/dev/null
then
    echo "Please install wireguard!" 1>&2
    exit 1
fi

if [ "$checkname" != "" ]
then
    echo "Keyname exist!" 1>&2
    exit 1
else
    echo "dn: ou=wireguard,cn=$username,ou=people,$basedn
objectClass: organizationalUnit
ou: wireguard" | ldapadd -x $ldapurl -D "$binddn" -w "$bindpasswd"

    echo "dn: cn=$keyname,ou=wireguard,cn=$username,ou=people,$basedn
objectClass: wireguardKey
cn: $keyname
ipindex: $(getindex)
wgprivkey: $(wg genkey)" | ldapadd -x $ldapurl -D "$binddn" -w "$bindpasswd"
fi






