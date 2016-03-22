FROM archlinux

RUN pacman -Syyu --noconfirm \
        deluge \
	python2-service-identity \
	python2-notify \
	python2-mako \
	unrar \
	unzip \
	p7zip \
	python2-pillow \
	sudo \
    && mkdir /etc/deluge \
    && chown http:http /etc/deluge

EXPOSE 8112 58846

CMD ["sudo", "-uhttp", "deluged", "-d", "-c/etc/deluge"]
