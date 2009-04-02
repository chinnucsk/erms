APP_NAME=erms
VSN=0.9
APP_DEPS="sasl,inets,mnesia,proc_reg,ibrowse,erlmail"

include Makefile.local

ERL_FILES ?=$(wildcard src/*.erl)
HRL_FILES ?=$(wildcard include/*.hrl)
BEAM_FILES ?=$(subst src/,ebin/,$(subst .erl,.beam,${ERL_FILES}))
MODULES ?=$(subst src/,,$(subst .erl,,${ERL_FILES}))
D_INC_DIRS=$(subst lib/, -I lib/,$(wildcard lib/*/include))
D_EBIN_DIRS=$(subst lib/, -pa lib/,$(wildcard lib/*/ebin))

INCLUDE ?=-I ${ERLANG_ROOT}/lib/stdlib-*/include ${D_INC_DIRS}
CODEPATH ?=-pz lib/*/ebin/

ERLC_CODEPATH ?=${D_EBIN_DIRS} -pz ${EUNIT_ROOT}/ebin
ERLC_FLAGS ?=+debug_info -W -o ebin/

EXTRA_DIALYZER_BEAM_FILES ?=$(wildcard lib/oserl*/ebin/*.beam lib/common_lib*/ebin/*.beam lib/proc_reg*/ebin/*.beam)

NODE ?=-name ${APP_NAME}@127.0.0.1

#shorthand
LEV=lib/erms-${VSN}

DEB_TMP_DIR=./deb_tmp
LIB_ERMS_DIRS=lib/erms-${VSN}/priv/yaws/tmp lib/erms-${VSN}/test lib/erms-${VSN}/log/msgs lib/erms-${VSN}/log/sasl lib/erms-${VSN}/inets/httpc lib/erms-${VSN}/db lib/erms-${VSN}/backups lib/erms-${VSN}/etc
LIB_ERMS_LINKS=${LEV}/src ${LEV}/include ${LEV}/ebin ${LEV}/priv/yaws/docroot ${LEV}/priv/yaws/pub_docroot 

all: ${BEAM_FILES} src/TAGS 

deb: makelibs release debonly

# no deps, just assume makelibs and release already done
debonly : 
	@rm -rf ${DEB_TMP_DIR}

	mkdir -p ${DEB_TMP_DIR}/lib
	mkdir -p ${DEB_TMP_DIR}/releases
	tar -zxvC ${DEB_TMP_DIR} -f releases/${VSN}/${APP_NAME}.tar.gz
	cp -a debian/ ${DEB_TMP_DIR}

	(cd ${DEB_TMP_DIR}; dpkg-buildpackage -aamd64 -rfakeroot -k${USER}@catalyst.net.nz )


	#@rm -rf ${DEB_TMP_DIR}


app: ${BEAM_FILES}

release: ${BEAM_FILES} test xref dialyzer.report docs releases/${VSN}/${APP_NAME}.tar.gz

.PHONY: info clean docs test xref shell dialyzer.report release shell_args shell_boot kannel kannel2 smppsim makelibs

info:
	@echo Erlang root: +${ERLANG_ROOT}+
	@echo Eunit root: +${EUNIT_ROOT}+
	@echo Beam dirs: ${D_EBIN_DIRS}
	@echo Extra dialyzer beam files: ${EXTRA_DIALYZER_BEAM_FILES}
	@echo Include: +${INCLUDE}+

clean:
	@rm -f ebin/*.beam priv/sasl/* priv/sasl.log priv/yaws/logs/*.{log,old,access}
	@find src/ priv/ -iname \*~ | xargs rm -v

ebin/%.beam: src/%.erl ${HRL_FILES}
	@echo $@: erlc ${ERLC_FLAGS} ${ERLC_CODEPATH} ${INCLUDE} $<
	@erlc ${ERLC_FLAGS} ${ERLC_CODEPATH} ${INCLUDE} $<

docs: ${ERL_FILES}
	erl -noshell -run edoc_run application "'$(APP_NAME)'" '"."' '[{def,{vsn,"$(VSN)"}}]'
	rm -rf priv/yaws/docroot/doc
	cp -r doc priv/yaws/docroot/

test: ${BEAM_FILES}
	erl $(CODEPATH) -config priv/${APP_NAME} -eval "lists:map(fun(A) -> {A,application:start(A)} end, [${APP_DEPS}]), application:load(${APP_NAME}), lists:foreach(fun (M) -> io:fwrite(\"Testing ~p:~n\", [M]), eunit:test(M) end, [`perl -e 'print join(",", qw(${MODULES}));'`])." -s init stop -noshell

xref: ${BEAM_FILES}
	erl $(CODEPATH) -eval "xref:start(${APP_NAME}), io:fwrite(\"~n~nXref: ~p~n~n\", [xref:d(\"ebin/\")])." -s init stop -noshell

src/TAGS: ${BEAM_FILES}
	erl $(CODEPATH) -eval "tags:dir(\"src/\", [{outdir, \"src/\"}])." -s init stop -noshell

shell_args:
	@(echo -ne "rr(\"include/*\").\nlists:map(fun(A) -> {A,application:start(A)} end, [${APP_DEPS}]).\napplication:start(${APP_NAME})." | pbcopy)

shell: ${BEAM_FILES}
	erl +K true -smp +A 10 ${NODE} -config priv/${APP_NAME} $(CODEPATH)

shell_boot: ${BEAM_FILES}
	erl ${NODE} -config priv/${APP_NAME} $(CODEPATH) -boot releases/${VSN}/${APP_NAME}

dialyzer.report: ${BEAM_FILES}
	@(dialyzer --verbose --succ_typings ${INCLUDE} ${D_EBIN_DIRS} -c ${BEAM_FILES} ${EXTRA_DIALYZER_BEAM_FILES}; if [ $$? != 1 ]; then true; else false; fi)

releases/${VSN}/${APP_NAME}.boot: ${BEAM_FILES} releases/${VSN}/${APP_NAME}.rel ebin/${APP_NAME}.app priv/${APP_NAME}.config
	erl $(CODEPATH) -eval 'systools:make_script("releases/${VSN}/${APP_NAME}").' -s init stop -noshell

releases/${VSN}/${APP_NAME}.tar.gz: releases/${VSN}/${APP_NAME}.boot docs
	erl $(CODEPATH) -eval 'systools:make_tar("releases/${VSN}/${APP_NAME}", [{path, ["lib/*/ebin"]},{dirs,[include,src]}]).' -s init stop -noshell

kannel:
	@bearerbox -v 1 test/kannel-conf/kannel.conf

kannel2:
	@bearerbox -v 1 test/kannel-conf/kannel2.conf

smppsim:
	@(cd test/SMPPSim; ./startsmppsim.sh)

makelibs:
	@for d in lib/common_lib-* lib/erlmail-* lib/oserl-*-catalyst lib/eunit lib/gregexp-* lib/prog_reg-BLDR; do \
		(cd $$d; $(MAKE)); \
	done ;\
	(cd lib/yaws-1.68; ./configure; make)