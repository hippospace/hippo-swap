# Formulas of Stable Curve Swap

Denote D as the sum of the ideal balance of the constant sum.

Constant Sum:

$$x + y = D$$

Constant Product:

$$ xy = \left(\dfrac{D}{2} \right)^2$$

Constructing the stable swap invariant:

$$\alpha{D}(x+y) + xy = \alpha{D}^2 + \left(\dfrac{D}{2} \right)^2$$


## Stable Curve Invariants

In order to support any prices, let $\alpha$ to be dynamic.

When the portfolio is in a perfect balance, it’s equal to a constant A, however falls off to 0 when going out of balance:

$$\alpha = \dfrac{Axy}{\left(\dfrac{D}{2}\right)^2}$$

$\implies$

$$\dfrac{4Axy(x+y)}{D^2} + xy = \dfrac{4xy}{D} + \dfrac{D^2}{4}$$

$\implies$

$$D^3 + 4xyD(4A-1) - 16Axy(x+y) = 0$$

A is the amplification coefficient.
x, y are the current coin reserves.

## Resolve D from A, x, y (Add, Remove)

Converging solution:
Newton's:
$$D_{n+1} = D_n - \dfrac{f(x)}{f'(x)}$$

:

$$D_{n+1} = D_n - \dfrac{D_n^3 + 4xyD_n(4A-1) - 16Axy(x+y)}{3D^2+4xy(4A-1)} $$

Simplified:

 $$D_{n+1} = \dfrac{16Axy(x+y) + 2D_n^3}
 {3D_n^2 + 4xy(4A-1)} $$


 Let $D_0 = x+y$, and it's easy to know that $D_0 > D$ . 

 That's how we get $D$ from $A$, $x$, and $y$. 

 ## Resolve y from A, x, and D (swap)

Derived from the Stable curve invariants:

$$ y^2 + \dfrac{4Ax+D-4AD}{4A} y = \dfrac{D^3}{16Ax} $$
or:
$$ y^2 + \left( x + \dfrac{D}{4A} - D \right) y = \dfrac{D^3}{16Ax} $$

Iterative Solution of :

$$y^2 + by = c$$

:

$$y_{n+1} = (y_n^2 + c) / (2y_n + b)$$
