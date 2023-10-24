#!/bin/bash

printhelp()
{
	echo "Usage: $0 [options] LOGIN

Options:
  -g, --gid GROUP               force use GROUP as new primary group
  -G, --groups GROUPS           new list of supplementary GROUPS
  -A, --pveACLs                 Set user pve acl. format: <path>:<rule>,/pool/PVEuser:PVEVMAdmin,...
  -k, --sshkeys KEYS            Your sshkeys for this account
      --newwgkey                Append new wgkey for this account
      --delwgkey PUBKEYS        Remove wgkeys for this account
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
  -w, --bindpasswd PASSWORD		bind password"
	exit 0
}

argnum=$#
if [ $argnum -eq 0 ]
then
	printhelp
	exit 0
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
newwgkey='false'
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
                --newwgkey)
                        newwgkey='true'
                        ;;
                --delwgkey)
                        shift
                        delwgkeys="$1"
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

oldgid=$(ldapsearch -x $ldapurl -D "$binddn" -w "$bindpasswd" -b "$basedn" "(&(objectClass=person)(cn=$username))" -LLL | grep -P "^gidNumber:" | awk '{print $2}' | sed "s/[^0-9]//g")

if [ "$gid" != "100" ]
then
	gid=$(ldapsearch -x $ldapurl -D "$binddn" -w "$bindpasswd" -b "$basedn" "(&(objectClass=posixGroup)(|(gidNumber=$gid)(cn=$gid)))" -LLL | grep -P "^gidNumber:" | tail -n 1 | awk '{print $2}')
fi

uid=$(echo $uid | sed "s/[^0-9]//g")

if [ "$displayName" != "" ]
then
    echo "dn: cn=$username,ou=people,$basedn
changetype: modify
replace: displayName
displayName: $displayName" | ldapmodify -x $ldapurl -D "$binddn" -w "$bindpasswd"
fi

if [ "$homedir" != "" ]
then
	echo "dn: cn=$username,ou=people,$basedn
changetype: modify
replace: homeDirectory
homeDirectory: $homedir" | ldapmodify -x $ldapurl -D "$binddn" -w "$bindpasswd"
fi

if [ "$shell" != "" ]
then
	echo "dn: cn=$username,ou=people,$basedn
changetype: modify
replace: loginShell
loginShell: $shell" | ldapmodify -x $ldapurl -D "$binddn" -w "$bindpasswd"
fi

if [ "$newpasswd" != "" ]
then
	echo "dn: cn=$username,ou=people,$basedn
changetype: modify
replace: userPassword
userPassword: $newpasswd" | ldapmodify -x $ldapurl -D "$binddn" -w "$bindpasswd"
    smbldap-usermod -a "$username"
    echo "$password
$password" | smbldap-passwd "$username"
    smbldap-usermod -H '[UX]' "$username"
fi

if [ "$uid" != "" ]
then
	echo "dn: cn=$username,ou=people,$basedn
changetype: modify
replace: uidNumber
uidNumber: $uid" | ldapmodify -x $ldapurl -D "$binddn" -w "$bindpasswd"
fi

if [ "$email" != "" ]
then
	echo "dn: cn=$username,ou=people,$basedn
changetype: modify
replace: mail
mail: $email" | ldapmodify -x $ldapurl -D "$binddn" -w "$bindpasswd"
fi

if [ "$gid" != "" ]
then
	if [ "$oldgid" != "100" ]
	then
		echo "dn: $(ldapsearch -x $ldapurl -D "$binddn" -w "$bindpasswd" -b "$basedn" "(&(objectClass=posixGroup)(gidNumber=$oldgid))" -LLL | grep -P "^dn:" | awk '{print $2}')
changetype: modify
delete: memberUid
memberUid: $username
-
delete: member
member: cn=$username,ou=people,$basedn" | ldapmodify -x $ldapurl -D "$binddn" -w "$bindpasswd"
	fi
	
	if [ "$gid" != "100" ]
	then
		echo "dn: $(ldapsearch -x $ldapurl -D "$binddn" -w "$bindpasswd" -b "$basedn" "(&(objectClass=posixGroup)(gidNumber=$gid))" -LLL | grep -P "^dn:" | awk '{print $2}')
changetype: modify
add: memberUid
memberUid: $username
-
add: member
member: cn=$username,ou=people,$basedn" | ldapmodify -x $ldapurl -D "$binddn" -w "$bindpasswd"
	fi

	echo "dn: cn=$username,ou=people,$basedn
changetype: modify
replace: gidNumber
gidNumber: $gid" | ldapmodify -x $ldapurl -D "$binddn" -w "$bindpasswd"
	
	oldgid=$gid
fi

if [ "$groups" != "" ]
then
	case "$groupsmode" in
			replace)
					for a in $(ldapsearch -x $ldapurl -D "$binddn" -w "$bindpasswd" -b "$basedn" "(&(objectClass=person)(uid=$username))" memberOf -LLL | grep -P "^memberOf:" | awk '{print $2}')
					do
						if [ "$a" != "$(ldapsearch -x $ldapurl -D "$binddn" -w "$bindpasswd" -b "$basedn" "(&(objectClass=posixGroup)(gidNumber=$oldgid))" -LLL | grep -P "^dn:" | awk '{print $2}')" ]
						then
							echo "dn: $a
changetype: modify
delete: memberUid
memberUid: $username
-
delete: member
member: cn=$username,ou=people,$basedn" | ldapmodify -x $ldapurl -D "$binddn" -w "$bindpasswd"
						fi
					done

                    IFS=,
					for a in $groups
					do
						echo "dn: cn=$a,ou=groups,$basedn
changetype: modify
add: memberUid
memberUid: $username
-
add: member
member: cn=$username,ou=people,$basedn" | ldapmodify -x $ldapurl -D "$binddn" -w "$bindpasswd"
					done
					;;
			add)
                    IFS=,
					for a in $groups
					do
						echo "dn: cn=$a,ou=groups,$basedn
changetype: modify
add: memberUid
memberUid: $username
-
add: member
member: cn=$username,ou=people,$basedn" | ldapmodify -x $ldapurl -D "$binddn" -w "$bindpasswd"
					done
					;;
			delete)
                    IFS=,
					for a in $groups
					do
						if [ "$a" != "$(ldapsearch -x $ldapurl -D "$binddn" -w "$bindpasswd" -b "$basedn" "(&(objectClass=posixGroup)(gidNumber=$oldgid))" -LLL | grep -P "^cn:" | awk '{print $2}')" ]
						then
							echo "dn: cn=$a,ou=groups,$basedn
changetype: modify
delete: memberUid
memberUid: $username
-
delete: member
member: cn=$username,ou=people,$basedn" | ldapmodify -x $ldapurl -D "$binddn" -w "$bindpasswd"
						fi
					done
					;;
	esac
    unset IFS
fi

if [ "$delwgkeys" == "" ]
then
    allprivkey="$(echo "[$(ldapsearch -x $ldapurl -D "$binddn" -w "$bindpasswd" -b "$basedn" "(&(objectClass=wireguardAccount)(uid=$username))" wgkey -LLL | grep -P "^wgkey:" | sed 's/^wgkey:\s*//g' | tr '\n' ',' | sed 's/,\+$//g')]" | jq -c 'sort_by(.index)')"
    
	modifybase="dn: cn=$username,ou=people,$basedn
changetype: modify
delete: wgkey"

    for a in $(seq 0 1 $(echo "$allprivkey" | jq '. | length - 1'))
    do
        pubkey="$(echo "$(echo "$allprivkey" | jq -rc ".[$a].key")" | wg pubkey)"

        IFS=,
        for b in $delwgkeys
        do
            if [ "$pubkey" == "$b" ]
            then
                modifybase="$modifybase
wgkey: $(echo "$allprivkey" | jq -rc ".[$a]")"
            fi
        done
        unset IFS
    done
    echo "$modifybase" | ldapmodify -x $ldapurl -D "$binddn" -w "$bindpasswd"
fi

if $newwgkey && hash wg &>/dev/null
then
	echo "dn: cn=$username,ou=people,$basedn
changetype: modify
add: objectClass
objectClass: wireguardAccount" | ldapmodify -x $ldapurl -D "$binddn" -w "$bindpasswd"

    privkey="$(wg genkey)"

    allprivkey="$(echo "[$(ldapsearch -x $ldapurl -D "$binddn" -w "$bindpasswd" -b "$basedn" "(objectClass=wireguardAccount)" wgkey -LLL | grep -P "^wgkey:" | sed 's/^wgkey:\s*//g' | tr '\n' ',' | sed 's/,\+$//g')]" | jq -c 'sort_by(.index)')"

    index=1
    for a in $(seq 0 1 $(echo "$allprivkey" | jq '. | length - 1'))
    do
        if [ $(echo "$allprivkey" | jq -rc ".[$a].index") -eq $index ]
        then
            index=$(($index+1))
        else
            break
        fi
    done

	echo "dn: cn=$username,ou=people,$basedn
changetype: modify
add: wgkey
wgkey: $(echo "{\"index\":$index,\"key\":\"$privkey\"}" | jq -c)" | ldapmodify -x $ldapurl -D "$binddn" -w "$bindpasswd"
fi

if [ $(echo "$pveACLs" | jq '. | length') -gt 0 ]
then
	echo "dn: cn=$username,ou=people,$basedn
changetype: modify
add: objectClass
objectClass: pveobject" | ldapmodify -x $ldapurl -D "$binddn" -w "$bindpasswd"

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
	allgroups="$(ldapsearch -x $ldapurl -D "$binddn" -w "$bindpasswd" -b "$basedn" "(&(objectClass=person)(uid=$username))" memberOf -LLL | grep -P "^memberOf:" | awk '{print $2}')"
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
		echo "dn: $a
changetype: modify
delete: memberUid
memberUid: $username
-
add: memberUid
memberUid: $newusername" | ldapmodify -x $ldapurl -D "$binddn" -w "$bindpasswd"
	done

    username=$newusername
fi

