git checkout master
git pull

sudo systemctl reload nginx.service
sudo systemctl restart nginx.service
sudo systemctl status nginx.service

sudo systemctl restart mariadb.service
sudo systemctl status mariadb.service

sudo systemctl restart isucon-ruby-isuwitter.service
sudo systemctl status isucon-ruby-isuwitter.service