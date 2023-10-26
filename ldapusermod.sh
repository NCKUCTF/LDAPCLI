#!/bin/bash

printhelp()
{
	echo "Usage: $0 [options] LOGIN

Options:
  -g, --gid GROUP               force use GROUP as new primary group
  -G, --groups GROUPS           new list of supplementary GROUPS
  -A, --pveACLs                 Set user pve acl. format: <path>:<rule>,/pool/PVEuser:PVEVMAdmin,...
  -k, --sshkeys KEYS            Your sshkeys for this account
  -a, --append                  append the user to the supplemental GROUPS
                                mentioned by the -G or append sshkey to 
                                this user mentioned by the -k or append pveACL to 
                                this user mentioned by the -A option without removing
  -r, --remove                  remove the user to the supplemental GROUPS
                                mentioned by the -G or remove sshkey from 
                                this user mentioned by the -k or remove pveACL from 
                                this user mentioned by the -A option without appending
  -h, --help                    display this help message and exit
  -l, --login NEW_LOGIN         new value of the login name
  -n, --displayName NAME        User real name
  -p, --password PASSWORD       password of the new password
  -P, --Password				prompt for new password 
  -e, --email EMAIL             Set user email
  -s, --shell SHELL             new login shell for the user account
  -u, --uid UID                 new UID for the user account
  -f, --bindfile				set url,binddn,bindpasswd with file
  -H, --url URL					LDAP Uniform Resource Identifier(s)
  -D, --binddn DN				bind DN
  -w, --bindpasswd PASSWORD		bind password" 1>&2
	exit 1
}

groupset()
{
    cmd=$1
    user=$2
    dn=$3

	echo "dn: $dn
changetype: modify
$cmd: memberUid
memberUid: $user
-
$cmd: member
member: cn=$user,ou=people,$basedn" | ldapmodify -x $ldapurl -D "$binddn" -w "$bindpasswd"
}

setuserattr()
{
    cmd=$1
    attrname=$2
    attrdata=$3
    echo "dn: cn=$username,ou=people,$basedn
changetype: modify
$cmd: $attrname
$attrname: $attrdata" | ldapmodify -x $ldapurl -D "$binddn" -w "$bindpasswd"
}

getattr()
{
    filter=$1
    attrname=$2
    ldapsearch -x $ldapurl -D "$binddn" -w "$bindpasswd" -b "$basedn" "$filter" "$attrname" -LLL | grep -P "^$attrname:" | cut -d ' ' -f 2-
}

argnum=$#
if [ $argnum -eq 0 ]
then
	printhelp
fi

username=""
newusername=""
password=""
promptpassword=false
homedir=""
gid=""
uid=""
groupsmode="replace"
sshkeysmode="replace"
pveACLsmode="replace"
sshkeys=""
groups=""
pveACLs='[]'
delwgkeys=''
newwgkey=''
clearwgkey='false'
shell=""
email=""
url=""
binddn=""
bindpasswd=""
displayName=""

for a in $(seq 1 1 $argnum)
do
        nowarg=$1
        case "$nowarg" in
				-h|--help)
                        printhelp
                        ;;
				-d|--home-dir)
                        shift
                        homedir=$1
                        ;;
                -g|--gid)
                        shift
                        gid=$1
                        ;;
                -G|--groups)
                        shift
                        groups=$1  #$(echo $1 | sed "s/,/ /g")
                        ;;
                -A|--pveACLs)
                        shift
                        pveACLs="$(echo "\"$1\"" | jq -c 'split(",") | map({"path": split(":")[0], "rule": split(":")[1]})')"
                        ;;
                -a|--append)
                        if [ $2 == "-G" ] || [ $2 == "--groups" ]
                        then
                            groupsmode="add"
                        elif [ $2 == "-k" ] || [ $2 == "--sshkeys" ]
                        then
                            sshkeysmode="add"
                        elif [ $2 == "-A" ] || [ $2 == "--pveACLs" ]
                        then
                            pveACLsmode="add"
                        fi
                        ;;
                -r|--remove)
                        if [ $2 == "-G" ] || [ $2 == "--groups" ]
                        then
                            groupsmode="delete"
                        elif [ $2 == "-k" ] || [ $2 == "--sshkeys" ]
                        then
                            sshkeysmode="delete"
                        elif [ $2 == "-A" ] || [ $2 == "--pveACLs" ]
                        then
                            pveACLsmode="delete"
                        fi
                        ;;
                -s|--shell)
                        shift
                        shell=$1
                        ;;
                -n|--displayName)
                        shift
                        displayName=$1
                        ;;
                -u|--uid)
                        shift
                        uid=$1
                        ;;
                -e|--email)
                        shift
                        email=$1
                        ;;
                -p|--password)
                        shift
                        password=$1
                        ;;
                -P|--Password)
                        promptpassword=true
                        ;;
                -k|--sshkeys)
                        shift
                        sshkeys=$(echo $1 | sed "s/,/ /g")
                        ;;
                -l|--login)
                        shift
                        newusername=$1
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
                        if [ "$username" != "" ]
                        then
	                        echo "Bad args ..." 1>&2
                            printhelp
                        fi
						username=$1
                        ;;
        esac
        shift
done

if [ "$username" = "" ] || [ "$binddn" = "" ]
then
	echo "Please add your username and ldapbinddn." 1>&2
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

if $promptpassword
then
    read -p "New password: " -s password
    echo
    read -p "Re-enter new password: " -s checkpassword
    echo
    if [ "$password" != "$checkpassword" ]
    then
        echo "Password verification failed." 1>&2
        exit 0
    fi
fi

newpasswd=""
if [ "$password" != "" ]
then
    newpasswd=$(slappasswd -s $password)
fi

if $promptpassword && [ "$newpasswd" = "" ]
then
	exit 0
fi


basedn=$(echo $(for a in $(echo "$binddn" | sed "s/,/ /g"); do  printf "%s," $(echo $a | grep dc=); done) | sed "s/^,//g" | sed "s/,$//g")

oldgid=$(getattr "(&(objectClass=person)(cn=$username))" gidNumber | sed "s/[^0-9]//g")

if [ "$gid" != "100" ]
then
    gid=$(getattr "(&(objectClass=posixGroup)(|(gidNumber=$gid)(cn=$gid)))" gidNumber | tail -n 1 | sed "s/[^0-9]//g")
fi

uid=$(echo $uid | sed "s/[^0-9]//g")

if [ "$displayName" != "" ]
then
    setuserattr replace displayName "$displayName"
fi

if [ "$homedir" != "" ]
then
    setuserattr replace homeDirectory "$homedir"
fi

if [ "$shell" != "" ]
then
    setuserattr replace loginShell "$shell"
fi

if [ "$newpasswd" != "" ]
then
    setuserattr replace userPassword "$newpasswd"
    smbldap-usermod -a "$username"
    echo "$password
$password" | smbldap-passwd "$username"
    smbldap-usermod -H '[UX]' "$username"
fi

if [ "$uid" != "" ]
then
    setuserattr replace uidNumber "$uid"
fi

if [ "$email" != "" ]
then
    setuserattr replace mail "$email"
fi

if [ "$gid" != "" ]
then
	if [ "$oldgid" != "100" ]
	then
        groupset delete $username "$(getattr "(&(objectClass=posixGroup)(gidNumber=$oldgid))" dn)"
	fi
	
	if [ "$gid" != "100" ]
	then
		groupset add $username "$(getattr "(&(objectClass=posixGroup)(gidNumber=$gid))" dn)"
	fi

    setuserattr replace gidNumber "$gid"
	oldgid=$gid
fi

if [ "$groups" != "" ]
then
	case "$groupsmode" in
			replace)
					for a in $(getattr "(&(objectClass=person)(uid=$username))" memberOf)
					do
						if [ "$a" != "$(getattr "(&(objectClass=posixGroup)(gidNumber=$oldgid))" dn)" ]
						then
							groupset delete $username "$a"
						fi
					done

                    IFS=,
					for a in $groups
					do
						groupset add $username "cn=$a,ou=groups,$basedn"
					done
					;;
			add)
                    IFS=,
					for a in $groups
					do
						groupset add $username "cn=$a,ou=groups,$basedn"
					done
					;;
			delete)
                    IFS=,
					for a in $groups
					do
						if [ "$a" != "$(getattr "(&(objectClass=posixGroup)(gidNumber=$oldgid))" cn)" ]
						then
							groupset delete $username "cn=$a,ou=groups,$basedn"
						fi
					done
					;;
	esac
    unset IFS
fi

if [ $(echo "$pveACLs" | jq '. | length') -gt 0 ]
then
    setuserattr add objectClass "pveobject"

	modifybase="dn: cn=$username,ou=people,$basedn
changetype: modify
${pveACLsmode}: pveacl"

    for a in $(seq 0 1 $(echo "$pveACLs" | jq '. | length - 1'))
    do
        modifybase="$modifybase
pveacl: $(echo "$pveACLs" | jq -c ".[$a]")"
    done
    echo "$modifybase" | ldapmodify -x $ldapurl -D "$binddn" -w "$bindpasswd"
fi

if [ "$sshkeys" != "" ]
then
	modifybase="dn: cn=$username,ou=people,$basedn
changetype: modify
${sshkeysmode}: sshkey"
	for a in $sshkeys
	do
		modifybase=$modifybase"
sshkey: cn=$a,ou=sshkey,$basedn"
	done
	echo "$modifybase" | ldapmodify -x $ldapurl -D "$binddn" -w "$bindpasswd"
fi

if [ "$newusername" != "" ]
then
	allgroups="$(getattr "(&(objectClass=person)(uid=$username))" memberOf)"
	echo "dn: cn=$username,ou=people,$basedn
changetype: moddn
newrdn: cn=$newusername
deleteoldrdn: 1

dn: cn=$newusername,ou=people,$basedn
changetype: modify
replace: cn
cn: $newusername
-
replace: uid
uid: $newusername" | ldapmodify -x $ldapurl -D "$binddn" -w "$bindpasswd"

	for a in $allgroups
	do
		groupset delete $username "$a"
		groupset add $newusername "$a"
	done

    username=$newusername
fi

