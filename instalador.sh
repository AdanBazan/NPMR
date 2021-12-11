#!/bin/bash
#Instalador de Nginx, php-fmp, mariadb



###################Revisiones previas ######################
#Verificacion que esté instalado yum y si nó lo instala.
echo "\tScript instalador"
echo "\tRealizando pruebas de paquetes requeridos previamente"
yum --version >> /dev/null
VIY=$(echo $?)
if [ $VIY -ne 0 ]
then
        #Instala utilidades
        yum install dnf-utils -y
fi

dnf install wget tar curl bind-utils -y > /dev/null

################### Argumentos para validación

echo -e "Cual es el nombre del dominio donde se ejecuta este script:"
read DOMINIO

################## Validación de información
echo "Validando la información para el dominio $DOMINIO"
CONSDOM=$(host ugto.mx | head -1)
IPSERV=$(hostname -I)

grep $IPSERV $CONSDOM
CONSULTA=$(echo $?)

if [ $CONSULTA -eq 0 ]
then
    echo "Se esta configurando el $DOMINIO con la IP $IPSERV"
else
    echo "Los parametros ingresados no coinciden con los registrados para este dominio"
    exit 1
fi

######################### INSTALACION DE NGINX #########################
echo "\t ------- Instalando Nginx"
#Revisando que exista alguna versión previa.
rpm -qa | grep nginx
VIN=$(echo $?)
#Revisión de repositorio nginx
dnf repolist | grep nginx
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
dnf install -y nginx
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
echo "\t ------- Instalando MariaDB"
#Verificador de versiones previas
whereis mariadb | grep "mariadb "
VMDB=$(echo $?)
if [ $VMDB -ne 0 ]
then
        #Instalando MariaDB
        dnf -y install mariadb-server mariadb
fi
#Habilitando y volviendo persistente el servicio de MariaDB
systemctl enable mariadb.service
systemctl start mariadb.service
#Si deseas configurar MariaDB descomenta la siguiente línea, es interactiva la configuración:
#mysql_secure_installation

###################### Instalando php74 ######################
echo "\t ------- Instalando php7.4"
#Validamos que esté instalado
whereis php | grep "php "
PVIP=$(echo $?)
#Verificación de que exista el repositorio instalado
dnf repolist | grep epel
PVIR=$(echo $?)

if [ $PVIP -ne 0 ] && [ $PVIR -ne 0 ]
then
        #Instalacion de repositorios
        dnf install epel-release -y
        dnf install -y https://rpms.remirepo.net/enterprise/remi-release-8.rpm
        dnf module install php:remi-7.4 -y
        dnf install -y php php-fpm php-mcrypt php-cli php-gd php-curl php-xml php-mysql php-mbstring php-pspell php-imagick php-cgi php-ldap php-soap php-xsl php-zip php-common php-imap php-json php-bz2 php-intl php-gmp
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
echo "\t ------- Instalando Roudcube"

curl https://roundcube.net/download/ > temp-rc.txt

RVS=$(grep "Stable version" temp-rc.txt | awk -F "- " '{ print $2}' | awk -F "<" '{ print $1}')
RDVS=$(grep "1.5.0-complete.tar.gz" temp-rc.txt | awk -F "href=""" '{ print $2}' | awk -F " """ '{ print $1}' | tr -d '"')

wget $RDVS

tar xzf roundcubemail-$RVS-complete.tar.gz
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

rm -rf roundcubemail-$RVS-complete.tar.gz temp-rc.txt

echo "Instalación terminada"