module HippoSwap::StableCurveNumeral {

    const A_PRECISION: u128 = 100;

    const ERROR_SWAP_INVALID_DERIVIATION: u64 = 2020;


    public fun raw_A(future_A_time: u64, future_A: u64, initial_A_time: u64, initial_A: u64, timestamp: u64): u64 {
        if ( timestamp < future_A_time ) {
            if ( future_A < initial_A ) {
                initial_A - (initial_A - future_A) * (timestamp - initial_A_time) / (future_A_time - initial_A_time)
            } else {
                initial_A + (future_A - initial_A) * (timestamp - initial_A_time) / (future_A_time - initial_A_time)
            }
        } else { future_A }
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
    public fun get_D(x: u128, y: u128, amp: u64): u128 {
        let s = x + y;
        if ( s == 0 ) { s
        } else {
            let (d, ann, iter, end) = (s, (amp as u128) * 2, 0, 255);
            recur_D(d, x, y, s, ann, iter, end)
        }
    }

    #[test_only]
    fun time(offset_seconds: u64): u64 {
        let epoch = 1653289287000000;  // 2022-05-23 15:01:27
        epoch + offset_seconds * 1000000
    }

    #[test_only]
    fun mock_curve_params(): (u64, u64, u64, u64) {
        let initial_A = 3000000;        // 3 * (10**6)
        let future_A = 3500000;        // 3.5 * (10**6)
        let initial_A_time = time(0);
        let future_A_time = time(3600);
        (initial_A, future_A, initial_A_time, future_A_time)
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
    fun test_raw_A_branch_B() {
        let (ia, fa, iat, fat) = mock_curve_params();
        let timestamp = time(200);
        raw_A(fat, fa, iat, ia, timestamp);
    }

    #[test]
    fun test_raw_A_branch_A() {
        let (ia, _fa, iat, fat) = mock_curve_params();
        let fa = 2600000;
        let timestamp = time(200);
        raw_A(fat, fa, iat, ia, timestamp);
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
