#! /usr/bin/env sh
#
# Copyright (c) 2013 Antti Kantee <pooka@iki.fi>
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS
# OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
# SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
# HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
# LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
# OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
# SUCH DAMAGE.
#

# Fetches subset of the NetBSD source tree relevant for buildrump.sh

#
#	NOTE!
#
# DO NOT CHANGE THE VALUES WITHOUT UPDATING THE GIT REPO!
#
# The procedure is:
# 1) change the cvs tags, commit the change, DO NOT PUSH
# 2) run "./checkout.sh githubdate rumpkernel-netbsd-src"
# 3) push rumpkernel-netbsd-src
# 4) push buildrump.sh
#
NBSRC_CVSDATE="20130515 2200UTC"
NBSRC_CVSFLAGS="-z3 \
    -d ${BUILDRUMP_CVSROOT:-:pserver:anoncvs@anoncvs.netbsd.org:/cvsroot}"

# Cherry-pick patches are not in $NBSRC_CVSDATE
# the format is "date1:dir1 dir2 dir3 ...;date2:dir 4..."
NBSRC_EXTRA='20130601 2100UTC:
    src/sys/rump/net/lib/libvirtif
    src/sys/rump/librump/rumpkern/rump.c
    src/sys/rump/net/lib/libnet
    src/sys/rump/net/lib/libnetinet
    src/sys/netinet/portalgo.c;
	20130610 1500UTC:
    src/sys/rump/librump/rumpvfs/rumpfs.c
    src/sys/rump/net/lib/libshmif;
	20130623 1930UTC:
    src/sys/rump/net/lib/libsockin;
	20130625 2110UTC:
    src/sys/rump/include/rump;
	20130630 1715UTC:
    src/sys/rump/librump/rumpnet/net_stub.c
    src/sys/rump/net/lib/libnetinet/component.c'

GITREPO='https://github.com/anttikantee/rumpkernel-netbsd-src'
GITREPOPUSH='git@github.com:anttikantee/rumpkernel-netbsd-src'
GITREVFILE='.srcgitrev'

die ()
{

	echo ">> $*"
	exit 1
}

checkoutcvs ()
{
	cd ${SRCDIR}

	: ${CVS:=cvs}
	if ! type ${CVS} >/dev/null 2>&1 ;then
		echo '>> Need cvs for checkout-cvs functionality'
		echo '>> Set $CVS or ensure that cvs is in PATH'
		die \"${CVS}\" not found
	fi

	# squelch .cvspass whine
	export CVS_PASSFILE=/dev/null

	# we need listsrcdirs
	echo ">> Fetching the list of files we need to checkout ..."
	${CVS} ${NBSRC_CVSFLAGS} co -p -D "${NBSRC_CVSDATE}" \
	    src/sys/rump/listsrcdirs > listsrcdirs 2>/dev/null \
	    || die listsrcdirs checkout failed

	# trick cvs into "skipping" the module name so that we get
	# all the sources directly into $SRCDIR
	rm -f src
	ln -s . src

	# now, do the real checkout
	echo ">> Fetching the necessary subset of NetBSD source tree to:"
	echo "   "`pwd -P`
	echo '>> This will take a few minutes and requires ~200MB of disk space'
	sh listsrcdirs -c | xargs ${CVS} ${NBSRC_CVSFLAGS} co -P \
	    -D "${NBSRC_CVSDATE}" || die checkout failed

	IFS=';'
	for x in ${NBSRC_EXTRA}; do
		IFS=':'
		set -- ${x}
		unset IFS
		date=${1}
		dirs=${2}
		${CVS} ${NBSRC_CVSFLAGS} co -P -D "${date}" ${dirs} || die co2
	done

	# remove the symlink used to trick cvs
	rm -f src
	rm -f listsrcdirs
}

# Check out sources via git.  If there's already a git repo in the
# destination directory, assume that it's the correct repo.
checkoutgit ()
{

	if [ -d ${SRCDIR}/.git ] ; then
		cd ${SRCDIR}
		[ -z "$(git status --porcelain)" ] \
		    || die "Cloned repo in ${SRCDIR} is not clean, aborting."
		git fetch origin master
	else
		git clone -n ${GITREPO} ${SRCDIR}
		cd ${SRCDIR}
	fi

	git checkout $(cat ${GITREVFILE}) \
	    || die 'Could not find git revision. Wrong repo?'
}

# do a cvs checkout and push the results into the github mirror
githubdate ()
{

	[ -z "$(git status --porcelain | grep 'M checkout.sh')" ] \
	    || die checkout.sh contains uncommitted changes!
	gitrev=$(git rev-parse HEAD)

	[ -f ${SRCDIR} ] && die Error, ${SRCDIR} exists

	set -e

	git clone -n -b netbsd-cvs ${GITREPOPUSH} ${SRCDIR}

	# checkoutcvs does cd to SRCDIR
	curdir="$(pwd)"
	checkoutcvs

	git add -A
	git commit -m "NetBSD cvs for buildrump.sh git rev ${gitrev}"
	git checkout master
	git merge netbsd-cvs
	gitsrcrev=$(git rev-parse HEAD)
	cd "${curdir}"
	echo ${gitsrcrev} > ${GITREVFILE}
	git commit -m "Source for buildrump.sh git rev ${gitrev}" ${GITREVFILE}

	set +e
}

[ $# -ne 2 ] && die Invalid usage.  Run this script via buildrump.sh
SRCDIR=${2}

case "${1}" in
cvs)
	mkdir -p ${SRCDIR} || die cannot access ${SRCDIR}
	checkoutcvs
	echo '>> checkout done'
	;;
git)
	mkdir -p ${SRCDIR} || die cannot access ${SRCDIR}
	checkoutgit
	echo '>> checkout done'
	;;
githubdate)
	[ $(dirname $0) != '.' ] && die Script must be run as ./checkout.sh
	githubdate
	echo '>>'
	echo '>> Update done'
	echo '>>'
	echo ">> REMEMBER TO PUSH ${SRCDIR}"
	echo '>>'
	;;
*)
	die Invalid usage.  Run this script via buildrump.sh
	;;
esac

exit 0
