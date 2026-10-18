PORTNAME=	systools
DISTVERSION=	g20261018
CATEGORIES=	sysutils

MAINTAINER=	sdalu@sdalu.com
COMMENT=	Small system tools in POSIX sh for FreeBSD and Linux
WWW=		https://github.com/sdalu/systools

TEST_DEPENDS=	shellcheck:devel/hs-ShellCheck

# No licence is stated upstream yet: LICENSE is left unset until one is.

USE_GITHUB=	yes
GH_ACCOUNT=	sdalu
# systools has no releases: the port is a snapshot of one commit of main,
# DISTVERSION its date.
GH_TAGNAME=	638edae

NO_ARCH=	yes
NO_BUILD=	yes

TEST_TARGET=	check tests

OPTIONS_DEFINE=	DAV
OPTIONS_DEFAULT=	DAV
DAV_DESC=	caldav and carddav, the CalDAV and CardDAV clients (Ruby)

DAV_USES=	ruby shebangfix
DAV_RUN_DEPENDS=	rubygem-nokogiri>=0:textproc/rubygem-nokogiri
DAV_TEST_DEPENDS=	rubygem-nokogiri>=0:textproc/rubygem-nokogiri
DAV_PLIST_FILES=	bin/caldav \
		bin/carddav \
		share/man/man1/caldav.1.gz \
		share/man/man1/carddav.1.gz

SHEBANG_FILES=	bin/caldav bin/carddav
ruby_CMD=	${RUBY}

PLIST_FILES=	bin/compositor-picom \
		bin/default-gateway \
		bin/do-screenshot \
		bin/is-docked \
		bin/low-priority \
		bin/mullvad-relays \
		bin/openwrt-acl \
		bin/pdf2jpg \
		bin/pushover \
		bin/qr \
		bin/screen-extend \
		bin/screen-mirror \
		bin/shrink-pdf \
		bin/term-title \
		bin/transcribe \
		bin/vocalise \
		bin/vorbis-edit \
		bin/vpn-status \
		bin/where-am-i \
		bin/with-gnu-make \
		bin/zfs-prune-snapshots \
		bin/zfs-snapshot \
		share/man/man1/compositor-picom.1.gz \
		share/man/man1/default-gateway.1.gz \
		share/man/man1/do-screenshot.1.gz \
		share/man/man1/is-docked.1.gz \
		share/man/man1/low-priority.1.gz \
		share/man/man1/mullvad-relays.1.gz \
		share/man/man1/openwrt-acl.1.gz \
		share/man/man1/pdf2jpg.1.gz \
		share/man/man1/pushover.1.gz \
		share/man/man1/qr.1.gz \
		share/man/man1/screen-extend.1.gz \
		share/man/man1/screen-mirror.1.gz \
		share/man/man1/shrink-pdf.1.gz \
		share/man/man1/term-title.1.gz \
		share/man/man1/transcribe.1.gz \
		share/man/man1/vocalise.1.gz \
		share/man/man1/vorbis-edit.1.gz \
		share/man/man1/vpn-status.1.gz \
		share/man/man1/where-am-i.1.gz \
		share/man/man1/with-gnu-make.1.gz \
		share/man/man1/zfs-prune-snapshots.1.gz \
		share/man/man1/zfs-snapshot.1.gz

# The upstream Makefile installs every tool and its page; it is run as
# it is, and the option only takes the Ruby tools back out.
do-install:
	cd ${WRKSRC} && ${MAKE_CMD} install DESTDIR=${STAGEDIR} \
	    PREFIX=${PREFIX} MANDIR=${PREFIX}/share/man

post-install-DAV-off:
	${RM} ${STAGEDIR}${PREFIX}/bin/caldav ${STAGEDIR}${PREFIX}/bin/carddav \
	    ${STAGEDIR}${PREFIX}/share/man/man1/caldav.1 \
	    ${STAGEDIR}${PREFIX}/share/man/man1/carddav.1

.include <bsd.port.mk>
