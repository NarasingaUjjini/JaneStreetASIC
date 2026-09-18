# Tests

From the repo root (see the README for what these prove):

```
pip install -r test/requirements.txt
PYTHONPATH=$PWD python3 -m pytest isa/test_golden.py isa/test_random.py -q
cd test && make
```

Gate-level, after Tiny Tapeout copies `gate_level_netlist.v`:

```
make GATES=yes
```

That needs `$PDK_ROOT` pointing at CMOS5L, including `sg13cmos5l_udp.v`.
