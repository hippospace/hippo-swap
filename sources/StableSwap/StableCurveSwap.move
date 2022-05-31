module HippoSwap::StableCurveSwap {
    use Std::ASCII;
    use Std::Option;
    use AptosFramework::Coin;
    use AptosFramework::Timestamp;

    use HippoSwap::HippoConfig;
    use HippoSwap::StableCurveNumeral;
    use HippoSwap::Math;
    use Std::Signer;

    // Token

    struct LPToken<phantom X, phantom Y> {}

    struct LPCapability<phantom X, phantom Y> has key, store {
        mint: Coin::MintCapability<LPToken<X, Y>>,
        burn: Coin::BurnCapability<LPToken<X, Y>>,
    }

    // Swap

    struct StableCurvePoolInfo<phantom X, phantom Y> has key {
        disabled: bool,
        reserve_x: Coin::Coin<X>,
        reserve_y: Coin::Coin<Y>,
        fee_x: Coin::Coin<X>,
        fee_y: Coin::Coin<Y>,
        lp_precision: u64,
        // example: 1000000
        rate_x: u64,
        // example: 100
        rate_y: u64,
        // example: 1
        //lp_precision is the max value of decimal x and y
        fee: u128,
        admin_fee: u128,
        initial_A: u64,
        future_A: u64,
        initial_A_time: u64,
        future_A_time: u64,
    }

    const MIN_RAMP_TIME: u64 = 86400;
    const FEE_DENOMINATOR: u128 = 1000000;     // 10 ** 6


    const MAX_ADMIN_FEE: u64 = 1000000;
    const MAX_FEE: u64 = 500000;
    const MAX_A: u64 = 1000000;
    const MAX_A_CHANGE: u64 = 10;

    const ERROR_ITERATE_END: u64 = 1000;
    const ERROR_EXCEEDED: u64 = 1001;
    // 10 ** 10
    const ERROR_SWAP_INVALID_TOKEN_PAIR: u64 = 2000;
    const ERROR_SWAP_PRECONDITION: u64 = 2001;
    const ERROR_SWAP_PRIVILEGE_INSUFFICIENT: u64 = 2003;
    const ERROR_SWAP_BURN_CALC_INVALID: u64 = 2004;
    const ERROR_SWAP_ADDLIQUIDITY_INVALID: u64 = 2007;
    const ERROR_SWAP_TOKEN_NOT_EXISTS: u64 = 2008;
    const ERROR_SWAP_RAMP_TIME: u64 = 2009;
    const ERROR_SWAP_A_VALUE: u64 = 2010;
    const ERROR_SWAP_INVALID_DERIVIATION: u64 = 2020;


    // Token utilities

    fun assert_admin(signer: &signer) {
        assert!(Signer::address_of(signer) == HippoConfig::admin_address(), ERROR_SWAP_PRIVILEGE_INSUFFICIENT);
    }

    public fun initialize_coin<X, Y>(signer: &signer, name: ASCII::String, symbol: ASCII::String, decimals: u64) {
        assert_admin(signer);
        assert!(Coin::is_coin_initialized<X>(), ERROR_SWAP_INVALID_TOKEN_PAIR);
        assert!(Coin::is_coin_initialized<Y>(), ERROR_SWAP_INVALID_TOKEN_PAIR);
        let (mint_capability, burn_capability) = Coin::initialize<LPToken<X, Y>>(
            signer, name, symbol, decimals, true
        );
        move_to(signer, LPCapability<X, Y>{ mint: mint_capability, burn: burn_capability });
    }

    fun mint<X, Y>(amount: u64): Coin::Coin<LPToken<X, Y>> acquires LPCapability {
        let liquidity_cap = borrow_global<LPCapability<X, Y>>(HippoConfig::admin_address());
        let mint_token = Coin::mint<LPToken<X, Y>>(amount, &liquidity_cap.mint);
        mint_token
    }

    fun burn<X: copy + store, Y: copy + store>(to_burn: Coin::Coin<LPToken<X, Y>>,
    ) acquires LPCapability {
        let liquidity_cap = borrow_global<LPCapability<X, Y>>(HippoConfig::admin_address());
        Coin::burn<LPToken<X, Y>>(to_burn, &liquidity_cap.burn);
    }

    #[test_only]
    fun init_mock_coin<Money: store>(creator: &signer): Coin::Coin<Money> {
        use HippoSwap::MockCoin;
        MockCoin::initialize<Money>(creator, 9);
        MockCoin::mint<Money>(20)
    }

    #[test(admin = @HippoSwap, core_resource_account = @CoreResources)]
    fun mint_mock_coin(admin: &signer) acquires LPCapability {
        use HippoSwap::MockCoin;
        let decimals = 6;
        MockCoin::initialize<HippoSwap::MockCoin::WETH>(admin, decimals);
        MockCoin::initialize<HippoSwap::MockCoin::WDAI>(admin, decimals);
        initialize_coin<HippoSwap::MockCoin::WETH, HippoSwap::MockCoin::WDAI>(
            admin,
            ASCII::string(b"Curve:WETH-WDAI"),
            ASCII::string(b"WEWD"),
            decimals
        );
        let coin = mint<HippoSwap::MockCoin::WETH, HippoSwap::MockCoin::WDAI>(1000000);
        burn(coin)
    }

    // Swap utilities

    public fun get_boundary<X, Y>(): (u64, u64, u64, u64) acquires StableCurvePoolInfo {
        let pair = borrow_global<StableCurvePoolInfo<X, Y>>(HippoConfig::admin_address());
        (pair.initial_A, pair.initial_A_time, pair.future_A, pair.future_A_time)
    }

    public fun get_rates<X, Y>(): (u64, u64, u64) acquires StableCurvePoolInfo {
        let pair = borrow_global<StableCurvePoolInfo<X, Y>>(HippoConfig::admin_address());
        (pair.lp_precision, pair.rate_x, pair.rate_y)
    }

    public fun get_admin_fee<X, Y>(): u128 acquires StableCurvePoolInfo {
        borrow_global<StableCurvePoolInfo<X, Y>>(HippoConfig::admin_address()).admin_fee
    }


    public fun get_fee<X, Y>(): u128 acquires StableCurvePoolInfo {
        borrow_global<StableCurvePoolInfo<X, Y>>(HippoConfig::admin_address()).fee
    }

    public fun get_reserves<X, Y>(): (u64, u64) acquires StableCurvePoolInfo {
        let pair = borrow_global<StableCurvePoolInfo<X, Y>>(HippoConfig::admin_address());
        let x_reserve = Coin::value(&pair.reserve_x);
        let y_reserve = Coin::value(&pair.reserve_y);
        (x_reserve, y_reserve)
    }

    fun create_pool_info<X, Y>(
        lp_precision: u64,
        x_rate: u64,
        y_rate: u64,
        initial_A: u64,
        future_A: u64,
        initial_A_time: u64,
        future_A_time: u64
    ): StableCurvePoolInfo<X, Y> {
        StableCurvePoolInfo<X, Y>{
            disabled: false,
            reserve_x: Coin::zero<X>(),
            reserve_y: Coin::zero<Y>(),
            fee_x: Coin::zero<X>(),
            fee_y: Coin::zero<Y>(),
            lp_precision,
            rate_x: x_rate,
            rate_y: y_rate,
            fee: 0,
            admin_fee: 0,
            initial_A,
            future_A,
            initial_A_time,
            future_A_time,
        }
    }

    public fun initialize<X: copy + store, Y: copy + store>(
        signer: &signer, name: ASCII::String, symbol: ASCII::String,
        initial_A: u64, future_A: u64, initial_A_time: u64, future_A_time: u64
    ) {
        let (x_decimal, y_decimal) = (Coin::decimals<X>(), Coin::decimals<Y>());
        let lp_decimal = Math::max_u64(x_decimal, y_decimal);
        let lp_precision = (Math::pow(10, (lp_decimal as u8)) as u64);
        let x_rate = (Math::pow(10, ((lp_decimal - x_decimal) as u8)) as u64);
        let y_rate = (Math::pow(10, ((lp_decimal - y_decimal) as u8)) as u64);
        initialize_coin<X, Y>(signer, name, symbol, (lp_precision as u64));
        let token_pair = create_pool_info<X, Y>(
            lp_precision, x_rate, y_rate, initial_A, future_A, initial_A_time, future_A_time
        );
        move_to(signer, token_pair);
    }


    fun get_A<X, Y>(): u64 acquires StableCurvePoolInfo {
        let (a0, t0, a1, t1) = get_boundary<X, Y>();
        let block_timestamp = Timestamp::now_microseconds();
        StableCurveNumeral::get_A(t1, a1, t0, a0, block_timestamp)
    }

    fun get_xp_mem<X, Y>(reserve_x: u64, reserve_y: u64): (u64, u64) acquires StableCurvePoolInfo {
        let (_, rate_x, rate_y) = get_rates<X, Y>();
        (rate_x * reserve_x, rate_y * reserve_y)
    }

    fun get_D<X, Y>(amount_x: u64, amount_y: u64, amp: u64): u128 acquires StableCurvePoolInfo {
        let (_lp_precision, rate_x, rate_y) = get_rates<X, Y>();
        StableCurveNumeral::get_D(((rate_x * amount_x) as u128), ((rate_y * amount_y) as u128), amp)
    }

    public fun add_liquidity_direct<X, Y>(x: Coin::Coin<X>, y: Coin::Coin<Y>,
    ): (Coin::Coin<X>, Coin::Coin<Y>, Coin::Coin<LPToken<X, Y>>)
    acquires StableCurvePoolInfo, LPCapability {
        let (x_reserve, y_reserve) = get_reserves<X, Y>();
        let x_value_prev = Coin::value<X>(&x);
        let y_value_prev = Coin::value<Y>(&y);

        let amp = get_A<X, Y>();
        let d0 = get_D<X, Y>(x_reserve, y_reserve, amp);

        let token_supply = (Option::extract(&mut Coin::supply<LPToken<X, Y>>()) as u128);

        if (token_supply == 0) {
            assert!(x_value_prev > 0, ERROR_SWAP_ADDLIQUIDITY_INVALID);
            assert!(y_value_prev > 0, ERROR_SWAP_ADDLIQUIDITY_INVALID);
        };
        let (new_reserve_x, new_reserve_y) = (x_reserve + x_value_prev, y_reserve + y_value_prev);

        let d1 = get_D<X, Y>(new_reserve_x, new_reserve_y, amp);

        assert!(d1 > d0, ERROR_SWAP_INVALID_DERIVIATION);

        let mint_amount;
        if (token_supply > 0) {
            let fee = get_fee<X, Y>() * 2 / 4;
            let admin_fee = get_admin_fee<X, Y>();
            let (n_b_x, _r_b_x, fee_x) = calc_reserve_and_fees((new_reserve_x as u128), (x_reserve as u128), d0, d1, fee, admin_fee);
            let (n_b_y, _r_b_y, fee_y) = calc_reserve_and_fees((new_reserve_y as u128), (y_reserve as u128), d0, d1, fee, admin_fee);
            let d2 = get_D<X, Y>((n_b_x as u64), (n_b_y as u64), amp);
            // x --> fee (fee), reserve (admin)
            let fee_coin_x = Coin::extract(&mut x, (fee_x as u64));
            let fee_coin_y = Coin::extract(&mut y, (fee_y as u64));
            let token_pair = borrow_global_mut<StableCurvePoolInfo<X, Y>>(HippoConfig::admin_address());
            Coin::merge(&mut token_pair.reserve_x, x);
            Coin::merge(&mut token_pair.reserve_y, y);
            Coin::merge(&mut token_pair.fee_x, fee_coin_x);
            Coin::merge(&mut token_pair.fee_y, fee_coin_y);
            mint_amount = token_supply * (d2 - d0) / d0;
        } else {
            mint_amount = d1;
            let token_pair = borrow_global_mut<StableCurvePoolInfo<X, Y>>(HippoConfig::admin_address());
            Coin::merge(&mut token_pair.reserve_x, x);
            Coin::merge(&mut token_pair.reserve_y, y);
        };
        let mint_token = mint<X, Y>((mint_amount as u64));
        (Coin::zero<X>(), Coin::zero<Y>(), mint_token)
    }

    fun calc_reserve_and_fees(
        new_reserve: u128, old_reserve: u128, d0: u128, d1: u128, average_fee: u128, admin_fee: u128
    ): (u128, u128, u128) {
        let ideal_reserve = d1 * old_reserve / d0;
        let difference;
        if (ideal_reserve > new_reserve) {
            difference = ideal_reserve - new_reserve;
        } else {
            difference = new_reserve - ideal_reserve;
        };
        let fee = average_fee * difference / FEE_DENOMINATOR ;
        let real_balance = new_reserve - (fee * admin_fee / FEE_DENOMINATOR);
        let name_balance = new_reserve - fee;
        (name_balance, real_balance, fee)
    }

    public fun add_liquidity<X, Y>(sender: &signer, amount_x: u64, amount_y: u64) acquires StableCurvePoolInfo, LPCapability {
        let x_coin = Coin::withdraw<X>(sender, amount_x);
        let y_coin = Coin::withdraw<Y>(sender, amount_y);
        let (x, y, minted_lp_token) = add_liquidity_direct(x_coin, y_coin);
        let addr = Signer::address_of(sender);
        Coin::deposit(addr, x);
        Coin::deposit(addr, y);
        Coin::deposit(addr, minted_lp_token);
    }

    fun get_y<X, Y>(i: u64, dx: u64, xp: u64, yp: u64): u64 acquires StableCurvePoolInfo {
        let amp = get_A<X, Y>();
        let d = StableCurveNumeral::get_D((xp as u128), (yp as u128), amp);
        let x = if (i == 0) dx + xp else dx + yp;
        (StableCurveNumeral::get_y(x, amp, d) as u64)
    }

    public fun swap_x_to_exact_y_direct<X, Y>(coins_in: Coin::Coin<X>): (Coin::Coin<X>, Coin::Coin<X>, Coin::Coin<Y>) acquires StableCurvePoolInfo {
        let (reserve_x, reserve_y) = get_reserves<X, Y>();
        let (xp, yp) = get_xp_mem<X, Y>(reserve_x, reserve_y);
        let (_lp_precision, rate_x, _rate_y) = get_rates<X, Y>();
        let i = 0;
        let dx = Coin::value(&coins_in);
        let x = xp + dx * rate_x;
        let y = get_y<X, Y>(i, x, xp, yp);

        let amount_dy = yp - y - 1;
        let amount_dy_fee = amount_dy * (get_fee<X, Y>() as u64) / (FEE_DENOMINATOR as u64);
        let pay_amount = (amount_dy - amount_dy_fee);
        assert!(pay_amount >= 0, ERROR_EXCEEDED);

        let swap_pair = borrow_global_mut<StableCurvePoolInfo<X, Y>>(HippoConfig::admin_address());

        Coin::merge(&mut swap_pair.reserve_x, coins_in);
        let coin_dy = Coin::extract<Y>(&mut swap_pair.reserve_y, amount_dy);
        let coin_fee = Coin::extract<Y>(&mut coin_dy, amount_dy_fee);
        Coin::merge(&mut swap_pair.fee_y, coin_fee);
        (Coin::zero<X>(), Coin::zero<X>(), coin_dy)
    }


    public fun swap_y_to_exact_x_direct<X, Y>(coins_in: Coin::Coin<Y>): (Coin::Coin<Y>, Coin::Coin<X>, Coin::Coin<Y>) acquires StableCurvePoolInfo {
        let (reserve_x, reserve_y) = get_reserves<X, Y>();
        let (xp, yp) = get_xp_mem<X, Y>(reserve_x, reserve_y);
        let (_lp_precision, _rate_x, rate_y) = get_rates<X, Y>();
        let i = 1;
        let dy = Coin::value(&coins_in);
        let y = yp + dy * rate_y;
        let x = get_y<X, Y>(i, y, xp, yp);

        let amount_dx = xp - x - 1;
        let amount_dx_fee = amount_dx * (get_fee<X, Y>() as u64) / (FEE_DENOMINATOR as u64);
        let pay_amount = (amount_dx - amount_dx_fee);
        assert!(pay_amount >= 0, ERROR_EXCEEDED);

        let swap_pair = borrow_global_mut<StableCurvePoolInfo<X, Y>>(HippoConfig::admin_address());

        Coin::merge(&mut swap_pair.reserve_y, coins_in);
        let coin_dx = Coin::extract<X>(&mut swap_pair.reserve_x, amount_dx);
        let coin_fee = Coin::extract<X>(&mut coin_dx, amount_dx_fee);
        Coin::merge(&mut swap_pair.fee_x, coin_fee);
        (Coin::zero<Y>(), coin_dx, Coin::zero<Y>(),)
    }


    public fun swap_x_to_exact_y<X: key, Y: key>(sender: &signer, amount_in: u64, to: address): (u64, u64, u64) // x-in, x-out, y-out
    acquires StableCurvePoolInfo {
        let coin_x = Coin::withdraw<X>(sender, amount_in);
        let (x_remain, x_out, coin_y) = swap_x_to_exact_y_direct<X, Y>(coin_x);
        let out_amount = Coin::value(&coin_y);
        Coin::merge(&mut x_out, x_remain);
        Coin::deposit(to, x_out);
        Coin::deposit(to, coin_y);
        (amount_in, 0, out_amount)
    }

    public fun swap_y_to_exact_x<X: key, Y: key>(sender: &signer, amount_in: u64, to: address): (u64, u64, u64) // x-in, x-out, y-out
    acquires StableCurvePoolInfo {
        let coin_y = Coin::withdraw<Y>(sender, amount_in);
        let (y_remain, x_out, y_out) = swap_y_to_exact_x_direct<X, Y>(coin_y);
        let out_amount = Coin::value(&x_out);
        Coin::merge(&mut y_out, y_remain);
        Coin::deposit(to, x_out);
        Coin::deposit(to, y_out);
        (amount_in, out_amount, 0)
    }

    public fun withdraw_liquidity<X: copy + store, Y: copy + store>(to_burn: Coin::Coin<LPToken<X, Y>>): (Coin::Coin<X>, Coin::Coin<Y>) acquires StableCurvePoolInfo, LPCapability {
        let to_burn_value = Coin::value(&to_burn);
        let swap_pair = borrow_global_mut<StableCurvePoolInfo<X, Y>>(HippoConfig::admin_address());
        let reserve_x = Coin::value(&swap_pair.reserve_x);
        let reserve_y = Coin::value(&swap_pair.reserve_y);
        let total_supply = Option::extract(&mut Coin::supply<LPToken<X, Y>>());
        let x = to_burn_value * reserve_x / total_supply;
        let y = to_burn_value * reserve_y / total_supply;
        // assert!(x > 0 && y > 0, ERROR_SWAP_BURN_CALC_INVALID);
        burn<X, Y>(to_burn);
        let coin_x = Coin::extract(&mut swap_pair.reserve_x, x);
        let coin_y = Coin::extract(&mut swap_pair.reserve_y, y);
        (coin_x, coin_y)
    }

    public fun remove_liquidity<X: copy + store, Y: copy + store>(
        sender: &signer,
        liquidity: u64,
        min_amount_x: u64,
        min_amount_y: u64,
    ) acquires StableCurvePoolInfo, LPCapability {
        let coin = Coin::withdraw<LPToken<X, Y>>(sender, liquidity);
        let (coin_x, coin_y) = withdraw_liquidity<X, Y>(coin);
        assert!(Coin::value<X>(&coin_x) > min_amount_x, ERROR_SWAP_PRECONDITION);
        assert!(Coin::value<Y>(&coin_y) > min_amount_y, ERROR_SWAP_PRECONDITION);
        Coin::deposit(Signer::address_of(sender), coin_x);
        Coin::deposit(Signer::address_of(sender), coin_y);
    }

    public fun ramp_A<X, Y>(account: &signer, future_A: u64, future_time: u64)acquires StableCurvePoolInfo {
        assert_admin(account);
        let block_timestamp = Timestamp::now_microseconds();
        let (_a0, t0, _a1, _t1) = get_boundary<X, Y>();
        assert!(block_timestamp >= t0 + MIN_RAMP_TIME, ERROR_SWAP_RAMP_TIME);
        assert!(future_time >= block_timestamp + MIN_RAMP_TIME, ERROR_SWAP_RAMP_TIME);

        let initial_A = get_A<X, Y>();
        let future_A_p = future_A;

        assert!(future_A > 0 && future_A < MAX_A, ERROR_SWAP_A_VALUE);

        if (future_A_p < initial_A) {
            assert!(future_A_p * MAX_A_CHANGE >= initial_A, ERROR_SWAP_A_VALUE);
        } else {
            assert!(future_A_p <= initial_A * MAX_A_CHANGE, ERROR_SWAP_A_VALUE);
        };

        let pair = borrow_global_mut<StableCurvePoolInfo<X, Y>>(HippoConfig::admin_address());
        pair.initial_A = initial_A;
        pair.future_A = future_A_p;
        pair.initial_A_time = block_timestamp;
        pair.future_A_time = future_time;
    }

    public fun stop_ramp_A<X, Y>(account: &signer) acquires StableCurvePoolInfo {
        assert_admin(account);

        let current_A = get_A<X, Y>();
        let block_timestamp = Timestamp::now_microseconds();
        let pair = borrow_global_mut<StableCurvePoolInfo<X, Y>>(HippoConfig::admin_address());
        pair.initial_A = current_A;
        pair.future_A = current_A;
        pair.initial_A_time = block_timestamp;
        pair.future_A_time = block_timestamp;
    }

    // Tests

    #[test_only]
    fun genesis(core: &signer, vm: &signer) {
        use AptosFramework::Genesis;
        Genesis::setup(core);
        update_time(vm, time(0));
    }

    #[test_only]
    fun update_time(account: &signer, time: u64) {
        use AptosFramework::Timestamp;
        Timestamp::update_global_time(account, @0x1000010, time);
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

    #[test_only]
    fun init_lp_token(admin: &signer, core: &signer, vm: &signer) {
        use HippoSwap::MockCoin;
        genesis(core, vm);

        MockCoin::initialize<MockCoin::WETH>(admin, 6);
        MockCoin::initialize<MockCoin::WDAI>(admin, 6);
        let (ia, fa, iat, fat) = mock_curve_params();
        initialize<HippoSwap::MockCoin::WETH, HippoSwap::MockCoin::WDAI>(
            admin,
            ASCII::string(b"Curve:WETH-WDAI"),
            ASCII::string(b"WEWD"),
            ia, fa, iat, fat
        );
    }

    #[test(admin = @HippoSwap, core = @CoreResources, vm = @0)]
    fun mint_lptoken_coin(admin: &signer, core: &signer, vm: &signer) acquires StableCurvePoolInfo, LPCapability {
        use Std::Signer;
        use HippoSwap::MockCoin;
        init_lp_token(admin, core, vm);
        update_time(vm, time(200));
        let x = MockCoin::mint<MockCoin::WETH>(10000000);
        let y = MockCoin::mint<MockCoin::WDAI>(10000000);
        let (x_remain, y_remain, liquidity) = add_liquidity_direct(x, y);
        let (x, y) = withdraw_liquidity(liquidity);
        let addr = Signer::address_of(admin);
        Coin::deposit(addr, x);
        Coin::deposit(addr, y);
        Coin::deposit(addr, x_remain);
        Coin::deposit(addr, y_remain);
    }

    #[test(admin = @HippoSwap, core = @CoreResources, vm = @0)]
    #[expected_failure(abort_code = 2007)]
    public fun fail_add_liquidity(admin: &signer, core: &signer, vm: &signer) acquires StableCurvePoolInfo, LPCapability {
        use Std::Signer;
        use HippoSwap::MockCoin;
        init_lp_token(admin, core, vm);
        update_time(vm, time(200));

        let x = MockCoin::mint<MockCoin::WETH>(0);
        let y = MockCoin::mint<MockCoin::WDAI>(0);
        let (x_remain, y_remain, liquidity) = add_liquidity_direct(x, y);
        Std::Debug::print(&777788888);
        Std::Debug::print(&Coin::value(&liquidity));
        Coin::deposit(Signer::address_of(admin), liquidity);
        Coin::deposit(Signer::address_of(admin), x_remain);
        Coin::deposit(Signer::address_of(admin), y_remain)
    }

    #[test(admin = @HippoSwap)]
    #[expected_failure(abort_code = 2000)]
    public fun fail_x(admin: &signer) {
        initialize_coin<HippoSwap::MockCoin::WETH, HippoSwap::MockCoin::WDAI>(
            admin, ASCII::string(b"Curve:WETH-WDAI"), ASCII::string(b"WEWD"), 1000000);
    }

    #[test(admin = @HippoSwap)]
    #[expected_failure(abort_code = 2000)]
    public fun fail_y(admin: &signer) {
        use HippoSwap::MockCoin;
        MockCoin::initialize<HippoSwap::MockCoin::WETH>(admin, 6);
        initialize_coin<HippoSwap::MockCoin::WETH, HippoSwap::MockCoin::WDAI>(
            admin, ASCII::string(b"Curve:WETH-WDAI"), ASCII::string(b"WEWD"), 1000000);
    }

    #[test(admin = @HippoSwap, core = @CoreResources, vm = @0)]
    fun test_swap_pair_case_A(admin: &signer, core: &signer, vm: &signer) acquires StableCurvePoolInfo {
        use HippoSwap::MockCoin;
        init_lp_token(admin, core, vm);
        let swap_pair = borrow_global_mut<StableCurvePoolInfo<MockCoin::WETH, MockCoin::WDAI>>(HippoConfig::admin_address());
        update_time(vm, time(3500));
        let block_timestamp = Timestamp::now_seconds();
        swap_pair.future_A_time = block_timestamp + 2;
        swap_pair.future_A = 20;
        swap_pair.initial_A = 4;
        let k = get_A<MockCoin::WETH, MockCoin::WDAI>();
        Std::Debug::print(&k)
    }

    #[test(admin = @HippoSwap, core = @CoreResources, vm = @0)]
    fun test_swap_pair_case_B(admin: &signer, core: &signer, vm: &signer) acquires StableCurvePoolInfo {
        use HippoSwap::MockCoin;
        init_lp_token(admin, core, vm);
        let swap_pair = borrow_global_mut<StableCurvePoolInfo<MockCoin::WETH, MockCoin::WDAI>>(HippoConfig::admin_address());
        update_time(vm, time(10000));
        let block_timestamp = Timestamp::now_seconds();
        swap_pair.future_A_time = block_timestamp + 200;
        swap_pair.future_A = 4;
        swap_pair.initial_A = 20;
        let k = get_A<MockCoin::WETH, MockCoin::WDAI>();
        Std::Debug::print(&k);
    }


    #[test(admin = @HippoSwap, core = @CoreResources, vm = @0, trader = @0xFFFFFF01, )]
    fun mock_add_liquidity(admin: &signer, core: &signer, vm: &signer, trader: &signer) acquires StableCurvePoolInfo, LPCapability {
        use Std::Signer;
        use HippoSwap::MockCoin;
        init_lp_token(admin, core, vm);
        update_time(vm, time(200));
        let trader_addr = Signer::address_of(trader);
        Coin::register_internal<MockCoin::WETH>(trader);
        Coin::register_internal<MockCoin::WDAI>(trader);
        Coin::register_internal<LPToken<MockCoin::WETH, MockCoin::WDAI>>(trader);
        let x = MockCoin::mint<MockCoin::WETH>(100000000);
        let y = MockCoin::mint<MockCoin::WDAI>(100000000);
        Coin::deposit(trader_addr, x);
        Coin::deposit(trader_addr, y);

        add_liquidity<MockCoin::WETH, MockCoin::WDAI>(trader, 7000000, 2000000);
        Std::Debug::print(&Coin::balance<LPToken<MockCoin::WETH, MockCoin::WDAI>>(trader_addr));
        add_liquidity<MockCoin::WETH, MockCoin::WDAI>(trader, 21000000, 38200000);
        Std::Debug::print(&Coin::balance<LPToken<MockCoin::WETH, MockCoin::WDAI>>(trader_addr));
    }

    #[test(admin = @HippoSwap, core = @CoreResources, vm = @0)]
    fun test_exchange_cion(admin: &signer, core: &signer, vm: &signer) acquires StableCurvePoolInfo, LPCapability {
        use Std::Signer;
        use HippoSwap::MockCoin;
        let addr = Signer::address_of(admin);
        init_lp_token(admin, core, vm);
        update_time(vm, time(200));
        let x = MockCoin::mint<MockCoin::WETH>(2000000);
        let y = MockCoin::mint<MockCoin::WDAI>(10000000);
        let (left_x, left_y, liquidity) = add_liquidity_direct(x, y);
        let a = MockCoin::mint<MockCoin::WETH>(2000000);
        let (x_remain, x_out, b) = swap_x_to_exact_y_direct<MockCoin::WETH, MockCoin::WDAI>(a);
        Coin::register_internal<LPToken<MockCoin::WETH, MockCoin::WDAI>>(admin);
        Coin::deposit(addr, liquidity);
        Coin::deposit(addr, x_remain);
        Coin::deposit(addr, x_out);
        Coin::deposit(addr, b);
        Coin::deposit(addr, left_x);
        Coin::deposit(addr, left_y);
    }
}
