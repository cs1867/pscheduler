#
# Makefile for any tool class
#

NAME=dhclient

FILES=\
	can-run \
	duration \
	enumerate \
	merged-results \
	participant-data \
	run \

MODULES=\
	common


PYS=$(MODULES:%=%.py)
PYCS=$(MODULES:%=__pycache__/%.pyc)

$(PYCS):
ifndef PYTHON
	@echo No PYTHON specified for build
	@false
endif
	$(PYTHON) -m compileall .
TO_CLEAN += $(PYCS)

CONFS=

install: $(FILES) $(CONFS) $(PYS) $(PYCS)
ifndef DESTDIR
	@echo No DESTDIR specified for installation
	@false
endif
ifdef CONFS
ifndef CONFDIR
	@echo No CONFDIR specified for installation
	@false
endif
endif
	mkdir -p $(DESTDIR)
	install -m 555 $(FILES) $(DESTDIR)
	install -m 444 $(PYS) $(DESTDIR)
	cp -r __pycache__ $(DESTDIR)
ifdef CONFS
	mkdir -p $(CONFDIR)
	install -m 644 $(CONFS) $(CONFDIR)
endif


clean:
	rm -f $(TO_CLEAN) *~
