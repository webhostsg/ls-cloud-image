#!/bin/bash
# /********************************************************************
# LiteSpeed domain setup Script
# @Author:   LiteSpeed Technologies, Inc. (https://www.litespeedtech.com)
# @Copyright: (c) 2019-2020
# @Version: 1.0.3
# *********************************************************************/
MY_DOMAIN=''
MY_DOMAIN2=''
ADMIN_USER=$(openssl rand -hex 8)
ADMIN_PASS=$(openssl rand -base64 10)
DOCHM='/var/www/html'
LSDIR='/usr/local/lsws'
WEBCF="${LSDIR}/conf/httpd_config.conf"
if [ -e "${LSDIR}/conf/vhosts/wordpress/vhconf.conf" ]; then
    VHNAME='wordpress'
else
    VHNAME='Example'
    DOCHM="${LSDIR}/${VHNAME}/html"
fi
LSVHCFPATH="${LSDIR}/conf/vhosts/${VHNAME}/vhconf.conf"
UPDATELIST='/var/lib/update-notifier/updates-available'
BOTCRON='/etc/cron.d/certbot'
WWW='FALSE'
UPDATE='TRUE'
OSNAME=''

echoY() {
    echo -e "\033[38;5;148m${1}\033[39m"
}
echoG() {
    echo -e "\033[38;5;71m${1}\033[39m"
}

check_os(){
    if [ -f /etc/redhat-release ] ; then
        OSNAME=centos
    elif [ -f /etc/lsb-release ] ; then
        OSNAME=ubuntu    
    elif [ -f /etc/debian_version ] ; then
        OSNAME=debian
    fi         
}

providerck()
{
  if [ "$(sudo cat /sys/devices/virtual/dmi/id/product_uuid | cut -c 1-3)" = 'EC2' ]; then 
    PROVIDER='aws'
  elif [ "$(dmidecode -s bios-vendor)" = 'Google' ];then
    PROVIDER='google'      
  elif [ "$(dmidecode -s bios-vendor)" = 'DigitalOcean' ];then
    PROVIDER='do'
  elif [ "$(dmidecode -s system-product-name | cut -c 1-7)" = 'Alibaba' ];then
    PROVIDER='aliyun'   
  elif [ "$(dmidecode -s system-manufacturer)" = 'Microsoft Corporation' ];then    
    PROVIDER='azure'  
  else
    PROVIDER='undefined'  
  fi
}

get_ip()
{
    if [ ${PROVIDER} = 'aws' ]; then 
        MY_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4) 
    elif [ ${PROVIDER} = 'google' ]; then 
        MY_IP=$(curl -s -H "Metadata-Flavor: Google" \
        http://metadata/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip)    
    elif [ ${PROVIDER} = 'aliyun' ]; then
        MY_IP=$(curl -s http://100.100.100.200/latest/meta-data/eipv4)   
    elif [ "$(dmidecode -s system-manufacturer)" = 'Microsoft Corporation' ];then    
        MY_IP=$(curl -s http://checkip.amazonaws.com || printf "0.0.0.0")    
    else
        MY_IP=$(ifconfig eth0 | grep 'inet '| awk '{printf $2}')
        #MY_IP=$(ip -4 route get 8.8.8.8 | awk {'print $7'} | tr -d '\n')
  fi    
}

domainhelp(){
    echo -e "********************************************************************************"
    echo -e "Please make sure the domain's DNS record has been properly pointed to this\nserver."
    echo -e "If you don't have one yet, you may cancel this process by pressing CTRL+C and\ncontinuing to SSH."
    echo -e "This prompt will open again the next time you log in, and will continue to do so\nuntil you finish the setup."
    echo -e "\n(If you are using top level (root) domain, please include it with\n\033[38;5;71mwww.\033[39m so both www and root domain will be added)"
    echo -e "(ex. www.domain.com or sub.domain.com). Do not include http/s.\n"
    echo -e "********************************************************************************"
}

restart_lsws(){
    ${LSDIR}/bin/lswsctrl restart >/dev/null
}   

domaininput(){
    printf "%s" "Your domain: "
    read MY_DOMAIN
    if [ -z "${MY_DOMAIN}" ] ; then
    echo -e "\nPlease input a valid domain\n"
    exit
    fi
    echo -e "The domain you put is: \e[31m${MY_DOMAIN}\e[39m"
    printf "%s"  "Please verify it is correct. [y/N] "
}

duplicateck(){
    grep "${1}" ${2} >/dev/null 2>&1
}

domainadd(){
    CHECK_WWW=$(echo ${MY_DOMAIN} | cut -c1-4)
    if [[ ${CHECK_WWW} == www. ]] ; then
        WWW='TRUE'
        #check if domain starts with www.
        MY_DOMAIN2=$(echo ${MY_DOMAIN} | cut -c 5-)
        duplicateck ${MY_DOMAIN2} ${WEBCF}
        if [ ${?} = 1 ]; then 
            #my_domain is domain wih www, and my_domain2 is domain without www, both added into listener.
            if [ "${VHNAME}" = 'wordpress' ]; then 
                sed -i 's|wordpress '${MY_IP}'|wordpress '${MY_IP}', '${MY_DOMAIN}', '${MY_DOMAIN2}' |g' ${WEBCF}
            else
                sed -i 's|Example '${MY_IP}'|Example '${MY_IP}', '${MY_DOMAIN}', '${MY_DOMAIN2}' |g' ${WEBCF}   
            fi      
        fi
    else
        duplicateck ${MY_DOMAIN} ${WEBCF}
        if [ ${?} = 1 ]; then
            #and if domain is not started with www. consider it as sub-domain
            if [ "${VHNAME}" = 'wordpress' ]; then 
                sed -i 's|wordpress '${MY_IP}'|wordpress '${MY_IP}', '${MY_DOMAIN}'|g' ${WEBCF}
            else
                sed -i 's|Example '${MY_IP}'|Example '${MY_IP}', '${MY_DOMAIN}'|g' ${WEBCF}   
            fi
        fi    
    fi
    restart_lsws
    echoG "\nDomain has been added into OpenLiteSpeed listener.\n"
}

domainverify(){
    curl -Is http://${MY_DOMAIN}/ | grep -i LiteSpeed > /dev/null 2>&1
    if [ $? = 0 ]; then
        echoG "\n${MY_DOMAIN} check PASS"
    else
        echo "\n${MY_DOMAIN} inaccessible, please verify."; exit 1    
    fi
    if [ ${WWW} = 'TRUE' ]; then
        curl -Is http://${MY_DOMAIN2}/ | grep -i LiteSpeed > /dev/null 2>&1
        if [ $? = 0 ]; then 
            echoG "\n${MY_DOMAIN2} check PASS"   
        else
            echo -e "\n${MY_DOMAIN2} inaccessible, please verify."; exit 1    
        fi    
    fi
}

main_domain_setup(){
    domainhelp
    while true; do
        domaininput
        read TMP_YN
        if [[ "${TMP_YN}" =~ ^(y|Y) ]]; then
            domainadd
            break
        fi
    done    
}
emailinput(){
    CKREG="^[a-z0-9!#\$%&'*+/=?^_\`{|}~-]+(\.[a-z0-9!#$%&'*+/=?^_\`{|}~-]+)*@([a-z0-9]([a-z0-9-]*[a-z0-9])?\.)+[a-z0-9]([a-z0-9-]*[a-z0-9])?\$"
    printf "%s" "Please enter your E-mail (The email will be used for WordPress login): "
    read EMAIL
    if [[ ${EMAIL} =~ ${CKREG} ]] ; then
      echo -e "The E-mail you entered is: \e[31m${EMAIL}\e[39m"
      printf "%s"  "Please verify it is correct: [y/N] "
    else
      echo -e "\nPlease enter a valid E-mail, exit setup\n"; exit 1
    fi  
}

certbothook(){
    sed -i 's/0.*/&  --deploy-hook "\/usr\/local\/lsws\/bin\/lswsctrl restart"/g' ${BOTCRON}
    grep 'restart' ${BOTCRON} > /dev/null 2>&1
    if [ $? = 0 ]; then 
        echoG 'Certbot hook update success'
    else 
        echoY 'Please check certbot crond'
    fi        
}

lecertapply(){
    if [ ${WWW} = 'TRUE' ]; then
        certbot certonly --non-interactive --agree-tos -m ${EMAIL} --webroot -w ${DOCHM} -d ${MY_DOMAIN} -d ${MY_DOMAIN2}
    else
        certbot certonly --non-interactive --agree-tos -m ${EMAIL} --webroot -w ${DOCHM} -d ${MY_DOMAIN}
    fi    
    if [ $? -eq 0 ]; then
        echo "vhssl  {
            keyFile                 /etc/letsencrypt/live/${MY_DOMAIN}/privkey.pem
            certFile                /etc/letsencrypt/live/${MY_DOMAIN}/fullchain.pem
            certChain               1
        }" >> ${LSVHCFPATH}

        echoG "\nSSL certificate has been successfully installed..."
    else
        echo "Oops, something went wrong..."
        exit 1
    fi
}

force_https() {
    if [ "${VHNAME}" = 'wordpress' ]; then 
        duplicateck "RewriteCond %{HTTPS} on" "${DOCHM}/.htaccess"
        if [ ${?} = 1 ]; then 
            echo "$(echo '
### Forcing HTTPS rule start       
RewriteEngine On
RewriteCond %{HTTPS} off
RewriteRule (.*) https://%{HTTP_HOST}%{REQUEST_URI} [R=301,L]
### Forcing HTTPS rule end
            ' | cat - ${DOCHM}/.htaccess)" > ${DOCHM}/.htaccess
        fi
    else 
        ### Rewrite in rewrite tab
        sed -i '/^  logLevel                0/a\ \ rules                   <<<END_rules \
RewriteCond %{SERVER_PORT} 80\nRewriteRule (.*) https://%{HTTP_HOST}%{REQUEST_URI} [R=301,L]\
\ \ END_rules' ${LSVHCFPATH}   
    fi    
    echoG "Force HTTPS rules has been added..."
}

endsetup(){
    sed -i '/domainsetup.sh/d' /etc/profile
}

aptupgradelist() {
    PACKAGE=$(cat ${UPDATELIST} | awk '{print $1}' | sed -n 2p)
    SECURITY=$(cat ${UPDATELIST} | awk '{print $1}' | sed -n 3p)
    if [ "${PACKAGE}" = '0' ] && [ "${SECURITY}" = '0' ]; then 
        UPDATE='FALSE'    
    fi    
}

yumupgradelist(){
    PACKAGE=$(yum check-update | grep -v '*\|Load*\|excluded' | wc -l)
    if [ "${PACKAGE}" = '0' ]; then 
        UPDATE='FALSE'
    fi    
}

aptgetupgrade() {
    apt-get update > /dev/null 2>&1
    echo -ne '#####                     (33%)\r'
    DEBIAN_FRONTEND=noninteractive apt-get -y -o Dpkg::Options::='--force-confdef' -o Dpkg::Options::='--force-confold' upgrade > /dev/null 2>&1
    echo -ne '#############             (66%)\r'
    if [ -f /etc/apt/sources.list.d/mariadb_repo.list ]; then
        ### an apt bug
        mv  /etc/apt/sources.list.d/mariadb_repo.list /tmp/
    fi    
    DEBIAN_FRONTEND=noninteractive apt-get -y -o Dpkg::Options::='--force-confdef' -o Dpkg::Options::='--force-confold' dist-upgrade > /dev/null 2>&1
    echo -ne '####################      (99%)\r'
    apt-get clean > /dev/null 2>&1
    apt-get autoclean > /dev/null 2>&1
    systemctl daemon-reload > /dev/null 2>&1
    echo -ne '#######################   (100%)\r'
}

yumupgrade(){
    echo -ne '#                         (5%)\r'
    yum update -y > /dev/null 2>&1
    echo -ne '#######################   (100%)\r'
}
main_cert_setup(){
    printf "%s"   "Installing Let's Encrypt SSL for your domain..."
    
    #in case www domain , check both root domain and www domain accessibility.
        domainverify
        while true; do 
            emailinput
            read TMP_YN
            if [[ "${TMP_YN}" =~ ^(y|Y) ]]; then
                lecertapply
                break
            fi
        done   
        echoG 'Update certbot cronjob hook'
        certbothook 
        force_https
        restart_lsws
            
}

wordpress_finalise(){
   echoG "Finalizing WordPress Installation. Please wait."
   sed -i "/DB_HOST/s/'[^']*'/'127.0.0.1'/2" /var/www/html/wp-config.php
   /usr/local/bin/wp core install --url=${MY_DOMAIN} --title='My Website' --admin_user=${ADMIN_USER} --admin_password=${ADMIN_PASS} --admin_email=${EMAIL} --path=/var/www/html --allow-root > /dev/null 2>&1
   echoG "WordPress final setup completed"
   echoG "Removing unecessary WordPress installation files"
   apt-get -y remove hhvm > /dev/null 2>&1
   echoG "Unecessary WordPress installation files removed"
}

main_upgrade(){
    if [ "${OSNAME}" = 'ubuntu' ]; then 
        aptupgradelist
    else
        yumupgradelist
    fi    
    if [ "${UPDATE}" = 'TRUE' ]; then
        #START_TIME="$(date -u +%s)"
            echoG "Update Starting. Please wait." 
            if [ "${OSNAME}" = 'ubuntu' ]; then 
                aptgetupgrade
            else
                yumupgrade
            fi    
            echoG "\nUpdate complete" 
            #END_TIME="$(date -u +%s)"
            #ELAPSED="$((${END_TIME}-${START_TIME}))"
            #echoY "***Total of ${ELAPSED} seconds to finish process***"
            echoG 'Your system is up to date'
            echo -e "********************************************************************************"
            echoY "\n                     Congratulations! Setup has completed.                      "
            echoY "\n    You can close this and proceed to follow the instructions in the email.     "
            echo -e "********************************************************************************"
           
    else
        echoG 'Your system is up to date'
        echo -e "********************************************************************************"
        echoY "\n                     Congratulations! Setup has completed.                      "
        echoY "\n    You can close this and proceed to follow the instructions in the email.     "
        echo -e "********************************************************************************"
    fi        
}

main(){
    check_os
    providerck
    get_ip
    if [ ! -d /usr/local/CyberCP ]; then
        main_domain_setup
        main_cert_setup
        echoG "\nAccelerated OpenLiteSpeed server installation complete."
    fi
    wordpress_finalise
    main_upgrade
    endsetup
}
main
rm -- "$0"
exit 0
