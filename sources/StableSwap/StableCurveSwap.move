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

    struct LPToken<phantom X, phantom Y> has key, store, copy {}

    struct LPCapability<phantom X, phantom Y> has key, store {
        mint: Coin::MintCapability<LPToken<X, Y>>,
        burn: Coin::BurnCapability<LPToken<X, Y>>,
    }

    // Swap

    struct SwapPair<phantom X, phantom Y> has key, store {
        x_reserve: Coin::Coin<X>,
        y_reserve: Coin::Coin<Y>,
        lp_precision: u64,
        // example: 1000000
        x_rate: u64,
        // example: 100
        y_rate: u64,
        // example: 1
        //lp_precision is the max value of decimal x and y
        fee: u128,
        admin_fee: u128,
        initial_A: u64,
        future_A: u64,
        initial_A_time: u64,
        future_A_time: u64,
    }

    const A_PRECISION: u128 = 100;
    const FEE_DENOMINATOR: u128 = 10000000000;
    // 10 ** 10
    const ERROR_SWAP_INVALID_TOKEN_PAIR: u64 = 2000;
    const ERROR_SWAP_BURN_CALC_INVALID: u64 = 2004;
    const ERROR_SWAP_ADDLIQUIDITY_INVALID: u64 = 2007;
    const ERROR_SWAP_TOKEN_NOT_EXISTS: u64 = 2008;
    const ERROR_SWAP_INVALID_DERIVIATION: u64 = 2020;

    // Token utilities

    public fun initialize_coin<X, Y>(signer: &signer, name: ASCII::String, symbol: ASCII::String, decimals: u64) {
        assert!(Coin::is_coin_initialized<X>(), ERROR_SWAP_INVALID_TOKEN_PAIR);
        assert!(Coin::is_coin_initialized<Y>(), ERROR_SWAP_INVALID_TOKEN_PAIR);
        let (mint_capability, burn_capability) = Coin::initialize<LPToken<X, Y>>(
            signer, name, symbol, decimals, true
        );
        move_to(signer, LPCapability{ mint: mint_capability, burn: burn_capability });
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

    public fun get_initial_A<X, Y>(): u64 acquires SwapPair {
        borrow_global<SwapPair<X, Y>>(HippoConfig::admin_address()).initial_A
    }

    public fun get_initial_A_time<X, Y>(): u64 acquires SwapPair {
        borrow_global<SwapPair<X, Y>>(HippoConfig::admin_address()).initial_A_time
    }

    public fun get_future_A_time<X, Y>(): u64 acquires SwapPair {
        borrow_global<SwapPair<X, Y>>(HippoConfig::admin_address()).future_A_time
    }

    public fun get_future_A<X, Y>(): u64 acquires SwapPair {
        borrow_global<SwapPair<X, Y>>(HippoConfig::admin_address()).future_A
    }

    public fun get_rates<X, Y>(): (u64, u64, u64) acquires SwapPair {
        let pair = borrow_global<SwapPair<X, Y>>(HippoConfig::admin_address());
        (pair.lp_precision, pair.x_rate, pair.y_rate)
    }

    public fun get_admin_fee<X, Y>(): u128 acquires SwapPair {
        borrow_global<SwapPair<X, Y>>(HippoConfig::admin_address()).admin_fee
    }


    public fun get_fee<X, Y>(): u128 acquires SwapPair {
        borrow_global<SwapPair<X, Y>>(HippoConfig::admin_address()).fee
    }

    public fun get_reserves<X: copy + store, Y: copy + store>(): (u64, u64) acquires SwapPair {
        let pair = borrow_global<SwapPair<X, Y>>(HippoConfig::admin_address());
        let x_reserve = Coin::value(&pair.x_reserve);
        let y_reserve = Coin::value(&pair.y_reserve);
        (x_reserve, y_reserve)
    }

    fun make_swap_pair<X: copy + store, Y: copy + store>(
        lp_precision: u64,
        x_rate: u64,
        y_rate: u64,
        initial_A: u64,
        future_A: u64,
        initial_A_time: u64,
        future_A_time: u64
    ): SwapPair<X, Y> {
        SwapPair<X, Y>{
            x_reserve: Coin::zero<X>(),
            y_reserve: Coin::zero<Y>(),
            lp_precision,
            x_rate,
            y_rate,
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
        let token_pair = make_swap_pair<X, Y>(
            lp_precision, x_rate, y_rate, initial_A, future_A, initial_A_time, future_A_time
        );
        move_to(signer, token_pair);
    }


    fun get_raw_A<X, Y>(): u64 acquires SwapPair {
        let t1 = get_future_A_time<X, Y>();
        let a1 = get_future_A<X, Y>();
        let block_timestamp = Timestamp::now_microseconds();
        let a0 = get_initial_A<X, Y>();
        let t0 = get_initial_A_time<X, Y>();
        StableCurveNumeral::raw_A(t1, a1, t0, a0, block_timestamp)
    }

    fun get_D_mem<X, Y>(x_reserve: u64, y_reserve: u64, amp: u64): u128 acquires SwapPair {
        let (_lp_precision, rate_x, rate_y) = get_rates<X, Y>();
        StableCurveNumeral::get_D(((rate_x * x_reserve) as u128), ((rate_y * y_reserve) as u128), amp)
    }

    public fun deposit_liquidity<X: copy + store, Y: copy + store>(x: Coin::Coin<X>, y: Coin::Coin<Y>,
    ): Coin::Coin<LPToken<X, Y>> acquires SwapPair, LPCapability {
        let (x_reserve, y_reserve) = get_reserves<X, Y>();
        let x_value_prev = Coin::value<X>(&x);
        let y_value_prev = Coin::value<Y>(&y);

        let amp = get_raw_A<X, Y>();
        let d0 = get_D_mem<X, Y>(x_reserve, y_reserve, amp);

        let token_supply = (Option::extract(&mut Coin::supply<LPToken<X, Y>>()) as u128);

        if (token_supply == 0) {
            assert!(x_value_prev > 0, ERROR_SWAP_ADDLIQUIDITY_INVALID);
            assert!(y_value_prev > 0, ERROR_SWAP_ADDLIQUIDITY_INVALID);
        };
        let (new_reserve_x, new_reserve_y) = (x_reserve + x_value_prev, y_reserve + y_value_prev);

        let d1 = get_D_mem<X, Y>(new_reserve_x, new_reserve_y, amp);

        assert!(d1 > d0, ERROR_SWAP_INVALID_DERIVIATION);

        let mint_amount;
        if (token_supply > 0) {
            let fee = get_fee<X, Y>() * 2 / 4;
            let admin_fee = get_admin_fee<X, Y>();
            let (n_b_x, _r_b_x, _fee_x) = calc_reserve_and_fees((new_reserve_x as u128), (x_reserve as u128), d0, d1, fee, admin_fee);
            let (n_b_y, _r_b_y, _fee_y) = calc_reserve_and_fees((new_reserve_y as u128), (y_reserve as u128), d0, d1, fee, admin_fee);
            let d2 = get_D_mem<X, Y>((n_b_x as u64), (n_b_y as u64), amp);
            // x --> fee (fee), reserve (admin)
            // let fee_coin_x = Coin::extract(&mut x, (fee_x as u64));
            // let fee_coin_y = Coin::extract(&mut y, (fee_y as u64));
            let token_pair = borrow_global_mut<SwapPair<X, Y>>(HippoConfig::admin_address());
            Coin::merge(&mut token_pair.x_reserve, x);
            Coin::merge(&mut token_pair.y_reserve, y);
            // Coin::deposit(@HippoSwapFee, fee_coin_x);
            // Coin::deposit(@HippoSwapFee, fee_coin_y);
            mint_amount = token_supply * (d2 - d0) / d0;
        } else {
            mint_amount = d1;
            let token_pair = borrow_global_mut<SwapPair<X, Y>>(HippoConfig::admin_address());
            Coin::merge(&mut token_pair.x_reserve, x);
            Coin::merge(&mut token_pair.y_reserve, y);
        };
        let mint_token = mint<X, Y>((mint_amount as u64));
        mint_token
    }

    fun calc_reserve_and_fees(
        new_reserve: u128, old_reserve: u128, d0: u128, d1: u128, aver_fee: u128, admin_fee: u128
    ): (u128, u128, u128) {
        let ideal_reserve = d1 * old_reserve / d0;
        let difference;
        if (ideal_reserve > new_reserve) {
            difference = ideal_reserve - new_reserve;
        } else {
            difference = new_reserve - ideal_reserve;
        };
        let fee = aver_fee * difference / FEE_DENOMINATOR ;
        let real_balance = new_reserve - (fee * admin_fee / FEE_DENOMINATOR);
        let name_balance = new_reserve - fee;
        (name_balance, real_balance, fee)
    }

    public fun add_liquidity<X: copy + store, Y: copy + store>(account: &signer, x_amount: u64, y_amount: u64) acquires SwapPair, LPCapability {
        let x_coin = Coin::withdraw<X>(account, x_amount);
        let y_coin = Coin::withdraw<Y>(account, y_amount);
        let minted_lp_token = deposit_liquidity(x_coin, y_coin);
        Coin::deposit(Signer::address_of(account), minted_lp_token);
    }

    public fun remove_liquidity<X: copy + store, Y: copy + store>(to_burn: Coin::Coin<LPToken<X, Y>>,
    ): (Coin::Coin<X>, Coin::Coin<Y>) acquires SwapPair, LPCapability {
        let to_burn_value = Coin::value(&to_burn);
        let swap_pair = borrow_global_mut<SwapPair<X, Y>>(HippoConfig::admin_address());
        let x_reserve = Coin::value(&swap_pair.x_reserve);
        let y_reserve = Coin::value(&swap_pair.y_reserve);
        let total_supply = Option::extract(&mut Coin::supply<LPToken<X, Y>>());
        // TODO: Implement the algorithm   !!! Unsafe current
        let x = to_burn_value * x_reserve / total_supply;
        let y = to_burn_value * y_reserve / total_supply;
        // assert!(x > 0 && y > 0, ERROR_SWAP_BURN_CALC_INVALID);
        burn<X, Y>(to_burn);
        let x_coin = Coin::extract(&mut swap_pair.x_reserve, x);
        let y_coin = Coin::extract(&mut swap_pair.y_reserve, y);
        update_oracle<X, Y>(x_reserve, y_reserve);
        (x_coin, y_coin)
    }

    fun update_oracle<X: copy + store, Y: copy + store>(x_reserve: u64, y_reserve: u64, ) acquires SwapPair {
        let token_pair = borrow_global_mut<SwapPair<X, Y>>(HippoConfig::admin_address());
        // TODO: Not implemented.
        token_pair.future_A = x_reserve * y_reserve ;
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
    fun mint_lptoken_coin(admin: &signer, core: &signer, vm: &signer) acquires SwapPair, LPCapability {
        use Std::Signer;
        use HippoSwap::MockCoin;
        init_lp_token(admin, core, vm);
        update_time(vm, time(200));
        let x = MockCoin::mint<MockCoin::WETH>(10000000);
        let y = MockCoin::mint<MockCoin::WDAI>(10000000);
        let liquidity = deposit_liquidity(x, y);
        let (x, y) = remove_liquidity(liquidity);
        Coin::deposit(Signer::address_of(admin), x);
        Coin::deposit(Signer::address_of(admin), y);
    }

    #[test(admin = @HippoSwap, core = @CoreResources, vm = @0)]
    #[expected_failure(abort_code = 2007)]
    public fun fail_add_liquidity(admin: &signer, core: &signer, vm: &signer) acquires SwapPair, LPCapability {
        use Std::Signer;
        use HippoSwap::MockCoin;
        init_lp_token(admin, core, vm);
        update_time(vm, time(200));

        let x = MockCoin::mint<MockCoin::WETH>(0);
        let y = MockCoin::mint<MockCoin::WDAI>(0);
        let liquidity = deposit_liquidity(x, y);
        Std::Debug::print(&777788888);
        Std::Debug::print(&Coin::value(&liquidity));
        Coin::deposit(Signer::address_of(admin), liquidity)
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
    fun test_swap_pair_case_A(admin: &signer, core: &signer, vm: &signer) acquires SwapPair {
        use HippoSwap::MockCoin;
        init_lp_token(admin, core, vm);
        let swap_pair = borrow_global_mut<SwapPair<MockCoin::WETH, MockCoin::WDAI>>(HippoConfig::admin_address());
        update_time(vm, time(3500));
        let block_timestamp = Timestamp::now_seconds();
        swap_pair.future_A_time = block_timestamp + 2;
        swap_pair.future_A = 20;
        swap_pair.initial_A = 4;
        let k = get_raw_A<MockCoin::WETH, MockCoin::WDAI>();
        Std::Debug::print(&k)
    }

    #[test(admin = @HippoSwap, core = @CoreResources, vm = @0)]
    fun test_swap_pair_case_B(admin: &signer, core: &signer, vm: &signer) acquires SwapPair {
        use HippoSwap::MockCoin;
        init_lp_token(admin, core, vm);
        let swap_pair = borrow_global_mut<SwapPair<MockCoin::WETH, MockCoin::WDAI>>(HippoConfig::admin_address());
        update_time(vm, time(10000));
        let block_timestamp = Timestamp::now_seconds();
        swap_pair.future_A_time = block_timestamp + 200;
        swap_pair.future_A = 4;
        swap_pair.initial_A = 20;
        let k = get_raw_A<MockCoin::WETH, MockCoin::WDAI>();
        Std::Debug::print(&k);
    }


    #[test(admin = @HippoSwap, core = @CoreResources, vm = @0, trader = @0xFFFFFF01, )]
    fun mock_add_liquidity(admin: &signer, core: &signer, vm: &signer, trader: &signer) acquires SwapPair, LPCapability {
        use Std::Signer;
        use HippoSwap::MockCoin;
        init_lp_token(admin, core, vm);
        update_time(vm, time(200));
        Coin::register_internal<MockCoin::WETH>(trader);
        Coin::register_internal<MockCoin::WDAI>(trader);
        Coin::register_internal<LPToken<MockCoin::WETH, MockCoin::WDAI>>(trader);
        let x = MockCoin::mint<MockCoin::WETH>(100000000);
        let y = MockCoin::mint<MockCoin::WDAI>(100000000);
        Coin::deposit(Signer::address_of(trader), x);
        Coin::deposit(Signer::address_of(trader), y);
        Std::Debug::print(&987654321);
        add_liquidity<MockCoin::WETH, MockCoin::WDAI>(trader, 7000000, 2000000);
        Std::Debug::print(&Coin::balance<LPToken<MockCoin::WETH, MockCoin::WDAI>>(Signer::address_of(trader)));
        add_liquidity<MockCoin::WETH, MockCoin::WDAI>(trader, 21000000, 38200000);
        Std::Debug::print(&Coin::balance<LPToken<MockCoin::WETH, MockCoin::WDAI>>(Signer::address_of(trader)));
    }
}
