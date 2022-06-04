

def plot_debug_printout(path):
    lines = list(open(path, 'r').readlines())
    numbers = list(map(int, lines))
    xs = [x for (i, x) in enumerate(numbers) if i % 2 == 0]
    ys = [y for (i, y) in enumerate(numbers) if i % 2 == 1]

    import matplotlib.pyplot as plt

    plt.plot(xs, ys)
    plt.show()

if __name__ == '__main__':
    import sys
    plot_debug_printout(sys.argv[1])