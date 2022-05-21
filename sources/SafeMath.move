// Safe math implementation for number manipulation.
// TODO: make it into more sophosticated math operations. Currently
// TODO: just some place holder for the interfaces for functionalities.
module HippoSwap::SafeMath {
    const ERROR_UNDERFLOW: u64 = 0;

    public fun add(a: u128, b: u128): u128 {
        a + b
    }

    public fun sub(a: u128, b: u128): u128 {
        assert!(a >= b, ERROR_UNDERFLOW);
        a - b
    }

    public fun mul(a: u128, b: u128): u128 {
        a * b
    }

    public fun div(a: u128, b: u128): u128 {
        a / b
    }
    // ================ Tests ================
    #[test]
    public fun works() {
        assert!(add(1, 1) == 2, 0);

        assert!(sub(1, 1) == 0, 0);
        assert!(sub(0, 0) == 0, 0);
    }
}