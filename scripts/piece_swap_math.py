

def compute_optimal_parameters(K, w_end, w_switch):
    """
    (x+m)(y+m) = K
    y' = -K / (x+m)**2
    """
    m = (K / w_end) ** 0.5
    xa = (K / w_switch) ** 0.5 - m
    xb = K / (xa + m) - m
    k2 = w_switch * xa * xa
    n = k2 / xa - xb
    return m, n, xa, xb, k2

def plot_optimal_parameters(K, w_end, w_switch):
    m, n, xa, xb, k2 = compute_optimal_parameters(K, w_end, w_switch)
    print("xa={}".format(int(xa)))
    print("xb={}".format(int(xb)))
    print("m ={}".format(int(m)))
    print("n ={}".format(int(n)))
    print("k2={}".format(int(k2)))
    def plotter():
        def f(x):
            if x < xa:
                return k2 / x - n
            elif x < xb:
                return K /(x+m) - m
            else:
                return k2 / (x+n)
        import matplotlib.pyplot as plt
        import numpy as np
        x_end = xb * 2
        x_start = f(x_end)
        x_points = list(np.arange(x_start, x_end, (x_end-x_start) / 1000))
        y_points = list(map(f, x_points))
        plt.plot(x_points, y_points)
        plt.show()
    return plotter


if __name__ == '__main__':
    import sys
    if len(sys.argv) != 4:
        print("Usage: python piece_swap_math.py K w_end w_switch")
        exit()
    args = map(float, sys.argv[1:])
    plot_optimal_parameters(*args)()
