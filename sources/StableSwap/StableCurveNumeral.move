module HippoSwap::StableCurveNumeral {

    use SmoothAptos::Math;

    const PRECISION: u128 = 1000000000000000000;
    // 10 ** 18
    const A_PRECISION: u128 = 100;

    const ERROR_SWAP_INVALID_DERIVIATION: u64 = 2020;


    public fun raw_A(future_A_time: u128, future_A: u128, initial_A_time: u128, initial_A: u128, timestamp: u128): u128 {
        if ( timestamp < future_A_time ) {
            if ( future_A < initial_A ) {
                initial_A - (initial_A - future_A) * (timestamp - initial_A_time) / (future_A_time - initial_A_time)
            } else {
                initial_A + (future_A - initial_A) * (timestamp - initial_A_time) / (future_A_time - initial_A_time)
            }
        } else { future_A }
    }


    public fun precision_multiplier(decimal: u64): u128 {
        Math::pow(10, 18) / Math::pow(10, decimal)
    }

    public fun rates(x: u64, y: u64): (u128, u128) {
        (
            precision_multiplier(x) * Math::pow(10, 18),
            precision_multiplier(y) * Math::pow(10, 18)
        )
    }

    public fun xp_mem(x_reserve: u64, y_reserve: u64, rate_x: u128, rate_y: u128): (u128, u128) {
        (rate_x * (x_reserve as u128) / PRECISION, rate_y * (y_reserve as u128) / PRECISION)
    }

    fun recur_D(d: u128, x: u128, y: u128, s: u128, ann: u128, iter: u128, end: u128): u128 {
        assert!(iter < end, ERROR_SWAP_INVALID_DERIVIATION);
        let result = 0;
        let d_p = d;
        d_p = d_p * d / (x * 2);
        d_p = d_p * d / (y * 2);
        let new_d_prev = d;

        // D = (Ann * S / A_PRECISION + D_P * N_COINS) * D / ((Ann - A_PRECISION) * D / A_PRECISION + (N_COINS + 1) * D_P)
        let new_d = (ann * s / A_PRECISION + d_p * 2) * d / ((ann - A_PRECISION) * d / A_PRECISION + 3 * d_p);
        if ( new_d > new_d_prev && new_d <= new_d_prev + 1) result = new_d;
        if ( new_d <= new_d_prev && new_d_prev <= new_d + 1) result = new_d;
        if ( result == 0 ) { recur_D(new_d, x, y, s, ann, iter + 1, end) }
        else { result }
    }

    /// D invariant calculation in non-overflowing integer operations iteratively
    ///
    /// A * sum(x_i) * n**n + D = A * D * n**n + D**(n+1) / (n**n * prod(x_i))
    ///
    /// Converging solution:
    ///
    ///  D[j+1] = (A * n**n * sum(x_i) - D[j]**(n+1) / (n**n prod(x_i))) / (A * n**n - 1)
    ///
    public fun get_D(x: u128, y: u128, amp: u128): u128 {
        let s = x + y;
        if ( s == 0 ) { s
        } else {
            let (d, ann, iter, end) = (s, amp * 2, 0, 255);
            recur_D(d, x, y, s, ann, iter, end)
        }
    }

    #[test]
    fun test_get_D() {
        let s = get_D(100, 400, 1000);
        Std::Debug::print(&s);
    }

    #[test]
    fun test_get_D_2() {
        let s = get_D(101010, 200, 50);
        Std::Debug::print(&s);
    }

    #[test]
    fun test_get_D_3() {
        let s = get_D(10074, 10074, 50);
        Std::Debug::print(&s);
    }

    #[test]
    fun test_iter_loop_D() {
        let s = get_D(100, 200, 1000);
        Std::Debug::print(&s);
    }

    #[test]
    fun test_get_D4() {
        let s = get_D(100, 300, 90);
        Std::Debug::print(&s);
    }


    #[test]
    #[expected_failure(abort_code = 2020)]
    public fun fail_recur_D() {
        recur_D(1, 1, 1, 1, 1, 1, 1);
    }

    #[test]
    public fun recur_D_ok_1() {
        recur_D(100, 2, 2, 1, 100, 1, 10);
    }


    #[test]
    fun test_redur_D_ok_2() {
        recur_D(101210, 101010, 200, 101210, 100, 1, 10);
    }
}
