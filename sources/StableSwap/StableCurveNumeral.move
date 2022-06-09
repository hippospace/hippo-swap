module HippoSwap::StableCurveNumeral {

    // const A_PRECISION: u128 = 100;

    const ERROR_SWAP_INVALID_DERIVIATION: u64 = 2020;
    const ERROR_SWAP_INVALID_AMOUNT: u64 = 2021;


    public fun get_A(initial_A: u64, future_A: u64, initial_A_time: u64, future_A_time: u64, timestamp: u64): u64 {
        if ( timestamp < future_A_time ) {
            if ( future_A < initial_A ) {
                initial_A - (initial_A - future_A) * (timestamp - initial_A_time) / (future_A_time - initial_A_time)
            } else {
                initial_A + (future_A - initial_A) * (timestamp - initial_A_time) / (future_A_time - initial_A_time)
            }
        } else { future_A }
    }

    fun recur_D_origin(d: u128, x: u128, y: u128, s: u128, ann: u128, iter: u128, end: u128): (u128, u128) {
        assert!(iter < end, ERROR_SWAP_INVALID_DERIVIATION);
        let d_prev = d;
        let result = 0;
        let d_p = d;
        d_p = d_p * d / (x * 2);
        d_p = d_p * d / (y * 2);

        // D = (Ann * S / A_PRECISION + D_P * N_COINS) * D / ((Ann - A_PRECISION) * D / A_PRECISION + (N_COINS + 1) * D_P)
        // (2A(x+y) + 2*D**3 / 4xy) * D / ((2A-1)d + 3 * D**3 / 4xy)
        let new_d = (ann * s + d_p * 2) * d / ((ann - 1) * d + 3 * d_p);
        if ( new_d > d_prev && new_d <= d_prev + 1) result = new_d;
        if ( new_d <= d_prev && d_prev <= new_d + 1) result = new_d;
        if ( result == 0 ) { recur_D_origin(new_d, x, y, s, ann, iter + 1, end) }
        else { (result, iter) }
    }

    fun recur_D_improved(d: u128, x: u128, y: u128, s: u128, ann: u128, iter: u128, end: u128): (u128, u128) {
        assert!(iter < end, ERROR_SWAP_INVALID_DERIVIATION);
        let d_prev = d;
        let result = 0;
        d = d * d * d / x / y / 4;

        let new_d = (ann * s + d * 2) * d_prev / ((ann - 1) * d_prev + 3 * d);
        if ( new_d > d_prev && new_d <= d_prev + 1) result = new_d;
        if ( new_d <= d_prev && d_prev <= new_d + 1) result = new_d;
        if ( result == 0 ) { recur_D_improved(new_d, x, y, s, ann, iter + 1, end) }
        else { (result, iter) }
    }

    /// D invariant calculation in non-overflowing integer operations iteratively
    ///
    /// A * sum(x_i) * n**n + D = A * D * n**n + D**(n+1) / (n**n * prod(x_i))
    ///
    /// Simplification:
    ///
    /// 4A (x + y) + D == 4AD + D**3 / 4xy
    ///
    /// D**3 + 4xy(4A - 1)D - 16Axy(x+y) == 0
    ///
    /// Converging solution: (Raphson method)
    ///
    ///  D[j+1] = (A * n**n * sum(x_i) - D[j]**(n+1) / (n**n prod(x_i))) / (A * n**n - 1)
    ///
    ///  D[j+1] = (4A(x + y) - D ** 3 / 4xy )/ (4A-1)
    public fun get_D_origin(x: u128, y: u128, amp: u64): u128 {
        let s = x + y;
        if ( s == 0 ) {
            s
        } else {
            let (d, ann, iter, end) = (s, (amp as u128) * 2, 0, 255);
            let (result, _iter) = recur_D_origin(d, x, y, s, ann, iter, end);
            result
        }
    }

    public fun recur_D_newton_method(d: u128, x: u128, y: u128, amp: u128, iter: u128, end: u128): (u128, u128) {
        assert!(iter < end, ERROR_SWAP_INVALID_DERIVIATION);

        // ...:   new_d =  (2A(x+y) + 2*D**3 / 4xy) * D / ((2A-1)d + 3 * D**3 / 4xy)
        // D**3 + 4xy(2A - 1)D - 8Axy(x+y) == 0
        // Correct: new_d = ( 8Axy(x+y) + 2D**3 ) / ( 3D**2 + 4xy(2A - 1))
        // Correct: new_d = ( 16Axy(x+y) + 2D**3 ) / ( 3D**2 + 4xy(4A - 1))

        // let minuend = (d*d*d + 4*x*y*(amp*4 - 1)*d - 16*amp*x*y*(x+y)) / (3*d*d + 4*x*y*(4*amp -1));
        let d1 = (8 * amp * x * y * (x + y) + 2 * d * d * d) / (3 * d * d + 4 * x * y * (2 * amp - 1));
        let minuend = d - d1;
        if (minuend <= 1) (d1, iter) else { recur_D_newton_method(d1, x, y, amp, iter + 1, end) }
    }

    public fun get_D_newton_method(x: u128, y: u128, amp: u64): u128 {
        let d0 = x + y;
        if ( d0 == 0 ) { return d0 };
        let (result, _) = recur_D_newton_method(d0, x, y, (amp as u128), 0, 100);
        result
    }

    public fun get_D(x: u128, y: u128, amp: u64): u128 {
        get_D_origin(x, y, amp)
    }

    #[test_only]
    fun time(offset_seconds: u64): u64 {
        let epoch = 1653289287000000;  // 2022-05-23 15:01:27
        epoch + offset_seconds * 1000000
    }

    #[test_only]
    fun mock_curve_params(): (u64, u64, u64, u64) {
        let initial_A = 3000000;        // 3 * (10**6)
        let future_A = 3000200;        // 3.5 * (10**6)
        let initial_A_time = time(0);
        let future_A_time = time(3600);
        (initial_A, future_A, initial_A_time, future_A_time)
    }

    #[test]
    fun test_get_D() {
        let s = get_D(100, 400, 1000);
        assert!(s==499, 10000);
    }

    #[test]
    fun test_get_D_2() {
        let s = get_D(101010, 200, 50);
        assert!(s==66112, 10000);
    }

    #[test]
    fun test_get_D_3() {
        let s = get_D(10074, 10074, 50);
        assert!(s==20148, 10000);
    }

    #[test]
    fun test_iter_loop_D() {
        let s = get_D(100, 200, 1000);
        assert!(s==299, 10000);
    }

    #[test]
    fun test_get_D4() {
        let s = get_D(100, 300, 90);
        assert!(s==399, 10000);
    }

    #[test]
    fun test_raw_A_branch_B() {
        let (ia, fa, iat, fat) = mock_curve_params();
        let timestamp = time(100);
        let f = get_A(ia, fa, iat, fat, timestamp);
        Std::Debug::print(&1999999);
        Std::Debug::print(&f);
    }

    #[test]
    fun test_raw_A_branch_A() {
        let (ia, _fa, iat, fat) = mock_curve_params();
        let fa = 2600000;
        let timestamp = time(200);
        get_A(ia, fa, iat, fat, timestamp);
    }

    #[test]
    fun test_raw_A_branch_fa_expire() {
        let (ia, _fa, iat, fat) = mock_curve_params();
        let fa = 2600000;
        let timestamp = time(11111111111200);
        get_A(ia, fa, iat, fat, timestamp);
    }

    #[test]
    #[expected_failure(abort_code = 2020)]
    public fun fail_recur_D() {
        recur_D_origin(1, 1, 1, 1, 1, 1, 1);
    }

    #[test]
    public fun test_recur_D_ok_1() {
        // Iter for 4 rounds.
        let (result1, iter_times) = recur_D_origin(32, 120, 20, 32, 1, 0, 20);
        assert!(result1 == 69, 10003);
        assert!(iter_times == 4, 10003);
        let (result2, iter_times2) = recur_D_improved(32, 120, 20, 32, 1, 0, 20);

        assert!(result2 == 68, 10003);
        assert!(iter_times2 == 4, 10003);

    }

    #[test]
    fun test_recur_D_ok_2() {
        // Iter for 8 rounds.
        let (result, _) = recur_D_origin(101210, 101010, 200, 101210, 100, 1, 10);
        assert!(result == 66112, 10000);
        let (res1, _) = recur_D_improved(101210, 101010, 200, 101210, 100, 1, 10);
//
        assert!(res1 == 66112, 10003);
        let (res2, rnd2) = recur_D_newton_method(101210, 101010, 200, 50, 1, 100);

        assert!(res2 == 66112, 10004);
        assert!(rnd2 == 5, 10004);
    }


    #[test]
    #[expected_failure(abort_code = 2020)]
    fun test_recur_D_bad() {
        // CALL STACK OVERFLOW 1024,
        let (_, _) = recur_D_origin(1101210, 1101010, 200, 1101210, 10, 1, 255);
        let (_, _) = recur_D_improved(1101210, 1101010, 200, 1101210, 10, 1, 255);
    }

    #[test]
    fun test_recur_D_newton() {
        let (res, rnd) = recur_D_newton_method(1101210, 1101010, 200, 5, 1, 255);
        assert!(res == 200888, 10000);
        assert!(rnd == 8, 10000);
        let (res, rnd) = recur_D_newton_method(11101210, 11101010, 200, 1000, 1, 255);
        // assert!(res == 5750252, 10000);
        assert!(res == 4815732, 10000);
        assert!(rnd == 6, 10000);

        let (res, rnd) = recur_D_newton_method(10002, 10000, 2, 10, 1, 255);

        assert!(res == 2319, 10000);
        assert!(rnd == 7, 10000);
    }


    #[test]
    fun test_recur_D_ok_3() {
        // Iter for 8 rounds. more realistic
        let (result, round) = recur_D_origin(101210000000, 101010000000, 200000000, 101210000000, 1, 1, 10);
        assert!(result == 20147720974, 10009);
        assert!(round == 9, 10009);

        let (res2, rnd2) = recur_D_improved(101210000000, 101010000000, 200000000, 101210000000, 1, 1, 10);
        assert!(res2 == 20147720972, 10009);
        assert!(rnd2 == 9, 10009);
    }

    #[test]
    fun test_curvature() {
        let (result, round) = recur_D_origin(3200, 2200, 1000, 3200, 160, 1, 10);
        assert!(result == 3196, 100);
        assert!(round == 2, 100);

        let (res2, rn2) = recur_D_newton_method(3200, 2200, 1000, 80, 1, 100);
        assert!(res2 == 3196 || res2 == 3198, 100);
        assert!(rn2 == 2, 100);
    }

    #[test]
    fun test_method_diff() {
        // Iter for 8 rounds.
        let (result, round) = recur_D_origin(100200, 100000, 200, 100200, 2, 1, 10);

        assert!(result == 24159, 10003);
        assert!(round == 7, 10003);

        let (res2, rnd2) = recur_D_newton_method(100200, 100000, 200, 1, 1, 100);

        assert!(res2 == 24159 || res2 == 24158, 10004);
        assert!(rnd2 == 7, 10004);
    }


    #[test]
    fun test_method_large_a() {
        // Iter for 8 rounds.
        let (result, rounds) = recur_D_origin(100200, 100000, 200, 100200, 160, 1, 10);
        assert!(result == 71769, 10003);
        assert!(rounds == 4, 10003);

        let (res2, round2) = recur_D_newton_method(100200, 100000, 200, 80, 1, 100);

        assert!(res2 == 71769 || res2 == 71768, 10004);
        assert!(round2 == 4, 10004);
    }

    fun recur_y(y: u128, b: u128, c: u128, d: u128, iter: u128, end: u128): (u128, u128) {
        assert!(iter < end, ERROR_SWAP_INVALID_DERIVIATION);

        let y_next = (y * y + c) / (2 * y + b - d);
        let difference = if (y_next > y) y_next - y else y - y_next;
        if (difference <= 1) return (y_next, iter) else { return recur_y(y_next, b, c, d, iter + 1, end) }
    }

    /// invariant
    /// y**2 + (x + D/4A - D) * y = D**3 / 16*A*x
    ///
    /// y**2 + by = c
    /// y_n_1 = (y_n**2 + c)/(2*y_n +b)
    /// invariant
    /// y**2 + (x + D/2A - D) * y = D**3 / 8*A*x
    ///
    /// y**2 + by = c
    /// y_n_1 = (y_n**2 + c)/(2*y_n +b)
    public fun get_y(x: u64, amp: u64, d: u128, ): u128 {
        assert!(x != 0, ERROR_SWAP_INVALID_AMOUNT);
        if (d == 0) { return 0 };
        let amp = (amp as u128);
        let x = (x as u128);
        let y = d;
        let b = x + (d / (2 * amp));  // - d
        let c = d * d * d / (8 * amp * x);
        let (result, _) = recur_y(y, b, c, d, 0, 100);
        result
    }


    #[test]
    fun test_y_ok() {
        let result = get_y(1, 60, 8000);
        assert!(result == 36866, 10003);
    }

    #[test]
    #[expected_failure(abort_code = 2021)]
    fun test_fail_recur_y() {
        get_y(0, 10, 10);
    }

    #[test]
    #[expected_failure(abort_code = 2020)]
    fun test_fail_get_y() {
        recur_y(10, 10, 10, 10, 6, 4);
    }

    #[test]
    fun test_get_y_branch_zero() {
        let y = get_y(10, 10, 0);
        assert!(y == 0, 1000);
    }

    #[test]
    #[expected_failure(abort_code = 2020)]
    fun test_fail_recur_D_newton() {
        recur_D_newton_method(10, 10, 10, 10, 6, 4);
    }

    #[test]
    fun test_get_D_newton_branch_zero() {
        let y = get_D_newton_method(0, 0, 10);
        assert!(y == 0, 1000);
        let y = get_D_newton_method(10, 10, 10);
        Std::Debug::print(&10000002222);
        Std::Debug::print(&y);
        assert!(y == 20, 1000);
    }


    #[test]
    fun test_get_D_origin() {
        let y = get_D_origin(0, 0, 10);
        assert!(y == 0, 1000);
        let d = get_D_origin(200, 100, 30);
        Std::Debug::print(&d);
        // assert!(d == 0, 1000);
    }

    #[test]
    #[expected_failure(abort_code = 2020)]
    fun test_fail_recur_D_improved() {
        recur_D_improved(10, 10, 10, 20, 10, 6, 4);
    }


    #[test]
    fun test_recur_D_improve() {
        let (res, rnd) = recur_D_improved(1101210, 1101010, 200, 1101210, 10, 1, 255);

        assert!(res == 200888, 10000);
        assert!(rnd == 8, 10000);
        let (res, rnd) = recur_D_improved(11101210, 11101010, 200,11101210, 2000, 1, 255);
        // assert!(res == 5750252, 10000);

        assert!(res == 4815732, 10000);
        assert!(rnd == 6, 10000);

        let (res, rnd) = recur_D_improved(10002, 10000, 2,  10002,20,  1, 255);

        assert!(res == 2319, 10000);
        assert!(rnd == 7, 10000);

    }


    #[test]
    fun test_recur_D_improve_loop_gt() {

        let (res, _rnd) = recur_D_improved(22, 12, 11,  23,2,  1, 255);
        Std::Debug::print(&res);
        // assert!(res == 2319, 10000);
        // assert!(rnd == 7, 10000);
    }

}
