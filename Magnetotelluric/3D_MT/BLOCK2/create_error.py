import sys
import math

import random

from PyModEM import ModEMData

filename = sys.argv[1]

data = ModEMData.ModEMData(filename)

for period in data.periods:
    for s in data.stations.values():
        zxx = s.get_component(period, 'ZXX')
        zxy = s.get_component(period, 'ZXY')
        zyx = s.get_component(period, 'ZYX')
        zyy = s.get_component(period, 'ZYY')

        error = math.sqrt(abs(zxy.real) * abs(zyx.real))
        synth_error = random.gauss(error * 0.05, sigma=1.0)

        zxx.error = synth_error
        zxy.error = synth_error
        zyx.error = synth_error
        zyy.error = synth_error


data.write_data('synth_error.dat', comment="# Data with a synthetic error")
