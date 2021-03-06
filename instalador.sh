#!/bin/bash -x
#Instalador de Nginx, php-fmp, mariadb

###################Revisiones previas ######################
#Verificacion que esté instalado yum y si nó lo instala.
echo -e "\n\t#########################  Script instalador ########################"
echo -e "\t#####################################################################\n"
echo -e "\n\t######### Realizando pruebas de paquetes requeridos previamente #####\n"
#Ejecucion y comprobacion de que esté instalado yum
yum --version >> /dev/null
#Validación de la ejecucion anterior
VIY=$(echo $?)
if [ $VIY -ne 0 ]
then
        #Instala utilidades en caso de que no exista yum 
        yum install dnf-utils -y
fi
#Instala otros paquetes necesarios
dnf install wget tar curl bind-utils -y > /dev/null

################### Argumentos para validación

echo -n "Cual es el nombre del dominio donde se ejecuta este script: "
read DOMINIO

################## Validación de información
echo -e "\n******* Validando la información para el dominio $DOMINIO"
CONSDOM=/tmp/consdom.txt
host $DOMINIO > $CONSDOM
grep "not found" $CONSDOM > /dev/null
VCONSDOM=$(echo $?)
IPSERV=$(hostname -I)

if [ $VCONSDOM -eq 0 ]
then
        echo -e "++++ El dominio $DOMINIO no se encuentra registrado"
        exit 1
else
        echo -e "El dominio $DOMINIO si existe"
        grep "$IPSERV" $CONSDOM >> /dev/null
        CONSULTA=$(echo $?)

        if [ $CONSULTA -ne 0 ]
        then
                IPDOM=$(cat $CONSDOM | head -1 | awk '{ print $4 }')
                echo -e "++++ Error al validar la información"
                echo -e "++++ Los parametros ingresados no coinciden con los registrados para este dominio"
                echo -e "++++ El dominio $DOMINIO tiene asignada la IP $IPDOM"
                echo -e "++++ El servidor donde se está ejecutando este Script es: $IPSERV"
                exit 1
        else
                echo -e "Información correcta"
                echo -e "Se esta configurando el $DOMINIO con la IP $IPSERV"
        fi
fi
rm $CONSDOM

######################### INSTALACION DE NGINX #########################
echo -e "\n\n\t ------- Instalando Nginx"
sleep 2
#Revisando que exista alguna versión previa.
rpm -qa | grep nginx > /dev/null
VIN=$(echo $?)
#Revisión de repositorio nginx
dnf repolist | grep nginx > /dev/null
VIR=$(echo $?)
if [ $VIN -ne 0 ]
then
        if [ $VIR -ne 0 ]
        then
                #Creación de repositorio nginx
                cat > /etc/yum.repos.d/nginx.repo << "EOF"
[nginx-stable]
name=nginx stable repo
baseurl=http://nginx.org/packages/centos/$releasever/$basearch/
gpgcheck=1
enabled=1
gpgkey=https://nginx.org/keys/nginx_signing.key
module_hotfixes=true

[nginx-mainline]
name=nginx mainline repo
baseurl=http://nginx.org/packages/mainline/centos/$releasever/$basearch/
gpgcheck=1
enabled=0
gpgkey=https://nginx.org/keys/nginx_signing.key
module_hotfixes=true
EOF
        fi

fi
#Instalacion de Nginx
dnf install -y nginx > /dev/null 
#Inicio y habilitado persistente
systemctl start nginx
systemctl enable nginx
#Habilitar los servicios en el firewalld
firewall-cmd --permanent --add-service={http,https}
firewall-cmd --reload
#Revisión de que esté ejecutandose correctamente.
systemctl status nginx | grep running
RSN=$(echo $?)
if [ $RSN -ne 0 ]
then
        echo "Hay un problema con la ejecución de NGINX"
fi

##################### Instalando MariaDB ###########################
echo -e "\n\n\t ------- Instalando MariaDB"
sleep 2
#Verificador de versiones previas
whereis mariadb | grep "mariadb " > /dev/null
VMDB=$(echo $?)
if [ $VMDB -ne 0 ]
then
        #Instalando MariaDB
        dnf -y install mariadb-server mariadb > /dev/null
fi
#Habilitando y volviendo persistente el servicio de MariaDB
systemctl enable mariadb.service
systemctl start mariadb.service
#Si deseas configurar MariaDB descomenta la siguiente línea, es interactiva la configuración:
mysql_secure_installation

###################### Instalando php74 ######################
echo -e "\n\n\t ------- Instalando php7.4"
sleep 2
#Validamos que esté instalado
whereis php | grep "php " > /dev/null
PVIP=$(echo $?)
#Verificación de que exista el repositorio instalado
dnf repolist | grep epel > /dev/null
PVIR=$(echo $?)

if [ $PVIP -ne 0 ] && [ $PVIR -ne 0 ]
then
        #Instalacion de repositorios
        dnf install epel-release -y > /dev/null
        dnf install -y https://rpms.remirepo.net/enterprise/remi-release-8.rpm > /dev/null
        dnf module install php:remi-7.4 -y > /dev/null
        dnf install -y php php-fpm php-mcrypt php-cli php-gd php-curl php-xml php-mysql php-mbstring php-pspell php-imagick php-cgi php-ldap php-soap php-xsl php-zip php-common php-imap php-json php-bz2 php-intl php-gmp > /dev/null
fi
#Habilitar y volver persistente el servicio
systemctl start php-fpm
systemctl enable php-fpm

#Revision de archivo php.ini y modificacion
if [ -e /etc/php.ini ]
then
        #Busqueda de la línea y deshabilitando la línea
        NL=$(sed -n '/cgi.fix_pathinfo=/ =' /etc/php.ini)
        sed -i "${NL}c\cgi.fix_pathinfo=0" /etc/php.ini
fi
#Revision y modificacion del archivo /etc/php-fpm.d/www.conf
if [ -e /etc/php-fpm.d/www.conf ]
then
        LLO=$(sed -n '/listen.owner = nobody/ =' /etc/php-fpm.d/www.conf)
        LLG=$(sed -n '/listen.group = nobody/ =' /etc/php-fpm.d/www.conf)
        LLM=$(sed -n '/listen.mode = 0660/ =' /etc/php-fpm.d/www.conf)

        if [ $LLO -gt 0 ] && [ $LLG -gt 0 ]
        then
                sed -i "${LLO}c\listen.owner = nginx" /etc/php-fpm.d/www.conf
                sed -i "${LLG}c\listen.group = nginx" /etc/php-fpm.d/www.conf
                sed -i "${LLM}c\listen.mode = 0660" /etc/php-fpm.d/www.conf
        fi

        LUA=$(sed -n '/user = apache/ =' /etc/php-fpm.d/www.conf)
        LGA=$(sed -n '/group = apache/ =' /etc/php-fpm.d/www.conf)
        if [ $LUA -gt 0 ] && [ $LGA -gt 0 ]
        then
                sed -i "${LUA}c\user = nginx" /etc/php-fpm.d/www.conf
                sed -i "${LGA}c\group = nginx" /etc/php-fpm.d/www.conf
        fi

fi
#Reiniciando servicio de php y nginx
systemctl start php-fpm
systemctl restart nginx

#################### Instalando Roudcube ####################
echo -e "\n\n\t ------- Instalando Roudcube"
sleep 2

TRC=/tmp/temp-rc.txt

curl https://roundcube.net/download/ > $TRC 

RVS=$(grep "Stable version" $TRC | awk -F "- " '{ print $2}' | awk -F "<" '{ print $1}')
RDVS=$(grep "$RVS" $TRC | awk -F "href=""" '{ print $2}' | awk -F " """ '{ print $1}' | tr -d '"')

wget $RDVS


tar xzf roundcubemail-$RVS-complete.tar.gz > /dev/null
mv roundcubemail-$RVS /var/www/html/roundcubemail
chown -R nginx:nginx /var/www/html/roundcubemail

cat > /etc/nginx/conf.d/mail.example.com.conf << "EOF"
server {
        listen 80;
        server_name mail.example.com;

        root /var/www/html/roundcubemail;
        index  index.php index.html;

        #i# Logging
        access_log /var/log/nginx/mail.example.com_access_log;
        error_log   /var/log/nginx/mail.example.com_error_log;

        location / {
                try_files $uri $uri/ /index.php?q=$uri&$args;
        }

        location ~ ^/(README.md|INSTALL|LICENSE|CHANGELOG|UPGRADING)$ {
                deny all;
        }

        location ~ ^/(config|temp|logs)/ {
                deny all;
        }

        location ~ /\. {
                deny all;
                access_log off;
                log_not_found off;
        }

        location ~ \.php$ {
                include /etc/nginx/fastcgi_params;
                fastcgi_pass unix:/var/run/php-fpm/php-fpm.sock;
                fastcgi_index index.php;
                fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        }
}
EOF

chown :nginx /var/lib/php/session/
systemctl restart nginx php-fpm

rm -rf roundcube* $TRC

echo "Instalación terminada"