#!/bin/bash
enabled=$(cat sources/PieceSwap/PieceSwapMath.move | grep ENABLE_PLOT | grep 'true')
if [[ $enabled ]]
then
    aptos move test --filter test_get_swap_x_to_y_out_1 | grep debug | cut -d' ' -f2 > t1.log
    python3 scripts/plot_debug_printout.py t1.log
    aptos move test --filter test_get_swap_x_to_y_out_2 | grep debug | cut -d' ' -f2 > t2.log
    python3 scripts/plot_debug_printout.py t2.log
else
    echo "set ENABLE_PLOT = true and NUM_STEPS = 1000 first in PieceSwapMath.move"
fi
