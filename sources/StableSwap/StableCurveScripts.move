module HippoSwap::StableCurveScripts {
    use Std::ASCII;
    use AptosFramework::Timestamp;
    use HippoSwap::StableCurveSwap;
    use Std::Signer;
    use TokenRegistry::TokenRegistry;
    use HippoSwap::MockDeploy;
    use HippoSwap::MockCoin;
    use AptosFramework::Coin;
    use HippoSwap::Math;

    const MICRO_CONVERSION_FACTOR: u64 = 1000000;

    const E_SWAP_ONLY_ONE_IN_ALLOWED: u64 = 0;
    const E_SWAP_ONLY_ONE_OUT_ALLOWED: u64 = 1;
    const E_SWAP_NONZERO_INPUT_REQUIRED: u64 = 2;
    const E_OUTPUT_LESS_THAN_MIN: u64 = 3;
    const E_TOKEN_REGISTRY_NOT_INITIALIZED: u64 = 4;
    const E_TOKEN_X_NOT_REGISTERED: u64 = 5;
    const E_TOKEN_Y_NOT_REGISTERED: u64 = 6;
    const E_LP_TOKEN_ALREADY_REGISTERED:u64 = 7;

    public fun create_new_pool<X, Y>(
        sender: &signer,
        lp_name: vector<u8>,
        lp_symbol: vector<u8>,
        lp_description: vector<u8>,
        lp_logo_url: vector<u8>,
        lp_project_url: vector<u8>,
        fee: u64,
        admin_fee: u64
    ) {

        let admin_addr = Signer::address_of(sender);
        assert!(TokenRegistry::is_registry_initialized(admin_addr), E_TOKEN_REGISTRY_NOT_INITIALIZED);
        assert!(TokenRegistry::has_token<X>(admin_addr), E_TOKEN_X_NOT_REGISTERED);
        assert!(TokenRegistry::has_token<Y>(admin_addr), E_TOKEN_Y_NOT_REGISTERED);
        assert!(!TokenRegistry::has_token<StableCurveSwap::LPToken<X,Y>>(admin_addr), E_LP_TOKEN_ALREADY_REGISTERED);
        assert!(!TokenRegistry::has_token<StableCurveSwap::LPToken<Y,X>>(admin_addr), E_LP_TOKEN_ALREADY_REGISTERED);

        let block_timestamp = Timestamp::now_microseconds();
        let future_time = block_timestamp + 24 * 3600 * MICRO_CONVERSION_FACTOR;

        let decimals = Math::max((Coin::decimals<X>() as u128), (Coin::decimals<Y>() as u128));
        let decimals = (decimals as u64);

        StableCurveSwap::initialize<X, Y>(
            sender,
            ASCII::string(lp_name),
            ASCII::string(lp_symbol),
            decimals,
            60,
            80,
            block_timestamp,
            future_time,
            fee, admin_fee
        );

        // register LP token to registry
        TokenRegistry::add_token<StableCurveSwap::LPToken<X,Y>>(
            sender,
            lp_name,
            lp_symbol,
            lp_description,
            8,
            lp_logo_url,
            lp_project_url,
        );
    }

    public(script) fun add_liquidity<X, Y>(sender: &signer, amount_x: u64, amount_y: u64) {
        StableCurveSwap::add_liquidity<X, Y>(sender, amount_x, amount_y);
    }

    public(script) fun remove_liquidity<X, Y>(sender: &signer, liquidity: u64, min_amount_x: u64, min_amount_y: u64,
    ) {
        StableCurveSwap::remove_liquidity<X, Y>(sender, liquidity, min_amount_x, min_amount_y);
    }

    public(script) fun swap_script<X, Y>(
        sender: &signer,
        x_in: u64,
        y_in: u64,
        x_min_out: u64,
        y_min_out: u64,
    ) {
        let cond_a = (x_in > 0 && y_in > 0);
        let cond_b = (x_in == 0 && y_in == 0);
        let cond_c = (x_min_out > 0 && y_min_out > 0);
        assert!(!(cond_a || cond_b), E_SWAP_ONLY_ONE_IN_ALLOWED);
        assert!(!cond_c, E_SWAP_ONLY_ONE_OUT_ALLOWED);
        let addr = Signer::address_of(sender);
        if (x_in > 0) {
            let (_, _, out_amount) = StableCurveSwap::swap_x_to_exact_y<X, Y>(sender, x_in, addr);
            assert!(out_amount > y_min_out, E_OUTPUT_LESS_THAN_MIN);
        }  else {
            let (_, out_amount, _) = StableCurveSwap::swap_y_to_exact_x<X, Y>(sender, y_in, addr);
            assert!(out_amount > x_min_out, E_OUTPUT_LESS_THAN_MIN);
        }
    }

    fun mock_create_pair_and_add_liquidity<X, Y>(
        admin: &signer,
        symbol: vector<u8>,
        fee: u64,
        admin_fee: u64,
        left_amt: u64,
        right_amt: u64,
        lp_amt: u64,
    ) {
        let name = ASCII::string(symbol);
        let (initial_A, future_A) = (60, 100);
        let initial_A_time = Timestamp::now_microseconds();
        let future_A_time = initial_A_time + 24 * 3600 * MICRO_CONVERSION_FACTOR;
        // Std::Debug::print(&199928828);
        // It's weird that the coverage does not mark the if branch.
        // Find the reason later from the compiler part of the aptos-core repo.
        let decimals = Math::max((Coin::decimals<X>() as u128), (Coin::decimals<Y>() as u128));
        let decimals = (decimals as u64);
        StableCurveSwap::initialize<X, Y>(
            admin, name, name, decimals, initial_A, future_A, initial_A_time, future_A_time, fee, admin_fee
        );

        TokenRegistry::add_token<StableCurveSwap::LPToken<X,Y>>(
            admin,
            symbol,
            symbol,
            symbol,
            (decimals as u8),
            b"",
            b"",
        );
        let some_x = MockCoin::mint<X>(left_amt);
        let some_y = MockCoin::mint<Y>(right_amt);

        let (unused_x, unused_y, some_lp) = StableCurveSwap::add_liquidity_direct(some_x, some_y);

        assert!(Coin::value(&some_lp) == lp_amt, 5);

        MockCoin::burn(unused_x);
        MockCoin::burn(unused_y);
        Coin::deposit(Signer::address_of(admin), some_lp);
    }

    // local validator deployment
    fun mock_deploy(admin: &signer) {
        /*
        1. initialize registry
        2. initialize coins (and add them to registry)
        3. create token pairs
        4. adds liquidity
        */
        let admin_addr = Signer::address_of(admin);
        // 1
        if (!TokenRegistry::is_registry_initialized(admin_addr)) {
            // Std::Debug::print(&299999919999);
            // It's weird that the coverage does not mark the if branch.
            // Find the reason later from the compiler part of the aptos-core repo.
            TokenRegistry::initialize(admin);
        };
        // 2

        MockDeploy::init_coin_and_create_store<MockCoin::WUSDC>(admin, b"USDC", b"USDC", 8);
        MockDeploy::init_coin_and_create_store<MockCoin::WUSDT>(admin, b"USDT", b"USDT", 8);
        MockDeploy::init_coin_and_create_store<MockCoin::WDAI>(admin, b"DAI", b"DAI", 8);
        // 3
        let (fee, admin_fee) = (3000, 200000);
        let coin_amt = 1000000000;
        mock_create_pair_and_add_liquidity<MockCoin::WUSDC, MockCoin::WUSDT>(
            admin,
            b"USDC-USDT-CURVE-LP",
            fee, admin_fee,
            coin_amt * 100,
            coin_amt * 100,
            200000000000
        );
        mock_create_pair_and_add_liquidity<MockCoin::WUSDC, MockCoin::WDAI>(
            admin,
            b"USDC-DAI-CURVE-LP",
            fee, admin_fee,
            coin_amt * 100,
            coin_amt * 100,
            200000000000
        );
    }

    public(script) fun mock_deploy_script(admin: &signer) {
        mock_deploy(admin);
    }


    #[test_only]
    public(script) fun start_up(admin: &signer, user: &signer, core: &signer) {
        use AptosFramework::Coin;
        use HippoSwap::MockCoin;
        Timestamp::set_time_has_started_for_testing(core);
        MockDeploy::init_registry(admin);
        MockDeploy::init_coin_and_create_store<MockCoin::WUSDT>(
            admin,
            b"USDT",
            b"USDT",
            6,
        );
        MockDeploy::init_coin_and_create_store<MockCoin::WDAI>(
            admin,
            b"DAI",
            b"DAI",
            6,
        );
        create_new_pool<MockCoin::WUSDT, MockCoin::WDAI>(
            admin,
            b"Curve:WUSDT-WDAI",
            b"WUWD",
            b"",
            b"",
            b"",
            3000, // 0.3 %
            200000, // 20 % from lp_fee -> 0.06 %
        );
        let x = MockCoin::mint<MockCoin::WUSDT>(100000000);
        let y = MockCoin::mint<MockCoin::WDAI>(100000000);
        let trader_addr = Signer::address_of(user);
        Coin::register_internal<MockCoin::WUSDT>(user);
        Coin::register_internal<MockCoin::WDAI>(user);
        Coin::register_internal<StableCurveSwap::LPToken<MockCoin::WUSDT, MockCoin::WDAI>>(user);
        Coin::deposit(trader_addr, x);
        Coin::deposit(trader_addr, y);
    }

    #[test(admin = @HippoSwap, user = @0x1234567, core = @0xa550c18)]
    public(script) fun test_scripts(admin: &signer, user: &signer, core: &signer) {
        use HippoSwap::MockCoin;
        start_up(admin, user, core);
        add_liquidity<MockCoin::WUSDT, MockCoin::WDAI>(user, 10000000, 20000000);
        swap_script<MockCoin::WUSDT, MockCoin::WDAI>(user, 2000000, 0, 0, 100);
        swap_script<MockCoin::WUSDT, MockCoin::WDAI>(user, 0, 2000000, 110, 0);
        remove_liquidity<MockCoin::WUSDT, MockCoin::WDAI>(user, 400000, 100, 100);
    }

    #[test(admin = @HippoSwap, user = @0x1234567, core = @0xa550c18)]
    #[expected_failure(abort_code = 0)]
    public(script) fun test_failx(admin: &signer, user: &signer, core: &signer) {
        use HippoSwap::MockCoin;
        start_up(admin, user, core);
        add_liquidity<MockCoin::WUSDT, MockCoin::WDAI>(user, 10000000, 20000000);
        swap_script<MockCoin::WUSDT, MockCoin::WDAI>(user, 0, 0, 0, 100);
    }

    #[test(admin = @HippoSwap, user = @0x1234567, core = @0xa550c18)]
    #[expected_failure(abort_code = 1)]
    public(script) fun test_faily(admin: &signer, user: &signer, core: &signer) {
        use HippoSwap::MockCoin;
        start_up(admin, user, core);
        add_liquidity<MockCoin::WUSDT, MockCoin::WDAI>(user, 10000000, 20000000);
        swap_script<MockCoin::WUSDT, MockCoin::WDAI>(user, 120, 0, 10, 10);
    }

    #[test(admin = @HippoSwap, user = @0x1234567, core = @0xa550c18)]
    #[expected_failure(abort_code = 3)]
    public(script) fun test_fail_output_less_x(admin: &signer, user: &signer, core: &signer) {
        use HippoSwap::MockCoin;
        start_up(admin, user, core);
        add_liquidity<MockCoin::WUSDT, MockCoin::WDAI>(user, 20000000, 20000000);
        swap_script<MockCoin::WUSDT, MockCoin::WDAI>(user, 1, 0, 0, 100000000000);
    }

    #[test(admin = @HippoSwap, user = @0x1234567, core = @0xa550c18)]
    #[expected_failure(abort_code = 3)]
    public(script) fun test_fail_output_less_y(admin: &signer, user: &signer, core: &signer) {
        use HippoSwap::MockCoin;
        start_up(admin, user, core);
        add_liquidity<MockCoin::WUSDT, MockCoin::WDAI>(user, 20000000, 20000000);
        swap_script<MockCoin::WUSDT, MockCoin::WDAI>(user, 0, 1, 10000000000, 0);
    }

    #[test(admin = @HippoSwap, user = @0x1234567, core = @0xa550c18)]
    public(script) fun test_mock_deploy(admin: &signer, core: &signer) {
        Timestamp::set_time_has_started_for_testing(core);
        mock_deploy_script(admin);
    }

    #[test(admin = @HippoSwap, user = @0x1234567, core = @0xa550c18)]
    #[expected_failure(abort_code = 5)]
    public(script) fun fail_lp_amt(admin: &signer, core: &signer) {
        Timestamp::set_time_has_started_for_testing(core);
        mock_deploy_script(admin);
        let btc_amt = 1000000000;
        let (fee, admin_fee) = (3000, 200000);
        MockDeploy::init_coin_and_create_store<MockCoin::WDAI>(admin, b"Dai", b"DAI", 8);
        Std::Debug::print(&110000000);
        mock_create_pair_and_add_liquidity<MockCoin::WUSDT, MockCoin::WDAI>(
            admin,
            b"USDT-DAI-LP",
            fee, admin_fee,
            btc_amt,
            btc_amt * 10000,
            32001352823
        )
    }


    #[test_only]
    public fun test_data_set_init_coins(admin: &signer, core: &signer) {
        Timestamp::set_time_has_started_for_testing(core);
        let admin_addr = Signer::address_of(admin);
        if (!TokenRegistry::is_registry_initialized(admin_addr)) {
            TokenRegistry::initialize(admin);
        };
        MockDeploy::init_coin_and_create_store<MockCoin::WUSDC>(admin, b"USDC", b"USDC", 8);
        MockDeploy::init_coin_and_create_store<MockCoin::WUSDT>(admin, b"USDT", b"USDT", 8);
        assert!(Coin::decimals<MockCoin::WUSDC>() == 8, 1);
        assert!(Coin::decimals<MockCoin::WUSDT>() == 8, 1);
    }

    #[test_only]
    public fun assert_launch_lq(admin: &signer, core: &signer, amt_x: u64, amt_y: u64, lp_predict: u64) {
        test_data_set_init_coins(admin, core);
        let (fee, admin_fee) = (3000, 200000);
        // the A value was initialed with 60.
        mock_create_pair_and_add_liquidity<MockCoin::WUSDC, MockCoin::WUSDT>(
            admin, b"USDC-USDT-LP", fee, admin_fee, amt_x, amt_y, lp_predict
        );
    }

    #[test(admin = @HippoSwap, user = @0x1234567, core = @0xa550c18)]
    public fun test_data_set_validate_basic(admin: &signer, core: &signer) {
        test_data_set_init_coins(admin, core);
        let usdc_amt = 500000000;
        let usdt_amt = 500000000;
        let (fee, admin_fee) = (3000, 200000);
        // Init with (5, 5) price unit of (x, y), which is the ideal balance and mint lp_token of 10 units.
        // Fee-free for the first investment.
        mock_create_pair_and_add_liquidity<MockCoin::WUSDC, MockCoin::WUSDT>(
            admin, b"USDC-USDT-LP", fee, admin_fee, usdc_amt, usdt_amt, 1000000000
        );
        let (_, _, _, _, _, lp_precision, multiplier_x, multiplier_y, _, _,
            _, _, _, _) = StableCurveSwap::get_pool_info<MockCoin::WUSDC, MockCoin::WUSDT>();

        assert!(lp_precision == 100000000, 2);  // 10 ** 8 , which is equal to the larger value between x and y.
        assert!(multiplier_x == 1, 2);                // the scaling factor of x and y is 1 because they share the same decimals.
        assert!(multiplier_y == 1, 2);
        StableCurveSwap::remove_liquidity<MockCoin::WUSDC, MockCoin::WUSDT>(admin, 100000000, 100000, 100000);
        let admin_addr = Signer::address_of(admin);
        let balance_x = Coin::balance<MockCoin::WUSDC>(admin_addr);
        let balance_y = Coin::balance<MockCoin::WUSDT>(admin_addr);
        assert!(balance_x == 50000000, 3);
        assert!(balance_y == 50000000, 3);
    }

    // Let's make initial value of x and y 10 times of the former test. We'll get lp_token of the corresponding factor.
    #[test(admin = @HippoSwap, user = @0x1234567, core = @0xa550c18)]
    public fun test_data_set_validate_scale(admin: &signer, core: &signer) {
        assert_launch_lq(admin, core, 5000000000, 5000000000, 10000000000)
    }


    #[test(admin = @HippoSwap, user = @0x1234567, core = @0xa550c18)]
    #[expected_failure]             //  ARITHMETIC_ERROR:  let new_d = (ann * s + d_p * 2) __*__ d / ((ann - 1) * d + 3 * d_p)
    public fun test_data_set_max_level(admin: &signer, core: &signer) {
        test_data_set_init_coins(admin, core);
        let usdc_amt = 5 * 100000000 * 10000000000;
        // 10 ** 10 of 8 decimal coin will cause the digits overflow from the optimized get_D_origin method.
        // The capacity will be much lower if using the get_D_improved or get_D_newton_method which are mathematically equivalent.
        let usdt_amt = 5 * 100000000 * 10000000000;
        let (fee, admin_fee) = (3000, 200000);
        mock_create_pair_and_add_liquidity<MockCoin::WUSDC, MockCoin::WUSDT>(
            admin, b"USDC-USDT-LP", fee, admin_fee, usdc_amt, usdt_amt,
            10 * 100000000 * 10000000000
        );
    }

    #[test(admin = @HippoSwap, user = @0x1234567, core = @0xa550c18)]
    public fun test_data_set_init_imbalance(admin: &signer, core: &signer) {
        assert_launch_lq(admin, core, 40 * 100000000, 60 * 100000000, 9996588165); // Slightly less than 100 * 100000000
    }

    #[test(admin = @HippoSwap, user = @0x1234567, core = @0xa550c18)]
    public fun test_data_set_init_tiny_q(admin: &signer, core: &signer) {
        assert_launch_lq(admin, core, 40, 60, 99);
    }

    #[test(admin = @HippoSwap, user = @0x1234567, core = @0xa550c18)]
    public fun test_data_set_init_tiny_qr_1(admin: &signer, core: &signer) {
        assert_launch_lq(admin, core, 30, 70, 99);
    }

    #[test(admin = @HippoSwap, user = @0x1234567, core = @0xa550c18)]
    public fun test_data_set_init_tiny_qr_2(admin: &signer, core: &signer) {
        assert_launch_lq(admin, core, 10, 90, 98);
    }

    #[test(admin = @HippoSwap, user = @0x1234567, core = @0xa550c18)]
    public fun test_data_set_init_tiny_qr_3(admin: &signer, core: &signer) {
        assert_launch_lq(admin, core, 1, 99, 86);
    }

    #[test(admin = @HippoSwap, user = @0x1234567, core = @0xa550c18)]
    public fun test_data_set_init_small_qr_1(admin: &signer, core: &signer) {
        assert_launch_lq(admin, core, 100, 9900, 8690);
    }

    #[test(admin = @HippoSwap, user = @0x1234567, core = @0xa550c18)]
    public fun test_data_set_init_small_qr_2(admin: &signer, core: &signer) {
        assert_launch_lq(admin, core, 1, 9999, 3199);
    }

    #[test(admin = @HippoSwap, user = @0x1234567, core = @0xa550c18)]
    public fun test_data_set_trade_proc(admin: &signer, core: &signer) {
        let admin_addr = Signer::address_of(admin);
        assert_launch_lq(admin, core, 500000, 500000, 1000000);
        // let balance = Coin::balance<LPToken<MockCoin::WUSDC, MockCoin::WUSDT>>(admin_addr);
        let balance = StableCurveSwap::balance<MockCoin::WUSDC, MockCoin::WUSDT>(admin_addr);
        assert!(balance == 1000000, 1);
        // let (fee_x, fee_y) = StableCurveSwap::get_fee_reserves<MockCoin::WUSDC, MockCoin::WUSDT>();

        // The second investment;

        MockCoin::faucet_mint_to<MockCoin::WUSDC>(admin, 500000);
        MockCoin::faucet_mint_to<MockCoin::WUSDT>(admin, 1000000);
        StableCurveSwap::add_liquidity<MockCoin::WUSDC, MockCoin::WUSDT>(admin, 500000, 1000000);

        // check intermediate data add_liquidity_direct:
        // d1: 2499147, d0: 1000000
        // calc_reserve_and_fees:
        // ideal_reserve: 1249573,
        // old_reserve_x: 500000, new_reserve_x: 1000000, differenct_x: 249573, fee_x: 374, admin_fee_x: 74
        // old_reserve_y: 500000, new_reserve_y: 1500000 differenct_y: 250427, fee_y: 375, admin_fee_y: 75
        // d2: 2498397      // which was caculated from the amount of coin x after fee (including lp&admin) charged,
        // existed lp_token ( token_supply ): 1000000
        // mint_amount: 1498397
        // reserve_x:  999926 - 500000 = 499926 ( increased including the lp_fee(300), the increase of value of the stake holder), the amount of the part minted is 499626
        // reserve_y:  1499925 - 500000 = 999925 ( increased including the lp_fee(300), the increase of value of the stake holder), the amount of the part minted is 1499625
        // now the token_supply increased to 2498397

        let balance = StableCurveSwap::balance<MockCoin::WUSDC, MockCoin::WUSDT>(admin_addr);
        // Std::Debug::print(&balance);
        // 1500000 incoming currencies totally brings 1498397 lp.
        assert!(balance == 2498397, 1);
        let (_, _, _, fee_amt_x, fee_amt_y, _, _, _, _, _, _, _, _, _) = StableCurveSwap::get_pool_info<MockCoin::WUSDC, MockCoin::WUSDT>();

        assert!(fee_amt_x == 74, 1);
        assert!(fee_amt_y == 75, 1);

        MockCoin::faucet_mint_to<MockCoin::WUSDC>(admin, 200000);
        StableCurveSwap::swap_x_to_exact_y<MockCoin::WUSDC, MockCoin::WUSDT>(admin, 200000, admin_addr);

        let balance = Coin::balance<MockCoin::WUSDT>(admin_addr);
        assert!(balance == 200097, 1);
        let (_, _, _, fee_amt_x, fee_amt_y, _, _, _, _, _, _, _, _, _) = StableCurveSwap::get_pool_info<MockCoin::WUSDC, MockCoin::WUSDT>();
        assert!(fee_amt_x == 74, 1);
        assert!(fee_amt_y == 195, 1); // increased 120 = 200000 * 0.003 * 0.2


        StableCurveSwap::swap_y_to_exact_x<MockCoin::WUSDC, MockCoin::WUSDT>(admin, 200000, admin_addr);

        let balance = Coin::balance<MockCoin::WUSDC>(admin_addr);
        assert!(balance == 198467, 1);      // nearly 2 % loss
        let (_, _, _, fee_x, fee_y, _, _, _, _, _, _, _, _, _) = StableCurveSwap::get_pool_info<MockCoin::WUSDC, MockCoin::WUSDT>();
        assert!(fee_x == 193, 1);
        assert!(fee_y == 195, 1);


        MockCoin::faucet_mint_to<MockCoin::WUSDC>(admin, 20000000);
        StableCurveSwap::swap_x_to_exact_y<MockCoin::WUSDC, MockCoin::WUSDT>(admin, 20000000, admin_addr);

        let balance = Coin::balance<MockCoin::WUSDT>(admin_addr);
        assert!(balance == 1494324, 1); // Seems that the pool was exhausted, and the lp earn a lot.
        let (_, _, _, fee_x, fee_y, _, _, _, _, _, _, _, _, _) = StableCurveSwap::get_pool_info<MockCoin::WUSDC, MockCoin::WUSDT>();
        assert!(fee_x == 193, 1);
        assert!(fee_y == 1094, 1);

        MockCoin::faucet_mint_to<MockCoin::WUSDC>(admin, 50000000);
        MockCoin::faucet_mint_to<MockCoin::WUSDT>(admin, 10000000);
        StableCurveSwap::add_liquidity<MockCoin::WUSDC, MockCoin::WUSDT>(admin, 50000000, 10000000);

        let balance = StableCurveSwap::balance<MockCoin::WUSDC, MockCoin::WUSDT>(admin_addr);
        assert!(balance == 17744674, 1);
        let (_, _, _, fee_x, fee_y, _, _, _, _, _, _, _, _, _) = StableCurveSwap::get_pool_info<MockCoin::WUSDC, MockCoin::WUSDT>();
        assert!(fee_x == 30061, 1);
        assert!(fee_y == 4085, 1);
    }
}
