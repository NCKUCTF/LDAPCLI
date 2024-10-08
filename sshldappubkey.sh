#!/bin/bash

export PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin:$PATH

passwd=""

if [ -f /etc/libnss-ldap.secret ]
then
    passwd="$(cat /etc/libnss-ldap.secret)"
elif [ -f /etc/ldap.secret ]
then
    passwd="$(cat /etc/ldap.secret)"
elif [ -f /etc/nslcd.conf ]
then
    passwd="$(grep "^bindpw" /etc/nslcd.conf | awk '{print $2}')"
elif [ -f /usr/local/etc/ldap.conf ]
then
    passwd="$(grep "^bindpw" /usr/local/etc/ldap.conf | awk '{print $2}')"
fi

ldapconf=/etc/libnss-ldap.conf
if [ -f /etc/nslcd.conf ]
then
    ldapconf=/etc/nslcd.conf
elif [ -f /usr/local/etc/ldap.conf ]
then
    ldapconf=/usr/local/etc/ldap.conf
fi

url="$(grep "^uri" $ldapconf | awk '{print $2}')"

base="$(grep "^base" $ldapconf | awk '{print $2}')"

binddn="$(grep "^\(rootbinddn\|binddn\)" $ldapconf | awk '{print $2}')"

#if [ -f /etc/libnss-ldap.conf ]
#then
#    binddn="$(grep "^\(rootbinddn\|binddn\)" /etc/libnss-ldap.conf | awk '{print $2}')"
#elif [ -f /etc/ldap.conf ]
#then
#    binddn="$(grep "^\(rootbinddn\|binddn\)" /etc/ldap.conf | awk '{print $2}')"
#elif [ -f /etc/nslcd.conf ]
#then
#    binddn="$(grep "^\(rootbinddn\|binddn\)" /etc/nslcd.conf | awk '{print $2}')"
#fi


sshkeydn="$(ldapsearch -x -H $url -b "$base" -D "$binddn" -w $passwd '(&(objectClass=posixAccount)(uid='"$1"'))' 'sshkey' | sed -n '/^ /{H;d;};/sshkey:/x;$g;s/\n *//g;s/sshkey: //gp')"


for a in $sshkeydn
do
    ldapsearch -x -H $url -b "$a" -D "$binddn" -w $passwd '(objectClass=sshPublicKey)' 'sshpubkey' | sed -n '/^ /{H;d;};/sshpubkey:/x;$g;s/\n *//g;s/sshpubkey: //gp'
done
