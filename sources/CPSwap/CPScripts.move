address HippoSwap {
module CPScripts {
    use HippoSwap::CPSwap;
    use Std::Signer;
    use TokenRegistry::TokenRegistry;
    use HippoSwap::MockCoin;
    use AptosFramework::Coin;


    const E_SWAP_ONLY_ONE_IN_ALLOWED: u64 = 0;
    const E_SWAP_ONLY_ONE_OUT_ALLOWED: u64 = 1;
    const E_SWAP_NONZERO_INPUT_REQUIRED: u64 = 2;
    const E_OUTPUT_LESS_THAN_MIN: u64 = 3;
    const E_TOKEN_REGISTRY_NOT_INITIALIZED:u64 = 4;
    const E_TOKEN_X_NOT_REGISTERED:u64 = 5;
    const E_TOKEN_Y_NOT_REGISTERED:u64 = 6;
    const E_LP_TOKEN_ALREADY_REGISTERED:u64 = 7;
    public fun create_new_pool<X, Y>(
        sender: &signer,
        fee_to: address,
        fee_on: bool,
        lp_name: vector<u8>,
        lp_symbol: vector<u8>,
        lp_description: vector<u8>,
        lp_logo_url: vector<u8>,
        lp_project_url: vector<u8>,
    ) {
        use HippoSwap::Math;

        let admin_addr = Signer::address_of(sender);
        assert!(TokenRegistry::is_registry_initialized(admin_addr), E_TOKEN_REGISTRY_NOT_INITIALIZED);
        assert!(TokenRegistry::has_token<X>(admin_addr), E_TOKEN_X_NOT_REGISTERED);
        assert!(TokenRegistry::has_token<Y>(admin_addr), E_TOKEN_Y_NOT_REGISTERED);
        assert!(!TokenRegistry::has_token<CPSwap::LPToken<X,Y>>(admin_addr), E_LP_TOKEN_ALREADY_REGISTERED);
        assert!(!TokenRegistry::has_token<CPSwap::LPToken<Y,X>>(admin_addr), E_LP_TOKEN_ALREADY_REGISTERED);

        let decimals = Math::max((Coin::decimals<X>() as u128), (Coin::decimals<Y>() as u128));
        let decimals = (decimals as u64);

        CPSwap::create_token_pair<X, Y>(sender, fee_to, fee_on, lp_name, lp_symbol, decimals);


        // register LP token to registry
        TokenRegistry::add_token<CPSwap::LPToken<X,Y>>(
            sender,
            lp_name,
            lp_symbol,
            lp_description,
            (decimals as u8),
            lp_logo_url,
            lp_project_url,
        );
    }
    public(script) fun create_new_pool_script<X, Y>(
        sender: &signer,
        fee_to: address,
        fee_on: bool,
        lp_name: vector<u8>,
        lp_symbol: vector<u8>,
        lp_description: vector<u8>,
        lp_logo_url: vector<u8>,
        lp_project_url: vector<u8>,
    ) {
        create_new_pool<X,Y>(
            sender,
            fee_to,
            fee_on,
            lp_name,
            lp_symbol,
            lp_description,
            lp_logo_url,
            lp_project_url,
        );
    }
    public(script) fun add_liquidity_script<X, Y>(
        sender: &signer,
        amount_x: u64,
        amount_y: u64
    ) {
        CPSwap::add_liquidity<X,Y>(sender, amount_x, amount_y);
    }
    public(script) fun remove_liquidity_script<X, Y>(
        sender: &signer,
        liquidity: u64,
        amount_x_min: u64,
        amount_y_min: u64
    ) {
        CPSwap::remove_liquidity<X,Y>(sender, liquidity, amount_x_min, amount_y_min);
    }
    public(script) fun swap_script<X, Y>(
        sender: &signer,
        x_in: u64,
        y_in: u64,
        x_min_out: u64,
        y_min_out: u64,
    ) {
        assert!(!(x_in > 0 && y_in > 0), E_SWAP_ONLY_ONE_IN_ALLOWED);
        assert!(!(x_min_out > 0 && y_min_out > 0), E_SWAP_ONLY_ONE_OUT_ALLOWED);
        // X to Y
        if (x_in > 0) {
            let y_out = CPSwap::swap_x_to_exact_y<X, Y>(sender, x_in, Signer::address_of(sender));
            assert!(y_out >= y_min_out, E_OUTPUT_LESS_THAN_MIN);
        }
        else if (y_in > 0) {
            let x_out = CPSwap::swap_y_to_exact_x<X, Y>(sender, y_in, Signer::address_of(sender));
            assert!(x_out >= x_min_out, E_OUTPUT_LESS_THAN_MIN);
        }
        else {
            assert!(false, E_SWAP_NONZERO_INPUT_REQUIRED);
        }
    }

    #[test_only]
    use AptosFramework::Timestamp;

    // #[test_only]
    fun init_coin_and_create_store<CoinType>(
        admin: &signer,
        name: vector<u8>,
        symbol: vector<u8>,
        decimals: u8,
    ) {
        // create CoinInfo
        MockCoin::initialize<CoinType>(admin, 8);

        // add coin to registry
        TokenRegistry::add_token<CoinType>(
            admin,
            name,
            symbol,
            name,
            decimals,
            b"",
            b"",
        );
    }

    fun mock_create_pair_and_add_liquidity<X, Y>(
        admin: &signer,
        symbol: vector<u8>,
        left_amt:u64,
        right_amt:u64,
        lp_amt:u64
    ) {
        create_new_pool<X, Y>(
            admin,
            Signer::address_of(admin),
            false,
            symbol,
            symbol,
            symbol,
            b"",
            b"",
        );

        let some_x = MockCoin::mint<X>(left_amt);
        let some_y = MockCoin::mint<Y>(right_amt);
        let (unused_x, unused_y, some_lp) = CPSwap::add_liquidity_direct(some_x, some_y);

        assert!(Coin::value(&unused_x) == 0, 5);
        assert!(Coin::value(&unused_y) == 0, 5);
        assert!(Coin::value(&some_lp) == lp_amt, 5);

        MockCoin::burn(unused_x);
        MockCoin::burn(unused_y);
        Coin::deposit(Signer::address_of(admin), some_lp);

    }

    // local validator deployment
    public(script) fun mock_deploy_script(admin: &signer) {
        /*
        1. initialize registry
        2. initialize coins (and add them to registry)
        3. create token pairs
        4. adds liquidity
        */
        let admin_addr = Signer::address_of(admin);
        // 1
        if(!TokenRegistry::is_registry_initialized(admin_addr)) {
            TokenRegistry::initialize(admin);
        };
        // 2
        init_coin_and_create_store<MockCoin::WBTC>(admin, b"Bitcoin", b"BTC", 8);
        init_coin_and_create_store<MockCoin::WUSDC>(admin,b"USDC", b"USDC", 8);
        init_coin_and_create_store<MockCoin::WUSDT>(admin, b"USDT", b"USDT", 8);
        // 3
        let btc_amt = 1000000000;
        mock_create_pair_and_add_liquidity<MockCoin::WBTC, MockCoin::WUSDC>(
            admin,
            b"BTC-USDC-LP",
            btc_amt,
            btc_amt * 10000,
            btc_amt * 100 - 1000,
        );

        mock_create_pair_and_add_liquidity<MockCoin::WBTC, MockCoin::WUSDT>(
            admin,
            b"BTC-USDT-LP",
            btc_amt,
            btc_amt * 10000,
            btc_amt * 100 - 1000,
        );
    }

    #[test(admin=@HippoSwap, user=@0x1234567, core=@0xa550c18)]
    public(script) fun test_initialization_cpswap(admin: &signer, user: &signer, core: &signer) {
        /*
        1. perform local depploy
        2. user trades
        */
        Timestamp::set_time_has_started_for_testing(core);
        let admin_addr = Signer::address_of(admin);
        // 1
        mock_deploy_script(admin);
        assert!(TokenRegistry::is_registry_initialized(admin_addr), 5);
        // 2
        Coin::register_internal<MockCoin::WBTC>(user);
        Coin::register_internal<MockCoin::WUSDC>(user);
        let user_addr = Signer::address_of(user);
        MockCoin::faucet_mint_to<MockCoin::WBTC>(user, 100);
        assert!(Coin::balance<MockCoin::WUSDC>(user_addr)==0, 5);
        CPSwap::swap_x_to_exact_y<MockCoin::WBTC, MockCoin::WUSDC>(user, 100, user_addr);
        assert!(Coin::balance<MockCoin::WUSDC>(user_addr) > 0, 5);

    }

    #[test(admin=@HippoSwap, user=@0x1234567, core=@0xa550c18)]
    public(script) fun test_add_remove_liquidity(admin: &signer, user: &signer, core: &signer) {

        /*
        1. create pools
        2. add liquidity to BTC-USDC
        3. remove liquidity from BTC-USDC
        */

        Timestamp::set_time_has_started_for_testing(core);
        // 1
        mock_deploy_script(admin);

        // 2
        let btc_amt = 100;
        let price = 10000;
        MockCoin::faucet_mint_to<MockCoin::WBTC>(user, btc_amt);
        MockCoin::faucet_mint_to<MockCoin::WUSDC>(user, btc_amt * price);
        add_liquidity_script<MockCoin::WBTC, MockCoin::WUSDC>(user, btc_amt, btc_amt * price);

        let user_addr = Signer::address_of(user);
        assert!(Coin::balance<MockCoin::WBTC>(user_addr) == 0, 0);
        assert!(Coin::balance<MockCoin::WUSDC>(user_addr) == 0, 0);

        // 3
        remove_liquidity_script<MockCoin::WBTC, MockCoin::WUSDC>(
            user,
            Coin::balance<CPSwap::LPToken<MockCoin::WBTC, MockCoin::WUSDC>>(user_addr),
            0,
            0,
        );
        assert!(Coin::balance<MockCoin::WBTC>(user_addr) == btc_amt, 0);
        assert!(Coin::balance<MockCoin::WUSDC>(user_addr) == btc_amt * price, 0);
    }

    #[test(admin=@HippoSwap, user=@0x1234567, core=@0xa550c18)]
    public(script) fun test_swap(admin: &signer, user: &signer, core: &signer) {
        /*
        1. create pools
        2. swap x to y
        3. swap y to x
        */
        Timestamp::set_time_has_started_for_testing(core);
        // 1
        mock_deploy_script(admin);

        // 2
        let btc_amt = 100;
        let price = 10000;
        MockCoin::faucet_mint_to<MockCoin::WBTC>(user, btc_amt);
        swap_script<MockCoin::WBTC, MockCoin::WUSDC>(user, btc_amt, 0, 0, btc_amt * price * 99 / 100);

        // 3
        let usdc_balance = Coin::balance<MockCoin::WUSDC>(Signer::address_of(user));
        swap_script<MockCoin::WBTC, MockCoin::WUSDC>(user, 0, usdc_balance, btc_amt * 99 / 100, 0);
        assert!(Coin::balance<MockCoin::WUSDC>(Signer::address_of(user)) == 0, 0);
        assert!(Coin::balance<MockCoin::WBTC>(Signer::address_of(user)) >= btc_amt * 99 / 100, 0);

    }

     #[test_only]
     public fun swap<X, Y>(
        sender: &signer,
        x_in: u64,
        y_in: u64,
        x_min_out: u64,
        y_min_out: u64,
    ) {
        assert!(!(x_in > 0 && y_in > 0), E_SWAP_ONLY_ONE_IN_ALLOWED);
        assert!(!(x_min_out > 0 && y_min_out > 0), E_SWAP_ONLY_ONE_OUT_ALLOWED);
        // X to Y
        if (x_in > 0) {
            let y_out = CPSwap::swap_x_to_exact_y<X, Y>(sender, x_in, Signer::address_of(sender));
            assert!(y_out >= y_min_out, E_OUTPUT_LESS_THAN_MIN);
        }
        else if (y_in > 0) {
            let x_out = CPSwap::swap_y_to_exact_x<X, Y>(sender, y_in, Signer::address_of(sender));
            assert!(x_out >= x_min_out, E_OUTPUT_LESS_THAN_MIN);
        }
        else {
            assert!(false, E_SWAP_NONZERO_INPUT_REQUIRED);
        }
    }
}
}
