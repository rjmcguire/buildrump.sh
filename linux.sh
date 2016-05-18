checkcheckout ()
{

	[ -f "${SRCDIR}/arch/lkl/Makefile" ] || \
	    die "Cannot find ${SRCDIR}/arch/lkl/Makefile!"

	[ ! -z "${TARBALLMODE}" ] && return

	if ! ${BRDIR}/checkout.sh checkcheckout ${SRCDIR} \
	    && ! ${TITANMODE}; then
		die 'revision mismatch, run checkout (or -H to override)'
	fi
}

maketools ()
{

	checkcheckout

	probeld
	probenm
	probear
	${HAVECXX} && probecxx

	cd ${OBJDIR}

	# Create mk.conf.  Create it under a temp name first so as to
	# not affect the tool build with its contents
	MKCONF="${BRTOOLDIR}/mk.conf.building"
	> "${MKCONF}"
	mkconf_final="${BRTOOLDIR}/mk.conf"
	> ${mkconf_final}

	${KERNONLY} || probe_rumpuserbits

	checkcompiler

	#
	# Create external toolchain wrappers.
	mkdir -p ${BRTOOLDIR}/bin || die "cannot create ${BRTOOLDIR}/bin"
	for x in CC AR NM OBJCOPY; do
		maketoolwrapper true $x
	done
	for x in AS CXX LD OBJDUMP RANLIB READELF SIZE STRINGS STRIP; do
		maketoolwrapper false $x
	done

	# create a cpp wrapper, but run it via cc -E
	if [ "${CC_FLAVOR}" = 'clang' ]; then
		cppname=clang-cpp
	else
		cppname=cpp
	fi
	tname=${BRTOOLDIR}/bin/${MACHINE_GNU_ARCH}--netbsd${TOOLABI}-${cppname}
	printf '#!/bin/sh\n\nexec %s -E -x c "${@}"\n' ${CC} > ${tname}
	chmod 755 ${tname}

	for x in 1 2 3; do
		! ${HOST_CC} -o ${BRTOOLDIR}/bin/brprintmetainfo \
		    -DSTATHACK${x} ${BRDIR}/brlib/utils/printmetainfo.c \
		    >/dev/null 2>&1 || break
	done
	[ -x ${BRTOOLDIR}/bin/brprintmetainfo ] \
	    || die failed to build brprintmetainfo

	${HOST_CC} -o ${BRTOOLDIR}/bin/brrealpath \
	    ${BRDIR}/brlib/utils/realpath.c || die failed to build brrealpath

	printoneconfig 'Cmd' "SRCDIR" "${SRCDIR}"
	printoneconfig 'Cmd' "DESTDIR" "${DESTDIR}"
	printoneconfig 'Cmd' "OBJDIR" "${OBJDIR}"
	printoneconfig 'Cmd' "BRTOOLDIR" "${BRTOOLDIR}"

	appendmkconf 'Cmd' "${RUMP_DIAGNOSTIC:-}" "RUMP_DIAGNOSTIC"
	appendmkconf 'Cmd' "${RUMP_DEBUG:-}" "RUMP_DEBUG"
	appendmkconf 'Cmd' "${RUMP_LOCKDEBUG:-}" "RUMP_LOCKDEBUG"
	appendmkconf 'Cmd' "${DBG:-}" "DBG"
	printoneconfig 'Cmd' "make -j[num]" "-j ${JNUM}"

	if ${KERNONLY}; then
		appendmkconf Cmd yes RUMPKERN_ONLY
	fi

	if ${KERNONLY} && ! cppdefines __NetBSD__; then
		appendmkconf 'Cmd' '-D__NetBSD__' 'CPPFLAGS' +
		appendmkconf 'Probe' "${RUMPKERN_UNDEF}" 'CPPFLAGS' +
	else
		appendmkconf 'Probe' "${RUMPKERN_UNDEF}" "RUMPKERN_UNDEF"
	fi
	appendmkconf 'Probe' "${RUMP_CURLWP:-}" 'RUMP_CURLWP' ?
	appendmkconf 'Probe' "${CTASSERT:-}" "CPPFLAGS" +
	appendmkconf 'Probe' "${RUMP_VIRTIF:-}" "RUMP_VIRTIF"
	appendmkconf 'Probe' "${EXTRA_CWARNFLAGS}" "CWARNFLAGS" +
	appendmkconf 'Probe' "${EXTRA_LDFLAGS}" "LDFLAGS" +
	appendmkconf 'Probe' "${EXTRA_CPPFLAGS}" "CPPFLAGS" +
	appendmkconf 'Probe' "${EXTRA_CFLAGS}" "BUILDRUMP_CFLAGS"
	appendmkconf 'Probe' "${EXTRA_AFLAGS}" "BUILDRUMP_AFLAGS"
	_tmpvar=
	for x in ${EXTRA_RUMPUSER} ${EXTRA_RUMPCOMMON}; do
		appendvar _tmpvar "${x#-l}"
	done
	appendmkconf 'Probe' "${_tmpvar}" "RUMPUSER_EXTERNAL_DPLIBS" +
	_tmpvar=
	for x in ${EXTRA_RUMPCLIENT} ${EXTRA_RUMPCOMMON}; do
		appendvar _tmpvar "${x#-l}"
	done
	appendmkconf 'Probe' "${_tmpvar}" "RUMPCLIENT_EXTERNAL_DPLIBS" +
	appendmkconf 'Probe' "${LDSCRIPT:-}" "RUMP_LDSCRIPT"
	appendmkconf 'Probe' "${SHLIB_MKMAP:-}" 'SHLIB_MKMAP'
	appendmkconf 'Probe' "${SHLIB_WARNTEXTREL:-}" "SHLIB_WARNTEXTREL"
	appendmkconf 'Probe' "${MKSTATICLIB:-}"  "MKSTATICLIB"
	appendmkconf 'Probe' "${MKPIC:-}"  "MKPIC"
	appendmkconf 'Probe' "${MKSOFTFLOAT:-}"  "MKSOFTFLOAT"
	appendmkconf 'Probe' $(${HAVECXX} && echo yes || echo no) _BUILDRUMP_CXX

	printoneconfig 'Mode' "${TARBALLMODE}" 'yes'

	rm -f ${BRTOOLDIR}/toolchain-conf.mk
	exec 3>&1 1>${BRTOOLDIR}/toolchain-conf.mk
	printf 'BUILDRUMP_TOOL_CFLAGS=%s\n' "${EXTRA_CFLAGS}"
	printf 'BUILDRUMP_TOOL_CXXFLAGS=%s\n' "${EXTRA_CFLAGS}"
	printf 'BUILDRUMP_TOOL_CPPFLAGS=-D__NetBSD__ %s %s\n' \
	       "${EXTRA_CPPFLAGS}" "${RUMPKERN_UNDEF}"
	exec 1>&3 3>&-

	# XXX: make rumpmake from src-netbsd
	cd ${SRCDIR}/../src-netbsd
	# create user-usable wrapper script
	makemake ${BRTOOLDIR}/rumpmake ${BRTOOLDIR}/dest makewrapper

	# create wrapper script to be used during buildrump.sh, plus tools
	makemake ${RUMPMAKE} ${OBJDIR}/dest.stage tools

	CC=${BRTOOLDIR}/bin/${MACHINE_GNU_ARCH}--${RUMPKERNEL}${TOOLABI}-gcc

}

makebuild ()
{
	echo "=== Linux build SRCDIR=${SRCDIR} ==="
	cd ${SRCDIR}
	VERBOSE="V=0"
	if [ ${NOISE} -gt 1 ] ; then
		VERBOSE="V=1"
	fi

	CROSS=$(${CC} -dumpmachine)
	if [ ${CROSS} = "$(gcc -dumpmachine)" ]
	then
		CROSS=
	else
		CROSS=${CROSS}-
	fi

	set -e
	set -x
	mkdir -p ${OBJDIR}/lkl-linux
	cd tools/lkl
	rm -f ${OBJDIR}/lkl-linux/tools/lkl/lib/lkl.o
	export RUMP_PREFIX=${RUMPSRC}/../src-netbsd/sys/rump # ${OBJDIR}/dest.stage/
	export RUMP_INCLUDE=${RUMPSRC}/../src-netbsd/sys/rump/include #${OBJDIR}/dest.stage/usr/include
	make CROSS_COMPILE=${CROSS} rumprun=yes -j ${JNUM} ${VERBOSE} O=${OBJDIR}/lkl-linux/ # FIXME: not supported yet O=${OBJDIR}/lkl-linux/
	cd ../../
	make CROSS_COMPILE=${CROSS} headers_install ARCH=lkl O=${RROBJ}/rumptools/dest
	set +e
	set +x
}

makeinstall ()
{

	export RUMP_PREFIX=${RUMPSRC}/../src-netbsd/sys/rump # ${OBJDIR}/dest.stage/
	export RUMP_INCLUDE=${RUMPSRC}/../src-netbsd/sys/rump/include #${OBJDIR}/dest.stage/usr/include
	make rumprun=yes install DESTDIR=${DESTDIR} -C ${SRCDIR}/tools/lkl/ O=${OBJDIR}/lkl-linux/

}

#
# install kernel headers.
# Note: Do _NOT_ do this unless you want to install a
#       full rump kernel application stack
#
makekernelheaders ()
{
	return
}

maketests ()
{
	printf 'Linux libos test ... '
	make -C ${SRCDIR}/tools/lkl test || die Linux libos failed
}

