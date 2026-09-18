# Tests
pip install -r test/requirements.txt
PYTHONPATH=$PWD python3 -m pytest isa/test_golden.py isa/test_random.py -q
cd test && make

# Gate-level: after Tiny Tapeout GDS action copies gate_level_netlist.v
#   make GATES=yes
