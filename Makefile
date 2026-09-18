test: golden rtl formal
golden:
	PYTHONPATH=$(PWD) python3 -m pytest isa/test_golden.py isa/test_random.py -q
rtl:
	$(MAKE) -C test
formal:
	bash scripts/formal_sim.sh
gl:
	bash scripts/gl_sim.sh
synth:
	bash scripts/synth.sh
fw:
	PYTHONPATH=$(PWD) python3 fw/programs.py
.PHONY: test golden rtl formal gl synth fw
